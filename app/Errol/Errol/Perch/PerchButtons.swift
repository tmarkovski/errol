// The capsule's labeled actions: one filled primary — Send, Continue,
// Arrange, Pause to steer — and outlined or bare secondaries beside or
// under it, in the panel's own idiom rather than the system's bezels.
// Labeled, because a first-time user has nothing to guess an icon from.

import SwiftUI

struct PerchCapsuleButton: View {
    enum Style {
        case filled, outlined
    }

    let title: String
    var style = Style.filled
    var icon: String? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Perch.s(6)) {
                if let icon {
                    Image(systemName: icon)
                        .font(Perch.text(12, .semibold))
                }
                Text(title)
                    .font(Perch.text(13, .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(style == .filled ? Perch.onAccent : Perch.accentText)
            .padding(.horizontal, Perch.s(16))
            .frame(height: Perch.s(38))
            .background(Capsule().fill(style == .filled ? Perch.accent : .clear))
            .overlay(Capsule().stroke(style == .filled ? .clear : Perch.accent.opacity(0.8), lineWidth: 1.2))
            .perchHover(Capsule(), tint: style == .filled ? .white : Perch.ink)
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
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
                .font(Perch.text(12, .medium))
                .lineLimit(1)
                .perchHoverInk(idle: Perch.secondary, active: Perch.ink)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}
