import SwiftUI

/// A compact, stable surface: changing tabs or ending mode never moves the menu.
///
/// No fill of its own, here or in the other popovers: the system's popover
/// chrome is already Liquid Glass, arrow and rim included, and an opaque
/// background is all it takes to hide it.
struct PerchSettingsPopover: View {
    enum Tab: String, CaseIterable {
        case conversation = "Conversation"
        case appearance = "Appearance"
    }

    @Bindable var controller: RelayController
    @State private var tab = Tab.conversation
    @State private var turnFocusRequest = 0
    @Bindable private var appearance = AppearanceStore.shared

    var body: some View {
        VStack(spacing: Perch.s(18)) {
            tabs
            Group {
                switch tab {
                case .conversation: conversation
                case .appearance: appearanceControls
                }
            }
            .frame(height: Perch.s(318), alignment: .top)
        }
        .padding(Perch.s(18))
        .frame(width: Perch.s(360))
        .foregroundStyle(Perch.ink)
        .tint(Perch.accent)
    }

    private var tabs: some View {
        HStack(spacing: Perch.s(22)) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    VStack(spacing: Perch.s(9)) {
                        Text(item.rawValue)
                            .font(Perch.text(12, tab == item ? .semibold : .medium))
                            .foregroundStyle(tab == item ? Perch.ink : Perch.muted)
                        Rectangle()
                            .fill(tab == item ? Perch.accent : .clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Image(systemName: "lock.fill")
                .font(Perch.text(10))
                .foregroundStyle(Perch.muted)
                .opacity(controller.isRunning ? 1 : 0)
                .accessibilityHidden(!controller.isRunning)
                .help("Conversation options unlock when this run ends")
                .padding(.bottom, Perch.s(10))
        }
        .background(alignment: .bottom) {
            Rectangle().fill(Perch.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings tabs")
    }

    /// The session's options. The shape row and the command to edit the
    /// shapes are off for now: every opening is the bare topic
    /// (RelayController.conversation).
    private var conversation: some View {
        VStack(spacing: Perch.s(12)) {
            row("Starts") {
                SettingsSegments(label: "Starts the conversation", selection: $controller.firstSpeaker,
                                 options: [(controller.chatgptStatus.appName, .chatgpt),
                                           (controller.claudeStatus.appName, .claude)])
            }
            row("Ending") {
                HStack(spacing: Perch.s(8)) {
                    SettingsSegments(label: "Conversation ending", selection: $controller.limitTurns,
                                     options: [("Auto", false), ("Limit", true)])
                    turnCount
                }
            }
            .help(controller.limitTurns
                  ? "Stop after at most \(controller.turns) turns"
                  : "End when both apps agree they’re done")
            row("Windows") {
                SettingsSegments(label: "Window layout",
                                 selection: Binding(get: { controller.setup.state.layout },
                                                    set: { controller.setup.choose($0) }),
                                 options: LayoutChoice.allCases.map { ($0.title, $0) })
            }
            Rectangle().fill(Perch.hairline).frame(height: 1)
                .padding(.top, Perch.s(2))
            VStack(spacing: Perch.s(4)) {
                command("Arrange windows now", icon: "rectangle.split.2x1") {
                    controller.setup.applyLayout()
                }
                .disabled(!controller.setup.state.layout.movesWindows || !controller.setup.state.canArrange)
                .help(controller.setup.state.canArrange
                      ? "Move both chat windows into the chosen layout"
                      : "Open a chat in both apps to arrange their windows")
                command("Restore window positions", icon: "arrow.uturn.backward") {
                    controller.setup.restoreLayout()
                }
                .disabled(!controller.setup.canRestoreLayout)
                .help("Put the arranged windows back where they were")
                command("Show the guided setup", icon: "list.number") {
                    controller.setup.restart()
                }
                .help("Open the apps, arrange, and connect the conversations step by step")
            }
        }
        .disabled(controller.isRunning)
        .opacity(controller.isRunning ? 0.5 : 1)
        .onChange(of: controller.limitTurns) { _, limited in
            if limited { turnFocusRequest += 1 }
        }
    }

    /// The number stays mounted and in place in Auto mode; only its availability changes.
    private var turnCount: some View {
        HStack(spacing: Perch.s(2)) {
            nudge("minus", label: "Fewer turns", disabled: controller.turns <= 1) {
                controller.turns = max(1, controller.turns - 1)
            }
            PerchTurnsField(value: $controller.turns,
                            font: .monospacedDigitSystemFont(ofSize: Perch.s(12), weight: .medium),
                            color: Perch.inkNS, focusRequest: turnFocusRequest)
                .accessibilityLabel("Turn limit")
            nudge("plus", label: "More turns", disabled: controller.turns >= 99) {
                controller.turns = min(99, controller.turns + 1)
            }
        }
        .padding(.horizontal, Perch.s(4))
        .frame(height: Perch.s(34))
        .background(RoundedRectangle(cornerRadius: Perch.s(8)).fill(Perch.well))
        .disabled(!controller.limitTurns)
        .opacity(controller.limitTurns ? 1 : 0.55)
        .fixedSize(horizontal: true, vertical: false)
        .help("Maximum number of turns")
    }

    private var appearanceControls: some View {
        VStack(alignment: .leading, spacing: Perch.s(16)) {
            row("Display") {
                SettingsSegments(label: "Appearance", selection: $appearance.appearance,
                                 options: AppAppearance.allCases.map { ($0.title, $0) })
            }
            VStack(alignment: .leading, spacing: Perch.s(9)) {
                Text("Color palette")
                    .font(Perch.text(11, .medium))
                    .foregroundStyle(Perch.muted)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: Perch.s(8)) {
                    ForEach(AppTheme.allCases) { theme in themeCard(theme) }
                }
            }
        }
    }

    private func themeCard(_ theme: AppTheme) -> some View {
        let selected = appearance.theme == theme
        let palette = theme.palette
        return Button { appearance.theme = theme } label: {
            HStack(spacing: Perch.s(8)) {
                ZStack {
                    RoundedRectangle(cornerRadius: Perch.s(5))
                        .fill(Color(nsColor: palette.paper))
                        .overlay(RoundedRectangle(cornerRadius: Perch.s(5))
                            .stroke(Color(nsColor: palette.chipEdge), lineWidth: 1))
                    HStack(spacing: Perch.s(4)) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(nsColor: palette.ink).opacity(0.6))
                            .frame(width: Perch.s(10), height: Perch.s(3))
                        Circle().fill(Color(nsColor: palette.accent))
                            .frame(width: Perch.s(10), height: Perch.s(10))
                    }
                }
                .frame(width: Perch.s(34), height: Perch.s(26))
                Text(theme.title.components(separatedBy: " & ")[0])
                    .font(Perch.text(11, selected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Perch.s(9))
            .frame(height: Perch.s(46))
            .background(RoundedRectangle(cornerRadius: Perch.s(8))
                .fill(selected ? Perch.well : .clear))
            .overlay(RoundedRectangle(cornerRadius: Perch.s(8))
                .stroke(selected ? Perch.accent : Perch.hairline, lineWidth: selected ? 1.5 : 1))
            .perchHover(RoundedRectangle(cornerRadius: Perch.s(8)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(theme.title)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Perch.s(12)) {
            Text(title)
                .font(Perch.text(12))
                .foregroundStyle(Perch.muted)
                .frame(width: Perch.s(48), alignment: .leading)
            content().frame(maxWidth: .infinity)
        }
    }

    private func command(_ title: String, icon: String, opensPage: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Perch.s(10)) {
                Image(systemName: icon)
                    .font(Perch.text(13))
                    .frame(width: Perch.s(18))
                Text(title).font(Perch.text(12))
                Spacer(minLength: 0)
                if opensPage {
                    Image(systemName: "chevron.right")
                        .font(Perch.text(9, .medium))
                        .foregroundStyle(Perch.muted)
                }
            }
            .padding(.horizontal, Perch.s(8))
            .frame(height: Perch.s(32))
            .contentShape(Rectangle())
            .perchHover(RoundedRectangle(cornerRadius: Perch.s(6)))
        }
        .buttonStyle(.plain)
    }

    private func nudge(_ icon: String, label: String, disabled: Bool,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(Perch.text(11, .medium))
                .frame(width: Perch.s(23), height: Perch.s(28))
                .contentShape(Rectangle())
                .perchHover(RoundedRectangle(cornerRadius: Perch.s(5)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Equal-width choices with the same soft surface as the shape and turn controls.
private struct SettingsSegments<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(String, Value)]

    var body: some View {
        HStack(spacing: Perch.s(2)) {
            ForEach(options.indices, id: \.self) { index in
                let (title, value) = options[index]
                Button { selection = value } label: {
                    Text(title)
                        .font(Perch.text(11, selection == value ? .medium : .regular))
                        .foregroundStyle(selection == value ? Perch.ink : Perch.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: Perch.s(28))
                        .background(RoundedRectangle(cornerRadius: Perch.s(5))
                            .fill(selection == value ? Perch.paper : .clear))
                        .contentShape(Rectangle())
                        .perchHover(RoundedRectangle(cornerRadius: Perch.s(5)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(Perch.s(3))
        .background(RoundedRectangle(cornerRadius: Perch.s(8)).fill(Perch.well))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
