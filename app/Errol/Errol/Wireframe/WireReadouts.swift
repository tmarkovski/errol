// The head unit's two readouts, cut to the same height so they sit on one
// line: the gauge's needle on each participant card, and the odometer's
// drums in the middle counting turns.

import SwiftUI

/// A half-circle gauge; the needle rises while that side is composing.
/// `driven` then knocks it about that reading on the beat the card's border
/// is playing (WireRhythm), so the pair reads as one instrument under load
/// rather than as a moving outline around a value someone set by hand.
struct WireGauge: View {
    var level: Double
    var driven = false

    var body: some View {
        WireSweptGauge(reading: level, driven: driven)
            .animation(Self.sweep, value: level)
    }

    /// How the needle crosses to a new reading when the turn changes hands.
    /// A spring rather than the eased curves the rest of the panel moves
    /// on, because this is the one instrument that has already been given
    /// weight: a needle that slid to its new angle at an even speed and
    /// stopped dead there would hand that weight straight back. It rings at
    /// about the rate a hit rings it (WireRhythm), since it is the same
    /// needle, but damped far harder — a tap is small enough that a little
    /// hunting reads as a live instrument, while a swing across half the
    /// dial that hunted would read as one that cannot make up its mind.
    ///
    /// Nothing sweeps on the first draw, which is what `value:` buys: a
    /// panel opening on a needle winding up to its reading would be the
    /// instrument announcing itself, and every other part of this skin
    /// stays still until it has something to say.
    private static let sweep = Animation.spring(response: 0.34, dampingFraction: 0.72)
}

/// The reading, which is the part that sweeps. SwiftUI interpolates
/// `animatableData` across a handoff, so the gauge is handed readings part
/// way between the old and the new and simply draws them. The wobble is
/// deliberately not part of that: it sits on top, taken fresh each frame,
/// so a needle crossing to a new reading while being knocked about on the
/// way does both at once instead of one smearing the other.
private struct WireSweptGauge: View, Animatable {
    var reading: Double
    var driven: Bool

    var animatableData: Double {
        get { reading }
        set { reading = newValue }
    }

    var body: some View {
        if driven {
            WireKnockedNeedle(reading: reading)
        } else {
            WireGaugeFace(level: reading)
        }
    }
}

/// The needle while the side is composing. Like the pulsing bulb and the
/// speaker border, it owns its frame clock in a child that exists only
/// while there is something to show, so nothing is animating on an idle
/// panel — and it stamps its start in the same update that mounts the
/// border, which is the whole of what keeps the two in phase.
private struct WireKnockedNeedle: View {
    var reading: Double

    @State private var started = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            WireGaugeFace(level: reading + swing(at: timeline.date))
        }
    }

    /// Where the needle is sitting relative to its reading: every hit still
    /// sounding, summed. They stack the way the cone's do, so a needle
    /// caught mid-swing by the next beat is carried further than either hit
    /// would have taken it alone.
    private func swing(at now: Date) -> Double {
        let elapsed = now.timeIntervalSince(started)
        var swing = 0.0
        for beat in WireBeatTrack.beats {
            guard let age = WireBeatTrack.age(of: beat, elapsed: elapsed) else { continue }
            swing += beat.velocity * WireBeatTrack.knock(age)
        }
        return swing * Self.travel
    }

    /// What a full-velocity hit is worth as a share of the scale — about
    /// sixteen degrees of the gauge's half circle. Far enough to read as
    /// movement from as far back as the lamps do, near enough that the
    /// needle still plainly reads its value while it wobbles.
    private static let travel = 0.09
}

/// The drawn face, at whatever angle the needle is reading this frame.
private struct WireGaugeFace: View {
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
            // The clamp is the needle's end stops: the swing a driven gauge
            // adds is a share of the scale on top of a reading, so this is
            // what keeps it on the dial however the two come out.
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
