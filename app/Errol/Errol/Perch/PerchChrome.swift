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
            HStack(spacing: Perch.s(6)) {
                PerchStatePill(controller: controller)
                PerchOverflowMenu(controller: controller)
            }
            .modifier(PanelScreenPresentation(isVisible: screen == .console,
                                              hiddenOffset: -Perch.s(18)))
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

/// What the panel is doing, as a tinted pill: green when both sides are
/// relayable, accented while a run owns them, quiet otherwise. An indicator,
/// not a control — hit testing is off so a click on it drags the window.
struct PerchStatePill: View {
    let controller: RelayController

    var body: some View {
        let look = pillLook
        HStack(spacing: Perch.s(6)) {
            Circle()
                .fill(look.tint)
                .frame(width: Perch.s(6), height: Perch.s(6))
            Text(look.word)
                .font(Perch.text(11, .medium))
                .foregroundColor(look.tint)
        }
        .padding(.horizontal, Perch.s(10))
        .frame(height: Perch.s(21))
        .background(Capsule().fill(look.back))
        .allowsHitTesting(false)
    }

    private var pillLook: (word: String, tint: Color, back: Color) {
        if controller.isRunning {
            guard controller.holdRequested else {
                return ("Running", Perch.accentText, Perch.accentBack)
            }
            return (controller.isHolding ? "Paused" : "Pausing",
                    Perch.accentText, Perch.accentBack)
        }
        if controller.hasFinishedRun {
            return ("Done", Perch.green, Perch.greenBack)
        }
        if bothReady { return ("Both ready", Perch.green, Perch.greenBack) }
        if [controller.chatgptStatus.state, controller.claudeStatus.state]
            .contains(.checking) {
            return ("Checking", Perch.muted, Perch.well)
        }
        return ("Waiting on apps", Perch.red, Perch.redBack)
    }

    private var bothReady: Bool {
        controller.chatgptStatus.state == .ready && controller.claudeStatus.state == .ready
    }
}

/// The session overflow: what the console offers outside a run's own
/// controls — Settings. Ending a run is the Stop button at the composer's
/// foot (PerchComposer), beside Pause.
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
