// The classic panel skin (see PanelRootView for skin selection): the
// conversation setup (shape picker, topic, instructions), run options,
// Start/Stop, and the live log.

import SwiftUI

struct ControlPanelView: View {
    @Bindable var controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            readinessStrip

            Group {
                sectionHeader("Conversation")
                conversationSetup

                HStack(spacing: 12) {
                    Toggle("Limit turns:", isOn: $controller.limitTurns)
                        .help("Off: the run ends when both agents sign off (or on an empty reply, a timeout, or Stop). On: also stop after this many responses.")
                    TextField("10", value: $controller.turns, format: .number)
                        .frame(width: 48)
                        .disabled(!controller.limitTurns)
                    Stepper("", value: $controller.turns, in: 1...99)
                        .labelsHidden()
                        .disabled(!controller.limitTurns)
                    Spacer()
                }

                Toggle("Tile the chat windows side by side", isOn: $controller.tileWindows)
            }
            .disabled(controller.isRunning)

            HStack {
                Button("Inspect") { controller.runInspect() }
                    .disabled(controller.isRunning)
                    .help("Dump both apps' windows, buttons, and selector matches into the log")
                Spacer()
                Button("Stop") { controller.stop() }
                    .disabled(!controller.isRunning)
                Button("Start") { controller.start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.isRunning || !controller.instructionsReady)
            }

            sectionHeader("Log")
            logView
        }
        .padding(14)
        .frame(width: 440, height: 620)
    }

    /// Shape selection and full-prompt editing are independent: Edit keeps the
    /// current shape selected, and choosing another shape keeps the editor at
    /// the same level of detail. Custom is only for writing from scratch.
    @ViewBuilder
    private var conversationSetup: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { controller.conversation },
                set: { controller.selectConversation($0) }
            )) {
                ForEach(conversationTemplates) { template in
                    Text(template.name).tag(template.name)
                }
                Divider()
                Text("Write from scratch")
                    .tag(RelayController.customConversation)
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
            if controller.selectedTemplate != nil {
                Button(controller.isEditingInstructions
                       ? "Back to simple setup" : "Edit full prompt") {
                    if controller.isEditingInstructions {
                        controller.resetInstructionsToTemplate()
                    } else {
                        controller.editInstructions()
                    }
                }
                    .buttonStyle(.link)
                    .help(controller.isEditingInstructions
                          ? "Discard full-prompt edits and return to the simple topic field"
                          : "Edit the full opening prompt without changing the selected shape")
            }
        }
        if !controller.showsFullInstructionsEditor,
           let template = controller.selectedTemplate {
            TextField(template.topicPrompt, text: $controller.topic, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
        } else {
            GrowingTextEditor(text: $controller.customInstructions,
                              font: .systemFont(ofSize: 13),
                              placeholder: controller.promptEditorPlaceholder)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(nsColor: .separatorColor)))
                .help(controller.selectedTemplate == nil
                      ? "Write the complete opening prompt"
                      : "Editing the complete \(controller.conversation) prompt; choosing another shape keeps this editor open")
        }
    }

    /// ChatGPT on the left, Claude on the right — the same sides the tiling
    /// arrangement uses — each with its live readiness and detected surface.
    private var readinessStrip: some View {
        HStack(spacing: 8) {
            SideStatusCard(status: controller.chatgptStatus,
                           conversation: controller.chatgptConversation)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            SideStatusCard(status: controller.claudeStatus,
                           conversation: controller.claudeConversation)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(controller.logLines) { line in
                        Text(line.text)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor)))
            .onChange(of: controller.logLines.count) { _, _ in
                if let last = controller.logLines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

private struct SideStatusCard: View {
    let status: SideStatus
    let conversation: ConversationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(status.appName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                Text(status.headline)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Text(subline)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(conversation.rawValue)
                .font(.system(size: 11))
                .foregroundColor(conversation == .ended ? .orange : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 5)
            .stroke(Color(nsColor: .separatorColor)))
    }

    /// A single space keeps the card height stable when there is no surface
    /// to show yet.
    private var subline: String {
        let lead = [status.surface, status.model].compactMap { $0 }.joined(separator: " · ")
        let parts = [lead.isEmpty ? nil : lead, status.detail].compactMap { $0 }
        return parts.isEmpty ? " " : parts.joined(separator: " — ")
    }

    private var dotColor: Color {
        switch status.state {
        case .checking: return .gray
        case .missing: return .red
        case .notReady: return .orange
        case .ready: return .green
        }
    }
}

#Preview {
    ControlPanelView(controller: RelayController())
}
