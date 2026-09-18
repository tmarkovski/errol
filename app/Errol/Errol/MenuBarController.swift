// The AppKit shell around the SwiftUI interface: the status item (the Errol symbol,
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
    /// Navigation gets the first chance at Escape; other screens hide the panel.
    var onCancel: (() -> Bool)?

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) {
        if onCancel?() != true { orderOut(nil) }
    }
    /// Every close path — the title bar's close button, Cmd+W, a menu Close
    /// — puts the console away rather than tearing it down. Errol is a
    /// menu-bar app: the window going away is the app going quiet in the
    /// status item, and the process only ends through Quit in that item's
    /// menu.
    override func performClose(_ sender: Any?) { orderOut(nil) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Borderless windows have no standard Close item of their own.
        if !styleMask.contains(.titled),
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        invalidateShadow()
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
    // Veils are temporarily disabled. Restore SideVeils() here to enable them again.
    private let relay = RelayController(veils: nil, transferOverlay: TransferOverlay())
    /// What fitPanel last applied, so a card re-reporting the same size
    /// doesn't restart the frame animation.
    private var lastPanelSize: CGSize?
    private var panelResizeTimer: Timer?
    private let navigation = PanelNavigation(accessibilityGranted: AXIsProcessTrusted())
    private var permissionTimer: Timer?
    /// The debug log window, behind the status item's "Show Last Run Log".
    private var logWindow: NSWindow?
    /// Auto-update. Created at launch so background checks start immediately;
    /// everything that could interrupt a run is gated inside it.
    private var updater: UpdaterController!
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
        relay.focusPanelHandler = { [weak self] in self?.showPanel() }
        // A menu-bar app with no window gives a first-time user nothing to
        // discover the permission need from, so while the grant is missing
        // every launch opens the panel with setup covering its console.
        // Keep watching for both grants and revocations, including while
        // the user is in System Settings or the panel is hidden.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshAccessibility()
        }
        if !navigation.accessibilityGranted { showPanel() }
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
        // Keep the original owl as a fallback; ErrolSymbol is the default mark.
        let mark = NSImage(named: "ErrolSymbol") ?? NSImage(named: "MenuBarIcon")
        if let image = mark?.copy() as? NSImage {
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
            menu.addItem(withTitle: "Show Debug Logs in Finder", action: #selector(showDebugLogs),
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

    /// A borderless panel removes AppKit's title bar and window buttons.
    /// SwiftUI provides the glass surface (PanelWindowSurface) and the
    /// header controls; AppKit casts the native shadow around the content's
    /// alpha silhouette. That shadow is also the thin rim along the edge:
    /// the window server draws a dark contact line just outside the alpha
    /// edge and a one-point highlight just inside it, and over a
    /// translucent surface the pair reads as a border. Accepted for now in
    /// exchange for the separation the shadow gives over white chat
    /// windows; turning `hasShadow` off removes the rim along with it.
    /// Nothing else draws that line, the style mask included.
    ///
    /// Esc hides it; the bare surface drags it; the frame follows the card
    /// (fitPanel).
    private func buildPanel() {
        panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: PerchMetrics.initialPanel),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        // Transparent, so the glass refracts what lies behind the window.
        // The shadow follows the content's alpha silhouette, so it has to
        // be invalidated whenever that silhouette changes (order-front,
        // every frame of a resize).
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // The card covers its whole window, so it names its own drag region
        // (PanelRootView and PerchChrome); this catches whatever they leave.
        panel.isMovableByWindowBackground = true
        panel.title = "Errol"
        // Ordering and occlusion combine into one effective visibility: a
        // panel parked behind other windows is still "visible" to AppKit's
        // ordering, but every sweep it drives is synchronous IPC into the
        // chat apps, so fully occluded counts as hidden. The notification
        // center retains the block observer for the app's life.
        panel.onVisibilityChange = { [weak self] visible in
            if visible { self?.refreshAccessibility() }
            self?.pushPanelVisibility()
        }
        panel.onCancel = { [weak self] in
            guard let self else { return false }
            if self.relay.setup.cancelIfDragging() { return true }
            guard self.navigation.screen == .settings else { return false }
            self.showConsole()
            return true
        }
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
        let host = FirstMouseHostingView(rootView: PanelRootView(
            controller: relay,
            navigation: navigation,
            onCardResize: { [weak self] size in
                // The report lands mid-layout; the hop keeps the window's
                // frame change out of the pass that measured the card.
                DispatchQueue.main.async { self?.fitPanel(to: size) }
            },
            onBack: { [weak self] in self?.showConsole() })
            .modifier(PanelWindowSurface(navigation: navigation)))
        // fitPanel is the one thing that sizes this window. Left to its
        // default, the hosting view also gives itself an intrinsic size and
        // can fight the shell's animated resize. With no intrinsic size the
        // frame is exactly what the card reported.
        host.sizingOptions = []
        panel.contentView = host
    }

    /// Console and permission report the same fixed footprint. Settings
    /// reports its own content size, applied through an anchored resize.
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
        relay.setPanelVisible(panel.isVisible && panel.occlusionState.contains(.visible)
                              && navigation.screen == .console)
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
        guard panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
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
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - startedAt)
                               / PanelNavigationMotion.duration)
            let eased = progress * progress * (3 - 2 * progress)
            let next = NSRect(
                x: start.minX + (target.minX - start.minX) * eased,
                y: start.minY + (target.minY - start.minY) * eased,
                width: start.width + (target.width - start.width) * eased,
                height: start.height + (target.height - start.height) * eased)
            panel.setFrame(progress == 1 ? target : next, display: true)
            panel.invalidateShadow()
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

    /// Open centrally near the top of the screen containing the menu item.
    private func positionPanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        let screen = window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        navigation.consoleWidth = min(Perch.widgetWidth, max(600, visible.width - 32))
        let x = visible.midX - panel.frame.width / 2
        let proposedTop = visible.maxY - min(120, visible.height * 0.16)
        let y = min(visible.maxY - 16, max(proposedTop, visible.minY + panel.frame.height + 16))
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    // MARK: Navigation

    @objc func showSettings() {
        refreshAccessibility()
        if navigation.accessibilityGranted {
            panel.makeFirstResponder(nil)
            navigation.showsSettings = true
            updateNavigation()
        }
        showPanel()
    }

    private func showConsole() {
        panel.makeFirstResponder(nil)
        navigation.showsSettings = false
        updateNavigation()
    }

    private func refreshAccessibility() {
        let granted = AXIsProcessTrusted()
        guard granted != navigation.accessibilityGranted else { return }
        panel.makeFirstResponder(nil)
        navigation.accessibilityGranted = granted
        updateNavigation()
    }

    private func updateNavigation() {
        pushPanelVisibility()
    }

    // MARK: Debug log window

    /// The last run's in-memory log, live while a run is going — the well
    /// the console used to carry, in a window of its own so it costs no
    /// panel room. Chrome follows the console: non-activating,
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

    /// The on-disk debug logs (RunLog in Core/Logging.swift): one file per
    /// run with the detail the window leaves out, plus the snapshots taken
    /// at failures. Reveals the latest run's file when this process has
    /// written one, else opens the folder.
    @objc private func showDebugLogs() {
        let directory = RunLog.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let path = RunLog.lastPath {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }

    /// Inspect from the menu: open the log window first, so the report —
    /// and anything that stops it, a missing app or permission — lands
    /// somewhere visible.
    @objc private func inspectApps() {
        showRunLog()
        relay.runInspect()
    }

    /// The console, forward and key. Besides its own callers, this is the
    /// end of every run: the chat app that replied last still has the
    /// keyboard, and New session is what comes next. A panel Esc put away
    /// mid-run comes back too — the summary is what there is to look at
    /// now. Making the panel key is the whole move: a non-activating panel
    /// takes keyboard focus without the app activating (see the file's
    /// header), and activating the app, which earlier builds did at run
    /// end through LaunchServices, left the panel without key status.
    private func showPanel() {
        if !panel.isVisible { positionPanel() }
        panel.makeKeyAndOrderFront(nil)
    }
}
