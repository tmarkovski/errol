// The console's buttons, drawn flat: filled capsules and circles on the
// panel's glass, with no material of their own. Running actions reveal
// labels beside stationary icons; editors, permission setup, and the
// ending keep their labeled pills.

import SwiftUI

/// Only the circular control participates in layout. The label is revealed
/// behind it towards the left, so neither the icon nor adjacent content moves.
struct PerchRevealButton: View {
    let title: String
    let icon: String
    var prominent = true
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: revealed)
        .accessibilityLabel(title)
    }
}

struct PerchCapsuleButton: View {
    enum Style {
        /// The accent, for the one action that goes forward.
        case prominent
        /// The well, for the action beside it.
        case secondary
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
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    private var prominent: Bool { style == .prominent }

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
            .foregroundStyle(prominent ? Perch.onAccent : Perch.ink)
            .padding(.horizontal, Perch.s(size == .large ? 18 : 13))
            .frame(height: Perch.s(size == .large ? 42 : 29))
            .background(Capsule().fill(prominent ? Perch.accent : Perch.well))
            .overlay(Capsule().stroke(prominent ? Color.clear : Perch.chipEdge, lineWidth: 1))
            .perchHover(Capsule(), tint: prominent ? .white : Perch.ink, opacity: prominent ? 0.12 : 0.06)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        // An action coming into reach fades in like the text beside it.
        .animation(Perch.fade, value: isEnabled)
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
