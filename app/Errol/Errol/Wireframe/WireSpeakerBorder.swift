// The working card's border, played like a speaker: a rhythm track, and
// the Canvas that thumps the outline and throws rings on it.

import SwiftUI

/// One hit in the rhythm the working card's border plays to.
private struct WireBeat {
    /// Seconds into the loop.
    var onset: Double
    /// How hard this one lands, 0...1.
    var velocity: Double
}

/// The rhythm itself. A metronome would read as a progress indicator
/// ticking, so instead of one steady interval the track is a fixed loop of
/// hits on a sixteenth grid: the downbeats always land, and the offbeats
/// and the ghost notes between them are drawn from hash noise on the slot
/// number. That keeps a tempo — the card is plainly working — while no two
/// bars fall the same way, which is what stops the eye filing the border
/// away as decoration after the first few seconds.
///
/// The loop is built once and played forever, so the border's draw is a
/// pure function of the clock: nothing to keep in sync, nothing to wind
/// back when a card stops working and later starts again.
private enum WireBeatTrack {
    /// A sixteenth at roughly 100 BPM — fast enough to feel played, slow
    /// enough that one hit reads as a thump rather than a flicker.
    private static let slot = 0.15
    private static let slotsPerBar = 16
    private static let bars = 8
    static let period = Double(bars * slotsPerBar) * slot

    /// How long the cone takes to settle after a hit, and how long a ring
    /// takes to travel its full reach and go. The ring outlives the thump
    /// on purpose: the halo is still going out after the border has come
    /// back to rest, the way sound keeps leaving a driver that has already
    /// stopped moving. It is the shorter of the two by a lot, though — a
    /// ring that drifts out reads as a slow ripple on water, and what
    /// should read is a wavefront leaving under pressure.
    private static let thumpLife = 0.40
    static let ringLife = 0.62
    /// The snap outward. Short, because what makes a speaker read as struck
    /// rather than as breathing is that the rise is not symmetric with the
    /// fall — the breathing fade is the THINK bulb's job, one row down.
    private static let attack = 0.05

    static let beats: [WireBeat] = {
        var out: [WireBeat] = []
        for index in 0 ..< (bars * slotsPerBar) {
            let position = index % slotsPerBar
            let roll = noise(index)
            let velocity: Double = switch position {
            // The bar's downbeat and its half are always struck, so the
            // tempo survives however the noise falls around them.
            case 0: 1.0
            case 8: 0.74
            // Then the quarters, the eighths, and the sixteenths between
            // them — each rung less likely to sound, and softer when it does.
            case 4, 12: roll < 0.72 ? 0.52 : 0
            case 2, 6, 10, 14: roll < 0.40 ? 0.36 : 0
            default: roll < 0.20 ? 0.24 : 0
            }
            if velocity > 0 {
                out.append(WireBeat(onset: Double(index) * slot, velocity: velocity))
            }
        }
        return out
    }()

    /// Seconds since a hit landed, or nil if it is not currently sounding.
    /// The first pass through the loop refuses to wrap, so a card that has
    /// just started working opens on its own downbeat instead of walking in
    /// on whatever the tail of the bar was still playing.
    static func age(of beat: WireBeat, elapsed: Double) -> Double? {
        var age = elapsed.truncatingRemainder(dividingBy: period) - beat.onset
        if age < 0 {
            guard elapsed >= period else { return nil }
            age += period
        }
        return age < ringLife ? age : nil
    }

    /// One hit's share of the cone's excursion: out over the attack, then
    /// falling back along a curve that goes slack at the end rather than
    /// arriving flat.
    static func thump(_ age: Double) -> Double {
        guard age < thumpLife else { return 0 }
        if age < attack { return age / attack }
        return pow(1 - (age - attack) / (thumpLife - attack), 2.2)
    }

    /// Hash noise rather than a random number generator: the loop has to
    /// come out identical every time the app builds it, or the rhythm would
    /// be a different instrument on every launch.
    private static func noise(_ index: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: index &* 0x9E37_79B1 &+ 0x632B_E59B)
        x ^= x >> 33
        x = x &* 0xFF51_AFD7_ED55_8CCD
        x ^= x >> 33
        x = x &* 0xC4CE_B9FE_1A85_EC53
        x ^= x >> 33
        return Double(x & 0xFF_FFFF) / Double(0x100_0000)
    }
}

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
