// The busy shimmer: a sheen of near-white sweeping through a line of text,
// masked to the glyphs, for the one line that means "working" —
// the perch subline while its side is composing. Off it is plain text, and
// under Reduce Motion it stays plain text.

import SwiftUI

struct PerchShimmer: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if active, !reduceMotion {
                PerchShimmerBand()
                    .mask(content)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// The band itself: a gradient whose highlight travels from beyond the
/// leading edge to beyond the trailing one, then starts over. Its state
/// lives here so the sweep begins fresh each time the shimmer switches on.
private struct PerchShimmerBand: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                // A near-white sheen: on the muted gray it reads as light
                // passing over the letters, where a darker band barely
                // registered.
                .init(color: .white.opacity(0.9), location: 0.5),
                .init(color: .clear, location: 1),
            ],
            startPoint: UnitPoint(x: phase - 1, y: 0.5),
            endPoint: UnitPoint(x: phase, y: 0.5))
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 2
            }
        }
    }
}

extension View {
    /// The busy shimmer over this text while `active`.
    func perchShimmer(active: Bool) -> some View {
        modifier(PerchShimmer(active: active))
    }
}
