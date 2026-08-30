// The AppKit shell around the SwiftUI interface: the status item (an owl,
// hidden until clicked) and the floating panel that hosts the compiled-in
// skin (PanelRootView).
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
    private let relay = RelayController()
    /// What the layout tracker last applied, so re-runs that land on the
    /// same size don't restart the frame animation.
    private var lastPanelSize: CGSize?
    /// Settings rides the same non-activating panel machinery as the console
    /// and floats one level above it, so it opens over the panel without
    /// stealing focus; only the system close button distinguishes its chrome.
    /// The permission explainer stays an ordinary activating window — it
    /// greets a first launch, when there is nothing to avoid deactivating.
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in the Info.plist already hides the Dock icon; this
        // keeps the behavior if the binary is ever run outside the bundle.
        NSApp.setActivationPolicy(.accessory)
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
            menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Errol", action: #selector(quit), keyEquivalent: "q").target = self
            if let button = statusItem.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 6), in: button)
            }
            return
        }
        togglePanel()
    }

    @objc private func quit() {
        relayControl.cancel()
        NSApp.terminate(nil)
    }

    // MARK: Panel

    /// Window chrome follows the compiled-in skin: classic keeps the original
    /// titled utility panel; glass and wireframe get a borderless transparent
    /// panel (glass so its Liquid Glass surfaces sample the desktop behind the
    /// window, wireframe so its painted paper card is the panel's edge; Esc
    /// still hides it, the header strip and bare paper drag it) whose frame
    /// animates with the console/companion morph.
    private func buildPanel() {
        let size = PanelLayout.size(style: activePanelStyle, compact: relay.compact,
                                    logOpen: relay.logOpen, steering: relay.isSteering,
                                    fullPrompt: relay.showsFullInstructionsEditor)
        switch activePanelStyle {
        case .classic:
            panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        case .glass, .wireframe:
            panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            // Carries the glass skin, whose surfaces float over window
            // background AppKit can see is unclaimed. The wireframe card
            // covers its whole window, so it names its own drag regions
            // (WireframePanelView.header) rather than trusting this.
            panel.isMovableByWindowBackground = true
            // Follow presentation changes with an animated frame change,
            // anchored top-center so the panel hangs from the status item.
            trackPanelLayout()
        }
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
        panel.contentView = NSHostingView(rootView: PanelRootView(controller: relay))
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
    }

    private func trackPanelLayout() {
        let rearm = MainQueueHop { [weak self] in self?.trackPanelLayout() }
        let size = withObservationTracking {
            PanelLayout.size(style: activePanelStyle, compact: relay.compact,
                             logOpen: relay.logOpen, steering: relay.isSteering,
                             fullPrompt: relay.showsFullInstructionsEditor)
        } onChange: {
            rearm.run()
        }
        guard size != lastPanelSize else { return }
        lastPanelSize = size
        resizePanel(to: size)
    }

    private func resizePanel(to size: CGSize) {
        guard let panel else { return }
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
            panel.setFrame(frame, display: true)
            return
        }
        // The animator proxy animates on the run loop, where the synchronous
        // setFrame(_:display:animate:) would hold the main thread inside a
        // nested animation loop for the whole 0.32s; a morph arriving
        // mid-flight retargets the animation instead of queueing behind it.
        // The duration paces the frame to the SwiftUI content animation.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
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

    /// The settings card wears the wireframe skin, so its window chrome
    /// follows the panel's: non-activating (typing works — KeyablePanel
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
            window.backgroundColor = NSColor(calibratedWhite: 0.94, alpha: 1)
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
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
