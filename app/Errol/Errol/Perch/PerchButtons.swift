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

    var body: some View {
        Button(action: action) {
            PerchCapsuleLabel(title: title, style: style, size: size, icon: icon)
        }
        .buttonStyle(.plain)
    }
}

/// The capsule itself, for a Button or a Menu to wear. It dims while
/// disabled, and an action coming into reach fades in like the text
/// beside it.
struct PerchCapsuleLabel: View {
    let title: String
    var style = PerchCapsuleButton.Style.prominent
    var size = PerchCapsuleButton.Size.regular
    var icon: String? = nil
    @Environment(\.isEnabled) private var isEnabled

    private var prominent: Bool { style == .prominent }

    var body: some View {
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
        .opacity(isEnabled ? 1 : 0.45)
        .animation(Perch.fade, value: isEnabled)
    }
}

// MARK: - Chips

/// A control that reads as text in the console's rows: a menu showing its
/// value, a side's destination, the ··· menu. Secondary ink and no fill at
/// rest; under the pointer, the panel's wash in a rounded rectangle around
/// it. The inset is the wash's margin, so a row pulls its own padding in by
/// that much to keep the text on the prompt box's text edge.
enum PerchChip {
    static let inset = Perch.s(5)
    static let height = Perch.s(21)
    static let shape = RoundedRectangle(cornerRadius: Perch.s(6), style: .continuous)
}

extension View {
    func perchChip() -> some View {
        padding(.horizontal, PerchChip.inset)
            .frame(height: PerchChip.height)
            .contentShape(PerchChip.shape)
            .perchHover(PerchChip.shape)
    }
}

/// A menu's face in the console's rows: its current value and a chevron.
/// While a new value springs the chip to its width, the text rolls to it
/// glyph by glyph, keeping in place what the two values share ("Ends ",
/// " starts"), and stays inside its own frame, clear of the chevron. A
/// plain crossfade laid the two phrases over each other.
struct PerchChipLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: Perch.s(3)) {
            Text(title).contentTransition(.numericText()).clipped()
            Image(systemName: "chevron.down")
                .font(Perch.text(8, .semibold))
                .foregroundStyle(Perch.muted)
        }
        .font(Perch.text(11.5))
        .foregroundStyle(Perch.secondary)
        .lineLimit(1)
        .perchChip()
    }
}

/// A SwiftUI menu worn as a chip. The button menu style with the plain
/// button style leaves the label to SwiftUI, so it keeps its ink, its
/// hover, and a width that animates with its value; the borderless style
/// redraws the label in the tint and snaps to each new width.
struct PerchChipMenu<Items: View>: View {
    let title: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu { items() } label: { PerchChipLabel(title: title) }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}
