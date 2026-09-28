// The run's transcript (PerchTranscript) in its window under the console:
// when it stands there, where it goes, and how it comes and goes. Its own
// file, apart from the menu-bar shell that owns the console, because the
// window is a child of the console's and follows only from it — the shell
// hands over the console, a way to bring it forward, and whether its
// frame is still animating, and calls in at each showing, hiding, move
// and resize of the console.

import AppKit
import Observation
import SwiftUI

final class TranscriptPanelController {
    private let relay: RelayController
    private let navigation: PanelNavigation
    /// The console's panel, which the transcript is a child of.
    private let console: NSPanel
    /// Whether the console's frame is still animating to a new size: the
    /// transcript waits for it to settle (show).
    private let isConsoleResizing: () -> Bool
    /// The console, forward and key, for Escape in the transcript.
    private let showConsole: () -> Void
    /// The transcript's window, under the console: a child of the panel,
    /// so it goes where the console is dragged and is put away with it.
    /// Made at the first run.
    private var panel: NSPanel?
    /// A count of the transcript's fades, so a hide whose fade is still
    /// going does not finish over a show that came after it.
    private var fade = 0

    init(relay: RelayController, navigation: PanelNavigation, console: NSPanel,
         isConsoleResizing: @escaping () -> Bool, showConsole: @escaping () -> Void) {
        self.relay = relay
        self.navigation = navigation
        self.console = console
        self.isConsoleResizing = isConsoleResizing
        self.showConsole = showConsole
    }

    /// The transcript stands under the console from a run's start until
    /// New topic clears its ending, while the console is up and on its
    /// own screen (not the permission ask). Read again at each
    /// change of stage or screen, and at each showing or hiding of the
    /// console.
    func track() {
        let rearm = MainQueueHop { [weak self] in self?.track() }
        withObservationTracking {
            _ = relay.stage
            _ = navigation.screen
        } onChange: {
            rearm.run()
        }
        update()
    }

    func update() {
        let wanted = relay.stage != .compose && navigation.screen == .console && console.isVisible
        if wanted { show() } else { hide() }
    }

    /// A borderless, non-activating panel like the console's, transparent
    /// so the card's paper is its silhouette, and with the console's kind
    /// of shadow around that silhouette, rim and all
    /// (MenuBarController.buildPanel), so it stands apart from the chat
    /// windows under it the way the console does. The shadow is AppKit's
    /// rather than drawn in the card, so the window stays the card's size
    /// and a click beside the card reaches the window under it. It cannot
    /// become key, so a click or a scroll in it never takes the keyboard
    /// from the console's field, and it never moves on its own: it goes
    /// where the console is dragged.
    private func makePanel() -> NSPanel {
        let transcript = KeyablePanel(contentRect: NSRect(origin: .zero,
                                                     size: NSSize(width: 1, height: PerchTranscript.height)),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        transcript.permitsKey = { [weak self] in self?.relay.consoleAccess.canTakeFocus ?? false }
        transcript.onCancel = { [weak self] in
            self?.showConsole()
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
        transcript.level = console.level
        transcript.collectionBehavior = console.collectionBehavior
        let host = FirstMouseHostingView(rootView: PerchTranscript(controller: relay))
        // The window is the one thing that sizes the card (place).
        host.sizingOptions = []
        transcript.contentView = host
        return transcript
    }

    /// Under the console, centered on it, a gap below the capsule and as
    /// wide as the prompt box inside it, so it stands as the box's
    /// continuation — or over the console, when the screen ends before
    /// there is room under it.
    func place() {
        guard let transcript = panel, transcript.parent != nil else { return }
        let consoleFrame = console.frame
        let size = NSSize(width: PerchMetrics.promptBoxWidth(consoleWidth: consoleFrame.width).rounded(),
                          height: PerchTranscript.height.rounded())
        var origin = NSPoint(x: (consoleFrame.midX - size.width / 2).rounded(),
                             y: (consoleFrame.minY - PerchTranscript.gap - size.height).rounded())
        if let visible = (console.screen ?? NSScreen.main)?.visibleFrame, origin.y < visible.minY {
            origin.y = (consoleFrame.maxY + PerchTranscript.gap).rounded()
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
    private func show() {
        guard !isConsoleResizing() else { return }
        let transcript = panel ?? makePanel()
        panel = transcript
        fade += 1
        if transcript.parent == nil {
            transcript.alphaValue = 0
            // Adding the child orders it in with the console.
            console.addChildWindow(transcript, ordered: .above)
        }
        place()
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
    private func hide() {
        guard let transcript = panel, transcript.parent != nil else { return }
        fade += 1
        let ticket = fade
        let putAway = { [weak self] in
            guard let self, self.fade == ticket, let transcript = self.panel else { return }
            self.console.removeChildWindow(transcript)
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
}
