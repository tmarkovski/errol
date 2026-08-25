// The SwiftUI interface inside the floating panel: the seed instruction,
// run options, Start/Stop, and the live log.

import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var controller: RelayController

    private var seedIsEmpty: Bool {
        controller.seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            readinessStrip

            Group {
                sectionHeader("Instruction to seed the conversation")
                TextEditor(text: $controller.seed)
                    .font(.system(size: 13))
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(nsColor: .separatorColor)))

                HStack(spacing: 12) {
                    Text("Turns:")
                    TextField("10", value: $controller.turns, format: .number)
                        .frame(width: 48)
                    Stepper("", value: $controller.turns, in: 1...99)
                        .labelsHidden()
                    Toggle("Start new chats", isOn: $controller.newChats)
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
                    .disabled(controller.isRunning || seedIsEmpty)
            }

            sectionHeader("Log")
            logView
        }
        .padding(14)
        .frame(width: 440, height: 620)
    }

    /// ChatGPT on the left, Claude on the right — the same sides the tiling
    /// arrangement uses — each with its live readiness and detected surface.
    private var readinessStrip: some View {
        HStack(spacing: 8) {
            SideStatusCard(status: controller.chatgptStatus)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            SideStatusCard(status: controller.claudeStatus)
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
                VStack(alignment: .leading, spacing: 2) {
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
        let parts = [status.surface, status.detail].compactMap { $0 }
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
