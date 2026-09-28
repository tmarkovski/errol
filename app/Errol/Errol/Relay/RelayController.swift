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
// The records the model keeps — log lines, the steering note and its
// receipt, transcript entries — are plain values in RelayRecords.swift.

import AppKit
import Foundation
import Observation

@Observable
final class RelayController {
    /// The whole opening message, as the prompt box holds it. The
    /// conversation shapes that once framed it (Brainstorm, Debate, a
    /// prompt written from scratch) left the composer in Sep 2026 and were
    /// deleted on Sep 27 2026, so the topic goes out as written.
    var topic = ""
    /// How the next run ends, and its turn limit when it has one. Chosen on
    /// the console's ending chip and stepper, and copied into config at
    /// Start.
    var ending = config.ending
    var turns = config.turns
    /// Which side sends the opening message. Chosen on the console's Send
    /// starter menu, and copied into config at Start, which is
    /// where the relay loop reads it.
    var firstSpeaker = Speaker.chatgpt
    /// The setup: which apps are open, how their windows are arranged, and
    /// which conversation each side is connected to. A run goes into the
    /// windows it bound.
    let setup: SetupController
    /// The prompt the human sent to start the run on the panel, as they
    /// wrote it: the topic. Set at Start, cleared with the finished run.
    private(set) var runPrompt: String?
    /// One sentence on what the run is about, once the on-device model has
    /// written it from the prompt (TopicSummarizer); nil until then, and
    /// for good when the model cannot.
    private(set) var topicSummary: String?
    /// What writes the sentence; the live model, or a stand-in in previews.
    @ObservationIgnored var summarize: @Sendable (String) async -> String? = { await TopicSummarizer.summarize($0) }
    @ObservationIgnored private var summaryTask: Task<Void, Never>?
    /// The run's transcript for the window under the console
    /// (PerchTranscript), oldest first: each reply once it is in hand,
    /// each note once it sets off. Kept whole through the ending, and
    /// cleared at the next start and by New topic.
    private(set) var transcript: [TranscriptEntry] = []
    /// What writes a reply's line; the live model, or a stand-in in previews.
    @ObservationIgnored var summarizeReply: @Sendable (String) async -> String? = { await ReplySummarizer.gist($0) }
    @ObservationIgnored private var gistTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextTranscriptID = 0
    private(set) var isRunning = false
    /// Whether Stop has been pressed on this run — or on the run that just
    /// finished, since the summary names it as the ending. The Stop button
    /// dims on it, because the run may be mid-reply for a while before the
    /// next safe point. Cleared at the next start and by New topic.
    private(set) var stopRequested = false
    /// The field opens only after focus ownership is granted. Both relay
    /// operations wait until Return or Continue closes the editor.
    private(set) var isSteering = false
    private(set) var isSteeringPending = false
    let steeringEditor = TextEditorSession()
    /// The prompt box's mic: speaking into the field the box shows
    /// (toggleVoice). Sending or clearing that field closes it.
    let voice: VoiceInput
    /// Whether the worker has parked at a capture or delivery gate. A hold
    /// requested during an operation stays pending until that operation ends.
    private(set) var isHolding = false
    /// The condition in the apps the run is standing on — a changed
    /// conversation, an unsent draft — until the apps clear it. Separate
    /// from the steering hold, which the human asks for; the two can
    /// coincide, and neither clears the other.
    private(set) var block: RunBlock?
    /// How the last run ended, from the run itself. Set by the run's
    /// `.ended` event — or by a start that failed before the run began —
    /// and cleared by New topic and at the next start.
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
    private(set) var logLines: [LogLine] = []
    private(set) var chatgptConversation = ConversationStatus.notStarted
    private(set) var claudeConversation = ConversationStatus.notStarted
    /// The running turn number (1-based) during a relay run; 0 outside one.
    /// Feeds the head's turn line. It survives the run's end so the finished
    /// state stays readable, until resetSession or the next start clears it.
    private(set) var currentTurn = 0
    /// How long the last run took, for the turn line's post-run clock. Set when
    /// a run finishes; cleared by resetSession and at the next start.
    var lastRunDuration: TimeInterval?
    @ObservationIgnored private var runStartedAt: Date?

    /// The apps' names as the panel shows them, for the summary and the
    /// hold lines the engine reports by side.
    var names: (chatgpt: String, claude: String) {
        ("ChatGPT", "Claude")
    }

    /// The reason the last start failed, while nothing has replaced it: the
    /// line under the composer, where the run would have been.
    var failedStart: String? {
        if case .failedStart(let reason)? = lastReport?.outcome { return reason }
        return nil
    }

