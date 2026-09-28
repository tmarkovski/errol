// The AppKit shell around the SwiftUI interface: the status item (the Errol symbol,
// hidden until clicked) and the floating panel that hosts the console
// (PerchConsoleView). The panel's own window class, and the hosting view
// that takes the first click, are in KeyablePanel.swift.
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
    private let relay = RelayController(engine: LiveRelayEngine(), transferOverlay: TransferOverlay())
    /// What fitPanel last applied, so a card re-reporting the same size
    /// doesn't restart the frame animation.
    private var lastPanelSize: CGSize?
    private var panelResizeTimer: Timer?
    private let navigation = PanelNavigation(accessibilityGranted: AXIsProcessTrusted())
    /// The debug log window, behind the status item's "Show Last Run Log".
    private var logWindow: NSWindow?
    private var aboutWindow: NSWindow?
    /// The run's transcript (PerchTranscript), in a window under the
    /// console: a child of the panel, so it goes where the console is
    /// dragged and is put away with it. Made at the first run.
    private var transcriptPanel: NSPanel?
    /// A count of the transcript's fades, so a hide whose fade is still
    /// going does not finish over a show that came after it.
    private var transcriptFade = 0
    /// Auto-update. Created at launch so background checks start immediately;
    /// everything that could interrupt a run is gated inside it.
    private var updater: UpdaterController!
    /// Edge detection for the run-finished hook below. The observation
    /// callback also fires once at launch, which is not a transition.
    private var wasRunning = false
    /// The capsule that lights the status item while a run lasts.
    private let statusLight = StatusItemLight()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in the Info.plist already hides the Dock icon; this
        // keeps the behavior if the binary is ever run outside the bundle.
        NSApp.setActivationPolicy(.accessory)
        trackAppearance()
        updater = UpdaterController { [weak self] in self?.relay.isRunning ?? false }
        updater.bringConsoleForward = { [weak self] in self?.showPanel() }
        buildStatusItem()
        buildPanel()
        trackStatusIcon()
        trackTranscript()
        relay.appMenuProvider = { [weak self] in self?.makeAppMenu() ?? NSMenu() }
        relay.focusPanelHandler = { [weak self] in self?.showPanel() }
        // A menu-bar app with no window gives a first-time user nothing to
        // discover the permission need from, so while the grant is missing
        // every launch opens the panel with setup covering its console.
        // Keep watching for both grants and revocations, including while
        // the user is in System Settings or the panel is hidden. The run
        // loop keeps the timer for the app's life; the tolerance lets the
        // system fold this poll into other wakeups.
        let permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshAccessibility()
        }
        permissionTimer.tolerance = 0.5
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
        logWindow?.backgroundColor = selection.0.palette.shell
        aboutWindow?.backgroundColor = selection.0.palette.shell
    }

    // MARK: Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = StatusIcon.image(running: false)
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = makeAppMenu()
            if let button = statusItem.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 6), in: button)
            }
            return
        }
        togglePanel()
    }

    /// The status item's menu, which the console's ··· button also shows.
    /// There is no settings screen: the appearance and the color palette
    /// are chosen here, and apply at once.
    private func makeAppMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "About Errol", action: #selector(showAbout), keyEquivalent: "").target = self
        // A check while nothing is on offer, then the console's Update
        // button's own action. Refused rather than queued during a run.
        let updateItem = menu.addItem(
            withTitle: updater.menuTitle, action: #selector(updateItemChosen), keyEquivalent: "")
        updateItem.target = self
        updateItem.isEnabled = updater.menuEnabled
        menu.addItem(.separator())
        addAppearanceOptions(to: menu)
        menu.addItem(.separator())
        // The logs, for a report of what went wrong. The console dropped
        // its log well; the in-memory run log lives here.
        menu.addItem(withTitle: "Show Last Run Log", action: #selector(showRunLog),
                 keyEquivalent: "").target = self
        let finderItem = menu.addItem(withTitle: "Show Debug Logs in Finder", action: #selector(showDebugLogs),
                                     keyEquivalent: "")
        finderItem.target = self
        finderItem.isEnabled = relay.consoleAccess.canChangeDestination
        #if DEBUG
        // The selector inspector is for working on Errol, so only a debug
        // build offers it.
        let inspectItem = menu.addItem(
            withTitle: "Inspect Apps", action: #selector(inspectApps), keyEquivalent: "")
        inspectItem.target = self
        // A run owns the apps' AX trees; inspecting mid-run would fight it.
        inspectItem.isEnabled = relay.consoleAccess.canChangeDestination
        #endif
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Errol", action: #selector(quit), keyEquivalent: "q").target = self
        return menu
    }

    /// The console comes forward, since the button, and the note when
    /// there is nothing new, are where the answer shows.
    @objc private func updateItemChosen() {
        if UpdateStatus.shared.phase == .idle { showPanel() }
        updater.menuItemChosen()
    }

    // MARK: Appearance options

    private func addAppearanceOptions(to menu: NSMenu) {
        let display = submenu("Appearance", in: menu)
        for mode in AppAppearance.allCases {
            option(mode.title, #selector(chooseAppearance(_:)), mode,
                   checked: AppearanceStore.shared.appearance == mode, in: display)
        }

        let palette = submenu("Color Palette", in: menu)
        for theme in AppTheme.allCases {
            option(theme.title, #selector(chooseTheme(_:)), theme,
                   checked: AppearanceStore.shared.theme == theme, in: palette)
        }

    }

    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
        return submenu
    }

    /// One checkable choice, carrying the value it stands for.
    @discardableResult
    private func option(_ title: String, _ action: Selector, _ value: Any, checked: Bool,
                        in menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = value
        item.state = checked ? .on : .off
        return item
    }

    @objc private func chooseAppearance(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? AppAppearance else { return }
        AppearanceStore.shared.appearance = mode
    }

    @objc private func chooseTheme(_ sender: NSMenuItem) {
        guard let theme = sender.representedObject as? AppTheme else { return }
        AppearanceStore.shared.theme = theme
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// The console being put away is not the app ending — AppKit's default
    /// already agrees, but the close button depends on it, so it is stated.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Every termination path cancels a run here: the Quit item included,
    /// logout, and Sparkle's own install-on-quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        relay.stop()
        return .terminateNow
    }

    // MARK: Panel

    /// A borderless panel removes AppKit's title bar and window buttons.
    /// SwiftUI provides the solid surface (PanelWindowSurface) and the
    /// header controls; AppKit casts the native shadow around the content's
    /// alpha silhouette. That shadow is also the thin rim along the edge:
    /// the window server draws a dark contact line just outside the alpha
    /// edge and a one-point highlight just inside it, and the pair reads
    /// as a border. Accepted for now in exchange for the separation the
    /// shadow gives over white chat windows; turning `hasShadow` off
    /// removes the rim along with it. Nothing else draws that line, the
    /// style mask included.
    ///
    /// Esc hides it; the bare surface drags it; the frame follows the card
    /// (fitPanel).
    private func buildPanel() {
        panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: PerchMetrics.initialPanel),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.permitsKey = { [weak self] in self?.relay.consoleAccess.canTakeFocus ?? true }
        // Transparent, so the capsule's rounded ends and the card's corners
        // show what lies behind the window. The shadow follows the
        // content's alpha silhouette, so it has to be invalidated whenever
        // that silhouette changes (order-front, every frame of a resize).
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // The card covers its whole window, so it names its own drag region
        // (PanelRootView); this catches whatever it leaves.
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
            self?.updateTranscript()
        }
        _ = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: panel, queue: .main) { [weak self] _ in
            self?.pushPanelVisibility()
        }
        // The transcript follows a drag as the panel's child. This is for
        // the one move that changes where it belongs: the console reaching
        // the screen's bottom edge, which turns it over the console.
        _ = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel, queue: .main) { [weak self] _ in
            self?.placeTranscript()
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
            })
            .modifier(PanelWindowSurface()))
        // fitPanel is the one thing that sizes this window. Left to its
        // default, the hosting view also gives itself an intrinsic size and
        // can fight the shell's animated resize. With no intrinsic size the
        // frame is exactly what the card reported.
        host.sizingOptions = []
        panel.contentView = host
    }

    /// Console and permission report the same fixed footprint; its width
    /// follows the screen (positionPanel), applied through an anchored
    /// resize.
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
        let showing = panel.isVisible && panel.occlusionState.contains(.visible)
            && navigation.screen == .console
        relay.setPanelVisible(showing)
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
        // The theme too: the icon a run lights takes its colors from it.
        let (running, theme) = withObservationTracking {
            (relay.isRunning, AppearanceStore.shared.theme)
        } onChange: {
            rearm.run()
        }
        statusItem.button?.image = StatusIcon.image(running: running)
        statusLight.show(running, accent: theme.palette.accent, behind: statusItem.button)
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
            updateTranscript()
            return
        }
        // Apply frames on run-loop ticks. This keeps the resize out of
        // SwiftUI's measuring pass and avoids AppKit's synchronous animated
        // resize/display loop. A new target cancels the old timer and starts
        // at the current frame, so rapid state changes do not queue resizes.
        let start = panel.frame
        let target = frame
        let startedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak panel] timer in
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
            if progress == 1 {
                timer.invalidate()
                // The transcript waited for the console's frame to settle.
                if let self, self.panelResizeTimer === timer {
                    self.panelResizeTimer = nil
                    self.updateTranscript()
                }
            }
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

    private func refreshAccessibility() {
        let granted = AXIsProcessTrusted()
        guard granted != navigation.accessibilityGranted else { return }
        panel.makeFirstResponder(nil)
        navigation.accessibilityGranted = granted
        pushPanelVisibility()
        // The grant came through the guide under System Settings: put it
        // away and bring the console up, even if it was hidden meanwhile,
        // since setup is the next step. The permission timer and the panel's
        // showing both call this on the main thread, where the guide lives.
        if granted, MainActor.assumeIsolated({ PermissionGuide.dismiss() }) { showPanel() }
    }

    // MARK: The transcript

    /// The transcript stands under the console from a run's start until
    /// New topic clears its ending, while the console is up and on its
    /// own screen (not the permission ask). Read again at each
    /// change of stage or screen, and at each showing or hiding of the
    /// console.
    private func trackTranscript() {
        let rearm = MainQueueHop { [weak self] in self?.trackTranscript() }
        withObservationTracking {
            _ = relay.stage
            _ = navigation.screen
        } onChange: {
            rearm.run()
        }
        updateTranscript()
    }

    private func updateTranscript() {
        let wanted = relay.stage != .compose && navigation.screen == .console && panel.isVisible
        if wanted { showTranscript() } else { hideTranscript() }
    }

    /// A borderless, non-activating panel like the console's, transparent
    /// so the card's paper is its silhouette, and with the console's kind
    /// of shadow around that silhouette, rim and all (buildPanel), so it
    /// stands apart from the chat windows under it the way the console
    /// does. The shadow is AppKit's rather than drawn in the card, so the
    /// window stays the card's size and a click beside the card reaches
    /// the window under it. It cannot become key, so a click or a scroll
    /// in it never takes the keyboard from the console's field, and it
    /// never moves on its own: it goes where the console is dragged.
    private func makeTranscriptPanel() -> NSPanel {
        let transcript = KeyablePanel(contentRect: NSRect(origin: .zero,
                                                     size: NSSize(width: 1, height: PerchTranscript.height)),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        transcript.permitsKey = { [weak self] in self?.relay.consoleAccess.canTakeFocus ?? false }
        transcript.onCancel = { [weak self] in
            self?.showPanel()
            self?.relay.steeringEditor.restoreFocus()
            return true
        }
        transcript.isOpaque = false
        transcript.backgroundColor = .clear
        transcript.hasShadow = true
        transcript.title = "Errol Transcript"
        transcript.isMovableByWindowBackground = false
        transcript.isFloatingPanel = true
        transcript.hidesOnDeactivate = false
        transcript.isReleasedWhenClosed = false
        transcript.level = panel.level
        transcript.collectionBehavior = panel.collectionBehavior
        let host = FirstMouseHostingView(rootView: PerchTranscript(controller: relay))
        // The window is the one thing that sizes the card (placeTranscript).
        host.sizingOptions = []
        transcript.contentView = host
        return transcript
    }

    /// Under the console, centered on it, a gap below the capsule and as
    /// wide as the prompt box inside it, so it stands as the box's
    /// continuation — or over the console, when the screen ends before
    /// there is room under it.
    private func placeTranscript() {
        guard let transcript = transcriptPanel, transcript.parent != nil else { return }
        let console = panel.frame
        let size = NSSize(width: PerchMetrics.promptBoxWidth(consoleWidth: console.width).rounded(),
                          height: PerchTranscript.height.rounded())
        var origin = NSPoint(x: (console.midX - size.width / 2).rounded(),
                             y: (console.minY - PerchTranscript.gap - size.height).rounded())
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame, origin.y < visible.minY {
            origin.y = (console.maxY + PerchTranscript.gap).rounded()
        }
        let frame = NSRect(origin: origin, size: size)
        guard transcript.frame != frame else { return }
        transcript.setFrame(frame, display: true)
        // The shadow follows the silhouette, which a new size changes.
        transcript.invalidateShadow()
    }

    /// The transcript comes in with a fade, under the console's own frame:
    /// while the panel is still resizing, the resize's end calls back
    /// here. A transcript still fading out is turned around.
    private func showTranscript() {
        guard panelResizeTimer == nil else { return }
        let transcript = transcriptPanel ?? makeTranscriptPanel()
        transcriptPanel = transcript
        transcriptFade += 1
        if transcript.parent == nil {
            transcript.alphaValue = 0
            // Adding the child orders it in with the console.
            panel.addChildWindow(transcript, ordered: .above)
        }
        placeTranscript()
        guard transcript.alphaValue < 1 else { return }
        // The shadow is taken from the drawn card, once it is drawn whole.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            transcript.alphaValue = 1
            transcript.invalidateShadow()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            transcript.animator().alphaValue = 1
        }, completionHandler: { transcript.invalidateShadow() })
    }

    /// Out with a fade, then off the console: a child window ordered out
    /// leaves its parent, and is added back when it shows again. A
    /// transcript the console took with it when it was put away goes at
    /// once.
    private func hideTranscript() {
        guard let transcript = transcriptPanel, transcript.parent != nil else { return }
        transcriptFade += 1
        let fade = transcriptFade
        let putAway = { [weak self] in
            guard let self, self.transcriptFade == fade, let transcript = self.transcriptPanel else { return }
            self.panel.removeChildWindow(transcript)
            transcript.orderOut(nil)
        }
        guard transcript.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            putAway()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            transcript.animator().alphaValue = 0
        }, completionHandler: putAway)
    }

    // MARK: Debug log window

    /// The last run's in-memory log, live while a run is going — the well
    /// the console used to carry, in a window of its own so it costs no
    /// panel room. Chrome follows the console: non-activating,
    /// bare-titled, floating a level above the console; resizable, because
    /// inspect reports are long.
    @objc private func showRunLog() {
        if logWindow == nil {
            logWindow = utilityPanel(title: "Errol Log", size: NSSize(width: 560, height: 420),
                                     resizable: true,
                                     content: FirstMouseHostingView(
                                        rootView: PerchLogWindowView(controller: relay)))
        }
        if let logWindow { present(logWindow) }
    }

    /// The on-disk debug logs (RunLog in Core/Logging/RunLog.swift): one file per
    /// run with the detail the window leaves out, plus the snapshots taken
    /// at failures. Reveals the latest run's file when this process has
    /// written one, else opens the folder.
    @objc private func showDebugLogs() {
        guard relay.consoleAccess.canChangeDestination else { return }
        let directory = RunLog.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let path = RunLog.lastPath {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }

    #if DEBUG
    /// Inspect from the menu: open the log window first, so the report —
    /// and anything that stops it, a missing app or permission — lands
    /// somewhere visible.
    @objc private func inspectApps() {
        guard relay.consoleAccess.canChangeDestination else { return }
        showRunLog()
        relay.runInspect()
    }
    #endif

    // MARK: About

    /// Errol's About window (AboutView): a small window of its own, not
    /// the console, in the theme's shell. Its chrome follows the log
    /// window's: non-activating and floating a level above the console, so
    /// opening it mid-run never takes the keyboard from an app the relay
    /// is typing into. Esc and the close button put it away.
    @objc func showAbout() {
        if aboutWindow == nil {
            let host = FirstMouseHostingView(rootView: AboutView())
            aboutWindow = utilityPanel(title: "About Errol", size: host.fittingSize,
                                       resizable: false, content: host)
        }
        if let aboutWindow { present(aboutWindow) }
    }

    /// The console, forward and key. Besides its own callers, this is the
    /// end of every run: the chat app that replied last still has the
    /// keyboard, and New topic is what comes next. A panel Esc put away
    /// mid-run comes back too — the summary is what there is to look at
    /// now. Making the panel key is the whole move: a non-activating panel
    /// takes keyboard focus without the app activating (see the file's
    /// header), and activating the app, which earlier builds did at run
    /// end through LaunchServices, left the panel without key status.
    private func showPanel() {
        if !panel.isVisible { positionPanel() }
        present(panel)
    }

    // MARK: Utility windows

    /// The log's and About's shared chrome: bare-titled and closable,
    /// non-activating, floating a level above the console in the theme's
    /// shell (trackAppearance repaints it), and dragged by its background.
    /// It takes the keyboard only when the console could, so opening one
    /// mid-run never takes it from an app the relay is typing into.
    private func utilityPanel(title: String, size: NSSize, resizable: Bool,
                              content: NSView) -> KeyablePanel {
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView,
                                             .nonactivatingPanel]
        if resizable { styleMask.insert(.resizable) }
        let window = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: styleMask, backing: .buffered, defer: false)
        window.title = title
        window.permitsKey = { [weak self] in self?.relay.consoleAccess.canTakeFocus ?? false }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.backgroundColor = Perch.shellNS
        window.contentView = content
        window.center()
        return window
    }

    /// Forward, and key only when the relay allows the keyboard to move.
    private func present(_ window: NSWindow) {
        if relay.consoleAccess.canTakeFocus { window.makeKeyAndOrderFront(nil) }
        else { window.orderFront(nil) }
    }
}
