// Hover feedback for the skin's controls. Everything clickable here is a
// plain-styled button or a tap target drawing its own look, so nothing
// answers the pointer unless asked to; this is the one idiom they share: a
// tint washed over the control's own shape while the pointer rests on it —
// ink at a few percent on the paper-colored controls, white on the filled
// ones — faded over a beat. Bare glyphs (the ··· menu, the pencil) get the
// same wash, which shows as the soft square macOS draws behind a toolbar
// button.
//
// It works in the non-activating panel: SwiftUI's onHover installs an
// activeAlways tracking area (probed on macOS 26), so the pointer is noticed
// while the panel is not key and Errol is not the active app, which is the
// console's normal condition.

import SwiftUI

struct PerchHoverTint<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color
    let opacity: Double
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay(
                shape.fill(tint)
                    .opacity(hovering && isEnabled ? opacity : 0)
                    .allowsHitTesting(false)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The text-link variant: a bare text button has no shape to wash, so the
/// pointer darkens its ink instead, the way a link in a macOS sidebar
/// answers. The modifier owns the color, so the text sets none of its own.
struct PerchHoverInk: ViewModifier {
    let idle: Color
    let active: Color
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .foregroundColor(hovering && isEnabled ? active : idle)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    /// The skin's hover wash over `shape`, the control's own outline. The
    /// default is the ink tint that suits paper-colored controls; filled
    /// controls pass their own (white over ink, a deeper ink over amber).
    func perchHover<S: Shape>(_ shape: S, tint: Color = Perch.ink,
                              opacity: Double = 0.06) -> some View {
        modifier(PerchHoverTint(shape: shape, tint: tint, opacity: opacity))
    }

    /// Hover for text-only buttons: `idle` normally, `active` under the
    /// pointer.
    func perchHoverInk(idle: Color = Perch.secondary,
                       active: Color = Perch.ink) -> some View {
        modifier(PerchHoverInk(idle: idle, active: active))
    }
}
