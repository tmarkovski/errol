import SwiftUI

/// The center of the capsule: the guided instruction, then the topic
/// editor, then the exchange's one running sentence — or the note editor
/// while the run is paused — and the ending's summary. It shares the
/// controller's existing editing and handoff lifetimes, and the transfer
/// probe stays mounted through every state.
struct PerchWidgetCenter: View {
    @Bindable var controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: Perch.s(8)) {
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
                    PerchRunSummary(controller: controller)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                PromptTransferProbe(source: controller.promptTransferSource)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if controller.stage == .running {
                runningDetails
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Compose

    /// The topic, the shape it completes, the one sentence about what
    /// happens next, and — when a destination is not ready — why Send
    /// waits.
    private var composer: some View {
        VStack(alignment: .leading, spacing: Perch.s(6)) {
            openingEditor
            HStack(spacing: Perch.s(8)) {
                PerchShapeMenu(controller: controller)
                Text("Errol exchanges replies automatically. Pause before typing in either app.")
                    .font(Perch.text(11))
                    .foregroundStyle(Perch.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let (problem, isProblem) = composeProblem {
                Text(problem)
                    .font(Perch.text(11))
                    .foregroundStyle(isProblem ? Perch.red : Perch.muted)
                    .lineLimit(2)
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
                              placeholder: controller.topic.isEmpty ? topicPlaceholder : nil,
                              minimumLines: 1, maximumLines: Perch.promptMaximumLines,
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
                          textColor: Perch.inkNS, placeholderColor: Perch.placeholderNS,
                          placeholder: controller.steeringText.isEmpty
                              ? "A note for the next handoff\u{2026}" : nil,
                          minimumLines: 1, maximumLines: Perch.promptMaximumLines, takesFocusOnAppear: true,
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
            if controller.isSteering {
                Text("Paused \u{00B7} Nothing is being copied or sent")
                    .font(Perch.text(11, .medium))
                    .foregroundStyle(Perch.accentText)
                    .lineLimit(1)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("\(controller.conversation) \u{00B7} \(turnText) \u{00B7} \(clock(at: context.date))")
                    .font(Perch.text(11))
                    .foregroundStyle(Perch.muted)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
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
        runClock(controller.elapsedRunDuration(at: date))
    }
}

/// The conversation shape, in the editor's own line: the name to read,
/// the menu to change it. Locked with the rest of the options during a run.
struct PerchShapeMenu: View {
    let controller: RelayController
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Menu {
            Picker("Conversation shape", selection: Binding(
                get: { controller.conversation }, set: { controller.selectConversation($0) })) {
                Text(RelayController.freeConversation).tag(RelayController.freeConversation)
                ForEach(settings.templates) { template in Text(template.name).tag(template.name) }
                Text("Write from scratch").tag(RelayController.customConversation)
            }
        } label: {
            HStack(spacing: Perch.s(4)) {
                Image(systemName: PerchShapeIcons.icon(for: controller.conversation))
                    .font(Perch.text(10, .medium))
                Text(controller.conversation == RelayController.customConversation
                     ? "Write from scratch" : controller.conversation)
                    .font(Perch.text(11, .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(Perch.text(8, .semibold))
                    .foregroundStyle(Perch.muted)
            }
            .foregroundStyle(Perch.secondary)
            .padding(.horizontal, Perch.s(7))
            .frame(height: Perch.s(22))
            .background(Capsule().fill(Perch.well))
            .perchHover(Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(controller.isRunning)
        .accessibilityLabel("Conversation shape")
        .accessibilityValue(controller.conversation)
        .help("The conversation's shape; the topic completes it")
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
                .frame(width: Perch.s(38), height: Perch.s(38))
                .background(Circle().fill(showingSetup ? Perch.well : .clear))
                .perchHover(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .help("Conversation, who starts, turn limit, windows, and appearance")
        .popover(isPresented: $showingSetup, arrowEdge: .bottom) {
            PerchSettingsPopover(controller: controller) {
                showingSetup = false
                controller.openSettings()
            }
        }
    }
}

/// The actions beside the center: the step's during setup, the named Send
/// with the editor, Pause to steer and Stop during the exchange, the
/// note's send and resume while paused, and the two next intentions at
/// the end. The settings entry point stands beside them throughout.
struct PerchWidgetActions: View {
    let controller: RelayController

    var body: some View {
        HStack(alignment: .center, spacing: Perch.s(10)) {
            PerchWidgetSetup(controller: controller)
            switch controller.stage {
            case .setup:
                PerchSetupActions(controller: controller)
            case .compose:
                send
            case .running:
                if controller.isSteering { paused } else { running }
            case .finished:
                finished
            }
        }
        .fixedSize()
    }

    private var send: some View {
        PerchCapsuleButton(title: controller.sendLabel, icon: "paperplane.fill") { controller.start() }
            .disabled(controller.sendBlocker != nil)
            .keyboardShortcut(.defaultAction)
            .help(controller.sendBlocker ?? "Send the topic to \(controller.appName(controller.firstSpeaker)) and start relaying")
    }

    private var running: some View {
        HStack(spacing: Perch.s(8)) {
            PerchCapsuleButton(title: controller.steeringQueued ? "Edit note" : "Pause to steer",
                               icon: "pause.fill") { controller.beginSteering() }
                .disabled(controller.isSteeringPending || controller.stopRequested)
                .help(controller.isSteeringPending
                      ? "Pausing after the current handoff"
                      : "Pause at a safe handoff and write a note for the next side")
            stop
        }
    }

    private var paused: some View {
        VStack(alignment: .trailing, spacing: Perch.s(6)) {
            HStack(spacing: Perch.s(8)) {
                PerchCapsuleButton(title: "Send note & continue", icon: "arrow.up") { controller.sendSteering() }
                    .disabled(!controller.steeringHasText)
                    .help(controller.nextRecipient.map { "The note goes to \($0) with the next handoff" }
                          ?? "The note goes with the next handoff")
                stop
            }
            PerchTextButton(title: "Resume without note") { controller.resumeWithoutNote() }
        }
    }

    private var stop: some View {
        PerchCapsuleButton(title: "Stop", style: .outlined, icon: "stop.fill") { controller.stop() }
            .disabled(controller.stopRequested)
            .help("Stop at the next safe point")
    }

    private var finished: some View {
        VStack(alignment: .trailing, spacing: Perch.s(6)) {
            PerchCapsuleButton(title: "Another topic here", icon: "arrow.counterclockwise") {
                controller.anotherTopicHere()
            }
            .keyboardShortcut(.defaultAction)
            .help("A new topic in these same conversations; their context carries on")
            PerchTextButton(title: "Set up fresh conversations\u{2026}") { controller.setUpFreshConversations() }
                .help("Open new chats in the apps, then connect them")
        }
    }
}
