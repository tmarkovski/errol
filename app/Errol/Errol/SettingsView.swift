// The settings card: the wireframe instrument's idiom — paper, mono caps,
// hairline wells — inside a real titled window that keeps the system close
// button and floats one level above the console (MenuBarController owns
// the window). For now it manages one thing: the conversation shapes
// behind the panel's picker — add, rename, rewrite, delete.

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var selected: String
    /// The name field commits on Enter or focus loss rather than per
    /// keystroke: names are the shapes' identity (the picker selection and
    /// the per-shape drafts key on them), and half-typed renames would
    /// trip the uniqueness rule on every letter.
    @State private var nameDraft: String
    @FocusState private var nameFocused: Bool

    init() {
        let first = SettingsStore.shared.templates.first?.name ?? ""
        _selected = State(initialValue: first)
        _nameDraft = State(initialValue: first)
    }

    var body: some View {
        VStack(spacing: Wire.s(10)) {
            header
            HStack(alignment: .top, spacing: Wire.s(12)) {
                rail
                editor
            }
        }
        .padding(Wire.s(16))
        .frame(width: Wire.s(480), height: Wire.s(400))
        .background(Wire.paper)
        .environment(\.colorScheme, .light)
        .onAppear {
            if store.template(named: selected) == nil {
                selected = store.templates.first?.name ?? ""
                nameDraft = selected
            }
        }
    }

    /// Mirrors the panel's title strip. The left side stays empty on
    /// purpose — the window's traffic lights sit there, over the
    /// transparent title bar.
    private var header: some View {
        HStack {
            Spacer()
            Text("SETTINGS")
                .font(Wire.mono(8, .bold))
                .tracking(1.2)
                .foregroundColor(Wire.ink)
        }
    }

    // MARK: Shape rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: Wire.s(6)) {
            Text("SHAPES")
                .font(Wire.mono(8, .bold))
                .tracking(1.2)
                .foregroundColor(Wire.faint)
            ScrollView {
                VStack(alignment: .leading, spacing: Wire.s(3)) {
                    ForEach(store.templates) { template in
                        shapeRow(template)
                    }
                }
            }
            wireButton("+ NEW", disabled: false) {
                select(store.addTemplate())
                // Naming it is the first thing to do.
                nameFocused = true
            }
            .help("Add a conversation shape")
        }
        .frame(width: Wire.s(120))
    }

    private func shapeRow(_ template: ConversationTemplate) -> some View {
        let isSelected = template.name == selected
        return Button {
            select(template.name)
        } label: {
            Text(template.name.uppercased())
                .font(Wire.mono(8.5, .bold))
                .foregroundColor(isSelected ? Wire.ink : Wire.faint)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, Wire.s(6))
                .padding(.vertical, Wire.s(4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Rectangle().fill(isSelected ? Wire.well : .clear))
                .overlay(Rectangle().stroke(isSelected ? Wire.ink : .clear,
                                            lineWidth: Wire.s(1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Shape editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: Wire.s(6)) {
            fieldLabel("NAME")
            wireField {
                TextField("Shape name", text: $nameDraft)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
            }
            .onChange(of: nameFocused) { _, focused in
                if !focused { commitName() }
            }
            .help("Shown in the panel's shape picker")

            fieldLabel("TOPIC PROMPT")
                .padding(.top, Wire.s(4))
            wireField {
                TextField("What the topic field should ask for",
                          text: topicPromptBinding)
            }
            .help("Placeholder for the panel's topic field — say what the shape expects")

            fieldLabel("OPENING TEXT")
                .padding(.top, Wire.s(4))
            TextEditor(text: bodyBinding)
                .font(Wire.text(11))
                .foregroundColor(Wire.ink)
                .scrollContentBackground(.hidden)
                .padding(Wire.s(4))
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
                .help("The run's opening message; the panel's topic is appended after a blank line, so refer to it as \u{201C}below\u{201D}")

            HStack {
                wireButton("DELETE", disabled: store.templates.count <= 1) {
                    deleteSelected()
                }
                .help(store.templates.count <= 1
                      ? "The picker needs at least one shape"
                      : "Remove this shape")
                Spacer()
                if store.canReset(selected) {
                    wireButton("RESET", disabled: false) {
                        store.resetTemplate(named: selected)
                        nameDraft = selected
                    }
                    .help("Restore the shipped \(selected) text")
                }
            }
            .padding(.top, Wire.s(2))
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

    // MARK: Wireframe furniture

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(Wire.mono(8, .bold))
            .tracking(1.2)
            .foregroundColor(Wire.faint)
    }

    /// The skin's one-line input plate: plain field in a well, hairline rule.
    private func wireField(@ViewBuilder content: () -> some View) -> some View {
        content()
            .textFieldStyle(.plain)
            .font(Wire.text(11))
            .foregroundColor(Wire.ink)
            .padding(.horizontal, Wire.s(8))
            .padding(.vertical, Wire.s(6))
            .background(Rectangle().fill(Wire.well))
            .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
    }

    private func wireButton(_ label: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Wire.mono(9, .bold))
                .foregroundColor(disabled ? Wire.faint : Wire.ink)
                .padding(.horizontal, Wire.s(8))
                .padding(.vertical, Wire.s(3))
                .overlay(Rectangle().stroke(disabled ? Wire.faint : Wire.ink,
                                            lineWidth: Wire.s(1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Previews

#Preview("Settings card") {
    SettingsView()
}