    /// Read by the widget's one-second timeline, without publishing a tick
    /// through the controller or changing any relay timing.
    func elapsedRunDuration(at date: Date) -> TimeInterval {
        max(0, runStartedAt.map { date.timeIntervalSince($0) } ?? lastRunDuration ?? 0)
    }
    @ObservationIgnored private var nextLogID = 0
    /// What drives the apps and reports back; LiveRelayEngine in the app.
    private let engine: RelayEngine
    private let transferOverlay: TransferOverlay?
    let promptTransferSource = TransferAnchorSource()
    /// Each side's icon in the console, where its replies set off from
    /// (TransferSource).
    let iconTransferSources = [Speaker.chatgpt: TransferAnchorSource(),
                                                   .claude: TransferAnchorSource()]
    /// The engine's inward flags and mailbox, written here at the human's
    /// actions and read by the run at its handoff boundaries.
    private var control: RelayControl { engine.control }
    @ObservationIgnored private var panelVisible = false
    /// The native shell builds the same menu for the console and status item.
    @ObservationIgnored var appMenuProvider: (() -> NSMenu)?
    private(set) var isShowingWindow = false

    var consoleAccess: ConsoleAccess {
        ConsoleAccess(running: isRunning, steering: isSteering, pending: isSteeringPending,
                      stopping: isRunning && stopRequested, showingWindow: isShowingWindow,
                      focusOperationActive: control.hasFocusOperation)
    }

    /// Brings a side's window forward. Show window hands the keyboard back
    /// to the console once the window is up, and to the note during a pause;
    /// a click on the side's icon focuses the app, so it leaves the keyboard
    /// there (`returningKeyboard: false`).
    func showWindow(_ side: Speaker, returningKeyboard: Bool = true) {
        guard consoleAccess.canShowWindow else { return }
        isShowingWindow = true
        setup.bringForward(side) { [weak self] in
            guard let self else { return }
            isShowingWindow = false
            guard returningKeyboard else { return }
            focusPanelHandler?()
            if consoleAccess.pauseGranted { steeringEditor.restoreFocus() }
        }
    }

    func connect(_ side: Speaker, to window: WindowID) {
        guard consoleAccess.canChangeDestination else { return }
        if hasFinishedRun { resetSession() }
        setup.connect(side, to: window)
    }
    /// Set by the AppKit shell. A finished run routes here so the console
    /// takes the keyboard back from the chat app that replied last, and so
    /// do an arrangement of the windows, which brings both chat apps
    /// forward on the way, and Show window, once the window is up.
    @ObservationIgnored var focusPanelHandler: (() -> Void)?

