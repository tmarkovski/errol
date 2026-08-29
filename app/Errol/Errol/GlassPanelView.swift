// The glass skin: the Liquid Glass console from DesignMockupsTake3 made
// real. Same UX surface as the classic skin — readiness cards, shape
// picker with topic and free "Edit instructions" handoff, run options,
// Start/Stop, live log — restyled as floating glass over the desktop
// (the panel window is transparent; see MenuBarController).
//
// Starting a run morphs the console into the compact companion pane:
// just the two agents' live status tiles and a prominent pause/resume
// button. Both states render inside one GlassEffectContainer, and the
// agent cards and primary control carry glassEffectID + matched geometry
// so the material itself flows between the two layouts while the AppKit
// shell animates the panel frame (PanelLayout has the sizes).
//
// Utility actions that had buttons in the classic skin (Inspect) live in
// the toolbar's gear menu, alongside Open Transcript and Restore Window
// Positions. This skin is compiled in by pointing activePanelStyle at
// .glass (see PanelRootView).

import SwiftUI

/// Agent identity tints, carried over from the design studies.
private enum GlassTheme {
    static let teal = Color(red: 0.29, green: 0.58, blue: 0.55)   // ChatGPT
    static let coral = Color(red: 0.80, green: 0.49, blue: 0.38)  // Claude
    static let amber = Color(red: 0.92, green: 0.68, blue: 0.30)

    static func tint(for appName: String) -> Color {
        appName == "ChatGPT" ? teal : coral
    }
}

