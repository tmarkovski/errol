// The app's model: form state, the log, and the start/stop wiring around
// the relay engine. UI-facing state is Observable and mutated on the main
// thread only; runs and inspections live on worker threads so the panel's
// event loop stays free. Observation tracks per property, so a view body
// re-evaluates only for the properties it actually read — which is why the
// panel is split into child views along update boundaries.

import AppKit
import ApplicationServices
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
/// end: typing holds the run, Return queues, the head says where the note
/// is.
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
    var tileWindows = false
    var isRunning = false
    /// Whether the human has *asked for* a pause with the Pause control (see
    /// RelayControl). The run keeps going until it reaches the next handoff.
    /// The other way a hold gets requested is a note being written;
    /// `holdRequested` is the two together, and is what the chrome reads.
    var isPaused = false
    /// Whether the run has actually parked at that handoff. Between the two
    /// the agent that was composing is still finishing its reply, which is
    /// the gap the panel's route draws.
    var isHolding = false
    /// The steering field's text. The composer writes it through
    /// setSteeringText, which is where typing takes effect on the run.
    var steeringText = ""
    /// The field's text as it stood when Return queued it, while the note
    /// is in the mailbox; nil otherwise. Text that differs from it is a
    /// note being written, and a note being written holds the run.
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
    @ObservationIgnored private let scanner = ReadinessScanner()
    @ObservationIgnored private var panelVisible = false
    /// Set by the AppKit shell; the panel's Settings… item routes here to
    /// open the settings window above the panel.
    @ObservationIgnored var openSettingsHandler: (() -> Void)?
    @ObservationIgnored private var templatesWatcher: AnyCancellable?

    init() {
        // Most sweeps see the same picture as the last one; publishing them
        // anyway would re-render the status views each poll, so only
        // changed statuses reach the observable properties.
        scanner.onUpdate = { [weak self] chatgpt, claude in
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
        relayEvents.onEvent { [weak self] event in
            guard let self else { return }
            switch event {
            case .log(let line):
                append(line)
            case .conversation(let chatgpt, let claude):
                chatgptConversation = chatgpt
                claudeConversation = claude
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
        scanner.setActive(panelVisible && !isRunning)
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
        guard ensureTrusted(), let apps = resolveApps() else { return }

        config.seed = composedInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        config.limitTurns = limitTurns
        turns = max(1, turns)
        config.turns = turns
        config.first = firstSpeaker
        let tile = tileWindows

        isRunning = true
        isPaused = false
        isHolding = false
        resetSteering()
        lastReceipt = nil
        relayControl.reset()
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
        let origin = currentFrontmostApp()
        log("Run starting. Transcript: \(config.transcriptPath)")

        runOnWorkerThread {
            // First contact only: the scanner has usually nudged both long
            // ago, and then the trees are already populated and the settle
            // wait would just delay the run.
            let freshChatgpt = electronNudges.beginContact(apps.chatgpt)
            let freshClaude = electronNudges.beginContact(apps.claude)
            if freshChatgpt || freshClaude { usleep(700_000) }
            if tile { arrangeSideBySide(left: apps.chatgpt, right: apps.claude) }
            _ = runRelay(chatgpt: apps.chatgpt, claude: apps.claude)
            refocus(to: origin)
            relayEvents.post(.finished)
        }
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
        isPaused = false
        isHolding = false
        recordSteeringAtRunEnd()
        resetSteering()
        relayControl.setPaused(false)
        updateScanner()
    }

    func stop() {
        guard isRunning else { return }
        // Clear every hold so the loop wakes and reaches its cancel check.
        // The note stays where it is; the run's end records what became of it.
        isPaused = false
        relayControl.setPaused(false)
        relayControl.cancel()
        append("Stop requested — ending the run at the next safe point...")
    }

    // MARK: Pause

    /// Whether a hold is asked for, by either route: the Pause control, or
    /// a note being written. The pill and the turn line read this, since a
    /// hold is a hold whoever asked.
    var holdRequested: Bool { isPaused || steeringDirty }

    /// Pause holds the run at the next handoff boundary; the agent currently
    /// composing finishes its reply, which is captured but not delivered
    /// until Resume. Resume lifts the pressed pause and nothing else: a note
    /// still being written keeps its own hold until it is queued or cleared.
    func togglePause() {
        guard isRunning else { return }
        isPaused.toggle()
        syncHold()
        if isPaused {
            append("Pause requested — the run holds at the next handoff.")
        } else if steeringDirty {
            append("Resumed — the note being written still holds the next handoff until you queue it or clear it.")
        }
    }

    /// The engine's pause flag is the two holds together. Every change to
    /// either goes through here, so the flag never lags the state the
    /// chrome shows.
    private func syncHold() {
        relayControl.setPaused(isPaused || steeringDirty)
    }

    // MARK: Steering

    /// Whether the field holds a note that is not queued: something written
    /// since the last queue, or a first draft. It is the note's hold on the
    /// run — writing one is asking the relay to wait at the next handoff —
    /// and the state in which the primary circle is Queue.
    var steeringDirty: Bool {
        queuedSteering == nil
            && !steeringText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    /// The field's write path, and where typing acts on the run. Text that
    /// is not queued holds the next handoff, so the note lands where the
    /// human meant it to rather than one handoff late; the hold lifts when
    /// Return queues it or Esc clears it. Typing into a queued note takes
    /// it back off the mailbox and puts the hold on in one locked step
    /// (RelayControl.claimSteering). If the worker committed it first, the
    /// claim loses: that note is on its way, the committed event says so,
    /// and what is in the field from here is a new note.
    func setSteeringText(_ text: String) {
        guard isRunning else { return }
        if let queued = queuedSteering, text != queued {
            queuedSteering = nil
            if relayControl.claimSteering() != nil {
                append("Note taken back to change it — the run holds at the next handoff until you queue it again or clear it.")
            } else {
                append("The note had already gone out with the handoff; what you type now is a new note.")
            }
        }
        steeringText = text
        syncHold()
    }

    /// Return, or the Queue circle: commit the text to the next handoff.
    /// The mailbox takes the trimmed note, the field keeps the text as
    /// written under a wash, and the note's hold lifts — a pressed pause
    /// stays, and the note goes out when the human resumes. Posting comes
    /// before the hold lifts, so the handoff the flag releases is one that
    /// finds the note.
    func queueSteering() {
        guard isRunning, steeringDirty else { return }
        let note = steeringText.trimmingCharacters(in: .whitespacesAndNewlines)
        relayControl.postSteering(note)
        queuedSteering = steeringText
        syncHold()
        append(isPaused
            ? "Note queued — it goes out with the handoff when you resume."
            : "Note queued — it goes out with the next handoff.")
    }

    /// Esc: clear the field, take a queued note back, and lift the note's
    /// hold. A pressed pause stays; Resume is what lifts that. Returns
    /// whether there was anything to clear, so the composer can let Esc
    /// mean "leave the field" when there was not.
    @discardableResult
    func clearSteering() -> Bool {
        guard isRunning else { return false }
        var cleared = false
        if queuedSteering != nil {
            queuedSteering = nil
            cleared = true
            if relayControl.takeSteering() != nil {
                append("Note withdrawn.")
            } else {
                append("The note had already gone out with the handoff.")
            }
        }
        if !steeringText.isEmpty {
            steeringText = ""
            cleared = true
        }
        syncHold()
        return cleared
    }

    /// Everything about the note, at a run's start and end.
    private func resetSteering() {
        steeringText = ""
        queuedSteering = nil
        steeringInFlight = nil
    }

    /// The worker won the handoff: the note is the courier's, and the field
    /// lets go of it — its text clears and the head takes over the story.
    /// The field is left alone when it no longer shows that note: the human
    /// typed in the instant before the commit and the claim lost, and what
    /// they have now is a new note, holding the next handoff as any draft
    /// does.
    private func steeringCommitted(_ note: String, to recipient: Speaker, turn: Int) {
        steeringInFlight = SteeringInFlight(note: note, recipient: appName(recipient), turn: turn)
        if let queued = queuedSteering,
           queued.trimmingCharacters(in: .whitespacesAndNewlines) == note {
            queuedSteering = nil
            steeringText = ""
            syncHold()
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
                syncHold()
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

    /// What the run's end leaves of the note becomes its record: a note
    /// being written was never queued; a queued note the worker never took
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
        } else if steeringDirty {
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
    /// window it opens.
    func runInspect() {
        guard !isRunning else { return }
        guard ensureTrusted(), let apps = resolveApps() else { return }
        append("Inspecting both apps...")
        runOnWorkerThread { [weak self] in
            let freshChatgpt = electronNudges.beginContact(apps.chatgpt)
            let freshClaude = electronNudges.beginContact(apps.claude)
            if freshChatgpt || freshClaude { usleep(700_000) }
            let report = inspectReport(apps.chatgpt) + "\n\n" + inspectReport(apps.claude)
            DispatchQueue.main.async { self?.append(report) }
        }
    }

    func openTranscript() {
        let url = URL(fileURLWithPath: config.transcriptPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            append("No transcript yet at \(config.transcriptPath).")
        }
    }

    /// Prompting on demand (not at app launch) means the permission dialog
    /// appears while the user is looking at the panel, not out of nowhere.
    private func ensureTrusted() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) { return true }
        append("Accessibility permission missing. Grant Errol in System Settings > Privacy & Security > Accessibility, then try again.")
        return false
    }

    private func resolveApps() -> (chatgpt: TargetApp, claude: TargetApp)? {
        guard let chatgpt = findApp(bundleID: config.chatgptBundleID, name: "Codex",
                                    selectors: config.chatgptSelectors) else {
            append("ERROR: Codex/ChatGPT (\(config.chatgptBundleID)) is not running. Launch it with a conversation open.")
            return nil
        }
        guard let claude = findApp(bundleID: config.claudeBundleID, name: "Claude",
                                   selectors: config.claudeSelectors) else {
            append("ERROR: Claude Desktop (\(config.claudeBundleID)) is not running. Launch it with a conversation open.")
            return nil
        }
        return (chatgpt, claude)
    }

    /// The deep AX tree walks need more stack than the default worker thread
    /// provides.
    private func runOnWorkerThread(_ work: @escaping () -> Void) {
        let worker = Thread(block: work)
        worker.stackSize = 4 << 20
        worker.start()
    }
}
