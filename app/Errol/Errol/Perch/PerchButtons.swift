// The console's buttons, drawn flat: filled capsules and circles on the
// panel's glass, with no material of their own. The running actions are
// bare icons in circles — pause and stop say themselves; editors,
// permission setup, and the ending keep their labeled pills.

import SwiftUI

/// A circle with an icon in it and nothing beside it. The title is the
/// accessible name only.
struct PerchRoundButton: View {
    let title: String
    let icon: String
    var prominent = true
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    private var ink: Color { prominent ? Perch.onAccent : Perch.ink }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(Perch.text(13, .semibold))
                .foregroundStyle(ink)
                .frame(width: Perch.actionDiameter, height: Perch.actionDiameter)
                .background(Circle().fill(prominent ? Perch.accent : Perch.paper))
                .overlay(Circle().stroke(prominent ? Perch.accent : Perch.chipEdge, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
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