struct GlassPanelView: View {
    @ObservedObject var controller: RelayController
    @Namespace private var morph

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            if controller.compact {
                companion
            } else {
                console
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: controller.compact)
        .animation(.easeInOut(duration: 0.22), value: controller.logOpen)
    }

    // MARK: - Full console

    private var console: some View {
        VStack(spacing: 12) {
            toolbar
            HStack(spacing: 12) {
                agentCard(controller.chatgptStatus,
                          conversation: controller.chatgptConversation,
                          matchID: "cardL")
                routeGlyph
                    .frame(width: 44, height: 20)
                agentCard(controller.claudeStatus,
                          conversation: controller.claudeConversation,
                          matchID: "cardR")
            }
            composer
                .disabled(controller.isRunning)
            optionsRow
                .disabled(controller.isRunning)
            actionRow
            if controller.logOpen {
                logPanel
                    .transition(.opacity)
            }
        }
        .frame(width: 520)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "bird.fill")
                .font(.system(size: 10))
            Text("ERROL")
                .font(.system(size: 10, weight: .bold))
                .tracking(2.5)
            Spacer()
            summaryBadge
            gearMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }

    private var summaryBadge: some View {
        HStack(spacing: 7) {
            if controller.isRunning {
                Image(systemName: controller.isPaused ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(controller.isPaused ? GlassTheme.amber : GlassTheme.teal)
            } else if bothReady {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(GlassTheme.teal)
            } else {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i < readyDots
                                  ? AnyShapeStyle(.secondary)
                                  : AnyShapeStyle(.quaternary))
                            .frame(width: 4, height: 4)
                    }
                }
            }
            Text(summaryText)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
        }
    }

    private var bothReady: Bool {
        controller.chatgptStatus.state == .ready && controller.claudeStatus.state == .ready
    }

    private var readyDots: Int {
        1 + [controller.chatgptStatus.state, controller.claudeStatus.state]
            .filter { $0 == .ready }.count
    }

    private var summaryText: String {
        if controller.isRunning { return controller.isPaused ? "PAUSED" : "RUNNING" }
        if bothReady { return "READY" }
        let states = [controller.chatgptStatus.state, controller.claudeStatus.state]
        if states.contains(.checking) { return "CHECKING" }
        return "GETTING READY"
    }

    private var gearMenu: some View {
        Menu {
            Button("Inspect") {
                controller.logOpen = true
                controller.runInspect()
            }
            .disabled(controller.isRunning)
            Button("Open Transcript") { controller.openTranscript() }
            Button("Restore Window Positions") { controller.restoreWindows() }
                .disabled(controller.isRunning)
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Inspect, transcript, and window positions")
    }

    /// The live readiness card: the glass mock's card shape carrying the
    /// classic skin's SideStatus data, plus the conversation state during
    /// a run. Rows keep stable heights so the cards never jitter.
    private func agentCard(_ status: SideStatus, conversation: ConversationStatus,
                           matchID: String) -> some View {
        let tint = GlassTheme.tint(for: status.appName)
        let ready = status.state == .ready
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .stroke(tint.opacity(ready ? 0.9 : 0.35), lineWidth: 1.5)
                        .frame(width: 15, height: 15)
                    Circle()
                        .fill(tint.opacity(ready ? 1 : 0.4))
                        .frame(width: 7, height: 7)
                }
                Text(status.appName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text(badgeText(status: status, conversation: conversation))
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(badgeStyle(status: status, conversation: conversation))
            }
            HStack(spacing: 7) {
                stateIcon(status.state, tint: tint)
                Text(status.headline)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(surfaceLine(status))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(detailLine(status: status, conversation: conversation))
                .font(.system(size: 10.5))
                .foregroundStyle(conversation == .ended
                                 ? AnyShapeStyle(GlassTheme.amber)
                                 : AnyShapeStyle(.tertiary))
                .lineLimit(1)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .glassEffectID(matchID, in: morph)
        .matchedGeometryEffect(id: matchID, in: morph)
    }

    private func badgeText(status: SideStatus, conversation: ConversationStatus) -> String {
        if controller.isRunning {
            switch conversation {
            case .chatting: return "COMPOSING"
            case .waiting: return "WAITING"
            case .ended: return "ENDED"
            case .notStarted: return "IDLE"
            }
        }
        return status.state == .ready ? "READY" : "PREP"
    }

    private func badgeStyle(status: SideStatus, conversation: ConversationStatus) -> AnyShapeStyle {
        let tint = GlassTheme.tint(for: status.appName)
        if controller.isRunning {
            return conversation == .chatting ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary)
        }
        return status.state == .ready ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary)
    }

    @ViewBuilder
    private func stateIcon(_ state: ReadyState, tint: Color) -> some View {
        Group {
            switch state {
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(tint)
            case .checking:
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(.tertiary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 9, height: 9)
            case .notReady:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(GlassTheme.amber)
            case .missing:
                // Red stays reserved for true failures, the Night Signal rule.
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 10, weight: .medium))
        .frame(width: 12)
    }

    /// A single space keeps the row height stable with nothing to show,
    /// the same trick the classic card uses.
    private func surfaceLine(_ status: SideStatus) -> String {
        let line = [status.surface, status.model].compactMap { $0 }
            .joined(separator: " \u{00B7} ")
        return line.isEmpty ? " " : line
    }

    private func detailLine(status: SideStatus, conversation: ConversationStatus) -> String {
        if controller.isRunning || conversation == .ended {
            return conversation.rawValue
        }
        return status.detail ?? " "
    }

    /// The relay route between the cards: dashed until both sides are
    /// ready, solid with the courier bead once the line is live.
    private var routeGlyph: some View {
        let live = bothReady || controller.isRunning
        return Canvas { ctx, size in
            let midY = size.height / 2
            var line = Path()
            line.move(to: CGPoint(x: 2, y: midY))
            line.addLine(to: CGPoint(x: size.width - 2, y: midY))
            ctx.stroke(line, with: .color(.primary.opacity(live ? 0.45 : 0.22)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                          dash: live ? [] : [3, 4]))
            let cx = size.width / 2
            let dot = CGRect(x: cx - 4, y: midY - 4, width: 8, height: 8)
            ctx.fill(Path(ellipseIn: dot),
                     with: .color(.primary.opacity(live ? 0.65 : 0.25)))
        }
    }

    // MARK: - Composer & options

    @ViewBuilder
    private var composer: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(conversationTemplates) { template in
                    Button(template.name) { controller.conversation = template.name }
                }
                Divider()
                Button(RelayController.customConversation) {
                    controller.conversation = RelayController.customConversation
                }
            } label: {
                HStack(spacing: 5) {
                    Text(controller.conversation)
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .glassEffect(.regular, in: .capsule)
            Spacer()
            if controller.selectedTemplate != nil {
                Button("Edit instructions") { controller.editInstructions() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Show the full opening message this shape composes, and edit it freely")
            }
        }
        if let template = controller.selectedTemplate {
            TextField(template.topicPrompt, text: $controller.topic, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...3)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            TextEditor(text: $controller.customInstructions)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(height: 100)
                .padding(6)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }

    private var optionsRow: some View {
        HStack(spacing: 12) {
            Toggle("Limit turns", isOn: $controller.limitTurns)
                .help("Off: the run ends when both agents sign off (or on an empty reply, a timeout, or Stop). On: also stop after this many responses.")
            TextField("10", value: $controller.turns, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 38)
                .disabled(!controller.limitTurns)
            Stepper("", value: $controller.turns, in: 1...99)
                .labelsHidden()
                .disabled(!controller.limitTurns)
            Divider().frame(height: 12)
            Toggle("New chats", isOn: $controller.newChats)
            Toggle("Tile windows", isOn: $controller.tileWindows)
                .help("Tile the chat windows side by side when the run starts")
            Spacer(minLength: 0)
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Actions & log

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                controller.logOpen.toggle()
            } label: {
                Label("Log", systemImage: controller.logOpen ? "chevron.up" : "terminal")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.glass)
            Spacer()
            if controller.isRunning {
                Button {
                    controller.compact = true
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.glass)
                .help("Shrink to the companion pane")
                pauseResumeCapsule
                Button {
                    controller.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(GlassTheme.coral)
            } else {
                beginButton
            }
        }
    }

    /// The console's pause control while a run is expanded; the companion's
    /// big circle is the same semantic control, so they share the morph id.
    private var pauseResumeCapsule: some View {
        Button {
            controller.togglePause()
        } label: {
            Label(controller.isPaused ? "Resume" : "Pause",
                  systemImage: controller.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.glass)
        .help(controller.isPaused
              ? "Send the held reply and continue"
              : "Hold the run at the next handoff")
        .glassEffectID("primary", in: morph)
        .matchedGeometryEffect(id: "primary", in: morph)
    }

    @ViewBuilder private var beginButton: some View {
        let label = Label(controller.instructionsReady ? "Begin" : "Waiting",
                          systemImage: controller.instructionsReady ? "play.fill" : "hourglass")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 4)
        Group {
            if controller.instructionsReady {
                Button { controller.start() } label: { label }
                    .buttonStyle(.glassProminent)
                    .tint(GlassTheme.teal)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button {} label: { label.foregroundStyle(.tertiary) }
                    .buttonStyle(.glass)
                    .disabled(true)
                    .help(controller.selectedTemplate == nil
                          ? "Write the instructions first"
                          : "Add a topic first")
            }
        }
        .glassEffectID("primary", in: morph)
        .matchedGeometryEffect(id: "primary", in: morph)
    }

    private var logPanel: some View {
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
                .padding(10)
            }
            .frame(height: 168)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .onChange(of: controller.logLines.count) { _, _ in
                if let last = controller.logLines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Companion (compact, in run)

    private var companion: some View {
        HStack(spacing: 14) {
            companionTile(controller.chatgptStatus,
                          conversation: controller.chatgptConversation,
                          matchID: "cardL")
            VStack(spacing: 9) {
                pauseResumeButton
                HStack(spacing: 8) {
                    miniButton("stop.fill", help: "End the run") { controller.stop() }
                    miniButton("arrow.up.left.and.arrow.down.right", help: "Expand the console") {
                        controller.compact = false
                    }
                }
            }
            companionTile(controller.claudeStatus,
                          conversation: controller.claudeConversation,
                          matchID: "cardR")
        }
    }

    private func companionTile(_ status: SideStatus, conversation: ConversationStatus,
                               matchID: String) -> some View {
        let tint = GlassTheme.tint(for: status.appName)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint.opacity(controller.isPaused ? 0.45 : 1))
                    .frame(width: 7, height: 7)
                Text(status.appName)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                if conversation == .ended {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(tint)
                }
            }
            Text(companionStatus(conversation))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            meterBars(level: meterLevel(conversation), tint: tint)
        }
        .padding(12)
        .frame(width: 132, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .glassEffectID(matchID, in: morph)
        .matchedGeometryEffect(id: matchID, in: morph)
    }

    private func companionStatus(_ conversation: ConversationStatus) -> String {
        if controller.isPaused { return "Paused" }
        switch conversation {
        case .chatting: return "Composing\u{2026}"
        case .waiting: return "Waiting"
        case .ended: return "Signed off"
        case .notStarted: return "Standing by"
        }
    }

    private func meterLevel(_ conversation: ConversationStatus) -> Int {
        if controller.isPaused { return 0 }
        switch conversation {
        case .chatting: return 3
        case .waiting: return 1
        case .ended: return 0
        case .notStarted: return 1
        }
    }

    private func meterBars(level: Int, tint: Color) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i < level ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 14, height: 4)
            }
        }
    }

    /// Resume is the tinted, inviting state; pause stays neutral glass so
    /// the button never nags while the run is healthy.
    private var pauseResumeButton: some View {
        Button {
            controller.togglePause()
        } label: {
            Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(controller.isPaused
                                 ? AnyShapeStyle(.white)
                                 : AnyShapeStyle(.primary))
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(controller.isPaused
                     ? Glass.regular.tint(GlassTheme.teal.opacity(0.9)).interactive()
                     : Glass.regular.interactive(),
                     in: .circle)
        .glassEffectID("primary", in: morph)
        .matchedGeometryEffect(id: "primary", in: morph)
        .help(controller.isPaused
              ? "Send the held reply and continue"
              : "Hold the run at the next handoff")
    }

    private func miniButton(_ symbol: String, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(help)
    }
}

// MARK: - Previews

/// A stand-in desktop; the real panel floats transparent over whatever is
/// behind it, so previews need color for the glass to sample.
private struct PreviewBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.78, green: 0.83, blue: 0.92),
                    Color(red: 0.86, green: 0.79, blue: 0.89),
                    Color(red: 0.76, green: 0.88, blue: 0.86),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(GlassTheme.teal.opacity(0.4))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -170, y: -120)
            Circle()
                .fill(GlassTheme.coral.opacity(0.35))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 190, y: 80)
        }
        .ignoresSafeArea()
    }
}

#Preview("Glass console") {
    ZStack {
        PreviewBackdrop()
        GlassPanelView(controller: RelayController())
    }
    .frame(width: 560, height: 470)
}

#Preview("Glass companion") {
    let controller = RelayController()
    controller.isRunning = true
    controller.compact = true
    controller.chatgptConversation = .chatting
    controller.claudeConversation = .waiting
    return ZStack {
        PreviewBackdrop()
        GlassPanelView(controller: controller)
    }
    .frame(width: 430, height: 160)
}
