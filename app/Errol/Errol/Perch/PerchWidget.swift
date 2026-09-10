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
                            .perchShimmer(active: !controller.holdRequested && !controller.stopRequested
                                                  && controller.block == nil)
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
                // A start that failed says why, where the run would have
                // been; otherwise what the readiness sweep found wanting.
                if let problem = controller.failedStart ?? readinessProblem {
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
                              font: Perch.promptFont,
                              minimumFontSize: Perch.promptMinimumFontSize,
                              textColor: Perch.inkNS, placeholderColor: Perch.placeholderNS,
                              placeholder: controller.promptEditorPlaceholder,
                              minimumLines: 1, maximumLines: Perch.promptMaximumLines)
        } else {
            GrowingTextEditor(text: $controller.topic,
                              font: Perch.promptFont,
                              minimumFontSize: Perch.promptMinimumFontSize,
                              textColor: Perch.inkNS, placeholderColor: Perch.placeholderNS,
                              placeholder: controller.topic.isEmpty
                                  ? "What should they work on together?" : nil,
                              minimumLines: 1, maximumLines: Perch.promptMaximumLines,
                              onSubmit: { controller.start() })
        }
    }

    private var steeringEditor: some View {
        GrowingTextEditor(text: Binding(get: { controller.steeringText },
                                       set: { controller.setSteeringText($0) }),
                          font: Perch.promptFont,
                          minimumFontSize: Perch.promptMinimumFontSize,
                          textColor: Perch.inkNS, placeholderColor: Perch.placeholderNS,
                          placeholder: controller.steeringText.isEmpty
                              ? "A note for the next handoff…" : nil,
                          minimumLines: 1, maximumLines: Perch.promptMaximumLines, takesFocusOnAppear: true,
                          onSubmit: { controller.sendSteering() },
                          onEscape: { _ in controller.escapeSteering() },
                          session: controller.steeringEditor)
    }

    private var runHeadline: String {
        if controller.stopRequested { return "Ending at the next safe point…" }
        if let block = controller.block { return block.headline(names: controller.names) }
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
            if let block = controller.block, !controller.stopRequested {
                Text(block.recovery(names: controller.names))
                    .font(Perch.text(11))
                    .foregroundStyle(Perch.red)
                    .lineLimit(2)
                    .help(block.recovery(names: controller.names))
                    .transition(.opacity)
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

/// One configuration entry point beside the primary action, in every state.
/// Run options stay visible but locked while the relay owns the conversation.
struct PerchWidgetSetup: View {
    @Bindable var controller: RelayController
    @State private var showingSetup = false

    var body: some View {
        Button { showingSetup.toggle() } label: {
            Image(systemName: "slider.horizontal.3")
                .font(Perch.text(15, .medium))
                .foregroundStyle(Perch.secondary)
                .frame(width: Perch.s(42), height: Perch.s(42))
                .background(Circle().fill(showingSetup ? Perch.well : .clear))
                .perchHover(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .help("Conversation, turn limit, windows, and appearance")
        .popover(isPresented: $showingSetup, arrowEdge: .bottom) {
            PerchSettingsPopover(controller: controller) {
                showingSetup = false
                controller.openSettings()
            }
        }
    }
}

struct PerchWidgetActions: View {
    let controller: RelayController

    var body: some View {
        HStack(spacing: Perch.s(10)) {
            PerchWidgetSetup(controller: controller)
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
            }
        }
        .fixedSize()
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
