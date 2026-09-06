// The AppKit shell around the SwiftUI interface: the status item (an owl,
// hidden until clicked) and the floating panel that hosts the console
// (PerchPanelView).
//
// The shell stays AppKit on purpose. SwiftUI's MenuBarExtra window dismisses
// itself whenever another app activates — which the relay does on every
// turn — so the controls and log would vanish exactly when a run needs them
// visible. A non-activating floating NSPanel (the Spotlight pattern) is the
// only window kind that stays up without stealing focus from the chat apps;
// text entry still works because the panel can become key without
// activating the app.

import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// NSPanel refuses key status in some non-activating configurations, which
/// would make the instruction field untypeable; force it. Esc hides the
/// panel instead of beeping.
final class KeyablePanel: NSPanel {
    /// Fires on every path the panel appears or disappears through — toggle,
    /// Esc, the close button — so the readiness scanner tracks visibility.
    var onVisibilityChange: ((Bool) -> Void)?

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    /// Every close path — the title bar's close button, Cmd+W, a menu Close
    /// — puts the console away rather than tearing it down. Errol is a
    /// menu-bar app: the window going away is the app going quiet in the
    /// status item, and the process only ends through Quit in that item's
    /// menu.
    override func performClose(_ sender: Any?) { orderOut(nil) }
    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        onVisibilityChange?(true)
    }
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        onVisibilityChange?(false)
    }
    override func close() {
        super.close()
        onVisibilityChange?(false)
    }
}

/// The panel floats over the chat apps without taking their focus, so most
/// clicks land on a window that is not key — and AppKit spends the first
/// click on a window like that activating it, never delivering it to the
/// content. That is why the console had to be clicked once before it could
/// be dragged or pressed. Claiming the click makes it behave like the
/// floating palette it is: the first one acts, wherever it lands.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Carries a main-thread callback into withObservationTracking's @Sendable
/// onChange without capturing the (non-Sendable) shell there. Unchecked is
/// sound because the work both closes over and executes on the main queue.
private struct MainQueueHop: @unchecked Sendable {
    private let work: () -> Void
    init(_ work: @escaping () -> Void) { self.work = work }
    func run() { DispatchQueue.main.async(execute: work) }
}

