// The wireframe instrument skin (see PanelRootView for skin selection):
// DesignMockups' Option A made real. The study's rule carries over as the
// design itself — every state is legible from lamps, needles, counters,
// and labels alone; four grays, no glow, no chassis color. The exceptions
// are the two signal lamps in the old machine-panel idiom — the readiness
// lamp burning red, amber, or green, and THINK an orange bulb breathing
// while a side composes; everything they say is still said in words on the
// nameplate below them, so the rule holds. The working side's card keeps
// the palette and spends motion instead: its border is played like a
// speaker, thumping and throwing rings on an irregular beat, so the busy
// actor is the one thing on the panel that moves. The panel window is
// borderless (MenuBarController), so the paper card this view paints is
// the panel's own edge.
//
// Idle, the full console shows the instrument head, the conversation
// setup, run options, and the log. Starting a run shrinks the panel to
// the head unit alone (controller.compact drives the AppKit frame change;
// PanelLayout has the sizes). EXPAND brings the full console back mid-run
// with the setup rows disabled.
//
// The skin is split into child views along update boundaries, not visual
// ones: the controller is Observable, so each struct re-renders only for
// the properties its own body read. The editor sits in its own scope so a
// keystroke never touches the instruments, and the log well owns the one
// list that grows. Extracted computed properties would not do this — only
// a child struct starts a new observation scope.

import AppKit
import SwiftUI

// MARK: - Palette

/// The skin draws from four grays, plus the lens colors the two signal
/// lamps burn — the muted red, jade green, and orange of old equipment
/// panels rather than screen primaries.
/// Internal, not private: the settings card (SettingsView) speaks the same
/// idiom from these tokens.
enum Wire {
    static let ink = Color(white: 0.20)
    static let faint = Color(white: 0.52)
    static let paper = Color(white: 0.94)
    static let well = Color(white: 0.885)

    /// Every length and type size on the card is a study measurement put
    /// through `s`, so this one number sets how large the instrument reads.
    /// The study drew at 1.0 and came out cramped on a laptop display.
    static let scale: CGFloat = 1.2
    static func s(_ points: CGFloat) -> CGFloat { points * scale }
    /// Instrument type: monospaced, scaled with everything else.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: s(size), weight: weight, design: .monospaced)
    }
    /// The few proportional strings — what a person types, and the topic.
    static func text(_ size: CGFloat) -> Font { .system(size: s(size)) }

    /// The fixed card size; the panel adds the outer padding. Expanded, the
    /// card height is pinned and the log absorbs the difference between the
    /// topic field and the taller custom-instructions editor; compact, the
    /// card hugs the head unit.
    static let cardWidth = s(480)
    static let expandedCardHeight = s(560)
    /// The shadow's room around the card, a side.
    static let cardMargin = s(14)
}

/// The window frames the skin needs, derived from the card itself so the
/// panel grows with `Wire.scale` instead of drifting from it. PanelLayout
/// hands these straight through. The compact card is content-sized, so its
/// height carries slack.
enum WireframeMetrics {
    static let expandedPanel = CGSize(width: Wire.cardWidth + 2 * Wire.cardMargin,
                                      height: Wire.expandedCardHeight + 2 * Wire.cardMargin)
    static let compactPanel = CGSize(width: expandedPanel.width, height: Wire.s(252))
    /// The compact window with the steering editor's row added — sized for
    /// the field at its three-line tallest. Expanded needs no counterpart:
    /// the card height is pinned and the log absorbs the editor's row.
    static let compactSteeringPanel = CGSize(width: expandedPanel.width,
                                             height: Wire.s(318))
}

// MARK: - Instrument parts

/// The pointing-hand cursor over a control, but only while the control does
/// something. Tracks its own push so a view that never pushed never pops
/// somebody else's cursor off the stack.
private struct WireHandCursor: ViewModifier {
    var active: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, active, !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            // A panel that closes under the cursor never gets its hover exit.
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

/// The courier: an open bead riding the route, with a pointer swinging out
/// of it toward the side the next message is bound for. The arm is drawn
/// pointing right and turned around by rotation, so a handoff reads as one
/// pointer swinging over rather than as an arrow blinking out on one side
/// and in on the other.
///
/// Outside a run the courier is also the control that aims it. A click turns
/// it around. Holding it opens the bead, and letting go spins the pointer
/// like a roulette wheel that coasts to a stop on a side at random — for the
/// conversations where who opens is worth not deciding.
private struct WireCourier: View {
    /// Where the next message is bound: the pointer's resting angle.
    var pointsRight: Bool
    /// False only in the one state with no next message.
    var showsPointer: Bool
    /// Whether the courier can be aimed, which is to say: outside a run.
    var interactive: Bool
    /// A plain click turns the courier around.
    var onFlip: () -> Void
    /// The roulette's verdict, handed over as the wheel stops.
    var onRoulette: (Speaker) -> Void

    /// How long the bead has to be held before the roulette arms, and how
    /// long the wheel then takes to coast down.
    private static let chargeSeconds = 1.4
    private static let spinSeconds = 2.4

