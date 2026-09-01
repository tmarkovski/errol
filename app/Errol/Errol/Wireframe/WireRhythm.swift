// The rhythm a working card plays to, in one place because two instruments
// move on it: the card's border, which thumps like a speaker cone
// (WireSpeakerBorder), and the gauge needle beside it, which gets knocked
// about its reading by the same hits (WireReadouts).

import Foundation

/// One hit in the rhythm the working card plays to.
struct WireBeat {
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
/// The loop is built once and played forever, so an instrument's draw is a
/// pure function of the clock: nothing to keep in sync, nothing to wind
/// back when a card stops working and later starts again. That is also
/// what keeps the border and the needle on the same beat without either
/// one telling the other anything — they mount together when the side
/// starts composing, stamp the same instant, and read this one track from
/// it.
enum WireBeatTrack {
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
    /// The window is the ring's, the longest-lived of the three things a
    /// hit sets going, so every instrument can share one gate — the cone
    /// and the needle have both come to rest well inside it.
    ///
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

    /// One hit's share of the needle's swing. The cone is driven straight
    /// off `thump` because a cone only moves the way it is pushed, but a
    /// needle hangs on a hairspring and carries its own weight: the same
    /// hit throws it past where it was reading, back through that angle,
    /// and around again a little smaller each time until the wobble dies.
    /// Signed, so the swing straddles the value rather than lifting it, and
    /// so the needle is still reading what it was reading before the hit.
    ///
    /// Its crest lands a shade after the cone's, which is the point of
    /// giving the needle weight: the border snaps and the needle catches up.
    static func knock(_ age: Double) -> Double {
        exp(-age / swingLife) * sin(swingRate * age) / swingCrest
    }

    /// How fast the needle rings, in radians a second, and how quickly that
    /// ringing dies. A little over three swings a second, spent inside half
    /// of one: a needle still ringing when the next hit lands reads as a
    /// shiver rather than as an instrument being struck.
    private static let swingRate = 2 * Double.pi * 3.2
    private static let swingLife = 0.16

    /// `knock`'s own crest, divided back out of it, so the swing a caller
    /// asks for is the swing a full-velocity hit actually gives it.
    private static let swingCrest: Double = {
        let crest = atan(swingRate * swingLife) / swingRate
        return exp(-crest / swingLife) * sin(swingRate * crest)
    }()

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
