// The app's model: form state, the log, and the start/stop wiring around
// the relay engine. UI-facing state is Observable and mutated on the main
// thread only; everything that touches the apps — the permission, the
// readiness sweeps, the run itself — is the engine's (RelayEngine), which
// works on its own threads and reports back over its event stream, so the
// panel's event loop stays free and a preview can substitute an engine
// that touches nothing. Observation tracks per property, so a view body
// re-evaluates only for the properties it actually read — which is why the
// panel is split into child views along update boundaries.
//
// The veil over whichever chat window is waiting (SideVeils, an AppKit
// object the shell hands in) is driven from here too, off the same
// events, so what it shows and what the perches say cannot disagree.

import Combine
import Foundation
import Observation

struct LogLine: Identifiable {
    let id: Int
    let text: String
}

/// A note the worker has committed to a handoff and is pasting now: out
/// of the field, not yet with an outcome. The design is
/// docs/design-proposals/steering/the-note-stays-put.md, as revised at its
/// end: Pause to steer opens the field and holds the run, Return sends the
/// note and lets the run go, the head says where the note is.
struct SteeringInFlight: Equatable {
    var note: String
    /// The recipient's app name.
    var recipient: String
    var turn: Int
}

/// The record of a note's journey, the head's line under the turn line
/// once the note has left the field, kept until the next note or New
/// session. Every field is what was observed, so "shared" is never assumed.
struct SteeringReceipt: Equatable {
    enum Outcome: Equatable {
        /// Delivery confirmed: paste verified and a submission signal seen.
        case sent
        /// Submitted, no confirming signal.
        case unconfirmed
        /// Never reached the recipient, for the reason given.
        case notSent(SteeringOutcome)
        /// A draft the run ended on, never queued.
        case neverQueued
    }
    enum Echo: Equatable {
        case shared(turn: Int)
        case unconfirmed
        case notShared
    }
    var note: String
    /// The recipient's app name; nil for a draft that never went anywhere.
    var recipient: String?
    var turn: Int?
    var outcome: Outcome
    /// The echo to the other side, once its handoff has happened or been
    /// ruled out; nil while it is still ahead.
    var echo: Echo?
}

