// The prompt box's mic, beside Start relay and Resume: a press fills the
// field above it with what the human says (VoiceInput), and another press
// finishes. It is a circle of Liquid Glass the size of the capsule beside
// it, clear at rest; while the microphone is open the glass takes the
// accent, the mark filled, and a ring breathes out from it, so it reads as live the way the
// menu bar's orange dot does. The line under the box says what it is doing.

import SwiftUI

struct PerchMicButton: View {
    let controller: RelayController
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: VoiceInput.Phase { controller.voice.phase }
    /// The microphone is open, or its last words are settling.
    private var live: Bool { phase == .listening || phase == .finishing }

    var body: some View {
        Button { controller.toggleVoice() } label: {
            // Set in text: as an image inside the console, symbols came out
            // white in the offscreen renders, while a symbol in text keeps
            // its ink (PerchChipLabel).
            Text(Image(systemName: live ? "mic.fill" : "mic"))
                .font(Perch.text(12, .semibold))
                .foregroundStyle(live ? Perch.onAccent : phase == .starting ? Perch.accentText : Perch.secondary)
                .frame(width: Perch.capsuleHeight, height: Perch.capsuleHeight)
                .perchGlassButton(prominent: live, in: Circle())
                .background { if phase == .listening && !reduceMotion { Breath() } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(Perch.fade, value: phase)
        .help(live ? "Finish dictating" : "Dictate instead of typing")
        .accessibilityLabel(live ? "Finish dictating" : "Dictate")
        // The field it fills is going: the run started, the note was sent,
        // or the box closed some other way.
        .onDisappear { controller.voice.cancel() }
    }

    /// A ring of the accent that grows out of the button and fades, over
    /// and over, while the microphone is open.
    private struct Breath: View {
        @State private var out = false

        var body: some View {
            Circle()
                .stroke(Perch.accent, lineWidth: 1.5)
                .scaleEffect(out ? 1.45 : 1)
                .opacity(out ? 0 : 0.7)
                .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: out)
                .onAppear { out = true }
                .allowsHitTesting(false)
        }
    }
}