final class MenuBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: KeyablePanel!
    private let relay = RelayController(veils: SideVeils())
    /// What fitPanel last applied, so a card re-reporting the same size
    /// doesn't restart the frame animation.
    private var lastPanelSize: CGSize?
    private var panelResizeTimer: Timer?
    /// Settings rides the same non-activating panel machinery as the console
    /// and floats one level above it, so it opens over the panel without
    /// stealing focus; only the system close button distinguishes its chrome.
    /// The permission explainer stays an ordinary activating window — it
    /// greets a first launch, when there is nothing to avoid deactivating.
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    /// The debug log window, behind the status item's "Show Last Run Log".
    private var logWindow: NSWindow?
    /// Auto-update. Created at launch so background checks start immediately;
    /// everything that could interrupt a run is gated inside it.
    private var updater: UpdaterController!
    /// The panel's toolbar delegate (PerchChrome). NSToolbar holds its
    /// delegate weakly, so the shell keeps it alive.
    private var panelChrome: PerchChromeToolbar?
    /// Edge detection for the run-finished hook below. The observation
    /// callback also fires once at launch, which is not a transition.
    private var wasRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in the Info.plist already hides the Dock icon; this
        // keeps the behavior if the binary is ever run outside the bundle.
        NSApp.setActivationPolicy(.accessory)
        trackAppearance()
        updater = UpdaterController { [weak self] in self?.relay.isRunning ?? false }
        buildStatusItem()
        buildPanel()
        trackStatusIcon()
        relay.openSettingsHandler = { [weak self] in self?.showSettings() }
        // A menu-bar app with no window gives a first-time user nothing to
        // discover the permission need from, so while the grant is missing
        // every launch opens the explainer instead of waiting for a Start
        // press to fail. It closes itself out of the way once granted.
        if !AXIsProcessTrusted() {
            showPermissionOnboarding()
        }
    }

    // MARK: Appearance

    /// Native chrome and editors inherit the app appearance. SwiftUI colors
    /// observe the theme independently, keeping view identity and drafts intact.
    private func trackAppearance() {
        let rearm = MainQueueHop { [weak self] in self?.trackAppearance() }
        let selection = withObservationTracking {
            (AppearanceStore.shared.theme, AppearanceStore.shared.appearance)
        } onChange: {
            rearm.run()
        }
        NSApp.appearance = selection.1.nativeAppearance
        settingsWindow?.backgroundColor = selection.0.palette.paper
        logWindow?.backgroundColor = selection.0.palette.paper
    }

    // MARK: Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = statusIcon(running: false)
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func statusIcon(running: Bool) -> NSImage? {
        if let image = NSImage(named: "MenuBarIcon")?.copy() as? NSImage {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = running ? "Errol is running" : "Errol"
            return image
        }

        return NSImage(systemSymbolName: running ? "bird.fill" : "bird", accessibilityDescription: "Errol")
            ?? NSImage(systemSymbolName: "paperplane", accessibilityDescription: "Errol")
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
            let checkForUpdatesItem = menu.addItem(
                withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            checkForUpdatesItem.target = self
            // Refused rather than queued during a run: queueing would only
            // surface Sparkle's window later, at a moment nobody chose.
            checkForUpdatesItem.isEnabled = updater.canCheckForUpdates
            menu.addItem(.separator())
            // The debug pair. The console dropped its log well and Inspect
            // button; the in-memory run log and the inspector live here.
            menu.addItem(withTitle: "Show Last Run Log", action: #selector(showRunLog),
                         keyEquivalent: "").target = self
            let inspectItem = menu.addItem(
                withTitle: "Inspect Apps", action: #selector(inspectApps), keyEquivalent: "")
            inspectItem.target = self
            // A run owns the apps' AX trees; inspecting mid-run would fight it.
            inspectItem.isEnabled = !relay.isRunning
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Errol", action: #selector(quit), keyEquivalent: "q").target = self
            if let button = statusItem.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 6), in: button)
            }
            return
        }
        togglePanel()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func quit() {
        relayControl.cancel()
        NSApp.terminate(nil)
    }

    /// The console being put away is not the app ending — AppKit's default
    /// already agrees, but the close button depends on it, so it is stated.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Every termination path, not just the Quit item: logout, and Sparkle's
    /// own install-on-quit. Cancelling is idempotent, so the Quit item having
    /// already done it costs nothing.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        relay.stop()
        return .terminateNow
    }

    // MARK: Panel

    /// The console's window is titled, but draws none of its chrome —
    /// transparent title bar, hidden title, content run up under it — so the
    /// paper card fills the window and AppKit's close button lands on the
    /// strip across its top (Perch.chromeBand). That is the one way to get
    /// the real window buttons with their own behavior (the hover glyphs, a
    /// first click that lands on an unfocused window, Cmd+W) without AppKit
    /// drawing a title bar over the card: a borderless window has no title
    /// bar to hang them on, and `standardWindowButton` answers nil for one.
    /// The cost is that AppKit owns where they sit — top-left, in the title
    /// bar's strip — which is why the card pads its top past them, and owns
    /// the window's corner mask and shadow, which the card reads as its own
    /// edge instead of painting.
    ///
    /// Esc hides it; the bare paper drags it; the frame follows the card
    /// (fitPanel).
    private func buildPanel() {
        panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: PerchMetrics.initialPanel),
                             styleMask: [.titled, .closable, .fullSizeContentView,
                                         .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.titlebarSeparatorStyle = .none
        // The toolbar does two jobs. Attached at all, it grows the title
        // strip from the bare 28pt to the unified bar's 52pt and centers the
        // close button in it with the roomier inset Safari and Mail have
        // (Perch.chromeBand mirrors the height). And it carries the strip's
        // contents — the state pill and the session menu — as real toolbar
        // items, the one way controls up there receive clicks rather than
        // losing them to the bar's drag (PerchChromeToolbar).
        let chrome = PerchChromeToolbar(controller: relay)
        panelChrome = chrome
        panel.toolbar = chrome.makeToolbar()
        panel.toolbarStyle = .unified
        // Close is the only button offered: the card is a fixed width and
        // sizes its own height, so zoom has nothing to do, and a panel does
        // not miniaturize.
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        // The card paints the paper over the whole window; AppKit masks the
        // corners and casts the shadow from that shape.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The card covers its whole window, so it names its own drag region
        // (PerchPanelView); this catches whatever it leaves, the title bar's
        // own strip aside.
        panel.isMovableByWindowBackground = true
        panel.title = "Errol"
        // Ordering and occlusion combine into one effective visibility: a
        // panel parked behind other windows is still "visible" to AppKit's
        // ordering, but every sweep it drives is synchronous IPC into the
        // chat apps, so fully occluded counts as hidden. The notification
        // center retains the block observer for the app's life.
        panel.onVisibilityChange = { [weak self] _ in self?.pushPanelVisibility() }
        _ = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: panel, queue: .main) { [weak self] _ in
            self?.pushPanelVisibility()
        }
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = FirstMouseHostingView(rootView: PerchPanelView(
            controller: relay,
            onCardResize: { [weak self] size in
                // The report lands mid-layout; the hop keeps the window's
                // frame change out of the pass that measured the card.
                DispatchQueue.main.async { self?.fitPanel(to: size) }
            })
            // The card hangs from the top of whatever frame the window has
            // at the moment — its opening size, or the last fit while a
            // resize is still animating — and runs up under the title bar,
            // whose strip is where the close button stands, so the
            // safe-area inset is declined. Both are window concerns, kept
            // here rather than in the view so it previews at its own size.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea())
        // fitPanel is the one thing that sizes this window. Left to its
        // default, the hosting view also gives itself an intrinsic size —
        // the card plus the title strip's safe-area inset (66pt with the
        // unified bar) — and its compression resistance outranks the
        // window's stay-put priority, so every fit was undone a beat
        // later: the window sprang back to card-plus-strip, a transparent
        // band under the paper, and AppKit's own constraint passes were
        // resizing the window behind the shell's back. With no intrinsic
        // size the frame is exactly what the card reported.
        host.sizingOptions = []
        panel.contentView = host
    }

    /// Follow the card: it is content-sized, and each size it reports
    /// (PerchPanelView.onCardResize) becomes the window's, through an
    /// anchored, animated frame change.
    private func fitPanel(to size: CGSize) {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return }
        // NSWindow rounds its frame to points. Compare the dimensions it
        // can actually apply so fractional layout noise cannot retarget it.
        let size = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard size != lastPanelSize else { return }
        lastPanelSize = size
        resizePanel(to: size)
    }

    private func pushPanelVisibility() {
        guard let panel else { return }
        relay.setPanelVisible(panel.isVisible && panel.occlusionState.contains(.visible))
    }

    // MARK: Observation bridges

    // Observation replaced the Combine publishers when the model moved to
    // @Observable: each tracker reads its dependencies inside
    // withObservationTracking and re-arms itself on the main queue after a
    // change. onChange fires at willSet — the mutated values aren't
    // readable yet — so the re-run waits a turn of the run loop, which also
    // coalesces a burst of changes into one application.

    private func trackStatusIcon() {
        let rearm = MainQueueHop { [weak self] in self?.trackStatusIcon() }
        let running = withObservationTracking { relay.isRunning } onChange: {
            rearm.run()
        }
        statusItem.button?.image = statusIcon(running: running)
        // A run reaching idle is when the updater can release what it held
        // back: a staged install, or an update it found but never presented.
        if wasRunning, !running { updater?.relayDidFinish() }
        wasRunning = running
    }

    private func resizePanel(to size: CGSize) {
        guard let panel else { return }
        panelResizeTimer?.invalidate()
        panelResizeTimer = nil
        var frame = panel.frame
        let topY = frame.maxY
        let midX = frame.midX
        frame.size = size
        frame.origin = NSPoint(x: midX - size.width / 2, y: topY - size.height)
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = max(visible.minX + 8,
                                 min(frame.origin.x, visible.maxX - size.width - 8))
        }
        guard panel.isVisible else {
            panel.setFrame(frame, display: false)
            return
        }
        // Apply frames on run-loop ticks. This keeps the resize out of
        // SwiftUI's measuring pass and avoids AppKit's synchronous animated
        // resize/display loop. A new target cancels the old timer and starts
        // at the current frame, so rapid state changes do not queue resizes.
        let start = panel.frame
        let target = frame
        let startedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak panel] timer in
            guard let panel else { timer.invalidate(); return }
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - startedAt) / 0.32)
            let eased = progress * progress * (3 - 2 * progress)
            let next = NSRect(
                x: start.minX + (target.minX - start.minX) * eased,
                y: start.minY + (target.minY - start.minY) * eased,
                width: start.width + (target.width - start.width) * eased,
                height: start.height + (target.height - start.height) * eased)
            panel.setFrame(progress == 1 ? target : next, display: false)
            if progress == 1 { timer.invalidate() }
        }
        panelResizeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Drop the panel just under the status item, clamped to the screen.
    private func positionPanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        var x = buttonFrame.midX - panel.frame.width / 2
        var y = buttonFrame.minY - 8
        if let visible = screen?.visibleFrame {
            x = max(visible.minX + 8, min(x, visible.maxX - panel.frame.width - 8))
            // Lift a panel whose bottom would run off the screen — but only
            // while it still fits; taller than the screen, hanging from the
            // status item at least keeps the instrument head in view.
            if panel.frame.height + 16 <= visible.height {
                y = max(y, visible.minY + panel.frame.height + 8)
            }
        }
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    // MARK: Settings window

    /// The settings card wears the console's idiom, so its window chrome
    /// follows the console's: non-activating (typing works — KeyablePanel
    /// forces key status), titled but bare so only the system close button
    /// shows over the card's paper, and a level above the floating console
    /// so it always opens on top of it.
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = KeyablePanel(contentRect: .zero,
                                      styleMask: [.titled, .closable,
                                                  .fullSizeContentView,
                                                  .nonactivatingPanel],
                                      backing: .buffered, defer: false)
            window.title = "Errol Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            window.backgroundColor = Perch.paperNS
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Debug log window

    /// The last run's in-memory log, live while a run is going — the well
    /// the console used to carry, in a window of its own so it costs no
    /// panel room. Chrome follows the settings card: non-activating,
    /// bare-titled, floating a level above the console; resizable, because
    /// inspect reports are long.
    @objc private func showRunLog() {
        if logWindow == nil {
            let window = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                                      styleMask: [.titled, .closable, .resizable,
                                                  .fullSizeContentView,
                                                  .nonactivatingPanel],
                                      backing: .buffered, defer: false)
            window.title = "Errol Log"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            window.backgroundColor = Perch.paperNS
            window.contentView = FirstMouseHostingView(
                rootView: PerchLogWindowView(controller: relay))
            window.center()
            logWindow = window
        }
        logWindow?.makeKeyAndOrderFront(nil)
    }

    /// Inspect from the menu: open the log window first, so the report —
    /// and anything that stops it, a missing app or permission — lands
    /// somewhere visible.
    @objc private func inspectApps() {
        showRunLog()
        relay.runInspect()
    }

    // MARK: Permission explainer

    private func showPermissionOnboarding() {
        if onboardingWindow == nil {
            let view = PermissionOnboardingView(
                onFinished: { [weak self] in
                    self?.onboardingWindow?.close()
                    self?.showPanel()
                },
                onDismiss: { [weak self] in
                    self?.onboardingWindow?.close()
                })
            let window = NSWindow(contentViewController:
                NSHostingController(rootView: view))
            // Onboarding chrome: closable but title-less, dragged by its
            // own background like the system's first-run sheets.
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func showPanel() {
        guard !panel.isVisible else { return }
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
    }
}
