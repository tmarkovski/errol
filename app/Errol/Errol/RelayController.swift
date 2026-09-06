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
    var conversation = conversationTemplates[0].name
    /// Completes the selected template ("What to brainstorm about").
    var topic = ""
    /// The opening message written from scratch under Custom (More → Write
    /// from scratch). A stored draft: it survives comparing other shapes, so
    /// coming back to Custom finds the writing where it was left.
    var customInstructions = ""
    var limitTurns = config.limitTurns
    var turns = config.turns
    /// Which side sends the opening message. Chosen before a run by clicking
    /// a perch (the turn line names the opener), and copied into config at
    /// Start, which is where the relay loop reads it.
    var firstSpeaker = Speaker.chatgpt
    /// Whether the chat windows stand tiled — ChatGPT left, Claude right —
    /// by the Tile chip. A live arrangement, not a run option: the chip
    /// tiles the windows the moment it is pressed and puts them back where
    /// they were when pressed again, so the layout is settled and visible
    /// before Start and the console can be set beside it. Flipped here at
    /// the press, for the chip's sake; the engine's `.arranged` pulls it
    /// back down when a tiling could not be done.
    var windowsTiled = false
    var isRunning = false
    /// Whether the field is open: the human pressed Pause to steer, the
    /// engine's pause flag is on (see RelayControl), and the run holds at
    /// the next handoff until Return or the circle closes the field and lets
    /// it go. The run keeps going until it reaches that handoff.
    var isSteering = false
    /// Whether the run has actually parked at that handoff. Between the two
    /// the agent that was composing is still finishing its reply, which is
    /// the gap the panel's route draws.
    var isHolding = false
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
    @ObservationIgnored private var nextLogID = 0
    /// What drives the apps and reports back; LiveRelayEngine in the app.
    @ObservationIgnored private let engine: RelayEngine
    /// The veil over the waiting chat window; nil in previews, which have
    /// no windows to veil.
    @ObservationIgnored private let veils: SideVeils?
    /// The engine's inward flags and mailbox, written here at the human's
    /// actions and read by the run at its handoff boundaries.
    private var control: RelayControl { engine.control }
    @ObservationIgnored private var panelVisible = false
    /// Set by the AppKit shell; the panel's Settings… item routes here to
    /// open the settings window above the panel.
    @ObservationIgnored var openSettingsHandler: (() -> Void)?
    @ObservationIgnored private var templatesWatcher: AnyCancellable?

    init(engine: RelayEngine = LiveRelayEngine(), veils: SideVeils? = nil) {
        self.engine = engine
        self.veils = veils
        // Most sweeps see the same picture as the last one; publishing them
        // anyway would re-render the status views each poll, so only
        // changed statuses reach the observable properties.
        engine.onReadiness = { [weak self] chatgpt, claude in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.chatgptStatus != chatgpt { self.chatgptStatus = chatgpt }
                if self.claudeStatus != claude { self.claudeStatus = claude }
            }
        }
        // The engine's ordered event stream, delivered on the main thread.
        // Consuming it in one place keeps related updates — a turn, a hold,
        // the log line about them — from interleaving the way the separate
        // callbacks it replaced could.
        engine.events.onEvent { [weak self] event in
            guard let self else { return }
            switch event {
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
            case .steeringCommitted(let note, let recipient, let turn):
                steeringCommitted(note, to: recipient, turn: turn)
            case .steering(let delivery):
                steeringDelivered(delivery)
            case .finished:
                finishRun()
            case .arranged(let tiled):
                // The engine's word on where the windows stand. True only
                // confirms a press already shown; false takes the chip down
                // — a tiling that found no window, or a restore done.
                if !tiled { windowsTiled = false }
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

    // MARK: Tiling

    /// Tiling needs both chat windows found: the strip's two Ready dots,
    /// the same test the run preflight applies. Tiled windows can always
    /// be put back, whatever the strip says by then.
    var canTile: Bool {
        chatgptStatus.state == .ready && claudeStatus.state == .ready
    }

    /// The Tile chip: tile the chat windows now, or put them back. Not a
    /// run option — a run owns the windows, and the chip is not offered
    /// during one.
    func toggleTiling() {
        guard !isRunning else { return }
        if windowsTiled {
            windowsTiled = false
            engine.setTiling(false)
        } else if canTile {
            windowsTiled = true
            engine.setTiling(true)
        }
    }

    /// The log is an in-memory tail read through the status item's debug
    /// window (PerchLogWindowView) — the transcript file holds the whole
    /// run. Bounded, trimming in chunks so removeFirst's element shuffle
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
        guard !isRunning else { return }

        guard instructionsReady else {
            if showsFullInstructionsEditor {
                append("Write the instructions first — they become the opening message handed to the first agent.")
            } else if isFreeChat {
                append("Add a topic first — it is the whole opening message handed to the first agent.")
            } else {
                append("Add a topic first — it completes the \(conversation) opening handed to the first agent.")
            }
            return
        }
        guard engine.preflight() else { return }

        config.seed = composedInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        config.limitTurns = limitTurns
        turns = max(1, turns)
        config.turns = turns
        config.first = firstSpeaker

        isRunning = true
        isHolding = false
        resetSteering()
        lastReceipt = nil
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

    /// Whether a finished run is still on the panel: a turn count, no run to
    /// own it. The head shows New session in this state, and resetSession is
    /// what leaves it.
    var hasFinishedRun: Bool { !isRunning && currentTurn > 0 }

    /// New session: clear the finished run off the panel — the turn count,
    /// the perches' sign-offs, the run clock, the last note's record. The
    /// prompt and the run options stay as they are; they belong to the next
    /// run, not the finished one.
    func resetSession() {
        guard hasFinishedRun else { return }
        currentTurn = 0
        lastRunDuration = nil
        lastReceipt = nil
        chatgptConversation = .notStarted
        claudeConversation = .notStarted
    }

    /// The run's `.finished` event: put the panel back to idle. Ordered
    /// after every line the run logged, because it rides the same stream.
    /// Whatever the note was doing becomes its record for the head, since
    /// the composer goes back to the topic and ending is exactly when
    /// someone inspects what happened.
    private func finishRun() {
        lastRunDuration = runStartedAt.map { Date().timeIntervalSince($0) }
        runStartedAt = nil
        isRunning = false
        isHolding = false
        veils?.end()
        recordSteeringAtRunEnd()
        resetSteering()
        control.setPaused(false)
        updateScanner()
    }

    func stop() {
        guard isRunning else { return }
        // Lift the hold so the loop wakes and reaches its cancel check. The
        // field stays as it is; the run's end records what became of the note.
        control.setPaused(false)
        control.cancel()
        append("Stop requested — ending the run at the next safe point...")
    }

    // MARK: Steering

    /// Whether a hold is asked for. There is one way to ask: Pause to
    /// steer, which opens the field. The pill and the turn line read this.
    var holdRequested: Bool { isSteering }

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

    private func appName(_ speaker: Speaker) -> String {
        switch speaker {
        case .chatgpt: chatgptStatus.appName
        case .claude: claudeStatus.appName
        }
    }

    /// Pause to steer: the run holds at the next handoff and the field
    /// opens. A queued note comes back into the field to be changed — taken
    /// off the mailbox and the hold put on in one locked step
    /// (RelayControl.claimSteering), so the handoff it was queued for cannot
    /// slip through between the two. If the worker committed it first the
    /// claim loses: that note is on its way, the committed event says so,
    /// and the field opens empty for a new one.
    func beginSteering() {
        guard isRunning, !isSteering else { return }
        if queuedSteering != nil {
            queuedSteering = nil
            if control.claimSteering() != nil {
                append("Note taken back — the run holds at the next handoff while you change it.")
            } else {
                steeringText = ""
                append("The note had already gone out with the handoff; the field is open for a new one.")
            }
        } else {
            append("Pausing to steer — the run holds at the next handoff while you write.")
        }
        control.setPaused(true)
        isSteering = true
    }

    /// Return, or the circle: the field closes and the run goes on. Words
    /// in it are the note — the mailbox takes them trimmed, and the field
    /// keeps them as written to show under the blur — and an empty field
    /// just continues. Posting comes before the hold lifts, so the handoff the
    /// flag releases is one that finds the note.
    func sendSteering() {
        guard isRunning, isSteering else { return }
        let note = steeringText.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty {
            steeringText = ""
            queuedSteering = nil
            append("Continued without a note.")
        } else {
            control.postSteering(note)
            queuedSteering = steeringText
            append("Note queued — the run goes on, and the note rides the next handoff.")
        }
        isSteering = false
        control.setPaused(false)
    }

    /// Esc in the open field. The first press empties it; the second, on an
    /// empty field, closes it and continues — so Esc twice drops whatever
    /// note was there, queued before or not.
    func escapeSteering() {
        guard isRunning, isSteering else { return }
        if steeringText.isEmpty {
            sendSteering()
        } else {
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
        isSteering = false
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
        } else if isSteering, steeringHasText {
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

    func openTranscript() {
        engine.openTranscript()
    }
}
