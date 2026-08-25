// The AppKit shell around the SwiftUI interface: the status item (an owl,
// hidden until clicked) and the floating panel that hosts ControlPanelView.
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
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class MenuBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: KeyablePanel!
    private let relay = RelayController()
    private var iconWatcher: AnyCancellable?

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

    private func buildPanel() {
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
                             styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.title = "Errol"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ControlPanelView(controller: relay))
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
        if let visible = screen?.visibleFrame {
            x = max(visible.minX + 8, min(x, visible.maxX - panel.frame.width - 8))
        }
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: buttonFrame.minY - 8))
    }
}
