// The setup rows: which conversation shape to run, and the topic or the
// full prompt behind it. See WireframePanelView for the skin.

import SwiftUI

struct WireConversationSetup: View {
    @Bindable var controller: RelayController

    var body: some View {
        Group {
            shapeRow
            WirePromptEditor(controller: controller)
            optionsRow
        }
        .disabled(controller.isRunning)
        .opacity(controller.isRunning ? 0.45 : 1)
    }

    private var shapeRow: some View {
        HStack(spacing: Wire.s(8)) {
            Menu {
                ForEach(conversationTemplates) { template in
                    Button(template.name) {
                        controller.selectConversation(template.name)
                    }
                }
                Divider()
                Button("Write from scratch") {
                    controller.selectConversation(RelayController.customConversation)
                }
            } label: {
                Text("[ \(controller.conversation.uppercased()) \u{25BE} ]")
                    .font(Wire.mono(9, .bold))
                    .foregroundColor(Wire.ink)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer()
            if controller.selectedTemplate != nil {
                Button {
                    if controller.isEditingInstructions {
                        controller.resetInstructionsToTemplate()
                    } else {
                        controller.editInstructions()
                    }
                } label: {
                    Text(controller.isEditingInstructions
                         ? "BACK TO SIMPLE SETUP" : "EDIT FULL PROMPT")
                        .font(Wire.mono(8, .bold))
                        .underline()
                        .foregroundColor(Wire.faint)
                }
                .buttonStyle(.plain)
                .help(controller.isEditingInstructions
                      ? "Discard full-prompt edits and return to the simple topic field"
                      : "Edit the full opening prompt without changing the selected shape")
            }
        }
    }

    private var optionsRow: some View {
        HStack(spacing: Wire.s(14)) {
            wireToggle("LIMIT TURNS", isOn: $controller.limitTurns)
                .help("Off: the run ends when both agents sign off (or on an empty reply, a timeout, or Stop). On: also stop after this many responses.")
            HStack(spacing: Wire.s(3)) {
                TextField("10", value: $controller.turns, format: .number)
                    .textFieldStyle(.plain)
                    .font(Wire.mono(10))
                    .foregroundColor(Wire.ink)
                    .multilineTextAlignment(.center)
                    .frame(width: Wire.s(26))
                    .padding(.vertical, Wire.s(2))
                    .background(Rectangle().fill(Wire.well))
                    .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
                Stepper("", value: $controller.turns, in: 1...99)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            .disabled(!controller.limitTurns)
            .opacity(controller.limitTurns ? 1 : 0.45)
            wireToggle("TILE", isOn: $controller.tileWindows)
                .help("Tile the chat windows side by side when the run starts")
            Spacer(minLength: 0)
        }
    }

    private func wireToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: Wire.s(5)) {
                ZStack {
                    Rectangle()
                        .stroke(Wire.ink, lineWidth: Wire.s(1))
                        .frame(width: Wire.s(10), height: Wire.s(10))
                    if isOn.wrappedValue {
                        Rectangle().fill(Wire.ink).frame(width: Wire.s(5), height: Wire.s(5))
                    }
                }
                Text(label)
                    .font(Wire.mono(8, .bold))
                    .foregroundColor(Wire.ink)
            }
            // A stroked Rectangle only hit-tests along its outline, so an
            // unticked box swallowed clicks aimed straight at it. The whole
            // row — box, gap, and label — is the target.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The topic field or the full-prompt editor. Its own view so a keystroke
/// invalidates only this scope (plus the run gate reading the prompt), not
/// the picker and options around it.
private struct WirePromptEditor: View {
    @Bindable var controller: RelayController

    var body: some View {
        if !controller.showsFullInstructionsEditor,
           let template = controller.selectedTemplate {
            TextField(template.topicPrompt, text: $controller.topic, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Wire.text(11))
                .foregroundColor(Wire.ink)
                .lineLimit(1...3)
                .padding(.horizontal, Wire.s(8))
                .padding(.vertical, Wire.s(6))
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
        } else {
            GrowingTextEditor(text: $controller.customInstructions,
                              font: .systemFont(ofSize: Wire.s(11)),
                              textColor: NSColor(calibratedWhite: 0.20, alpha: 1),
                              placeholder: controller.promptEditorPlaceholder)
                .padding(.horizontal, Wire.s(8))
                .padding(.vertical, Wire.s(6))
                .background(Rectangle().fill(Wire.well))
                .overlay(Rectangle().stroke(Wire.faint.opacity(0.5)))
                .help(controller.selectedTemplate == nil
                      ? "Write the complete opening prompt"
                      : "Editing the complete \(controller.conversation) prompt; choosing another shape keeps this editor open")
        }
    }
}