    /// Turns the roulette has wound on. It is never wound back: whole turns
    /// are visually identity, and leaving the last partial turn in place is
    /// what lets the nomination land without the pointer twitching.
    @State private var spin: Double = 0
    /// 0 with the bead at rest, 1 with it fully open under a held click.
    @State private var charge: CGFloat = 0
    @State private var armed = false
    @State private var spinning = false
    @State private var chargeTask: Task<Void, Never>?

    /// The pointer's total rotation. Both the ordinary handoff swing and the
    /// roulette move this one number, which is why the spin can hand over to
    /// a new nomination without a seam.
    private var angle: Double { spin + (pointsRight ? 0 : 180) }

    var body: some View {
        ZStack {
            pointer
                .rotationEffect(.degrees(angle))
                .opacity(showsPointer ? 1 : 0)
                .animation(spinning ? .timingCurve(0.1, 0.72, 0.18, 1,
                                                   duration: Self.spinSeconds)
                                    : .easeInOut(duration: 0.45),
                           value: angle)
            Circle()
                .fill(Wire.paper)
                .overlay(Circle().stroke(Wire.ink, lineWidth: Wire.s(1.5)))
                .frame(width: Wire.s(10 + 9 * charge), height: Wire.s(10 + 9 * charge))
        }
        .frame(width: Wire.s(44), height: Wire.s(36))
        // The arrowhead alone is a miserable target; the whole bead and arm
        // take the press.
        .contentShape(Rectangle())
        .gesture(press)
        .modifier(WireHandCursor(active: interactive && !spinning))
        .help(interactive ? "Click to turn the courier around, or hold it" : "")
    }

    private var pointer: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let style = StrokeStyle(lineWidth: Wire.s(1.5), lineCap: .round, lineJoin: .round)
            var arm = Path()
            arm.move(to: CGPoint(x: c.x + Wire.s(7), y: c.y))
            arm.addLine(to: CGPoint(x: c.x + Wire.s(18), y: c.y))
            ctx.stroke(arm, with: .color(Wire.ink), style: style)
            var head = Path()
            head.move(to: CGPoint(x: c.x + Wire.s(14), y: c.y - Wire.s(4)))
            head.addLine(to: CGPoint(x: c.x + Wire.s(18), y: c.y))
            head.addLine(to: CGPoint(x: c.x + Wire.s(14), y: c.y + Wire.s(4)))
            ctx.stroke(head, with: .color(Wire.ink), style: style)
        }
    }

    /// One gesture covers both moves, because they begin the same way: a
    /// quick click turns the courier around, and a click held past the charge
    /// time releases into a spin instead. A drag with no minimum distance is
    /// what gives the press a beginning and an end; a long-press gesture
    /// reports neither.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard interactive, !spinning, chargeTask == nil else { return }
                chargeTask = Task { @MainActor in
                    withAnimation(.easeIn(duration: Self.chargeSeconds)) { charge = 1 }
                    try? await Task.sleep(for: .seconds(Self.chargeSeconds))
                    if !Task.isCancelled { armed = true }
                }
            }
            .onEnded { _ in
                chargeTask?.cancel()
                chargeTask = nil
                guard interactive, !spinning else { return }
                if armed {
                    armed = false
                    startRoulette()
                } else {
                    withAnimation(.easeOut(duration: 0.18)) { charge = 0 }
                    onFlip()
                }
            }
    }

    private func startRoulette() {
        spinning = true
        let winner: Speaker = Bool.random() ? .chatgpt : .claude
        let landing: Double = winner == .claude ? 0 : 180
        // The wheel's own overshoot: whole turns for the show, plus the part
        // turn that leaves the pointer on the winning side.
        let delta = landing - (pointsRight ? 0 : 180)
        spin += 360 * Double(Int.random(in: 3...5)) + delta
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.spinSeconds))
            // Unwind exactly the part of the spin the nomination is about to
            // account for, so `angle` comes out unchanged and the pointer
            // does not move when the panel adopts the winner.
            var settle = Transaction()
            settle.disablesAnimations = true
            withTransaction(settle) {
                spin -= delta
                spinning = false
                onRoulette(winner)
            }
            withAnimation(.easeOut(duration: 0.3)) { charge = 0 }
        }
    }
}

/// A half-circle gauge; the needle rises while that side is composing.
private struct WireGauge: View {
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

/// A colored bulb behind glass: a bright filament core inside deeper glass,
/// or the cloudy tint of the same lens with nothing lit behind it.
private struct WireLens {
    var core: Color
    var glass: Color

    static let green = WireLens(core: Color(red: 0.60, green: 0.92, blue: 0.53),
                                glass: Color(red: 0.11, green: 0.42, blue: 0.19))
    static let amber = WireLens(core: Color(red: 0.99, green: 0.80, blue: 0.38),
                                glass: Color(red: 0.54, green: 0.33, blue: 0.04))
    static let red = WireLens(core: Color(red: 0.97, green: 0.42, blue: 0.26),
                              glass: Color(red: 0.51, green: 0.09, blue: 0.06))
    static let orange = WireLens(core: Color(red: 1.00, green: 0.78, blue: 0.30),
                                 glass: Color(red: 0.72, green: 0.37, blue: 0.02))
}

/// The drawn face of a lamp. A pulsing lamp animates both the bulb opacity
/// and the halo's color, so these two properties deliberately share one
/// state without owning the animation that drives it.
private struct WireLampFace: View {
    var lens: WireLens?
    var dimmed: Bool

