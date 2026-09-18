// Setup and running actions reveal labels beside stationary icons. Editors,
// permission setup, and the ending retain their labeled Liquid Glass pills.

import SwiftUI

/// Only the circular control participates in layout. The label is revealed
/// behind it towards the left, so neither the icon nor adjacent content moves.
struct PerchRevealButton: View {
    let title: String
    let icon: String
    var prominent = true
    var progress: Double? = nil
    var countdown: Int? = nil
    /// A secondary in a pair reveals its label before the other control.
    var labelClearance: CGFloat = 0
    let action: () -> Void
    @State private var hovering = false
    @State private var labelWidth: CGFloat = 0
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var revealed: Bool { isEnabled && (hovering || focused) }
    private var ink: Color { prominent ? Perch.onAccent : Perch.ink }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(Perch.text(13, .semibold))
                .foregroundStyle(ink)
                .frame(width: Perch.actionDiameter, height: Perch.actionDiameter)
                .background(Circle().fill(prominent ? Perch.accent : Perch.paper))
                .overlay(Circle().stroke(prominent ? Perch.accent : Perch.chipEdge, lineWidth: 1))
                .overlay {
                    if let progress {
                        GeometryReader { geometry in
                            Rectangle().fill(ink.opacity(0.2))
                                .frame(width: geometry.size.width * min(1, max(0, progress)))
                        }
                        .clipShape(Circle())
                        .allowsHitTesting(false)
                    }
                }
                .background(alignment: .trailing) {
                    Text(title)
                        .font(Perch.text(12, .medium))
                        .foregroundStyle(ink)
                        .padding(.leading, Perch.s(12))
                        .padding(.trailing, labelClearance == 0 ? Perch.actionDiameter / 2 + Perch.s(6) : Perch.s(12))
                        .frame(height: Perch.actionDiameter)
                        .fixedSize()
                        .background(Capsule().fill(prominent ? Perch.accent : Perch.paper))
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: revealed ? labelWidth : 0)
                        }
                        .offset(x: -(Perch.actionDiameter / 2 + labelClearance))
                        .opacity(revealed ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .onHover { hovering = $0 }
        .opacity(isEnabled ? 1 : 0.45)
        .overlay(alignment: .topTrailing) {
            if let countdown {
                Text("\(countdown)")
                    .font(Perch.text(9, .semibold)).monospacedDigit()
                    .foregroundStyle(Perch.ink)
                    .frame(width: Perch.s(16), height: Perch.s(16))
                    .background(Circle().fill(Perch.paper))
                    .overlay(Circle().stroke(Perch.chipEdge, lineWidth: 1))
                    .offset(x: Perch.s(4), y: -Perch.s(4))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: revealed)
        .accessibilityLabel(title)
    }
}

struct PerchCapsuleButton: View {
    enum Style {
        case prominent, glass
    }

    enum Size {
        /// The console's bands.
        case regular
        /// The permission screen's one action.
        case large
    }

    let title: String
    var style = Style.prominent
    var size = Size.regular
    var icon: String? = nil
    /// Optional elapsed countdown fill, over the pill and clipped to it.
    var progress: Double? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Button(action: action) {
            HStack(spacing: Perch.s(6)) {
                if let icon {
                    Image(systemName: icon)
                        .font(Perch.text(size == .large ? 12 : 11, .semibold))
                }
                Text(title)
                    .font(size == .large ? Perch.text(13, .semibold) : Perch.text(12, .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(ink)
            .frame(height: PerchGlassButton.labelHeight(pill: Perch.s(size == .large ? 42 : 29),
                                                        size: controlSize))
        }
        .modifier(PerchGlassButton(prominent: style == .prominent, size: controlSize))
        // The glass styles interpolate their tint, and the ink crosses with
        // it, so an action coming into reach fades in like the text does.
        .animation(Perch.fade, value: isEnabled)
        // The wash is the label's own color, so it passes over the label
        // without changing it.
        .overlay(alignment: .leading) {
            if let progress {
                GeometryReader { geometry in
                    Rectangle().fill(Perch.onAccent.opacity(0.2))
                        .frame(width: geometry.size.width * min(1, max(0, progress)))
                }
                .clipShape(Capsule())
                .allowsHitTesting(false)
            }
        }
    }

    private var controlSize: ControlSize { size == .large ? .extraLarge : .large }

    /// The prominent pill gives up its tint when it is disabled and when
    /// the console is not key, and the ink chosen to sit on the accent then
    /// has nothing to sit on: white on pale glass, in a light theme. The
    /// neutral inks read on bare glass, and the system dims a disabled one.
    private var ink: Color {
        guard isEnabled else { return Perch.secondary }
        guard style == .prominent else { return Perch.accentText }
        return appearsActive ? Perch.onAccent : Perch.ink
    }
}

/// The system's glass button styles in the console's shape. They bring the
/// material, the rim, the press response, and the disabled look, and they
/// follow the window: in a console that is not key the tint and the rim
/// fade, as every control does in an inactive window.
private struct PerchGlassButton: ViewModifier {
    let prominent: Bool
    let size: ControlSize

    func body(content: Content) -> some View {
        Group {
            if prominent {
                content.buttonStyle(.glassProminent).tint(Perch.accent)
            } else {
                // The console tints all it holds with the accent, and a
                // tinted glass pill would be accent text on accent glass.
                content.buttonStyle(.glass).tint(nil)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(size)
    }

    /// The styles pad their label and take their height from it, so a pill
    /// of a given height asks for a label this tall. The padding is what
    /// macOS 27 measures — 6 points on each side at large, 10 at extra
    /// large; a system that pads differently moves the pill by that much.
    static func labelHeight(pill: CGFloat, size: ControlSize) -> CGFloat {
        pill - (size == .extraLarge ? 20 : 12)
    }
}

/// A bare text action under or beside a capsule button.
struct PerchTextButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Perch.text(12))
                .lineLimit(1)
                .perchHoverInk(idle: Perch.secondary, active: Perch.ink)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}
