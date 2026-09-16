// The settings card: the console's own idiom — the panel's glass, system
// type, soft wells, capsule buttons — as a screen inside the main panel.
// The native header provides Back. Appearance preferences sit above the
// conversation shapes, which the composer does not offer for now
// (RelayController.conversation).

import SwiftUI

struct SettingsView: View {
    var isPresented = true
    @ObservedObject private var store = SettingsStore.shared
    @Bindable private var appearance = AppearanceStore.shared
    @State private var selected: String
    /// The name field commits on Enter or focus loss rather than per
    /// keystroke: names are the shapes' identity (the pill selection and
    /// the per-shape drafts key on them), and half-typed renames would
    /// trip the uniqueness rule on every letter.
    @State private var nameDraft: String
    @FocusState private var nameFocused: Bool

    init(isPresented: Bool = true) {
        self.isPresented = isPresented
        let first = SettingsStore.shared.templates.first?.name ?? ""
        _selected = State(initialValue: first)
        _nameDraft = State(initialValue: first)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(14)) {
            appearanceControls
            Rectangle().fill(Perch.hairline).frame(height: 1)
            HStack(alignment: .top, spacing: Perch.s(14)) {
                rail
                editor
            }
        }
        .padding(.horizontal, Perch.s(18))
        .padding(.bottom, Perch.s(18))
        .padding(.top, Perch.chromeInset)
        .frame(width: Perch.cardWidth, height: Perch.s(490))
        .tint(Perch.accent)
        // The title stays centered in the header, as on the console.
        .overlay(alignment: .top) {
            Text("Settings")
                .font(Perch.text(13, .semibold))
                .foregroundColor(Perch.ink)
                .frame(height: Perch.chromeBand)
                .allowsHitTesting(false)
        }
        .onAppear {
            if store.template(named: selected) == nil {
                selected = store.templates.first?.name ?? ""
                nameDraft = selected
            }
        }
        .onChange(of: isPresented) { _, presented in
            if !presented {
                commitName()
                nameFocused = false
            }
        }
    }

    // MARK: Appearance

    private var appearanceControls: some View {
        HStack(alignment: .top, spacing: Perch.s(14)) {
            VStack(alignment: .leading, spacing: Perch.s(6)) {
                sectionLabel("Theme")
                Picker("Theme", selection: $appearance.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Theme")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: Perch.s(6)) {
                sectionLabel("Appearance")
                Picker("Appearance", selection: $appearance.appearance) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Appearance")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pickerStyle(.menu)
        .font(Perch.text(12))
        .foregroundColor(Perch.ink)
    }

    // MARK: Shape rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: Perch.s(6)) {
            sectionLabel("Shapes")
            ScrollView {
                VStack(alignment: .leading, spacing: Perch.s(2)) {
                    ForEach(store.templates) { template in
                        shapeRow(template)
                    }
                }
            }
            capsuleButton("New shape", disabled: false) {
                select(store.addTemplate())
                // Naming it is the first thing to do.
                nameFocused = true
            }
            .help("Add a conversation shape")
        }
        .frame(width: Perch.s(132))
    }

    /// A row per shape, wearing the composer pill's look at rest and its
    /// ink fill when selected.
    private func shapeRow(_ template: ConversationTemplate) -> some View {
        let isSelected = template.name == selected
        return Button {
            select(template.name)
        } label: {
            HStack(spacing: Perch.s(6)) {
                Image(systemName: PerchShapeIcons.icon(for: template.name))
                    .font(.system(size: Perch.s(10), weight: .medium))
                Text(template.name)
                    .font(Perch.text(12, .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundColor(isSelected ? Perch.paper : Perch.secondary)
            .padding(.horizontal, Perch.s(9))
            .frame(height: Perch.s(26))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Perch.s(7))
                .fill(isSelected ? Perch.ink : .clear))
            .perchHover(RoundedRectangle(cornerRadius: Perch.s(7)),
                        tint: isSelected ? .white : Perch.ink,
                        opacity: isSelected ? 0.14 : 0.06)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Shape editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: Perch.s(6)) {
            sectionLabel("Name")
            field {
                TextField("Shape name", text: $nameDraft)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
            }
            .onChange(of: nameFocused) { _, focused in
                if !focused { commitName() }
            }
            .help("Shown on the composer's shape pills")

            sectionLabel("Topic prompt")
                .padding(.top, Perch.s(6))
            field {
                TextField("What the topic field should ask for",
                          text: topicPromptBinding)
            }
            .help("Placeholder for the composer's topic field — say what the shape expects")

            sectionLabel("Opening text")
                .padding(.top, Perch.s(6))
            TextEditor(text: bodyBinding)
                .font(Perch.text(12))
                .foregroundColor(Perch.ink)
                .scrollContentBackground(.hidden)
                .padding(Perch.s(6))
                .background(RoundedRectangle(cornerRadius: Perch.s(8)).fill(Perch.well))
                .overlay(RoundedRectangle(cornerRadius: Perch.s(8))
                    .stroke(Perch.chipEdge, lineWidth: 1))
                .help("The run's opening message; the composer's topic is appended after a blank line, so refer to it as \u{201C}below\u{201D}")

            HStack {
                capsuleButton("Delete", disabled: store.templates.count <= 1) {
                    deleteSelected()
                }
                .help(store.templates.count <= 1
                      ? "The composer needs at least one shape"
                      : "Remove this shape")
                Spacer()
                if store.canReset(selected) {
                    capsuleButton("Reset", disabled: false) {
                        store.resetTemplate(named: selected)
                        nameDraft = selected
                    }
                    .help("Restore the shipped \(selected) text")
                }
            }
            .padding(.top, Perch.s(4))
        }
    }

    private var topicPromptBinding: Binding<String> {
        Binding(get: { store.template(named: selected)?.topicPrompt ?? "" },
                set: { store.updateTopicPrompt($0, for: selected) })
    }

    private var bodyBinding: Binding<String> {
        Binding(get: { store.template(named: selected)?.body ?? "" },
                set: { store.updateBody($0, for: selected) })
    }

    /// Commit any half-typed rename before the selection moves.
    private func select(_ name: String) {
        commitName()
        selected = name
        nameDraft = name
    }

    private func commitName() {
        guard store.template(named: selected) != nil else { return }
        let landed = store.rename(selected, to: nameDraft)
        selected = landed
        nameDraft = landed
    }

    private func deleteSelected() {
        guard let index = store.templates.firstIndex(where: { $0.name == selected })
        else { return }
        store.deleteTemplate(named: selected)
        let next = store.templates[min(index, store.templates.count - 1)].name
        selected = next
        nameDraft = next
    }

    // MARK: Furniture

    private func sectionLabel(_ label: String) -> some View {
        Text(label)
            .font(Perch.text(11, .medium))
            .foregroundColor(Perch.muted)
    }

    /// The one-line input: a plain field in a well with a chip edge — the
    /// composer card's materials at field scale.
    private func field(@ViewBuilder content: () -> some View) -> some View {
        content()
            .textFieldStyle(.plain)
            .font(Perch.text(12))
            .foregroundColor(Perch.ink)
            .padding(.horizontal, Perch.s(10))
            .frame(height: Perch.s(28))
            .background(RoundedRectangle(cornerRadius: Perch.s(8)).fill(Perch.well))
            .overlay(RoundedRectangle(cornerRadius: Perch.s(8))
                .stroke(Perch.chipEdge, lineWidth: 1))
    }

    /// The console's capsule button (New session wears the same).
    private func capsuleButton(_ label: String, disabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Perch.text(11, .medium))
                .foregroundColor(Perch.secondary)
                .padding(.horizontal, Perch.s(12))
                .frame(height: Perch.s(24))
                .background(Capsule().fill(Perch.paper))
                .overlay(Capsule().stroke(Perch.chipEdge, lineWidth: 1))
                .perchHover(Capsule())
                .opacity(disabled ? 0.45 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Previews

#Preview("Settings card") {
    SettingsView()
}
