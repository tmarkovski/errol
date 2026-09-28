// The prompt box between the columns: editor or status panel, and the run's actions.
// Its own file because it is most of what the console says; the frame stays in PerchConsole.swift.

import SwiftUI

extension RelayController {
    /// Keyboard hints beside Resume or Send note & continue.
    var steeringHint: String {
        let side = nextRecipient
        if steeringHasText {
            return side.map { "Return sends it to \($0) \u{00B7} Esc clears it" }
                ?? "Return sends it with the next handoff \u{00B7} Esc clears it"
        }
        return side.map { "Write a note for \($0) \u{00B7} Return or Esc resumes without one" }
            ?? "Write a note \u{00B7} Return or Esc resumes without one"
    }

    /// The line under the box while the mic is open, or why the last
    /// listening broke off; nil leaves the line to the hints above.
    var voiceHint: String? {
        switch voice.phase {
        case .starting: "Getting the microphone ready\u{2026}"
        case .listening: "Listening \u{00B7} press the mic when you\u{2019}re done"
        case .finishing: "Finishing the last words\u{2026}"
        case .idle: voice.problem
        }
    }

    /// The status panel headline follows the actual relay state.
    var runHeadline: String {
        if stopRequested { return "Ending at the next safe point\u{2026}" }
        if let block { return block.headline(names: names) }
        if isSteeringPending { return "Pausing after the current handoff\u{2026}" }
        if isHolding { return "Paused \u{00B7} Nothing is being copied or sent" }
        switch (chatgptConversation, claudeConversation) {
        case (.chatting, _): return "\(names.chatgpt) is replying\u{2026}"
        case (_, .chatting): return "\(names.claude) is replying\u{2026}"
        case (.replied, _): return "Sending \(names.chatgpt)'s reply to \(names.claude)"
        case (_, .replied): return "Sending \(names.claude)'s reply to \(names.chatgpt)"
        default:
            return currentTurn == 0
                ? "Sending the topic to \(appName(firstSpeaker))\u{2026}"
                : "Relaying the reply\u{2026}"
        }
    }
}

/// The run's turn and clock, at the status line's trailing end.
struct PerchRunMetadata: View {
    let controller: RelayController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let turn = controller.ending == .turnLimit ? "Turn \(controller.currentTurn) of \(controller.turns)"
                : "Turn \(controller.currentTurn)"
            // Nothing else says a run of this kind won't end by itself.
            let until = controller.ending == .whenStopped ? " \u{00B7} until you stop it" : ""
            Text("\(turn) · \(runClock(controller.elapsedRunDuration(at: context.date)))\(until)")
                .font(Perch.text(11))
                .foregroundStyle(Perch.muted)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - The prompt box

/// Only composing and a granted pause mount a text editor. The remaining
/// stages show accessible status text with stable actions.
struct PerchPromptBox: View {
    @Bindable var controller: RelayController

    static let textInset = Perch.s(12)
    static let corner = Perch.s(16)
    /// The box's inset above its text and below its toolbar.
    static let verticalInset = Perch.s(6)

    private var editing: Bool { controller.stage == .compose || controller.consoleAccess.pauseGranted }

