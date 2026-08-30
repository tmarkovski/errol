// The card's top row. See WireframePanelView for the skin.

import AppKit
import SwiftUI

/// The name-and-state line doubles as the card's title bar: the panel is
/// borderless, so this is the one strip that always drags the window no
/// matter what state the console is in. It asks for the drag outright
/// rather than relying on `isMovableByWindowBackground`, which only moves
/// a window when AppKit judges that nothing in the content wanted the
/// click — an inference that does not hold on every macOS release. Text
/// selection in the log and the instruction editor is untouched, because
/// the gesture lives here and on the bare paper, not over those.
struct WireHeader: View {
    let controller: RelayController

    var body: some View {
        // Split by what the two ends are about: the app's own name and the
        // way into its settings on the left, what the run is doing right now
        // on the right. The gear sat beside the state word before, which read
        // as one group and pushed the card's only live readout off the edge
        // every other readout is aligned to.
        HStack(spacing: Wire.s(6)) {
            Text("ERROL")
                .font(Wire.mono(8, .bold))
                .tracking(1.2)
                .foregroundColor(Wire.faint)
            settingsButton
            Spacer()
            Text(stateWord)
                .font(Wire.mono(8, .bold))
                .tracking(1.2)
                .foregroundColor(Wire.ink)
        }
        // Stated rather than inherited from whichever label is tallest, so
        // the strip is the gear's target and nothing else decides its height.
        .frame(height: Wire.s(20))
        // The Spacer between the two labels is empty; without a content
        // shape the middle of the strip would not take the press.
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    /// The way into the settings card, kept in the title strip so it is
    /// reachable in every console state, compact head unit included.
    ///
    /// The glyph stays small and unboxed — it is a utility, not one of the
    /// run controls, and drawing a rectangle around it would give it their
    /// weight — but the target it sits in is a deliberate square. This strip
    /// drags the window, so a miss here does not merely do nothing, it picks
    /// the panel up and slides it; the frame and content shape are what stand
    /// between a slightly-off click and a moved window. A button's own
    /// gesture outranks one attached with `.gesture`, so every press inside
    /// the square is the button's and not the drag's.
    private var settingsButton: some View {
        Button {
            controller.openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: Wire.s(11), weight: .bold))
                .foregroundColor(Wire.faint)
                .frame(width: Wire.s(20), height: Wire.s(20))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(WireHandCursor(active: true))
        .help("Edit the conversation shapes")
    }

    private var stateWord: String {
        if controller.isRunning {
            guard controller.isPaused else { return "IN RUN" }
            return controller.isHolding ? "PAUSED" : "PAUSING"
        }
        if bothEnded { return "DONE" }
        if bothReady { return "READY" }
        if [controller.chatgptStatus.state, controller.claudeStatus.state]
            .contains(.checking) { return "CHECKING" }
        return "PREP"
    }

    private var bothReady: Bool {
        controller.chatgptStatus.state == .ready && controller.claudeStatus.state == .ready
    }

    private var bothEnded: Bool {
        controller.chatgptConversation == .ended && controller.claudeConversation == .ended
    }
}