    /// Filament off-center, the way a bulb sits behind its lens.
    private var glass: AnyShapeStyle {
        guard let lens else { return AnyShapeStyle(Wire.paper) }
        return AnyShapeStyle(RadialGradient(colors: [lens.core, lens.glass],
                                           center: UnitPoint(x: 0.36, y: 0.32),
                                           startRadius: 0, endRadius: Wire.s(11)))
    }

    var body: some View {
        Circle()
            .fill(glass)
            .opacity(dimmed ? 0.32 : 1)
            .overlay(Circle().stroke(lens == nil ? Wire.faint.opacity(0.35)
                                                 : Wire.ink.opacity(0.55),
                                     lineWidth: Wire.s(1)))
            .frame(width: Wire.s(14), height: Wire.s(14))
            .shadow(color: (lens?.glass ?? .clear).opacity(dimmed ? 0.15 : 0.55),
                    radius: Wire.s(4))
    }
}

/// Own the endless animation in a child that exists only while the lamp is
/// live. Removing this child removes the animated shadow render node too;
/// trying to cancel only `dimmed` left that halo's presentation animation
/// breathing after the core had stopped.
private struct WirePulsingBulb: View {
    let lens: WireLens
    @State private var dimmed = false

    var body: some View {
        WireLampFace(lens: lens, dimmed: dimmed)
            .onAppear {
                dimmed = false
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

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
private struct WireSpeakerBorder: View {
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
                let corner = Wire.s(6)
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

/// A signal lamp: a glass lens in a metal bezel, or — with no lens — the
/// plain dark-ringed dot the gray lamps show when off, since a tinted unlit
/// lens reads as a third state rather than as nothing. `pulsing` gives it
/// the slow breathing fade of a lamp wired to something still working, so
/// THINK reads as activity rather than as one more steady state. The bezel
/// is centered over the nameplate, and the row below hands each lamp a
/// fixed share of the card, so the label's length never moves the light.
private struct WireSignalLamp: View {
    var label: String
    var lens: WireLens?
    var pulsing = false

    var body: some View {
        VStack(spacing: Wire.s(3)) {
            if pulsing, let lens {
                WirePulsingBulb(lens: lens)
            } else {
                WireLampFace(lens: lens, dimmed: false)
            }
            Text(label)
                .font(Wire.mono(7, .bold))
                .tracking(0.5)
                .foregroundColor(Wire.faint)
                // A nameplate that changes with the state ("NOT READY") has
                // a space in it to wrap at; one line, always, so a state
                // change never grows the row.
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Boxed rolling digits: the turn counter.
private struct WireOdometer: View {
    var value: Int
    var digits = 2

    var body: some View {
        HStack(spacing: Wire.s(2)) {
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
    var digit: Character

    private var window: RoundedRectangle { RoundedRectangle(cornerRadius: Wire.s(3)) }

    var body: some View {
        ZStack {
            Text(String(digit))
                .font(Wire.mono(13, .bold))
                .foregroundColor(Wire.paper)
                // A full-box frame makes the slide a whole drum face, so the
                // outgoing digit is gone before the incoming one appears.
                .frame(width: Wire.s(16), height: Wire.s(21))
                .id(digit)
                .transition(.asymmetric(insertion: .move(edge: .bottom),
                                        removal: .move(edge: .top)))
        }
        .frame(width: Wire.s(16), height: Wire.s(21))
        .background(window.fill(Wire.ink))
        .clipShape(window)
        // The drum's seam, which is what makes a counter read as turned
        // rather than typed.
        .overlay(Rectangle().fill(Wire.paper.opacity(0.16)).frame(height: Wire.s(0.5)))
        .animation(.easeInOut(duration: 0.3), value: digit)
    }
}

/// The skin's boxed control, shared by the action row, the steering
/// editor, and the compact footer.
private struct WireButton: View {
    var label: String
    var disabled: Bool
    /// Return triggers the control (the RUN button).
    var isDefault = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Wire.mono(9, .bold))
                .foregroundColor(disabled ? Wire.faint : Wire.ink)
                .padding(.horizontal, Wire.s(8))
                .padding(.vertical, Wire.s(3))
                .overlay(Rectangle().stroke(disabled ? Wire.faint : Wire.ink,
                                            lineWidth: Wire.s(1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .keyboardShortcut(isDefault ? .defaultAction : nil)
    }
}

/// Pause/Steer wording shared by the action row and the compact footer.
private func wirePauseHelp(isPaused: Bool, isHolding: Bool) -> String {
    guard isPaused else { return "Hold the run at the next handoff" }
    return isHolding
        ? "Send the held reply and continue"
        : "Call off the pause and let the run carry on"
}

private let wireSteerHelp = "Hold the run and write a steering note into the conversation"

// MARK: - Skin

/// The shell: structure only. It reads the two properties that decide
/// which children mount (compact, isSteering); everything else is read
/// inside the child views, which is what keeps their invalidation apart.
struct WireframePanelView: View {
    let controller: RelayController

    var body: some View {
        VStack(spacing: Wire.s(12)) {
            WireHeader(controller: controller)
            WireInstrumentHead(controller: controller)
            if controller.compact {
                WireCompactFooter(controller: controller)
                if controller.isSteering { WireSteeringEditor(controller: controller) }
            } else {
                WireConversationSetup(controller: controller)
                WireActionControls(controller: controller)
                if controller.isSteering { WireSteeringEditor(controller: controller) }
                WireLogWell(controller: controller)
            }
        }
        .padding(Wire.s(16))
        .frame(width: Wire.cardWidth,
               height: controller.compact ? nil : Wire.expandedCardHeight)
        .background(
            RoundedRectangle(cornerRadius: Wire.s(10)).fill(Wire.paper)
                .shadow(color: .black.opacity(0.28), radius: Wire.s(9), y: Wire.s(4))
                // Bare paper — the card's padding and the gaps between rows
                // — moves the window. See WireHeader for why the card asks
                // for the drag instead of leaving it to the window
                // background.
                .gesture(WindowDragGesture())
        )
        .overlay(RoundedRectangle(cornerRadius: Wire.s(10)).stroke(Wire.ink.opacity(0.3)))
        .environment(\.colorScheme, .light)
        .padding(Wire.cardMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: Header

/// The name-and-state line doubles as the card's title bar: the panel is
/// borderless, so this is the one strip that always drags the window no
/// matter what state the console is in. It asks for the drag outright
/// rather than relying on `isMovableByWindowBackground`, which only moves
/// a window when AppKit judges that nothing in the content wanted the
/// click — an inference that does not hold on every macOS release. Text
/// selection in the log and the instruction editor is untouched, because
/// the gesture lives here and on the bare paper, not over those.
private struct WireHeader: View {
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

// MARK: Instrument head

/// Both participant cards, the route with its courier, the status plates,
/// and the odometer. One view on purpose: everything here depends on the
/// same relay-state cluster, so splitting it further would add plumbing
/// without separating meaningful updates.
private struct WireInstrumentHead: View {
    let controller: RelayController

    var body: some View {
        HStack(alignment: .top, spacing: Wire.s(14)) {
            participant(.chatgpt, status: controller.chatgptStatus,
                        conversation: controller.chatgptConversation)
            centerDeck
            participant(.claude, status: controller.claudeStatus,
                        conversation: controller.claudeConversation)
        }
    }

    private var bothReady: Bool {
        controller.chatgptStatus.state == .ready && controller.claudeStatus.state == .ready
    }

    private var bothEnded: Bool {
        controller.chatgptConversation == .ended && controller.claudeConversation == .ended
    }

    private func participant(_ speaker: Speaker, status: SideStatus,
                             conversation: ConversationStatus) -> some View {
        VStack(spacing: Wire.s(8)) {
            WireGauge(level: gaugeLevel(conversation))
            // The nameplate: who this is, the surface it is on, the model
            // behind it — identity in one block, state in the instruments
            // below. Every row reserves its height with a single space so
            // the lamps sit level on both cards whatever is missing.
            VStack(spacing: Wire.s(2)) {
                Text(status.appName.uppercased())
                    .font(Wire.mono(10, .bold))
                    .foregroundColor(Wire.ink)
                let surface = surfaceRow(status)
                Text(surface.text)
                    .foregroundColor(surface.diagnosis ? Wire.ink.opacity(0.75)
                                                       : Wire.faint)
                Text(modelRow(status))
                    .foregroundColor(Wire.faint)
            }
            .font(Wire.mono(8.5))
            .lineLimit(1)
            .truncationMode(.tail)
            // Half the card each, lamp centered in its half. Spacing the pair
            // by their own edges instead would hang the bezels off however
            // long the nameplates happen to be, and a renamed lamp would
            // shift both; halves are fixed, so the text underneath can say
            // anything. The negative inset cancels the card's padding for
            // this row alone, because the halves worth dividing are the drawn
            // card's, not the padded content box's.
            HStack(spacing: 0) {
                WireSignalLamp(label: readyLabel(status.state),
                               lens: readyLens(status.state))
                    .frame(maxWidth: .infinity)
                WireSignalLamp(label: "THINK",
                               lens: conversation == .chatting ? .orange : nil,
                               pulsing: conversation == .chatting)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, -Wire.s(10))
            // The states with no lamp of their own: a held reply, captured
            // but undelivered (in an uninterrupted run a side is never seen
            // in .replied), and the side's own sign-off, which a SEAL
            // indicator used to mark. Blank otherwise, height held.
            Text(footnote(conversation))
                .foregroundColor(Wire.ink.opacity(0.75))
                .font(Wire.mono(8.5))
                .lineLimit(1)
        }
        .padding(Wire.s(10))
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Wire.s(6)).fill(Wire.well))
        .overlay(cardStroke(for: speaker, conversation: conversation))
        // Clicking a card nominates that side to open the next run — the
        // largest target for the plainest statement of it. The courier's
        // pointer swinging over is the acknowledgement.
        .contentShape(Rectangle())
        .onTapGesture { nominate(speaker) }
        .modifier(WireHandCursor(active: canChooseOpener))
        .help(canChooseOpener ? "Have \(status.appName) send the opening message" : "")
    }

    /// The border tells the card's place in the turn. Waiting its turn, it
    /// speaks the dash grammar the rail and the ghost stop already use —
    /// dashed ink while the side's turn is on its way, the plain faint
    /// outline when the next message is none of its business — and the
    /// dashes hold still on purpose, since marching ones read as a
    /// selection rather than a state. Composing, the outline stops being a
    /// line and becomes the speaker it is driving (WireSpeakerBorder): the
    /// one card doing work is the one card moving, which is a thing the eye
    /// finds without being asked to compare anything.
    @ViewBuilder
    private func cardStroke(for speaker: Speaker,
                            conversation: ConversationStatus) -> some View {
        if conversation == .chatting {
            WireSpeakerBorder()
        } else {
            let upNext = nextTaker == speaker
            RoundedRectangle(cornerRadius: Wire.s(6))
                .stroke(upNext ? Wire.ink : Wire.faint.opacity(0.5),
                        style: StrokeStyle(lineWidth: Wire.s(1),
                                           dash: upNext ? [Wire.s(2.5), Wire.s(2.5)] : []))
        }
    }

    /// The readiness lamp's nameplate reads out the state rather than naming
    /// the instrument, because a red lamp under the word READY says the
    /// opposite of what it means at a glance. The lens is what the eye
    /// catches first; this is what settles it.
    private func readyLabel(_ state: ReadyState) -> String {
        switch state {
        case .ready: "READY"
        case .checking: "CHECKING"
        case .notReady, .missing: "NOT READY"
        }
    }

    /// Green when the side is relayable, red when it is not, amber while the
    /// first sweep is still out. The readiness lamp is never dark — an unlit
    /// one would read as "no signal" rather than "not ready".
    private func readyLens(_ state: ReadyState) -> WireLens {
        switch state {
        case .ready: .green
        case .checking: .amber
        case .notReady, .missing: .red
        }
    }

    /// The line under the lamps (see its call site for why these two states
    /// live in words rather than in a lamp).
    private func footnote(_ conversation: ConversationStatus) -> String {
        switch conversation {
        case .replied: conversation.rawValue
        case .ended: "Signed off"
        default: " "
        }
    }

    private func gaugeLevel(_ conversation: ConversationStatus) -> Double {
        switch conversation {
        case .chatting: 0.72
        // A held reply drops the needle the same way waiting does: the side
        // is in the conversation but not working.
        case .waiting, .replied: 0.28
        case .ended, .notStarted: 0.08
        }
    }

    /// The nameplate's surface row doubles as the diagnosis while the side
    /// is not relayable: a red lens conflates four failures whose remedies
    /// differ — launch the app, open a chat window, grant Accessibility —
    /// and a side in that state has no surface to name anyway. The
    /// isRunning guard keeps a stale diagnosis off a card mid-run, when
    /// the readiness scanner is paused.
    private func surfaceRow(_ status: SideStatus) -> (text: String, diagnosis: Bool) {
        if !controller.isRunning,
           status.state == .notReady || status.state == .missing {
            return (status.headline, true)
        }
        return (status.surface ?? " ", false)
    }

    /// Model and effort as one plate ("5.6 Sol High", "Fable 5 Extra") —
    /// the separator Readiness composes is for the skins that join surface
    /// and model on a single line, and this card gives each its own row.
    private func modelRow(_ status: SideStatus) -> String {
        status.model?.replacingOccurrences(of: " \u{00B7} ", with: " ") ?? " "
    }

    private var centerDeck: some View {
        VStack(spacing: Wire.s(8)) {
            // Named under the drums the way the lamps are named under
            // their lenses, in the same plate style.
            VStack(spacing: Wire.s(3)) {
                WireOdometer(value: controller.currentTurn)
                Text("TURN")
                    .font(Wire.mono(7, .bold))
                    .tracking(0.5)
                    .foregroundColor(Wire.faint)
            }
            route
            Text(primaryStatus.uppercased())
                .font(Wire.mono(8, .bold))
                .tracking(0.5)
                .foregroundColor(Wire.ink)
                .lineLimit(1)
                .fixedSize()
            secondaryStatus
        }
        .frame(width: Wire.s(150))
    }

    /// The line under the primary status: a single faint readout in one
    /// style, whichever state fills it in. In a run it
    /// reports a pause — the word alone tells PAUSING from PAUSED, and the
    /// ghost stop draws that distinction on the route besides. Idle it
    /// names the side the courier is aimed at, since an arrow's angle is
    /// not something the panel should make anyone read. Blank otherwise,
    /// so the row's height never moves.
    ///
    /// Plain faint text, not a control: flipping the opener already lives
    /// on the participant cards and on the courier itself, and brackets
    /// are what this panel puts around a choice — a readout gets none.
    private var secondaryStatus: some View {
        Text(controller.isRunning
                ? (controller.isHolding ? "PAUSED" : "PAUSING")
                : "\(openerName.uppercased()) OPENS")
            .font(Wire.mono(8, .bold))
            .tracking(0.5)
            .foregroundColor(Wire.faint)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, Wire.s(2))
            .opacity(controller.isRunning && !controller.isPaused ? 0 : 1)
    }

    private var primaryStatus: String {
        if controller.isRunning {
            if controller.isHolding { return "Holding at handoff" }
            if controller.chatgptConversation == .chatting { return "ChatGPT is composing" }
            if controller.claudeConversation == .chatting { return "Claude is composing" }
            return "Relaying"
        }
        if bothEnded { return "Run complete" }
        if bothReady { return "Ready" }
        if [controller.chatgptStatus.state, controller.claudeStatus.state]
            .contains(.checking) { return "Scanning" }
        return "Waiting on apps"
    }

    /// The route as a plain line — dashed while idle, solid in a run — with
    /// the courier riding it: an open bead that slides over to park beside
    /// whoever is composing, and a pointer swinging out of the bead toward
    /// the side the next message is bound for.
    private var route: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            let inset = Wire.s(6)
            ZStack {
                rail(width: geo.size.width, midY: midY)
                ghostStop
                    .position(x: geo.size.width / 2, y: midY)
                    .opacity(showsGhostStop ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: showsGhostStop)
                WireCourier(pointsRight: pointsRight,
                            showsPointer: routeIsLive,
                            interactive: canChooseOpener,
                            onFlip: flipOpener,
                            onRoulette: { controller.firstSpeaker = $0 })
                    .position(x: inset + courierFraction * (geo.size.width - 2 * inset),
                              y: midY)
                    .animation(.easeInOut(duration: 0.45), value: courierFraction)
            }
        }
        // Tall enough for the pointer's swing between the two sides to stay
        // inside the deck; the center column is still the shortest of the
        // three, so the head unit does not grow for it.
        .frame(height: Wire.s(36))
    }

    private func rail(width: CGFloat, midY: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: Wire.s(2), y: midY))
            p.addLine(to: CGPoint(x: width - Wire.s(2), y: midY))
        }
        .stroke(Wire.faint,
                style: StrokeStyle(lineWidth: Wire.s(1.5), lineJoin: .round,
                                   dash: controller.isRunning ? [] : [Wire.s(3), Wire.s(3)]))
    }

    /// The spot the courier will come to rest on, drawn only while a pause is
    /// on its way: dashed and muted, because a pause asked for mid-reply is
    /// not in effect yet — the agent is still writing, and the run carries on
    /// until it reaches the handoff.
    private var ghostStop: some View {
        Circle()
            .stroke(Wire.faint,
                    style: StrokeStyle(lineWidth: Wire.s(1.5),
                                       dash: [Wire.s(2.5), Wire.s(2.5)]))
            .frame(width: Wire.s(10), height: Wire.s(10))
    }

    /// Only in the gap between asking for a pause and the run taking it. Once
    /// the courier is standing there the mark has nothing left to say.
    private var showsGhostStop: Bool {
        controller.isPaused && !controller.isHolding
    }

    /// The bead parks beside whoever holds the message and waits in the
    /// middle when nobody does: before the run opens, after it closes, and
    /// once a pause has actually parked a captured reply there.
    private var courierFraction: CGFloat {
        if controller.isHolding { return 0.5 }
        if controller.chatgptConversation == .chatting { return 0.04 }
        if controller.claudeConversation == .chatting { return 0.96 }
        return 0.5
    }

    /// The pointer names the side the next message is bound for: away from
    /// whoever is composing now, and — with nobody composing — at whichever
    /// side is nominated to open.
    private var pointsRight: Bool {
        if holdsTheMessage(controller.chatgptConversation) { return true }
        if holdsTheMessage(controller.claudeConversation) { return false }
        return controller.firstSpeaker == .claude
    }

    /// Whether the next message is coming from this side: it is writing one,
    /// or it has written one that has not been delivered yet. Either way the
    /// pointer belongs on the far side.
    private func holdsTheMessage(_ status: ConversationStatus) -> Bool {
        status == .chatting || status == .replied
    }

    /// Every state has a next message except one: a finished run still on
    /// screen, both sides signed off. Once it lets go of the panel the
    /// pointer means the next run's opener again.
    private var routeIsLive: Bool { !(controller.isRunning && bothEnded) }

    /// The side that composes the next message: the far side of whoever
    /// holds one, or the nominated opener. Nil while a finished run is
    /// still on screen, and nil the moment a pause is asked for — from
    /// then on the next actor is the human, which the ghost stop and the
    /// parked courier already say, and no card's turn is on its way.
    private var nextTaker: Speaker? {
        guard routeIsLive, !controller.isPaused else { return nil }
        return pointsRight ? .claude : .chatgpt
    }

    // MARK: Nominating an opener

    /// Aiming the courier only means something before a run. Once the relay
    /// is going the message the pointer names is already written — paused, it
    /// is captured and waiting — and there is only one place it can go.
    private var canChooseOpener: Bool { !controller.isRunning }

    private func nominate(_ speaker: Speaker) {
        guard canChooseOpener else { return }
        controller.firstSpeaker = speaker
    }

    private func flipOpener() {
        nominate(controller.firstSpeaker == .chatgpt ? .claude : .chatgpt)
    }

    /// The nominated side, named the way its own card names it.
    private var openerName: String {
        switch controller.firstSpeaker {
        case .chatgpt: controller.chatgptStatus.appName
        case .claude: controller.claudeStatus.appName
        }
    }
}

// MARK: Setup (expanded, idle)

private struct WireConversationSetup: View {
    @Bindable var controller: RelayController

    var body: some View {
        Group {
            shapeRow
            WirePromptEditor(controller: controller)
            optionsRow
        }
        .disabled(controller.isRunning)
        .opacity(controller.isRunning ? 0.45 : 1)
    }

    private var shapeRow: some View {
        HStack(spacing: Wire.s(8)) {
            Menu {
                ForEach(conversationTemplates) { template in
                    Button(template.name) {
                        controller.selectConversation(template.name)
                    }
                }
                Divider()
                Button("Write from scratch") {
                    controller.selectConversation(RelayController.customConversation)
                }
            } label: {
                Text("[ \(controller.conversation.uppercased()) \u{25BE} ]")
                    .font(Wire.mono(9, .bold))
                    .foregroundColor(Wire.ink)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer()
            if controller.selectedTemplate != nil {
                Button {
                    if controller.isEditingInstructions {
                        controller.resetInstructionsToTemplate()
                    } else {
                        controller.editInstructions()
                    }
                } label: {
                    Text(controller.isEditingInstructions
                         ? "BACK TO SIMPLE SETUP" : "EDIT FULL PROMPT")
                        .font(Wire.mono(8, .bold))
                        .underline()
                        .foregroundColor(Wire.faint)
                }
                .buttonStyle(.plain)
                .help(controller.isEditingInstructions
                      ? "Discard full-prompt edits and return to the simple topic field"
                      : "Edit the full opening prompt without changing the selected shape")
            }
        }
    }

    private var optionsRow: some View {
        HStack(spacing: Wire.s(14)) {
            wireToggle("LIMIT TURNS", isOn: $controller.limitTurns)
                .help("Off: the run ends when both agents sign off (or on an empty reply, a timeout, or Stop). On: also stop after this many responses.")
            HStack(spacing: Wire.s(3)) {
                TextField("10", value: $controller.turns, format: .number)
                    .textFieldStyle(.plain)
                    .font(Wire.mono(10))
                    .foregroundColor(Wire.ink)
                    .multilineTextAlignment(.center)
                    .frame(width: Wire.s(26))
                    .padding(.vertical, Wire.s(2))
                    .background(Rectangle().fill(Wire.well))
                    .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
                Stepper("", value: $controller.turns, in: 1...99)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            .disabled(!controller.limitTurns)
            .opacity(controller.limitTurns ? 1 : 0.45)
            wireToggle("TILE", isOn: $controller.tileWindows)
                .help("Tile the chat windows side by side when the run starts")
            Spacer(minLength: 0)
        }
    }

    private func wireToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: Wire.s(5)) {
                ZStack {
                    Rectangle()
                        .stroke(Wire.ink, lineWidth: Wire.s(1))
                        .frame(width: Wire.s(10), height: Wire.s(10))
                    if isOn.wrappedValue {
                        Rectangle().fill(Wire.ink).frame(width: Wire.s(5), height: Wire.s(5))
                    }
                }
                Text(label)
                    .font(Wire.mono(8, .bold))
                    .foregroundColor(Wire.ink)
            }
            // A stroked Rectangle only hit-tests along its outline, so an
            // unticked box swallowed clicks aimed straight at it. The whole
            // row — box, gap, and label — is the target.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The topic field or the full-prompt editor. Its own view so a keystroke
/// invalidates only this scope (plus the run gate reading the prompt), not
/// the picker and options around it.
private struct WirePromptEditor: View {
    @Bindable var controller: RelayController

    var body: some View {
        if !controller.showsFullInstructionsEditor,
           let template = controller.selectedTemplate {
            TextField(template.topicPrompt, text: $controller.topic, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Wire.text(11))
                .foregroundColor(Wire.ink)
                .lineLimit(1...3)
                .padding(.horizontal, Wire.s(8))
                .padding(.vertical, Wire.s(6))
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
        } else {
            GrowingTextEditor(text: $controller.customInstructions,
                              font: .systemFont(ofSize: Wire.s(11)),
                              textColor: NSColor(calibratedWhite: 0.20, alpha: 1),
                              placeholder: controller.promptEditorPlaceholder)
                .padding(.horizontal, Wire.s(8))
                .padding(.vertical, Wire.s(6))
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
                .help(controller.selectedTemplate == nil
                      ? "Write the complete opening prompt"
                      : "Editing the complete \(controller.conversation) prompt; choosing another shape keeps this editor open")
        }
    }
}

// MARK: Actions (expanded)

/// Inspect/Run/Stop/Compact/Steer/Pause. Updates while the prompt is
/// typed — Run eligibility reads it — which is a small, deliberate
/// invalidation.
private struct WireActionControls: View {
    let controller: RelayController

    var body: some View {
        HStack(spacing: Wire.s(8)) {
            WireButton(label: "INSPECT", disabled: controller.isRunning) {
                controller.runInspect()
            }
            .help("Dump both apps' windows, buttons, and selector matches into the log")
            Spacer()
            if controller.isRunning {
                WireButton(label: "COMPACT", disabled: false) { controller.compact = true }
                    .help("Shrink to the head unit")
                WireButton(label: "STEER", disabled: controller.isSteering) {
                    controller.beginSteer()
                }
                .help(wireSteerHelp)
                WireButton(label: controller.isPaused ? "RESUME" : "PAUSE",
                           disabled: false) {
                    controller.togglePause()
                }
                .help(wirePauseHelp(isPaused: controller.isPaused,
                                    isHolding: controller.isHolding))
            }
            WireButton(label: "RUN",
                       disabled: controller.isRunning || !controller.instructionsReady,
                       isDefault: true) {
                controller.start()
            }
            WireButton(label: "STOP", disabled: !controller.isRunning) { controller.stop() }
        }
    }
}

// MARK: Steering (in run)

/// The steering editor: a note from the human, posted into the relay.
/// It rides the next handoff to whoever replies next, and is echoed to
/// the other side a turn later. Opening it holds the run the way Pause
/// does — the ghost stop and the PAUSED readout already narrate that —
/// and Send lets go again, unless the pause was the user's own.
/// Isolated with its own focus state so typing the note stays in this
/// scope.
private struct WireSteeringEditor: View {
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

// MARK: Log (expanded)

private struct WireLogWell: View {
    let controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: Wire.s(4)) {
            Text("LOG")
                .font(Wire.mono(8, .bold))
                .tracking(1.2)
                .foregroundColor(Wire.faint)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Wire.s(2)) {
                        ForEach(controller.logLines) { line in
                            Text(line.text)
                                .font(Wire.mono(10.5))
                                .foregroundColor(Wire.ink)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Wire.s(8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
                .onChange(of: controller.logLines.count) { _, _ in
                    if let last = controller.logLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: Compact footer (in run)

/// The head unit's bottom row: the loaded shape and topic on the left,
/// the run controls on the right.
private struct WireCompactFooter: View {
    let controller: RelayController

    var body: some View {
        HStack(spacing: Wire.s(8)) {
            Text("[ \(controller.conversation.uppercased()) ]")
                .font(Wire.mono(9, .bold))
                .foregroundColor(Wire.ink)
            Text(topicSummary)
                .font(Wire.text(10))
                .foregroundColor(Wire.faint)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Wire.s(8))
            WireButton(label: "STEER", disabled: controller.isSteering) {
                controller.beginSteer()
            }
            .help(wireSteerHelp)
            WireButton(label: controller.isPaused ? "RESUME" : "PAUSE", disabled: false) {
                controller.togglePause()
            }
            .help(wirePauseHelp(isPaused: controller.isPaused,
                                isHolding: controller.isHolding))
            WireButton(label: "STOP", disabled: false) { controller.stop() }
            WireButton(label: "EXPAND", disabled: false) { controller.compact = false }
                .help("Expand the full console")
        }
    }

    private var topicSummary: String {
        if controller.selectedTemplate == nil {
            return controller.customInstructions
                .components(separatedBy: .newlines).first ?? ""
        }
        return controller.topic
    }
}

// MARK: - Previews

#Preview("Wireframe console (idle)") {
    WireframePanelView(controller: RelayController())
        .background(Color(white: 0.75))
}

#Preview("Wireframe head unit (in run)") {
    let controller = RelayController()
    controller.isRunning = true
    controller.compact = true
    controller.currentTurn = 7
    controller.chatgptConversation = .chatting
    controller.claudeConversation = .waiting
    return WireframePanelView(controller: controller)
        .background(Color(white: 0.75))
}

#Preview("Wireframe steer (held at handoff)") {
    let controller = RelayController()
    controller.isRunning = true
    controller.compact = true
    controller.currentTurn = 4
    controller.isPaused = true
    controller.isHolding = true
    controller.isSteering = true
    controller.chatgptConversation = .replied
    controller.claudeConversation = .waiting
    return WireframePanelView(controller: controller)
        .background(Color(white: 0.75))
}

#if DEBUG
/// The one preview that moves: it hands the conversation back and forth
/// every couple of seconds, so the counter's roll and the pointer's swing
/// play in the canvas while the head unit is being edited. Every other
/// preview here is a frozen state, and a frozen state cannot show an
/// animation that has stopped working.
private struct WireframeHandoffPreview: View {
    @State private var controller: RelayController = {
        let c = RelayController()
        c.isRunning = true
        c.compact = true
        c.currentTurn = 1
        c.conversation = "Debate"
        c.topic = "Are code comments for the why or the what?"
        c.chatgptConversation = .chatting
        c.claudeConversation = .waiting
        return c
    }()

    var body: some View {
        WireframePanelView(controller: controller)
            .background(Color(white: 0.75))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.2))
                    let claudeSpeaks = controller.chatgptConversation == .chatting
                    controller.chatgptConversation = claudeSpeaks ? .waiting : .chatting
                    controller.claudeConversation = claudeSpeaks ? .chatting : .waiting
                    controller.currentTurn += 1
                }
            }
    }
}

#Preview("Wireframe handoff (animated)") {
    WireframeHandoffPreview()
}
#endif
