// The signal lamps, the one place the skin spends color: a glass lens in a
// metal bezel over a nameplate, dark or lit, steady or breathing.

import SwiftUI

/// A colored bulb behind glass: a bright filament core inside deeper glass,
/// or the cloudy tint of the same lens with nothing lit behind it.
struct WireLens {
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

/// A signal lamp: a glass lens in a metal bezel, or — with no lens — the
/// plain dark-ringed dot the gray lamps show when off, since a tinted unlit
/// lens reads as a third state rather than as nothing. `pulsing` gives it
/// the slow breathing fade of a lamp wired to something still working, so
/// THINK reads as activity rather than as one more steady state. The bezel
/// is centered over the nameplate, and the row below hands each lamp a
/// fixed share of the card, so the label's length never moves the light.
struct WireSignalLamp: View {
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
