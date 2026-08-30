// The courier: the bead that rides the route between the two cards, and
// the pointer that swings out of it toward whoever speaks next.

import SwiftUI

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
struct WireCourier: View {
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
