// The head unit's two readouts, cut to the same height so they sit on one
// line: the gauge's needle on each participant card, and the odometer's
// drums in the middle counting turns.

import SwiftUI

/// A half-circle gauge; the needle rises while that side is composing.
struct WireGauge: View {
    var level: Double

    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height - Wire.s(3))
            let r = min(sz.width / 2 - Wire.s(4), sz.height - Wire.s(8))
            var arc = Path()
            arc.addArc(center: c, radius: r,
                       startAngle: .degrees(180), endAngle: .degrees(360),
                       clockwise: false)
            ctx.stroke(arc, with: .color(Wire.faint),
                       style: StrokeStyle(lineWidth: Wire.s(3), lineCap: .round))
            for i in 0...4 {
                let a = Angle.degrees(180 + Double(i) * 45).radians
                var tick = Path()
                tick.move(to: CGPoint(x: c.x + cos(a) * (r - Wire.s(6)),
                                      y: c.y + sin(a) * (r - Wire.s(6))))
                tick.addLine(to: CGPoint(x: c.x + cos(a) * (r - Wire.s(2)),
                                         y: c.y + sin(a) * (r - Wire.s(2))))
                ctx.stroke(tick, with: .color(Wire.faint.opacity(0.7)), lineWidth: Wire.s(1))
            }
            let a = Angle.degrees(180 + 180 * min(max(level, 0), 1)).radians
            var hand = Path()
            hand.move(to: c)
            hand.addLine(to: CGPoint(x: c.x + cos(a) * (r - Wire.s(8)),
                                     y: c.y + sin(a) * (r - Wire.s(8))))
            ctx.stroke(hand, with: .color(Wire.ink),
                       style: StrokeStyle(lineWidth: Wire.s(2), lineCap: .round))
            let hub = Wire.s(6)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - hub / 2, y: c.y - hub / 2,
                                            width: hub, height: hub)),
                     with: .color(Wire.ink))
        }
        .frame(width: Wire.s(54), height: Wire.s(32))
    }
}

/// Boxed rolling digits: the turn counter. Sized to stand as the middle
/// column's instrument rather than as a caption between the two gauges —
/// the drums are cut to the gauge's own height (WireGauge), so the three
/// readouts across the top of the head unit sit on one line and the turn
/// count is legible from as far back as the lamps are.
struct WireOdometer: View {
    var value: Int
    var digits = 2

    var body: some View {
        HStack(spacing: Wire.s(3)) {
            let padded = String(format: "%0\(digits)d", value)
            ForEach(Array(padded.enumerated()), id: \.offset) { _, ch in
                WireDigitWheel(digit: ch)
            }
        }
    }
}

/// One counter wheel. A changed digit rolls up out of its window while the
/// next rolls in underneath, the way the drums in a mechanical counter turn.
/// Drums only turn one way, so a count that jumps backward — a new run
/// resetting to zero — rolls upward too rather than running in reverse.
private struct WireDigitWheel: View {
    /// The drum face. Named because the sliding digit and the window it
    /// slides behind have to be cut to the same rectangle, and the height
    /// is the gauge's so the head unit's three instruments align.
    private static let face = CGSize(width: Wire.s(24), height: Wire.s(32))

    var digit: Character

    private var window: RoundedRectangle { RoundedRectangle(cornerRadius: Wire.s(5)) }

    var body: some View {
        ZStack {
            Text(String(digit))
                .font(Wire.mono(20, .bold))
                .foregroundColor(Wire.paper)
                // A full-box frame makes the slide a whole drum face, so the
                // outgoing digit is gone before the incoming one appears.
                .frame(width: Self.face.width, height: Self.face.height)
                .id(digit)
                .transition(.asymmetric(insertion: .move(edge: .bottom),
                                        removal: .move(edge: .top)))
        }
        .frame(width: Self.face.width, height: Self.face.height)
        .background(window.fill(Wire.ink))
        .clipShape(window)
        // The drum's seam, which is what makes a counter read as turned
        // rather than typed. It stays a hairline as the drum grows — a seam
        // that scaled with the face would read as a painted stripe.
        .overlay(Rectangle().fill(Wire.paper.opacity(0.16)).frame(height: Wire.s(0.75)))
        .animation(.easeInOut(duration: 0.3), value: digit)
    }
}
