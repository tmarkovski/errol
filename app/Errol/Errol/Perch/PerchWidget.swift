import SwiftUI

/// The center of the capsule shares the controller's existing editing and
/// handoff lifetimes. The transfer probe stays mounted through every state.
struct PerchWidgetCenter: View {
    @Bindable var controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(9)) {
            ZStack(alignment: .leading) {
                if controller.isRunning {
                    if controller.isSteering {
                        steeringEditor
                    } else {
                        Text(runHeadline)
                            .font(Perch.text(19))
                            .foregroundStyle(Perch.ink)
                            .lineLimit(2)
                            .contentTransition(.opacity)
                            .perchShimmer(active: !controller.holdRequested && !controller.stopRequested)
                    }
                } else if controller.hasFinishedRun {
                    PerchRunSummary(controller: controller)
                } else {
                    openingEditor
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                PromptTransferProbe(source: controller.promptTransferSource)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if controller.isRunning {
                runningDetails
            } else if !controller.hasFinishedRun {
                PerchWidgetSetup(controller: controller)
                if let problem = readinessProblem {
                    Text(problem)
                        .font(Perch.text(11))
                        .foregroundStyle(Perch.red)
                        .lineLimit(2)
                        .help(problem)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readinessProblem: String? {
        let problems = [controller.chatgptStatus, controller.claudeStatus]
            .filter { $0.state == .missing || $0.state == .notReady }
            .map { "\($0.appName): \($0.headline)" }
        return problems.isEmpty ? nil : problems.joined(separator: " · ")
    }

    @ViewBuilder private var openingEditor: some View {
        if controller.showsFullInstructionsEditor {
            GrowingTextEditor(text: $controller.customInstructions,
                              font: .systemFont(ofSize: Perch.s(19)),
                              textColor: Perch.inkNS, placeholderColor: Perch.placeholderNS,
                              placeholder: controller.promptEditorPlaceholder,
                              minimumLines: 1, maximumLines: 8)
        } else {
            GrowingTextEditor(text: $controller.topic,
                              font: .systemFont(ofSize: Perch.s(19)),
                              textColor: Perch.inkNS, placeholderColor: Perch.placeholderNS,
                              placeholder: controller.topic.isEmpty
                                  ? "What should they work on together?" : nil,
                              minimumLines: 1, maximumLines: 8,
                              onSubmit: { controller.start() })
        }
    }

    private var steeringEditor: some View {
        GrowingTextEditor(text: Binding(get: { controller.steeringText },
                                       set: { controller.setSteeringText($0) }),
                          font: .systemFont(ofSize: Perch.s(19)),
                          textColor: Perch.inkNS, placeholderColor: Perch.placeholderNS,
                          placeholder: controller.steeringText.isEmpty
                              ? "A note for the next handoff…" : nil,
                          minimumLines: 1, maximumLines: 8, takesFocusOnAppear: true,
                          onSubmit: { controller.sendSteering() },
                          onEscape: { _ in controller.escapeSteering() },
                          session: controller.steeringEditor)
    }

    private var runHeadline: String {
        if controller.stopRequested { return "Ending at the next safe point…" }
        if controller.isSteeringPending { return "Finishing the handoff…" }
        if controller.isHolding { return "Paused at the handoff" }
        if controller.chatgptConversation == .chatting {
            return "\(controller.chatgptStatus.appName) is replying…"
        }
        if controller.claudeConversation == .chatting {
            return "\(controller.claudeStatus.appName) is replying…"
        }
        return controller.currentTurn == 0 ? "Starting the conversation…" : "Relaying the reply…"
    }

    private var hasNoteFeedback: Bool {
        controller.isSteering || controller.steeringQueued
            || controller.steeringInFlight != nil || controller.lastReceipt != nil
    }

    private var runningDetails: some View {
        VStack(alignment: .leading, spacing: Perch.s(6)) {
            HStack(spacing: Perch.s(12)) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(controller.conversation) · \(turnText) · \(clock(at: context.date))")
                        .font(Perch.text(11))
                        .foregroundStyle(Perch.muted)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !controller.holdRequested && !controller.stopRequested {
                    Button { controller.beginSteering() } label: {
                        Label(controller.steeringQueued ? "Edit note" : "Pause to steer",
                              systemImage: "pencil")
                            .font(Perch.text(11, .medium))
                            .foregroundStyle(Perch.secondary)
                            .padding(.horizontal, Perch.s(10))
                            .frame(height: Perch.s(26))
                            .background(Capsule().fill(Perch.well))
                            .perchHover(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Pause at a safe handoff and add a note here; avoid typing in the chat apps during a run.")
                }
            }
            if hasNoteFeedback {
                PerchRunLine(controller: controller)
            }
            if controller.steeringQueued {
                Text(controller.steeringText)
                    .font(Perch.text(12))
                    .foregroundStyle(Perch.secondary)
                    .lineLimit(2)
                    .help(controller.steeringText)
            }
        }
    }

    private var turnText: String {
        controller.limitTurns ? "Turn \(controller.currentTurn) of \(controller.turns)"
            : "Turn \(controller.currentTurn)"
    }

    private func clock(at date: Date) -> String {
        let elapsed = Int(controller.elapsedRunDuration(at: date))
        return elapsed >= 3600
            ? String(format: "%d:%02d:%02d", elapsed / 3600, elapsed / 60 % 60, elapsed % 60)
            : String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }
}

/// Frequently used choices stay direct. More shapes, the full instruction
/// preview, tiling, and Settings live in one compact, arrow-free setup control.
struct PerchWidgetSetup: View {
    @Bindable var controller: RelayController
    @State private var showingSetup = false
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Perch.s(10)) {
                modes
                turns
                Text("\(controller.firstSpeaker == .chatgpt ? controller.chatgptStatus.appName : controller.claudeStatus.appName) starts")
                    .font(Perch.text(11))
                    .foregroundStyle(Perch.muted)
                    .fixedSize()
                setupButton
            }
            HStack(spacing: Perch.s(8)) {
                setupButton
                Text("\(controller.conversation) · \(controller.limitTurns ? "\(controller.turns) turns" : "Auto")")
                    .font(Perch.text(11))
                    .foregroundStyle(Perch.muted)
                    .lineLimit(1)
            }
        }
        .popover(isPresented: $showingSetup, arrowEdge: .bottom) {
            setupContents
        }
    }

    private var quickName: String {
        settings.templates.first?.name ?? RelayController.customConversation
    }

    private var modes: some View {
        HStack(spacing: Perch.s(2)) {
            mode(RelayController.freeConversation)
            mode(quickName)
        }
        .padding(Perch.s(3))
        .background(Capsule().fill(Perch.well))
        .fixedSize()
    }

    private func mode(_ name: String) -> some View {
        Button { controller.selectConversation(name) } label: {
            Text(name)
                .font(Perch.text(11, controller.conversation == name ? .medium : .regular))
                .lineLimit(1)
                .padding(.horizontal, Perch.s(10))
                .frame(height: Perch.s(25))
                .foregroundStyle(controller.conversation == name ? Perch.ink : Perch.secondary)
                .background(Capsule().fill(controller.conversation == name ? Perch.paper : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(controller.conversation == name ? .isSelected : [])
    }

    private var turns: some View {
        HStack(spacing: Perch.s(6)) {
            Button { controller.limitTurns.toggle() } label: {
                Text(controller.limitTurns ? "Turns" : "Auto")
                    .font(Perch.text(11))
                    .foregroundStyle(Perch.muted)
                    .frame(minHeight: Perch.s(28))
            }
            .buttonStyle(.plain)
            .help(controller.limitTurns ? "Use automatic ending instead" : "Set a turn limit")
            .accessibilityLabel(controller.limitTurns ? "Turn limit on" : "Automatic ending")
            if controller.limitTurns {
                HStack(spacing: Perch.s(2)) {
                    nudge("minus", label: "Fewer turns", disabled: controller.turns <= 1) {
                        controller.turns = max(1, controller.turns - 1)
                    }
                    PerchTurnsField(value: $controller.turns,
                                    font: .monospacedDigitSystemFont(ofSize: Perch.s(11), weight: .medium),
                                    color: Perch.inkNS)
                        .accessibilityLabel("Turn limit")
                    nudge("plus", label: "More turns", disabled: controller.turns >= 99) {
                        controller.turns = min(99, controller.turns + 1)
                    }
                }
                .padding(.horizontal, Perch.s(3))
                .background(Capsule().fill(Perch.well))
            }
        }
        .fixedSize()
    }

    private func nudge(_ icon: String, label: String, disabled: Bool,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(Perch.text(12))
                .foregroundStyle(Perch.secondary)
                .frame(width: Perch.s(25), height: Perch.s(29))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
        .help(label)
    }

    private var setupButton: some View {
        Button { showingSetup.toggle() } label: {
            HStack(spacing: Perch.s(5)) {
                Image(systemName: "slider.horizontal.3")
                if controller.conversation != RelayController.freeConversation,
                   controller.conversation != quickName {
                    Text(controller.conversation).lineLimit(1)
                }
            }
            .font(Perch.text(11, .medium))
            .foregroundStyle(Perch.secondary)
            .padding(.horizontal, Perch.s(8))
            .frame(height: Perch.s(29))
            .background(Capsule().fill(Perch.well))
            .perchHover(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Conversation setup")
        .help("Shapes, instructions, window arrangement, and Settings")
    }

    private var setupContents: some View {
        VStack(alignment: .leading, spacing: Perch.s(12)) {
            Text("Conversation setup").font(Perch.text(13, .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: Perch.s(3)) {
                    shapeChoice(RelayController.freeConversation)
                    ForEach(settings.templates) { template in shapeChoice(template.name) }
                    shapeChoice(RelayController.customConversation)
                }
            }
            .frame(height: min(Perch.s(180), CGFloat(settings.templates.count + 2) * Perch.s(30)))
            if let template = controller.selectedTemplate {
                ScrollView {
                    Text(template.body)
                        .font(Perch.text(11))
                        .foregroundStyle(Perch.muted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: Perch.s(100))
            }
            Divider()
            turns
            Text("\(controller.firstSpeaker == .chatgpt ? controller.chatgptStatus.appName : controller.claudeStatus.appName) starts · click either app to change")
                .font(Perch.text(11)).foregroundStyle(Perch.muted)
            Toggle("Tile chat windows", isOn: Binding(get: { controller.windowsTiled },
                                                     set: { _ in controller.toggleTiling() }))
                .disabled(!controller.windowsTiled && !controller.canTile)
                .font(Perch.text(12))
            Button("Settings…") {
                showingSetup = false
                controller.openSettings()
            }
        }
        .padding(Perch.s(18))
        .frame(width: Perch.s(320))
        .background(Perch.paper)
        .foregroundStyle(Perch.ink)
        .tint(Perch.accent)
    }

    private func shapeChoice(_ name: String) -> some View {
        Button { controller.selectConversation(name) } label: {
            HStack {
                Text(name == RelayController.customConversation ? "Write from scratch" : name)
                Spacer()
                if controller.conversation == name { Image(systemName: "checkmark") }
            }
            .font(Perch.text(12))
            .padding(.horizontal, Perch.s(8))
            .frame(height: Perch.s(28))
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: Perch.s(6))
                .fill(controller.conversation == name ? Perch.well : .clear))
        }
        .buttonStyle(.plain)
    }
}

struct PerchWidgetActions: View {
    let controller: RelayController

    var body: some View {
        HStack(spacing: Perch.s(10)) {
            Button(action: primaryAction) {
                Image(systemName: primaryIcon)
                    .font(Perch.text(16, .semibold))
                    .foregroundStyle(Perch.onAccent)
                    .frame(width: Perch.s(42), height: Perch.s(42))
                    .background(Circle().fill(Perch.accent))
                    .perchHover(Circle(), tint: .white)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(primaryDisabled)
            .opacity(primaryDisabled ? 0.4 : 1)
            .help(primaryLabel)
            .accessibilityLabel(primaryLabel)
            .keyboardShortcut(controller.isRunning ? nil : .defaultAction)

            if controller.isRunning {
                Button { controller.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(Perch.text(14, .semibold))
                        .foregroundStyle(Perch.accentText)
                        .frame(width: Perch.s(42), height: Perch.s(42))
                        .overlay(Circle().stroke(Perch.accent.opacity(0.8), lineWidth: 1.2))
                        .perchHover(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(controller.stopRequested)
                .opacity(controller.stopRequested ? 0.4 : 1)
                .help("Stop at the next safe point")
                .accessibilityLabel("Stop")
            } else {
                PerchOverflowMenu(controller: controller)
            }
        }
        .frame(width: Perch.s(94))
    }

    private var primaryDisabled: Bool {
        if controller.isRunning { return controller.isSteeringPending || controller.stopRequested }
        return !controller.hasFinishedRun && !controller.instructionsReady
    }

    private var primaryIcon: String {
        if controller.hasFinishedRun { return "square.and.pencil" }
        if !controller.isRunning { return "play.fill" }
        if controller.isSteering { return controller.steeringHasText ? "arrow.up" : "play.fill" }
        return "pause.fill"
    }

    private var primaryLabel: String {
        if controller.hasFinishedRun { return "New session" }
        if !controller.isRunning { return "Run" }
        if controller.stopRequested { return "Ending the run" }
        if controller.isSteeringPending { return "Pausing at the next safe handoff" }
        if controller.isSteering { return controller.steeringHasText ? "Send note" : "Continue without a note" }
        return "Pause"
    }

    private func primaryAction() {
        if controller.hasFinishedRun { controller.resetSession() }
        else if !controller.isRunning { controller.start() }
        else if controller.isSteering { controller.sendSteering() }
        else { controller.beginSteering() }
    }
}
