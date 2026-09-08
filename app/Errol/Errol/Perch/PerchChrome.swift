// Header controls live inside the borderless panel's content. The background
// drags the window, while the buttons and menu receive clicks directly.

import SwiftUI

struct PerchChrome: View {
    let controller: RelayController
    let screen: PanelNavigation.Screen
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: Perch.s(6)) {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .font(Perch.text(12, .medium))
                    .foregroundStyle(Perch.ink)
                    .padding(.horizontal, Perch.s(6))
                    .frame(height: Perch.s(28))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back to Errol")
            .accessibilityLabel("Back to Errol")
            .modifier(PanelScreenPresentation(isVisible: screen == .settings,
                                              hiddenOffset: Perch.s(24)))
            Spacer(minLength: 0)

        }
        .padding(.horizontal, Perch.contentInset)
        .frame(height: Perch.chromeBand)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }
}

/// Settings remains available beside Run and New session.
struct PerchOverflowMenu: View {
    let controller: RelayController

    var body: some View {
        Menu {
            Button("Settings…") { controller.openSettings() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: Perch.s(12), weight: .semibold))
                .foregroundColor(Perch.muted)
                .frame(width: Perch.s(22), height: Perch.s(22))
                .contentShape(Rectangle())
                .perchHover(RoundedRectangle(cornerRadius: Perch.s(6)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Session actions")
    }
}
