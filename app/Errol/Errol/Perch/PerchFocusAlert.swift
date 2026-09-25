// The call to bring a chat app forward, over the whole console. When an
// app will not come to the front for the relay (RunBlock.notInFront), the
// run stands until the human clicks its window, and nothing else on the
// console matters meanwhile. So the ask covers the capsule, with the
// console showing faintly through it, and fades out once the app is in
// front and the run moves on.
//
// There is no countdown: the wait has no timeout of its own, and the
// reply timeout does not count while a run stands on a block. Stop stays
// within reach at the trailing end, since nothing else ends a run whose
// app will not come forward.

import SwiftUI

struct PerchFocusAlert: View {
    let controller: RelayController
    let side: Speaker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How the alert comes and goes over the console.
    static let fade = Animation.easeInOut(duration: 0.3)

    /// The side to bring forward, while the run stands on it and the alert
    /// would cover nothing the human needs: not while the note is being
    /// written, whose editor it would hide, and not once Stop is pressed.
    static func side(for controller: RelayController) -> Speaker? {
        guard controller.stage == .running, !controller.isSteering, !controller.stopRequested,
              case .notInFront(let side)? = controller.block else { return nil }
        return side
    }

    private var name: String { controller.appName(side) }

    var body: some View {
        HStack(spacing: 0) {
            // Empty, so the ask centers between the participants' columns.
            Color.clear.frame(width: Perch.participantWidth)
            Spacer(minLength: Perch.s(12))
            HStack(spacing: Perch.s(18)) {
                beacon
                VStack(alignment: .leading, spacing: Perch.s(5)) {
                    Text("Please focus \(name) to continue the conversation")
                        .font(Perch.text(19, .medium))
                        .foregroundStyle(Perch.ink)
                    Text("Click \(name)\u{2019}s window. Errol continues on its own once it is in front.")
                        .font(Perch.text(12))
                        .foregroundStyle(Perch.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: Perch.s(12))
            PerchRoundButton(title: "Stop", icon: "stop.fill", prominent: false) { controller.stop() }
                .help("Stop at the next safe point")
                .frame(width: Perch.participantWidth)
        }
        .padding(.horizontal, Perch.s(28))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The wash takes every click the console would have, and still
        // drags the window like the bare surface under it.
        .background(Perch.shell.opacity(0.74).contentShape(Rectangle()).gesture(WindowDragGesture()))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// The app's icon, with a ring that keeps swelling off it until the
    /// app is in front. Under Reduce Motion the icon stands alone.
    private var beacon: some View {
        let bundleID = side == .chatgpt ? config.chatgptBundleID : config.claudeBundleID
        let feather = side == .claude ? Perch.claudeFeather : Perch.chatgptFeather
        return PerchAvatar(bundleID: bundleID, initial: String(name.prefix(1)), feather: feather)
            .background {
                if !reduceMotion { PerchFocusRing() }
            }
            .accessibilityHidden(true)
    }
}

/// One ring at a time, in the icon's squircle, growing out of it and
/// fading as it goes. Its state lives here so the swell starts fresh each
/// time the alert comes up.
private struct PerchFocusRing: View {
    @State private var swelling = false

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: proxy.size.width * 0.225, style: .continuous)
                .stroke(Perch.accent, lineWidth: Perch.s(2))
                .scaleEffect(swelling ? 1.5 : 1)
                .opacity(swelling ? 0 : 0.7)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                swelling = true
            }
        }
    }
}
