// The working card's border, played like a speaker: the Canvas that thumps
// the outline and throws rings on it, on the beat WireRhythm keeps.

import SwiftUI

/// The working card's border, played like a speaker. The outline is the
/// cone: it snaps outward and thickens on every hit and settles back
/// between them. Each hit also throws a ring off the card's edge that
/// travels out and fades, the way a wavefront leaves the driver. Solid ink
/// stated "this side is composing" accurately and quietly, and quietly was
/// the problem — two cards differing only in stroke color make a person
/// compare them to find the working one, which is the single thing the
/// head unit exists to say without being read.
///
/// Drawn in one Canvas over the card rather than as a stack of animated
/// shapes: every ring in flight is a stroke recomputed from the clock, so
/// this is one render node with no per-ring view to mount, animate, and
/// tear down on each beat. Everything but the instant it started is a
/// function of elapsed time.
///
/// Like the pulsing bulb, it lives in a child that exists only while the
/// side is composing, so the frame clock stops when the state does.
struct WireSpeakerBorder: View {
    /// How far past the card's edge the outermost ring gets before it is
    /// gone. The head unit spaces the cards from the center deck by s(14)
    /// and the panel pads the card by s(16), so a ring at full reach travels
    /// into the gap and still stops short of what is on the other side.
    private static let reach = Wire.s(8)
    /// The cone's travel at a full-velocity hit, and the ink it puts on at
    /// rest. Kept near the s(1) of every other stroke on the card so the
    /// pulse is what draws the eye, not a permanently heavier outline.
    private static let excursion = Wire.s(1.5)

    @State private var started = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let elapsed = timeline.date.timeIntervalSince(started)
                let card = CGRect(origin: .zero, size: size)
                    .insetBy(dx: Self.reach, dy: Self.reach)
                let corner = Wire.boxCorner
                var drive = 0.0

                for beat in WireBeatTrack.beats {
                    guard let age = WireBeatTrack.age(of: beat, elapsed: elapsed)
                    else { continue }
                    drive += beat.velocity * WireBeatTrack.thump(age)

                    // The wavefront: outward at a speed set by how hard the
                    // hit was, thinning and fading the whole way out.
                    // Velocity counts against the fade harder than it does
                    // against the distance, so a ghost note is a flicker at
                    // the edge while a downbeat throws a ring across the gap.
                    let travel = age / WireBeatTrack.ringLife
                    let out = travel * Self.reach * (0.55 + 0.45 * beat.velocity)
                    let fade = pow(1 - travel, 1.4) * pow(beat.velocity, 1.6) * 0.9
                    ctx.stroke(Path(roundedRect: card.insetBy(dx: -out, dy: -out),
                                    cornerRadius: corner + out),
                               with: .color(Wire.ink.opacity(fade)),
                               lineWidth: Wire.s(1.5) * (1 - 0.5 * travel))
                }

                // The cone. Hits stack rather than replace each other — two
                // notes close together push it further out than either would
                // alone — so the sum is clamped rather than taken as a max.
                let push = min(1, drive) * Self.excursion
                ctx.stroke(Path(roundedRect: card.insetBy(dx: -push, dy: -push),
                                cornerRadius: corner + push),
                           with: .color(Wire.ink.opacity(0.8 + 0.2 * min(1, drive))),
                           lineWidth: Wire.s(1) + Wire.s(2) * min(1, drive))
            }
        }
        // The overlay is handed the card's own size; the negative padding is
        // what gives the Canvas margin to put the halo in, since a Canvas
        // clips to its frame. An overlay never lays out its parent, so
        // nothing on the card moves to make room.
        .padding(-Self.reach)
        .allowsHitTesting(false)
    }
}