    var body: some View {
        Group {
            if editing {
                VStack(alignment: .leading, spacing: Perch.s(4)) {
                    Group {
                        if controller.stage == .compose { openingEditor } else { steering }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, Self.textInset)
                    // The hint starts where the text above it does, and its
                    // bottom lines up with the buttons'.
                    HStack(alignment: .bottom, spacing: Perch.s(8)) {
                        Text(editorHint)
                            .font(Perch.text(11))
                            .foregroundStyle(hintIsProblem ? Perch.red : Perch.secondary)
                            .lineLimit(2).help(editorHint)
                        Spacer(minLength: 0)
                        PerchMicButton(controller: controller)
                        PerchConsoleActions(controller: controller)
                    }
                    .padding(.leading, Self.textInset)
                    .padding(.trailing, Perch.s(7))
                }
            } else {
                statusPanel
            }
        }
        .padding(.vertical, Self.verticalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A very soft shadow all around lifts the box off the shell.
        .background(RoundedRectangle(cornerRadius: Self.corner).fill(editing ? Perch.paper : Perch.well)
            .shadow(color: Perch.shadow.opacity(0.75), radius: Perch.s(5), y: Perch.s(1)))
        .overlay(RoundedRectangle(cornerRadius: Self.corner)
            .stroke(controller.consoleAccess.pauseGranted ? Perch.accent : Perch.chipEdge,
                    lineWidth: controller.consoleAccess.pauseGranted ? 1.5 : 1))
        .background {
            PromptTransferProbe(source: controller.promptTransferSource)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private var editorHint: String {
        if let voiceHint = controller.voiceHint { return voiceHint }
        if controller.consoleAccess.pauseGranted { return controller.steeringHint }
        return controller.failedStart ?? controller.setup.problem ?? controller.setup.state.layoutProblem
            ?? controller.sendBlocker ?? ""
    }

    private var hintIsProblem: Bool {
        if controller.voiceHint != nil { return controller.voice.problem != nil && !controller.voice.isActive }
        return controller.failedStart != nil
    }

    private var statusPanel: some View {
        HStack(alignment: .center, spacing: Perch.s(9)) {
            statusIcon.frame(width: Perch.s(24), height: Perch.s(24))
            VStack(alignment: .leading, spacing: Perch.s(3)) {
                Text(headline).font(Perch.text(13, .semibold))
                    .foregroundStyle(needsAttention ? Perch.red : Perch.ink)
                    .lineLimit(2).help(headline)
                if controller.stage == .finished {
                    let detail = controller.lastReport?.detail(names: controller.names,
                                                               timeout: config.timeout) ?? ""
                    if !detail.isEmpty {
                        Text(detail).font(Perch.text(11)).foregroundStyle(Perch.secondary)
                            .lineLimit(3).help(detail)
                    }
                } else if let block = controller.block, !controller.stopRequested {
                    let recovery = block.recovery(names: controller.names)
                    Text(recovery).font(Perch.text(11)).foregroundStyle(Perch.secondary)
                        .lineLimit(3).help(recovery)
                } else if controller.steeringQueued {
                    PerchRunLine(controller: controller)
                    Text(controller.steeringText).font(Perch.text(11))
                        .foregroundStyle(Perch.secondary).lineLimit(1).help(controller.steeringText)
                } else if controller.isSteeringPending {
                    Text("Finishing the current copy or delivery before you can write.")
                        .font(Perch.text(11)).foregroundStyle(Perch.secondary).lineLimit(2)
                }
                if controller.stage == .running { PerchRunMetadata(controller: controller) }
                // While a stop is under way the headline says so, and the
                // note's line waits for the run's end: a note the stop left
                // unsent shows then.
                if !controller.steeringQueued && !(controller.stopRequested && controller.stage == .running) {
                    if controller.steeringInFlight != nil {
                        PerchRunLine(controller: controller)
                    } else if let receipt = controller.lastReceipt,
                              controller.stage != .finished || receipt.outcome != .sent {
                        // After the run, a note that went is on its line in
                        // the conversation summary. One that didn't stays
                        // here: a queued note the run ended with, or words
                        // never sent, is on no line there.
                        PerchReceiptLine(controller: controller, receipt: receipt)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PerchConsoleActions(controller: controller)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.horizontal, Self.textInset)
    }

    private var headline: String {
        controller.stage == .finished
            ? controller.lastReport?.headline(names: controller.names) ?? "Run ended"
            : controller.runHeadline
    }

    private var needsAttention: Bool {
        controller.stage == .finished ? controller.lastReport?.outcome.needsAttention == true
            : controller.block != nil && !controller.stopRequested
    }

    @ViewBuilder private var statusIcon: some View {
        if controller.stage == .finished {
            Image(systemName: controller.lastReport?.outcome.symbol ?? "stop.circle")
                .font(Perch.text(20))
                .foregroundStyle(needsAttention ? Perch.red
                    : controller.lastReport?.outcome == .completed ? Perch.accentText : Perch.secondary)
        } else if needsAttention {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Perch.red)
        } else {
            let speaker: Speaker = controller.chatgptConversation == .chatting || controller.chatgptConversation == .replied
                ? .chatgpt : controller.claudeConversation == .notStarted ? controller.firstSpeaker : .claude
            PerchAvatar(bundleID: speaker == .chatgpt ? config.chatgptBundleID : config.claudeBundleID,
                        initial: String(controller.appName(speaker).prefix(1)),
                        feather: speaker == .chatgpt ? Perch.chatgptFeather : Perch.claudeFeather)
                .scaleEffect(0.48).frame(width: Perch.s(24), height: Perch.s(24))
                .accessibilityHidden(true)
        }
    }

    // MARK: Before a run

    /// Return sends only when Send would: a refusal the status line already
    /// explains is not also recorded as a failed start.
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
                              onSubmit: { if controller.sendBlocker == nil { controller.start() } })
        }
    }

    private var topicPlaceholder: String {
        if let template = controller.selectedTemplate { return template.topicPrompt }
        return "What should they work on together?"
    }

    // MARK: During a run

    /// The note editor. What its keys do is said under the box
    /// (RelayController.steeringHint).
    private var steering: some View {
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

}

// MARK: - The actions

/// The primary action and run controls stay at the trailing end.
struct PerchConsoleActions: View {
    @Bindable var controller: RelayController

    private var setup: SetupController { controller.setup }

    var body: some View {
        HStack(spacing: Perch.s(8)) {
            switch controller.stage {
            case .compose:
                if closedApps.isEmpty { send } else { open }
            case .running:
                if controller.consoleAccess.pauseGranted { paused } else { running }
            case .finished:
                finished
            }
        }
        .fixedSize()
    }

    private var closedApps: [Speaker] {
        [Speaker.chatgpt, .claude].filter { setup.state[$0].presence == .notRunning }
    }

    /// Apps open only through this explicit action or the participant popover.
    private var open: some View {
        let title = closedApps.count == 2 ? "Open both apps" : "Open \(setup.name(closedApps[0]))"
        return PerchCapsuleButton(title: title, icon: "arrow.up.right") { setup.launchBoth() }
            .help("Open whichever app isn\u{2019}t open yet")
    }

    private var send: some View {
        PerchCapsuleButton(title: "Start relay", icon: "arrow.right") { controller.start() }
            .disabled(controller.sendBlocker != nil)
            .help(controller.sendBlocker ?? "Send the topic to \(controller.appName(controller.firstSpeaker)) and begin relaying")
    }

    /// The status panel names a pending pause; Stop remains available.
    private var running: some View {
        HStack(spacing: Perch.s(8)) {
            PerchRoundButton(title: controller.steeringQueued ? "Edit note" : "Pause to steer",
                             icon: "pause.fill") { controller.beginSteering() }
                .disabled(controller.isSteeringPending || controller.stopRequested)
            PerchRoundButton(title: "Stop", icon: "stop.fill", prominent: false) { controller.stop() }
                .disabled(controller.stopRequested)
        }
    }

    /// One button continues the run: Resume while the field is empty,
    /// Send note once it has words. Stop stands at the end, where it does
    /// while the run is going.
    private var paused: some View {
        let hasNote = controller.steeringHasText
        return HStack(spacing: Perch.s(8)) {
            PerchCapsuleButton(title: hasNote ? "Send note & continue" : "Resume",
                               icon: hasNote ? "arrow.up" : "play.fill") { controller.sendSteering() }
                .help(hasNote
                      ? (controller.nextRecipient.map { "The note goes to \($0) with the next handoff" }
                         ?? "The note goes with the next handoff")
                      : "Continue without a note")
                .animation(Perch.fade, value: hasNote)
                .disabled(!controller.consoleAccess.canResume)
            PerchCapsuleButton(title: "Stop", style: .secondary, icon: "stop.fill") { controller.stop() }
                .disabled(controller.stopRequested)
                .help("Stop at the next safe point")
        }
    }

    /// One way on. The connections are held, and both are read again before
    /// Send is offered; a conversation changed in the apps meanwhile is
    /// picked up the way any other is.
    private var finished: some View {
        PerchCapsuleButton(title: "New topic in these chats", icon: "arrow.counterclockwise") { controller.anotherTopicHere() }
            .keyboardShortcut(.defaultAction)
            .help("Write another topic for these conversations; their context carries on")
    }
}
