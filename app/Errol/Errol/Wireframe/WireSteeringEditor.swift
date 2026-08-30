// The steering note field. See WireframePanelView for the skin.

import SwiftUI

/// The steering editor: a note from the human, posted into the relay.
/// It rides the next handoff to whoever replies next, and is echoed to
/// the other side a turn later. Opening it holds the run the way Pause
/// does — the ghost stop and the PAUSED readout already narrate that —
/// and Send lets go again, unless the pause was the user's own.
/// Isolated with its own focus state so typing the note stays in this
/// scope.
struct WireSteeringEditor: View {
    @Bindable var controller: RelayController
    @FocusState private var steerFocus: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: Wire.s(8)) {
            TextField("Steer the conversation\u{2026}", text: $controller.steeringText,
                      axis: .vertical)
                .textFieldStyle(.plain)
                .font(Wire.text(11))
                .foregroundColor(Wire.ink)
                .lineLimit(1...3)
                .padding(.horizontal, Wire.s(8))
                .padding(.vertical, Wire.s(6))
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
                .focused($steerFocus)
                .onSubmit { controller.sendSteering() }
                .onExitCommand { controller.cancelSteer() }
            WireButton(label: "SEND", disabled: steeringNoteEmpty) {
                controller.sendSteering()
            }
            .help("Post the note; it reaches whoever replies next, and the other side a turn later")
            WireButton(label: "CANCEL", disabled: false) { controller.cancelSteer() }
                .help("Close without posting")
        }
        // Async because focus set in the same transaction that inserts the
        // field does not reliably land in an NSHostingView.
        .onAppear { DispatchQueue.main.async { steerFocus = true } }
    }

    private var steeringNoteEmpty: Bool {
        controller.steeringText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