@Observable
final class RelayController {
    /// The picker tag for free-form instructions; not a ConversationTemplate.
    static let customConversation = "Custom"
    /// The picker tag for an open conversation with no preset structure: the
    /// topic is the whole opening message. Not a ConversationTemplate — a
    /// template with an empty body would still frame the topic as "below",
    /// and Settings should not offer its body for editing.
    static let freeConversation = "Free chat"
    /// The selected template's name, customConversation, or freeConversation.
    /// Free chat for now (Sep 2026): the shape choice is off the composer
    /// and the session settings, so every opening is the bare topic. The
    /// templates, their Settings editor, and selectConversation stay for
    /// when the choice comes back.
    var conversation = RelayController.freeConversation
    /// Completes the selected template ("What to brainstorm about").
    var topic = ""
    /// The opening message written from scratch under Custom (More → Write
    /// from scratch). A stored draft: it survives comparing other shapes, so
    /// coming back to Custom finds the writing where it was left.
    var customInstructions = ""
    var limitTurns = config.limitTurns
    var turns = config.turns
    /// Which side sends the opening message. Chosen in the session settings
    /// (the Send button names the recipient), and copied into config at
    /// Start, which is where the relay loop reads it.
    var firstSpeaker = Speaker.chatgpt
    /// The guided setup: which apps are open, how their windows are
    /// arranged, and which conversation each side is connected to. A run
    /// starts only from its editor phase, into the windows it bound.
    let setup: SetupController
    var isRunning = false
    /// Whether Stop has been pressed on this run — or on the run that just
    /// finished, since the summary names it as the ending. The Stop button
    /// dims on it, because the run may be mid-reply for a while before the
    /// next safe point. Cleared at the next start and by New session.
    private(set) var stopRequested = false
    /// The field opens only after focus ownership is granted. Both relay
    /// operations wait until Return or Continue closes the editor.
    var isSteering = false
    private(set) var isSteeringPending = false
    @ObservationIgnored let steeringEditor = TextEditorSession()
    /// Whether the worker has parked at a capture or delivery gate. A hold
    /// requested during an operation stays pending until that operation ends.
    var isHolding = false
    /// The condition in the apps the run is standing on — a changed
    /// conversation, an unsent draft — until the apps clear it. Separate
    /// from the steering hold, which the human asks for; the two can
    /// coincide, and neither clears the other.
    private(set) var block: RunBlock?
    /// How the last run ended, from the run itself. Set by the run's
    /// `.ended` event — or by a start that failed before the run began —
    /// and cleared by New session and at the next start.
    var lastReport: RunReport?
    /// The field's text: what the human is writing while the field is open,
    /// and the queued note as written — shown under a blur — while the
    /// mailbox holds it. The composer writes it through setSteeringText.
    var steeringText = ""
    /// The field's text as it stood when it was sent, while the note is in
    /// the mailbox; nil otherwise.
    private(set) var queuedSteering: String?
    /// The note the worker has committed and is pasting, between the
    /// committed event and the outcome.
    private(set) var steeringInFlight: SteeringInFlight?
    /// The last note's record, for the head. Cleared by resetSession and at
    /// the next start.
    private(set) var lastReceipt: SteeringReceipt?
    var logLines: [LogLine] = []
    var chatgptStatus = SideStatus(appName: "ChatGPT")
    var claudeStatus = SideStatus(appName: "Claude")
    var chatgptConversation = ConversationStatus.notStarted
    var claudeConversation = ConversationStatus.notStarted
    /// The running turn number (1-based) during a relay run; 0 outside one.
    /// Feeds the head's turn line. It survives the run's end so the finished
    /// state stays readable, until resetSession or the next start clears it.
    var currentTurn = 0
    /// How long the last run took, for the turn line's post-run clock. Set when
    /// a run finishes; cleared by resetSession and at the next start.
    var lastRunDuration: TimeInterval?
    @ObservationIgnored private var runStartedAt: Date?

    /// The apps' names as the panel shows them, for the summary and the
    /// hold lines the engine reports by side.
    var names: (chatgpt: String, claude: String) {
        (chatgptStatus.appName, claudeStatus.appName)
    }

    /// The reason the last start failed, while nothing has replaced it: the
    /// line under the composer, where the run would have been.
    var failedStart: String? {
        if case .failedStart(let reason)? = lastReport?.outcome { return reason }
        return nil
    }

    /// Read by the widget's one-second timeline, without publishing a tick
    /// through the controller or changing any relay timing.
    func elapsedRunDuration(at date: Date = Date()) -> TimeInterval {
        max(0, runStartedAt.map { date.timeIntervalSince($0) } ?? lastRunDuration ?? 0)
    }
    @ObservationIgnored private var nextLogID = 0
    /// What drives the apps and reports back; LiveRelayEngine in the app.
    @ObservationIgnored private let engine: RelayEngine
    /// The veil over the waiting chat window; nil in previews, which have
    /// no windows to veil.
    @ObservationIgnored private let veils: SideVeils?
    @ObservationIgnored private let transferOverlay: TransferOverlay?
    @ObservationIgnored let promptTransferSource = PromptTransferSource()
    /// Each side's icon in the console, where its replies set off from
    /// (TransferSource).
    @ObservationIgnored let iconTransferSources = [Speaker.chatgpt: PromptTransferSource(),
                                                   .claude: PromptTransferSource()]
    /// The engine's inward flags and mailbox, written here at the human's
    /// actions and read by the run at its handoff boundaries.
    private var control: RelayControl { engine.control }
    @ObservationIgnored private var panelVisible = false
    /// Set by the AppKit shell; the panel's Settings… item routes here to
    /// navigate to Settings inside the panel.
    @ObservationIgnored var openSettingsHandler: (() -> Void)?
    /// Set by the AppKit shell. A finished run routes here so the console
    /// takes the keyboard back from the chat app that replied last, and so
    /// does the guided setup on reaching the editor, so the topic can be
    /// typed at once.
    @ObservationIgnored var focusPanelHandler: (() -> Void)?
    @ObservationIgnored private var templatesWatcher: AnyCancellable?

