import SwiftUI

/// The center of the capsule: the guided instruction, then the topic
/// editor, then the exchange's one running sentence — or the note editor
/// while the run is paused — and the ending's summary. It shares the
/// controller's existing editing and handoff lifetimes, and the transfer
/// probe stays mounted through every state.
struct PerchWidgetCenter: View {
    @Bindable var controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(6)) {
            ZStack(alignment: .leading) {
                switch controller.stage {
                case .setup:
                    PerchSetupCenter(controller: controller)
                case .compose:
                    composer
                case .running:
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
                case .finished:
                    ScrollView(.vertical) {
                        PerchRunSummary(controller: controller)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                PromptTransferProbe(source: controller.promptTransferSource)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if controller.stage == .running {
                if controller.isSteering {
                    PerchRunLine(controller: controller)
                } else {
                    HStack(spacing: Perch.s(14)) {
                        ScrollView(.vertical) { runningDetails }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PerchWidgetActions(controller: controller)
                    }
                    .padding(.top, Perch.s(6))
                    .frame(minHeight: Perch.actionDiameter)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Compose

    /// The topic alone, and — when a destination is not ready — why Send
    /// waits. The shape choice is off the composer for now: the topic is
    /// the whole opening message (RelayController.conversation).
    private var composer: some View {
        VStack(alignment: .leading, spacing: Perch.s(6)) {
            openingEditor
            if let (problem, isProblem) = composeProblem {
                Text(problem)
                    .font(Perch.text(11))
                    .foregroundStyle(isProblem ? Perch.red : Perch.muted)
                    .lineLimit(1)
                    .help(problem)
                    .contentTransition(.opacity)
            }
        }
        .animation(Perch.fade, value: composeProblem?.0)
    }

    /// A start that failed says why, where the run would have been;
    /// otherwise a destination that is not ready. The topic's own absence
    /// only disables Send, whose tooltip says so.
    private var composeProblem: (String, Bool)? {
        if let failed = controller.failedStart { return (failed, true) }
        if let problem = controller.setup.problem { return (problem, true) }
        guard let blocker = controller.setup.state.sendBlocker(names: controller.names) else { return nil }
        let verifying = [Speaker.chatgpt, .claude].contains {
            controller.setup.state[$0].connection?.readiness == .unverified
        }
        return (blocker, !verifying)
    }

    /// The editor takes the keyboard as it appears: reaching this screen is
    /// the moment to type, and the shell has already made the console key
    /// (SetupController.onReachCompose).
    @ViewBuilder private var openingEditor: some View {
        if controller.showsFullInstructionsEditor {
            GrowingTextEditor(text: $controller.customInstructions,
                              font: Perch.promptFont,
                              minimumFontSize: Perch.promptMinimumFontSize,
                              textColor: Perch.inkNS, caretColor: Perch.accentTextNS,
                              placeholderColor: Perch.placeholderNS,
                              placeholder: controller.promptEditorPlaceholder,
                              minimumLines: 1, maximumLines: Perch.promptMaximumLines,
                              fitsAvailableHeight: true,
                              takesFocusOnAppear: true)
        } else {
            GrowingTextEditor(text: $controller.topic,
                              font: Perch.promptFont,
                              minimumFontSize: Perch.promptMinimumFontSize,
                              textColor: Perch.inkNS, caretColor: Perch.accentTextNS,
                              placeholderColor: Perch.placeholderNS,
                              placeholder: controller.topic.isEmpty ? topicPlaceholder : nil,
                              minimumLines: 1, maximumLines: Perch.promptMaximumLines,
                              fitsAvailableHeight: true,
                              takesFocusOnAppear: true,
                              onSubmit: { controller.start() })
        }
    }

    /// Each shape's own topic prompt; Free chat asks for the whole message.
    private var topicPlaceholder: String {
        if let template = controller.selectedTemplate { return template.topicPrompt }
        return "What should they work on together?"
    }

    // MARK: Running

    private var steeringEditor: some View {
        GrowingTextEditor(text: Binding(get: { controller.steeringText },
                                       set: { controller.setSteeringText($0) }),
                          font: Perch.promptFont,
                          minimumFontSize: Perch.promptMinimumFontSize,
                          textColor: Perch.inkNS, caretColor: Perch.accentTextNS,
                          placeholderColor: Perch.placeholderNS,
                          placeholder: controller.steeringText.isEmpty
                              ? "A note for the next handoff\u{2026}" : nil,
                          minimumLines: 1, maximumLines: Perch.promptMaximumLines,
                          fitsAvailableHeight: true, takesFocusOnAppear: true,
                          onSubmit: { controller.sendSteering() },
                          onEscape: { _ in controller.escapeSteering() },
                          session: controller.steeringEditor)
    }

    /// The one running sentence: what is happening in the apps now.
    private var runHeadline: String {
        let names = controller.names
        if controller.stopRequested { return "Ending at the next safe point\u{2026}" }
        if let block = controller.block { return block.headline(names: names) }
        if controller.isSteeringPending { return "Pausing after the current handoff\u{2026}" }
        if controller.isHolding { return "Paused \u{00B7} Nothing is being copied or sent" }
        switch (controller.chatgptConversation, controller.claudeConversation) {
        case (.chatting, _): return "\(names.chatgpt) is replying\u{2026}"
        case (_, .chatting): return "\(names.claude) is replying\u{2026}"
        case (.replied, _): return "Sending \(names.chatgpt)'s reply to \(names.claude)"
        case (_, .replied): return "Sending \(names.claude)'s reply to \(names.chatgpt)"
        default:
            return controller.currentTurn == 0
                ? "Sending the topic to \(controller.appName(controller.firstSpeaker))\u{2026}"
                : "Relaying the reply\u{2026}"
        }
    }

    private var hasNoteFeedback: Bool {
        controller.isSteering || controller.steeringQueued
            || controller.steeringInFlight != nil || controller.lastReceipt != nil
    }

    private var runningDetails: some View {
        VStack(alignment: .leading, spacing: Perch.s(5)) {
            if let block = controller.block, !controller.stopRequested {
                Text(block.recovery(names: controller.names))
                    .font(Perch.text(11))
                    .foregroundStyle(Perch.red)
                    .lineLimit(2)
                    .help(block.recovery(names: controller.names))
                    .transition(.opacity)
            } else if !hasNoteFeedback {
                Text("Pause before typing in either conversation.")
                    .font(Perch.text(12))
                    .foregroundStyle(Perch.secondary)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Run metadata takes the progress meter's toolbar slot, leaving room for
/// the large activity title and the copy beside Pause and Stop.
struct PerchRunMetadata: View {
    let controller: RelayController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let turn = controller.limitTurns ? "Turn \(controller.currentTurn) of \(controller.turns)"
                : "Turn \(controller.currentTurn)"
            let phase = controller.isSteering ? "Paused" : controller.conversation
            Text("\(phase) · \(turn) · \(runClock(controller.elapsedRunDuration(at: context.date)))")
                .font(Perch.text(11))
                .foregroundStyle(Perch.muted)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// One configuration entry point at the center's top-right corner, in
/// every state: the existing sliders icon in a quiet circular target.
/// Run options stay visible but locked while
/// the relay owns the conversation.
struct PerchWidgetSetup: View {
    @Bindable var controller: RelayController
    @State private var showingSetup = false

    var body: some View {
        Button { showingSetup.toggle() } label: {
            Image(systemName: "slider.horizontal.3")
                .font(Perch.text(15, .medium))
                .foregroundStyle(showingSetup ? Perch.ink : Perch.secondary)
                .frame(width: Perch.actionDiameter, height: Perch.actionDiameter)
                .background(Circle().fill(showingSetup ? Perch.well : .clear))
                .perchHover(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Configure")
        .help("Configure")
        .popover(isPresented: $showingSetup, arrowEdge: .bottom) {
            PerchSettingsPopover(controller: controller)
        }
    }
}

/// Named actions stay below editors and the ending. During a run, the
/// fixed Pause/Stop icons sit beside the supporting copy instead.
struct PerchWidgetActions: View {
    let controller: RelayController

    var body: some View {
        switch controller.stage {
        case .setup:
            PerchSetupActions(controller: controller)
        case .compose:
            leading { send }
        case .running:
            if controller.isSteering { leading { paused } } else { running }
        case .finished:
            leading { finished }
        }
    }

    private func leading<Actions: View>(@ViewBuilder _ actions: () -> Actions) -> some View {
        actions()
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var send: some View {
        PerchCapsuleButton(title: controller.sendLabel, icon: "paperplane.fill") { controller.start() }
            .disabled(controller.sendBlocker != nil)
            .keyboardShortcut(.defaultAction)
            .help(controller.sendBlocker ?? "Send the topic to \(controller.appName(controller.firstSpeaker)) and start relaying")
    }

    private var running: some View {
        HStack(spacing: Perch.s(8)) {
            PerchRevealButton(title: controller.steeringQueued ? "Edit note" : "Pause to steer",
                              icon: "pause.fill") { controller.beginSteering() }
                .disabled(controller.isSteeringPending || controller.stopRequested)
                .help(controller.isSteeringPending
                      ? "Pausing after the current handoff"
                      : "Pause at a safe handoff and write a note for the next side")
            PerchRevealButton(title: "Stop", icon: "stop.fill", prominent: false,
                              labelClearance: 1.5 * Perch.actionDiameter + Perch.s(16)) { controller.stop() }
                .disabled(controller.stopRequested)
                .help("Stop at the next safe point")
        }
    }

    private var paused: some View {
        HStack(spacing: Perch.s(8)) {
            PerchCapsuleButton(title: "Send note & continue", icon: "arrow.up") { controller.sendSteering() }
                .disabled(!controller.steeringHasText)
                .help(controller.nextRecipient.map { "The note goes to \($0) with the next handoff" }
                      ?? "The note goes with the next handoff")
            stop
            PerchTextButton(title: "Resume without note") { controller.resumeWithoutNote() }
        }
    }

    private var stop: some View {
        PerchCapsuleButton(title: "Stop", style: .glass, icon: "stop.fill") { controller.stop() }
            .disabled(controller.stopRequested)
            .help("Stop at the next safe point")
    }

    /// The two next intentions side by side, the filled one first: the
    /// same conversations again, or new ones — a glass secondary, as Stop
    /// is beside Pause.
    private var finished: some View {
        HStack(spacing: Perch.s(8)) {
            PerchCapsuleButton(title: "Another topic here", icon: "arrow.counterclockwise") {
                controller.anotherTopicHere()
            }
            .keyboardShortcut(.defaultAction)
            .help("A new topic in these same conversations; their context carries on")
            PerchCapsuleButton(title: "Set up fresh conversations\u{2026}", style: .glass, icon: "plus.bubble") {
                controller.setUpFreshConversations()
            }
            .help("Open new chats in the apps, then connect them")
        }
    }
}