    init(engine: RelayEngine, transferOverlay: TransferOverlay? = nil) {
        self.engine = engine
        self.transferOverlay = transferOverlay
        voice = VoiceInput(transcriber: engine.transcriber)
        setup = SetupController(engine: engine)
        setup.onArranged = { [weak self] in self?.focusPanelHandler?() }
        transferOverlay?.promptSource = promptTransferSource
        transferOverlay?.iconSource = { [iconTransferSources] in iconTransferSources[$0] }
        // Most sweeps see the same picture as the last one; publishing them
        // anyway would re-render the console each poll, so the sweep goes
        // to the setup alone, whose apply publishes only a changed state.
        // The names the console shows are constant and never ride a sweep.
        engine.onReadiness = { [weak self] report in
            let apply = {
                guard let self else { return }
                self.setup.apply(report)
            }
            // The live sweep reports from its own thread; a preview engine
            // answers on the main thread at once, so a canvas can connect
            // its sides in its own setup code.
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
            case .turn(let turn):
                currentTurn = turn
            case .reply(let side, let text):
                replyCaptured(text, from: side)
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
                openSteeringField()
            case .steeringCommitted(let note, let recipient, let turn):
                steeringCommitted(note, to: recipient, turn: turn)
            case .steering(let delivery):
                steeringDelivered(delivery)
            case .finished:
                finishRun()
            }
        }
    }

    /// Whether Start has something to send: a topic.
    var instructionsReady: Bool {
        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The mic button: speak into the field the prompt box shows — the note
    /// during a pause, else the topic — or finish the listening under way.
    /// The words land after what the field holds.
    func toggleVoice() {
        if consoleAccess.pauseGranted {
            voice.toggle(read: { [weak self] in self?.steeringText ?? "" },
                         write: { [weak self] in self?.setSteeringText($0) })
        } else if stage == .compose {
            voice.toggle(read: { [weak self] in self?.topic ?? "" },
                         write: { [weak self] in self?.topic = $0 })
        }
    }

    /// Readiness sweeps run only while someone can see the console, and
    /// none starts while a run owns the apps' AX trees and the machine's
    /// focus; a sweep already in flight finishes read-only beside the
    /// run's first steps.
    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        // No one hears into a field they can't see.
        if !visible { voice.cancel() }
        updateScanner()
    }

    private func updateScanner() {
        engine.setScanning(panelVisible && !isRunning)
    }

    // MARK: What the console shows

    /// The console's content, in the order the run's lifetime gives it:
    /// the editor, the exchange, the ending.
    enum Stage: Equatable {
        case compose, running, finished
    }

    var stage: Stage {
        if isRunning { return .running }
        if hasFinishedRun { return .finished }
        return .compose
    }

    /// Ask the model for the run's sentence. An answer that arrives after
    /// the run has left the panel, or for another prompt, is dropped.
    private func beginTopicSummary() {
        summaryTask?.cancel()
        let prompt = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        runPrompt = prompt
        topicSummary = nil
        let summarize = self.summarize
        summaryTask = Task { @MainActor [weak self] in
            let summary = await summarize(prompt)
            guard !Task.isCancelled, let self, runPrompt == prompt else { return }
            topicSummary = summary
        }
    }

    private func clearTopicSummary() {
        summaryTask?.cancel()
        summaryTask = nil
        runPrompt = nil
        topicSummary = nil
    }

    // MARK: The run's transcript

    /// A reply in hand goes on the transcript at once, as its opening (or
    /// whole, when it is short), and the model's sentence takes the
    /// opening's place when it comes. A sign-off is marked on the line; a
    /// reply that is nothing else is only that.
    private func replyCaptured(_ reply: String, from side: Speaker) {
        guard isRunning else { return }
        let signsOff = isSignOff(reply)
        let text = strippingSignOff(reply)
        let flat = ReplySummarizer.flatten(text)
        guard !flat.isEmpty else {
            if signsOff { appendTranscript(.side(side), text: "Signs off") }
            return
        }
        let summarizing = ReplySummarizer.needsGist(flat)
        let id = appendTranscript(.side(side), text: flat, verbatim: true, summarizing: summarizing,
                                  signsOff: signsOff)
        guard summarizing else { return }
        let summarize = summarizeReply
        gistTasks[id] = Task { @MainActor [weak self] in
            let gist = await summarize(text)
            guard !Task.isCancelled, let self else { return }
            gistTasks[id] = nil
            guard let index = transcript.firstIndex(where: { $0.id == id }) else { return }
            if let gist {
                transcript[index].text = gist
                transcript[index].verbatim = false
            }
            transcript[index].summarizing = false
        }
    }

    @discardableResult
    private func appendTranscript(_ author: TranscriptEntry.Author, text: String, verbatim: Bool = false,
                                  summarizing: Bool = false, signsOff: Bool = false,
                                  recipient: Speaker? = nil, delivery: TranscriptEntry.Delivery? = nil) -> Int {
        let id = nextTranscriptID
        nextTranscriptID += 1
        transcript.append(TranscriptEntry(id: id, author: author, text: text, verbatim: verbatim,
                                          summarizing: summarizing, signsOff: signsOff,
                                          recipient: recipient, delivery: delivery))
        return id
    }

    private func clearTranscript() {
        gistTasks.values.forEach { $0.cancel() }
        gistTasks.removeAll()
        transcript.removeAll()
    }

    /// A note's line: on the transcript as it sets off, and marked with
    /// how its handoff went. A note that never set off (too long to
    /// travel whole) still goes on, marked as not sent, so the transcript
    /// does not lose it; one the run ended on is the ending's to report.
    private func noteOnTranscript(_ delivery: SteeringDelivery) {
        guard isRunning, delivery.leg == .note else { return }
        let state: TranscriptEntry.Delivery
        switch delivery.outcome {
        case .delivered: state = .sent
        case .unconfirmed: state = .unconfirmed
        case .refused, .tooLong, .runEnded: state = .notSent
        }
        if let index = transcript.lastIndex(where: { $0.author == .human && $0.delivery == .sending }) {
            transcript[index].delivery = state
        } else if delivery.outcome != .runEnded {
            appendTranscript(.human, text: ReplySummarizer.flatten(delivery.note),
                             recipient: delivery.recipient, delivery: state)
        }
    }

    /// Why Send is unavailable now, beside it: the topic missing, or a
    /// destination not ready. nil when it can go.
    var sendBlocker: String? {
        if isShowingWindow { return "Waiting for the window to appear…" }
        if let blocker = setup.state.sendBlocker(names: names) { return blocker }
        guard instructionsReady else { return "Add a topic first: it is the whole opening message." }
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
        guard !isRunning, !isShowingWindow, stage == .compose else { return }
        // What is sent is what the box shows, words still forming included.
        voice.cancel()

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

        config.seed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        config.ending = ending
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
        beginTopicSummary()
        clearTranscript()
        // The buffer holds one run, so the debug window's "last run log"
        // means what it says; lines logged between runs (an inspect report,
        // a failed start) stay until the next run claims the buffer.
        logLines.removeAll()
        engine.startRun()
    }

    /// Whether a finished run is still on the panel: a report from a run
    /// that began, no run to own it. The composer shows the run's summary
    /// and New topic in these chats in this state, and resetSession is what leaves it.
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
        clearTopicSummary()
        clearTranscript()
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

    /// The run's `.finished` event: put the panel back to idle. Ordered
    /// after every line the run logged, because it rides the same stream.
    /// Whatever the note was doing becomes its record for the head, since
    /// the composer goes back to the topic and ending is exactly when
    /// someone inspects what happened. Last, the console takes the keyboard
    /// back: the run left it with whichever chat app replied last, and New
    /// topic is what comes next.
    private func finishRun() {
        if isSteering, let text = steeringEditor.end() { steeringText = text }
        lastRunDuration = runStartedAt.map { Date().timeIntervalSince($0) }
        runStartedAt = nil
        isRunning = false
        isHolding = false
        block = nil
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
    /// steer, which opens the field. beginSteering reads this to refuse a
    /// second ask.
    private var holdRequested: Bool { isSteering || isSteeringPending }

    /// Whether the field holds words. The paused button reads it to be
    /// Send note & continue rather than Resume, and the run's end records
    /// such words as a note never sent.
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
        case (.chatting, _), (.replied, _): return names.claude
        case (_, .chatting), (_, .replied): return names.chatgpt
        default: return nil
        }
    }

    /// The other side's name, for the receipt's echo clause.
    func otherName(than appName: String) -> String {
        appName == names.chatgpt ? names.claude : names.chatgpt
    }

    func appName(_ speaker: Speaker) -> String {
        switch speaker {
        case .chatgpt: names.chatgpt
        case .claude: names.claude
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
        if grant == .now { openSteeringField() }
    }

    /// The hold is granted: the field opens on whatever it holds.
    private func openSteeringField() {
        steeringEditor.begin(text: steeringText)
        isSteering = true
    }

    /// Return, or Send note & continue / Resume: the field closes and the run goes on. Words
    /// in it are the note — the mailbox takes them trimmed, and the field
    /// keeps them as written to show under the blur — and an empty field
    /// just continues. Posting comes before the hold lifts, so the handoff the
    /// flag releases is one that finds the note.
    func sendSteering() {
        guard consoleAccess.canResume, !control.isCancelled else { return }
        voice.cancel()
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

    /// Esc in the open field. The first press empties it; the second, on an
    /// empty field, closes it and continues — so Esc twice drops whatever
    /// note was there, queued before or not.
    func escapeSteering() {
        guard isRunning, isSteering else { return }
        // While the mic is open, Esc closes it and keeps the words.
        if voice.isActive { return voice.cancel() }
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
        appendTranscript(.human, text: ReplySummarizer.flatten(note), recipient: recipient, delivery: .sending)
        releaseQueued(matching: note)
    }

    /// The field lets go of the queued note, when the note the worker
    /// named is the one it shows.
    private func releaseQueued(matching note: String) {
        guard let queued = queuedSteering,
              queued.trimmingCharacters(in: .whitespacesAndNewlines) == note else { return }
        queuedSteering = nil
        steeringText = ""
    }

    /// One leg's outcome becomes the record. A note leg reported straight
    /// off the mailbox — too long to travel whole, or the run ended with
    /// it queued — never had a committed event, so the field lets go of it
    /// here instead.
    private func steeringDelivered(_ delivery: SteeringDelivery) {
        noteOnTranscript(delivery)
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
            releaseQueued(matching: delivery.note)
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
    /// got its outcome, which is what unconfirmed means, on its transcript
    /// line as on the receipt. Notes already resolved keep the record they
    /// have, and an echo still ahead is ruled out.
    private func recordSteeringAtRunEnd() {
        if let inFlight = steeringInFlight {
            lastReceipt = SteeringReceipt(note: inFlight.note, recipient: inFlight.recipient,
                                          turn: inFlight.turn, outcome: .unconfirmed)
            if let index = transcript.lastIndex(where: { $0.author == .human && $0.delivery == .sending }) {
                transcript[index].delivery = .unconfirmed
            }
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

    #if DEBUG
    /// Dump both apps' windows, buttons, and selector matches into the log —
    /// the way selector breakage gets diagnosed after an app update. A debug
    /// tool, reached through the app menu's Inspect Apps item and read in the
    /// log window it opens. The report arrives as a log line on the event
    /// stream.
    func runInspect() {
        guard !isRunning else { return }
        engine.inspect()
    }
    #endif
}