    /// `guidedSetup` brings back the four guided steps before the editor,
    /// for the screens kept from that flow (PerchPanelView and its
    /// canvases). The app's console is direct.
    init(engine: RelayEngine = LiveRelayEngine(), veils: SideVeils? = nil,
         transferOverlay: TransferOverlay? = nil, guidedSetup: Bool = false) {
        self.engine = engine
        self.veils = veils
        self.transferOverlay = transferOverlay
        setup = SetupController(engine: engine, guided: guidedSetup)
        // Reaching the editor is the moment to type: the console comes
        // forward and key through the shell's handler, and the editor takes
        // the keyboard as it appears (PerchWidgetCenter.openingEditor).
        setup.onReachCompose = { [weak self] in self?.focusPanelHandler?() }
        transferOverlay?.promptSource = promptTransferSource
        transferOverlay?.iconSource = { [iconTransferSources] in iconTransferSources[$0] }
        // Most sweeps see the same picture as the last one; publishing them
        // anyway would re-render the status views each poll, so only
        // changed statuses reach the observable properties. The setup
        // state does its own no-change filtering per side.
        engine.onReadiness = { [weak self] report in
            let apply = {
                guard let self else { return }
                if self.chatgptStatus != report.chatgpt { self.chatgptStatus = report.chatgpt }
                if self.claudeStatus != report.claude { self.claudeStatus = report.claude }
                self.setup.names = self.names
                self.setup.apply(report)
            }
            // The live sweep reports from its own thread; a preview engine
            // answers on the main thread at once, so a canvas can step
            // through setup in its own setup code.
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
        // The engine's ordered event stream, delivered on the main thread.
        // Consuming it in one place keeps related updates — a turn, a hold,
        // the log line about them — from interleaving the way the separate
        // callbacks it replaced could.
        engine.events.onEvent { [weak self] event in
            guard let self else { return }
            switch event {
            case .transfer(let feedback):
                if isRunning, !control.isCancelled { transferOverlay?.handle(feedback) }
            case .log(let line):
                append(line)
            case .conversation(let chatgpt, let claude):
                chatgptConversation = chatgpt
                claudeConversation = claude
                veils?.update(chatgpt: chatgpt, claude: claude)
            case .turn(let turn):
                currentTurn = turn
            case .holding(let holding):
                isHolding = holding
            case .blocked(let block):
                self.block = block
            case .ended(let report):
                lastReport = report
                block = nil
            case .steeringGranted:
                guard isRunning, isSteeringPending, control.canOpenSteering else { return }
                isSteeringPending = false
                steeringEditor.begin(text: steeringText)
                isSteering = true
            case .steeringCommitted(let note, let recipient, let turn):
                steeringCommitted(note, to: recipient, turn: turn)
            case .steering(let delivery):
                steeringDelivered(delivery)
            case .finished:
                finishRun()
            }
        }
        // A shape deleted or renamed in Settings can leave the picker
        // pointing at nothing; follow the list to its first shape (which
        // always exists — the store refuses to empty the list).
        templatesWatcher = SettingsStore.shared.$templates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] templates in
                guard let self, conversation != Self.customConversation,
                      conversation != Self.freeConversation,
                      !templates.contains(where: { $0.name == self.conversation })
                else { return }
                selectConversation(templates.first?.name ?? Self.customConversation)
            }
    }

    func openSettings() {
        openSettingsHandler?()
    }

    /// nil means the picker is on Custom or Free chat.
    var selectedTemplate: ConversationTemplate? {
        conversationTemplates.first { $0.name == conversation }
    }

    var isFreeChat: Bool { conversation == Self.freeConversation }

    /// Custom is the one shape with a full editor: its prompt is written from
    /// scratch. A template shows its topic field under a read-only preview of
    /// its body, and Free chat's topic field already holds the whole opening
    /// message, so neither has a composed prompt to reveal.
    var showsFullInstructionsEditor: Bool {
        selectedTemplate == nil && !isFreeChat
    }

    /// A visual hint at the insertion point in the full editor. It is never
    /// part of customInstructions, so an untouched placeholder cannot leak
    /// into the message sent to either agent.
    var promptEditorPlaceholder: String? {
        customInstructions.isEmpty ? "Write your complete opening prompt here…" : nil
    }

    /// The exact initial message the relay will hand to the first agent
    /// (before the framing preamble): the template composed with the topic,
    /// the bare topic for Free chat, or the from-scratch prompt as written.
    var composedInstructions: String {
        if isFreeChat { return topic }
        guard let template = selectedTemplate else { return customInstructions }
        return template.composed(topic: topic)
    }

    /// Whether Start has something to send: a topic for a template or Free
    /// chat, any text for a prompt written from scratch.
    var instructionsReady: Bool {
        let text = showsFullInstructionsEditor ? customInstructions : topic
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Select a shape. The from-scratch draft is left alone: it stays in
    /// customInstructions across the switch, so comparing the shapes and
    /// coming back to Custom does not throw the writing away.
    func selectConversation(_ name: String) {
        guard name == Self.customConversation
                || name == Self.freeConversation
                || conversationTemplates.contains(where: { $0.name == name }),
              name != conversation else { return }
        conversation = name
    }

    /// The readiness strip only scans while someone can see it, and never
    /// while a run owns the apps' AX trees and the machine's focus.
    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        updateScanner()
    }

    private func updateScanner() {
        engine.setScanning(panelVisible && !isRunning)
    }

    // MARK: What the capsule shows

    /// The capsule's content, in the order the run's lifetime gives it:
    /// the guided screens, the editor, the exchange, the ending.
    enum Stage: Equatable {
        case setup, compose, running, finished
    }

    var stage: Stage {
        if isRunning { return .running }
        if hasFinishedRun { return .finished }
        return setup.isGuiding ? .setup : .compose
    }

    /// The named Send: whoever starts the conversation receives the topic.
    var sendLabel: String {
        "Send to \(appName(firstSpeaker))"
    }

    /// Why Send is unavailable now, beside it: the topic missing, or a
    /// destination not ready. nil when it can go.
    var sendBlocker: String? {
        if let blocker = setup.state.sendBlocker(names: names) { return blocker }
        guard instructionsReady else {
            if showsFullInstructionsEditor { return "Write the opening prompt first." }
            return isFreeChat ? "Add a topic first: it is the whole opening message."
                              : "Add a topic first: it completes the \(conversation) opening."
        }
        return nil
    }

    /// The log is an in-memory tail read through the status item's debug
    /// window (PerchLogWindowView) — the debug log on disk (RunLog) holds
    /// the whole run. Bounded, trimming in chunks so removeFirst's element shuffle
    /// stays off the per-line path.
    private static let logCap = 500
    private static let logTrimSlack = 100

    /// Main thread only (relay events deliver here on the main thread).
    func append(_ line: String) {
        logLines.append(LogLine(id: nextLogID, text: line))
        nextLogID += 1
        if logLines.count > Self.logCap + Self.logTrimSlack {
            logLines.removeFirst(logLines.count - Self.logCap)
        }
    }

    func start() {
        guard !isRunning, stage == .compose else { return }

        // Rechecked at the click, against the last sweep: the destinations
        // must read ready and the opening content must exist. A refusal
        // shows where the run would have been and leaves the topic alone.
        lastReport = nil
        if let blocker = sendBlocker {
            append(blocker)
            lastReport = RunReport(outcome: .failedStart(reason: blocker))
            return
        }
        guard engine.preflight() else { return }

        config.seed = composedInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        config.limitTurns = limitTurns
        turns = max(1, turns)
        config.turns = turns
        config.first = firstSpeaker

        isRunning = true
        stopRequested = false
        transferOverlay?.stop()
        isHolding = false
        block = nil
        resetSteering()
        lastReceipt = nil
        setup.runStarted()
        updateScanner()
        chatgptConversation = .notStarted
        claudeConversation = .notStarted
        currentTurn = 0
        lastRunDuration = nil
        runStartedAt = Date()
        // The buffer holds one run, so the debug window's "last run log"
        // means what it says; lines logged between runs (an inspect report,
        // a failed start) stay until the next run claims the buffer.
        logLines.removeAll()
        engine.startRun()
        veils?.begin(chatgptName: chatgptStatus.appName, claudeName: claudeStatus.appName)
    }

    /// Whether a finished run is still on the panel: a report from a run
    /// that began, no run to own it. The composer shows the run's summary
    /// and New session in this state, and resetSession is what leaves it.
    /// A start that failed is not a finished run: its reason shows under
    /// the composer, and Run stays the action.
    var hasFinishedRun: Bool {
        guard !isRunning, let report = lastReport else { return false }
        return !report.outcome.isFailedStart
    }

    /// Clear the finished run off the panel — the report and its summary,
    /// the turn count, the perches' sign-offs, the run clock, the last
    /// note's record. The run options stay as they are; they belong to the
    /// next run, not the finished one. Only Errol resets: the conversations
    /// in the two apps are as the run left them.
    func resetSession() {
        guard hasFinishedRun else { return }
        lastReport = nil
        block = nil
        currentTurn = 0
        lastRunDuration = nil
        lastReceipt = nil
        stopRequested = false
        chatgptConversation = .notStarted
        claudeConversation = .notStarted
    }

    /// Another topic in these conversations: the editor comes back empty,
    /// and both destinations are verified again before Send is offered.
    /// Their context carries on in the apps; nothing there is touched.
    func anotherTopicHere() {
        guard hasFinishedRun else { return }
        resetSession()
        topic = ""
        setup.revalidate()
    }

    /// Set up fresh conversations: the topic is cleared with the run and
    /// both sides are connected anew, once the human has opened new chats
    /// in the apps. Errol makes no chats itself.
    func setUpFreshConversations() {
        guard hasFinishedRun else { return }
        resetSession()
        topic = ""
        setup.setUpFresh()
    }

    /// Choose another conversation for one side, from its details. A
    /// finished run's summary gives way first, so the picker has the
    /// capsule; the topic stays.
    func chooseAnotherConversation(_ side: Speaker) {
        guard !isRunning else { return }
        if hasFinishedRun { resetSession() }
        setup.chooseAnother(side)
    }

    /// The run's `.finished` event: put the panel back to idle. Ordered
    /// after every line the run logged, because it rides the same stream.
    /// Whatever the note was doing becomes its record for the head, since
    /// the composer goes back to the topic and ending is exactly when
    /// someone inspects what happened. Last, the console takes the keyboard
    /// back: the run left it with whichever chat app replied last, and New
    /// session is what comes next.
    private func finishRun() {
        if isSteering, let text = steeringEditor.end() { steeringText = text }
        lastRunDuration = runStartedAt.map { Date().timeIntervalSince($0) }
        runStartedAt = nil
        isRunning = false
        isHolding = false
        block = nil
        veils?.end()
        transferOverlay?.stop()
        recordSteeringAtRunEnd()
        resetSteering()
        setup.runEnded()
        updateScanner()
        focusPanelHandler?()
    }

    func stop() {
        guard isRunning else { return }
        stopRequested = true
        // Cancellation wins at both gates. Clearing pause first would admit
        // a focus operation between the two calls.
        isSteeringPending = false
        control.cancel()
        transferOverlay?.stop()
        append("Stop requested — ending the run at the next safe point...")
    }

    // MARK: Steering

    /// Whether a hold is asked for. There is one way to ask: Pause to
    /// steer, which opens the field. The pill and the turn line read this.
    var holdRequested: Bool { isSteering || isSteeringPending }

    /// Whether the field holds words. The circle reads it to be Send rather
    /// than Continue, and the run's end records such words as a note never
    /// sent.
    var steeringHasText: Bool {
        !steeringText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether a note is in the mailbox, waiting for its handoff.
    var steeringQueued: Bool { queuedSteering != nil }

    /// The side a queued note reaches first: whoever is about to reply,
    /// which is the side not composing now — the reply being written goes
    /// to them, and the note goes with it. nil in the moments nobody is
    /// composing.
    var nextRecipient: String? {
        switch (chatgptConversation, claudeConversation) {
        case (.chatting, _), (.replied, _): return claudeStatus.appName
        case (_, .chatting), (_, .replied): return chatgptStatus.appName
        default: return nil
        }
    }

    /// The other side's name, for the receipt's echo clause.
    func otherName(than appName: String) -> String {
        appName == chatgptStatus.appName ? claudeStatus.appName : chatgptStatus.appName
    }

    func appName(_ speaker: Speaker) -> String {
        switch speaker {
        case .chatgpt: chatgptStatus.appName
        case .claude: claudeStatus.appName
        }
    }

    /// Pause to steer requests focus ownership; the field waits for any
    /// active operation to finish. A queued note comes back to be changed — taken
    /// off the mailbox and the hold put on in one locked step
    /// (RelayControl.claimSteering), so the handoff it was queued for cannot
    /// slip through between the two. If the worker committed it first the
    /// claim loses: that note is on its way, the committed event says so,
    /// and the field opens empty for a new one.
    func beginSteering() {
        guard isRunning, !holdRequested else { return }
        let grant: HoldGrant
        if queuedSteering != nil {
            let claim = control.claimSteering()
            guard claim.grant != .cancelled else { return }
            grant = claim.grant
            queuedSteering = nil
            if claim.note != nil {
                append("Note taken back — the run holds at the next handoff while you change it.")
            } else {
                steeringText = ""
                append("The handoff already owns that note; opening a new one.")
            }
        } else {
            grant = control.requestHold()
            guard grant != .cancelled else { return }
            append("Pausing to steer — the run holds at the next handoff while you write.")
        }
        isSteeringPending = grant == .afterOperation
        if grant == .now {
            steeringEditor.begin(text: steeringText)
            isSteering = true
        }
    }

    /// Return, or the circle: the field closes and the run goes on. Words
    /// in it are the note — the mailbox takes them trimmed, and the field
    /// keeps them as written to show under the blur — and an empty field
    /// just continues. Posting comes before the hold lifts, so the handoff the
    /// flag releases is one that finds the note.
    func sendSteering() {
        guard isRunning, isSteering, !control.isCancelled else { return }
        // The outgoing SwiftUI view can survive its fade. Stop its NSTextView
        // synchronously, including any marked text, before opening either gate.
        if let text = steeringEditor.end() { steeringText = text }
        let note = steeringText.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty {
            steeringText = ""
            queuedSteering = nil
            append("Continued without a note.")
        } else {
            queuedSteering = steeringText
            append("Note queued — the run goes on, and the note rides the next handoff.")
        }
        isSteering = false
        control.finishSteering(note: note.isEmpty ? nil : note)
    }

    /// Resume without a note: whatever the field holds is dropped, the
    /// field closes, and the run goes on.
    func resumeWithoutNote() {
        guard isRunning, isSteering else { return }
        steeringEditor.clear()
        steeringText = ""
        sendSteering()
    }

    /// Esc in the open field. The first press empties it; the second, on an
    /// empty field, closes it and continues — so Esc twice drops whatever
    /// note was there, queued before or not.
    func escapeSteering() {
        guard isRunning, isSteering else { return }
        if steeringText.isEmpty {
            sendSteering()
        } else {
            steeringEditor.clear()
            steeringText = ""
        }
    }

    /// The explicit way to drop a queued note without opening the field:
    /// the mailbox gives it back and the field lets go of the text. On an
    /// open field it just empties it. Returns whether there was anything
    /// to drop.
    @discardableResult
    func clearSteering() -> Bool {
        guard isRunning else { return false }
        if queuedSteering != nil {
            queuedSteering = nil
            steeringText = ""
            if control.takeSteering() != nil {
                append("Note withdrawn.")
            } else {
                append("The note had already gone out with the handoff.")
            }
            return true
        }
        if !steeringText.isEmpty {
            steeringEditor.clear()
            steeringText = ""
            return true
        }
        return false
    }

    /// The field's write path. Only an open field takes text.
    func setSteeringText(_ text: String) {
        guard isRunning, isSteering else { return }
        steeringText = text
    }

    /// Everything about the note, at a run's start and end.
    private func resetSteering() {
        steeringEditor.end()
        isSteering = false
        isSteeringPending = false
        steeringText = ""
        queuedSteering = nil
        steeringInFlight = nil
    }

    /// The worker won the handoff: the note is the courier's, and the field
    /// lets go of it — the blurred text clears and the head takes over the
    /// story. The field is left alone when it no longer shows that note:
    /// Pause to edit lost its claim in the instant before the commit, and
    /// the field is already open and empty for a new one.
    private func steeringCommitted(_ note: String, to recipient: Speaker, turn: Int) {
        steeringInFlight = SteeringInFlight(note: note, recipient: appName(recipient), turn: turn)
        if let queued = queuedSteering,
           queued.trimmingCharacters(in: .whitespacesAndNewlines) == note {
            queuedSteering = nil
            steeringText = ""
        }
    }

    /// One leg's outcome becomes the record. A note leg reported straight
    /// off the mailbox — too long to travel whole, or the run ended with
    /// it queued — never had a committed event, so the field lets go of it
    /// here instead.
    private func steeringDelivered(_ delivery: SteeringDelivery) {
        let recipient = appName(delivery.recipient)
        switch delivery.leg {
        case .note:
            let outcome: SteeringReceipt.Outcome
            switch delivery.outcome {
            case .delivered: outcome = .sent
            case .unconfirmed: outcome = .unconfirmed
            case .refused, .tooLong, .runEnded: outcome = .notSent(delivery.outcome)
            }
            lastReceipt = SteeringReceipt(note: delivery.note, recipient: recipient,
                                          turn: delivery.turn, outcome: outcome)
            steeringInFlight = nil
            if let queued = queuedSteering,
               queued.trimmingCharacters(in: .whitespacesAndNewlines) == delivery.note {
                queuedSteering = nil
                steeringText = ""
            }
        case .echo:
            guard lastReceipt?.note == delivery.note else { return }
            switch delivery.outcome {
            case .delivered: lastReceipt?.echo = .shared(turn: delivery.turn)
            case .unconfirmed: lastReceipt?.echo = .unconfirmed
            case .refused, .tooLong, .runEnded: lastReceipt?.echo = .notShared
            }
        }
    }

    /// What the run's end leaves of the note becomes its record: words in
    /// an open field were never sent; a queued note the worker never took
    /// is reported by the worker itself before it finishes (a fallback here
    /// covers the case where it could not); a note still in flight never
    /// got its outcome, which is what unconfirmed means. Notes already
    /// resolved keep the record they have, and an echo still ahead is ruled
    /// out.
    private func recordSteeringAtRunEnd() {
        if let inFlight = steeringInFlight {
            lastReceipt = SteeringReceipt(note: inFlight.note, recipient: inFlight.recipient,
                                          turn: inFlight.turn, outcome: .unconfirmed)
        } else if let queued = queuedSteering {
            lastReceipt = SteeringReceipt(note: queued.trimmingCharacters(in: .whitespacesAndNewlines),
                                          recipient: nil, turn: nil, outcome: .notSent(.runEnded))
        } else if steeringHasText {
            lastReceipt = SteeringReceipt(note: steeringText, recipient: nil, turn: nil,
                                          outcome: .neverQueued)
        }
        if let receipt = lastReceipt, receipt.echo == nil,
           receipt.outcome == .sent || receipt.outcome == .unconfirmed {
            lastReceipt?.echo = .notShared
        }
    }

    /// Dump both apps' windows, buttons, and selector matches into the log —
    /// the way selector breakage gets diagnosed after an app update. A debug
    /// tool, reached through the status item's menu and read in the log
    /// window it opens. The report arrives as a log line on the event stream.
    func runInspect() {
        guard !isRunning else { return }
        engine.inspect()
    }
}
