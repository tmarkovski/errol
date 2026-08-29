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
import Combine
import SwiftUI

/// NSPanel refuses key status in some non-activating configurations, which
/// would make the instruction field untypeable; force it. Esc hides the
/// panel instead of beeping.
final class KeyablePanel: NSPanel {
    /// Fires on every path the panel appears or disappears through — toggle,
    /// Esc, the close button — so the readiness scanner tracks visibility.
    var onVisibilityChange: ((Bool) -> Void)?

    override var canBecomeKey: Bool { true }
    /// Frame changes (the console/companion morph) pace themselves to the
    /// SwiftUI content animation.
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.32 }
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

final class MenuBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: KeyablePanel!
    private let relay = RelayController()
    private var iconWatcher: AnyCancellable?
    private var layoutWatcher: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in the Info.plist already hides the Dock icon; this
        // keeps the behavior if the binary is ever run outside the bundle.
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        buildPanel()
        logSink = { [relay] line in
            DispatchQueue.main.async { relay.append(line) }
        }
        iconWatcher = relay.$isRunning.sink { [weak self] running in
            self?.statusItem.button?.image = self?.statusIcon(running: running)
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
        NSImage(systemSymbolName: running ? "bird.fill" : "bird", accessibilityDescription: "Errol")
            ?? NSImage(systemSymbolName: "paperplane", accessibilityDescription: "Errol")
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Transcript", action: #selector(openTranscript), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Restore Window Positions", action: #selector(restoreWindows), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Errol", action: #selector(quit), keyEquivalent: "q").target = self
            if let button = statusItem.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 6), in: button)
            }
            return
        }
        togglePanel()
    }

    @objc private func openTranscript() {
        relay.openTranscript()
    }

    @objc private func restoreWindows() {
        relay.restoreWindows()
    }

    @objc private func quit() {
        relayCancelled.set(true)
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
                                    logOpen: relay.logOpen)
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
            layoutWatcher = Publishers.CombineLatest(relay.$compact, relay.$logOpen)
                .map { PanelLayout.size(style: activePanelStyle, compact: $0, logOpen: $1) }
                .removeDuplicates()
                .sink { [weak self] size in self?.resizePanel(to: size) }
        }
        panel.title = "Errol"
        panel.onVisibilityChange = { [relay] visible in relay.setPanelVisible(visible) }
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PanelRootView(controller: relay))
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
        panel.setFrame(frame, display: true, animate: panel.isVisible)
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
}
