// Message framing and the orchestration loop.

import ApplicationServices
import Foundation

// MARK: - Message framing

/// The ground rules' shipped text and the token it carries. The text is
/// editable in Settings (behind a warning — it defines how runs end), so it
/// lives as a template rather than an interpolated literal: the token stands
/// in for `config.stopSequence` and is substituted at send time, keeping the
/// marker itself a single source of truth however the prose is rewritten.
enum RelayRules {
    static let stopSequenceToken = "{{stopSequence}}"
    static let defaultTemplate = """
        This is an automated agent-to-agent conversation: your replies are relayed \
        to another AI assistant, and its replies are relayed back to you. The human \
        who set this up is not taking part in the conversation, though they may \
        occasionally interject a steering note to guide it — such notes arrive in \
        clearly marked sections, and both sides get to see them. Treat it as a real \
        multi-turn dialogue, not a one-shot answer: contribute incrementally and \
        leave room for the other assistant to build on your reply. When you want to \
        end the conversation, include {{stopSequence}} anywhere in a reply — \
        but only once the exchange has genuinely run its course; never initiate \
        the sign-off in your first reply. When the other assistant sends it, reply \
        with your own goodbye containing {{stopSequence}} — the conversation \
        closes once both sides have sent it. Replying with an empty message ends \
        the conversation immediately.
        """
}

/// Ground rules given to each agent once, at the start of its side of the
/// conversation. Everything after these two framing messages passes through
/// verbatim. Reads the template from `config` (copied there at Start), not
/// the settings store — this runs on the relay worker thread.
func relayRules() -> String {
    config.relayRulesTemplate
        .replacingOccurrences(of: RelayRules.stopSequenceToken,
                              with: config.stopSequence)
}

/// What the first agent receives: the rules plus the human's initial message.
func openingMessage() -> String {
    relayRules()
        + "\n\nThe initial message from the human user follows.\n\n---\n\n"
        + config.seed
}

/// What the second agent receives on its first turn: the rules, the human's
/// initial message, and the first agent's response to it.
func introMessage(firstReply: String, from otherName: String) -> String {
    relayRules() + """
    \n
    Below are the human's initial message and \(otherName)'s response to it, \
    so you have the full context. Continue the conversation by replying to \
    \(otherName).

    --- Initial message from the human ---

    \(config.seed)

    --- \(otherName)'s response ---

    \(firstReply)
    """
}

/// A steering note as first delivered, to the side about to reply. It reads
/// after the reply it rode in with, and describes the order of delivery —
/// the note is in this handoff, and the peer has not had it yet — rather
/// than what the human was doing when they wrote it: a note is queued while
/// the run keeps going, so nothing here may claim a pause. The echo on the
/// next turn is what closes the gap it names.
func steeringNoteSection(_ note: String, unseenBy otherName: String) -> String {
    """
    --- Steering note from the human ---

    The human submitted this steering note for the conversation. It is \
    included with this handoff and may concern earlier context. \(otherName) \
    has not yet received this note through the relay; it will be shared with \
    \(otherName) alongside your reply. Take it into account as you continue.

    \(note)
    """
}

/// A relayed reply, framed only when the human has steered. `noteAfter` is
/// a note taken at this handoff: it reads after the reply it was written
/// in response to. `noteBefore` is the note taken at the previous handoff,
/// echoed to the side whose reply it followed: it reads before the reply,
/// because that is the order they were delivered in — the sender had it in
/// their input before writing the reply below. With neither, the reply
/// passes through verbatim, which is the everyday case.
func relayedReply(_ reply: String, from otherName: String,
                  noteBefore: String? = nil, noteAfter: String? = nil) -> String {
    guard noteBefore != nil || noteAfter != nil else { return reply }
    var sections: [String] = []
    if let note = noteBefore {
        sections.append("""
        --- Steering note from the human ---

        This note was included in the input sent to \(otherName) before the \
        reply below. Take it into account as you continue.

        \(note)
        """)
    }
    sections.append("--- \(otherName)'s reply ---\n\n\(reply)")
    if let note = noteAfter {
        sections.append(steeringNoteSection(note, unseenBy: otherName))
    }
    return sections.joined(separator: "\n\n")
}

/// The text of one handoff — the reply and, when the human has steered, the
/// sections around it — assembled so the steering sections always travel
/// whole. The per-message cap (`config.maxChars`) protects usage, and under
/// it the reply is what gives way: it is cut to the room left after the
/// framing and the notes, never the other way around, because a note cut
/// short is a direction misread, while a reply cut short is marked as such
/// and the conversation carries on.
struct HandoffPayload {
    /// The side whose reply this is, named in the framing.
    var from: String
    /// The listener's first message carries the rules and the full context.
    var intro: Bool
    /// The note taken at the previous handoff, echoed before the reply.
    var echo: String?
    /// The note taken at this handoff, read after the reply.
    var note: String?

    /// The whole thing around `reply`, cap or no cap.
    func assemble(reply: String) -> String {
        if intro {
            return introMessage(firstReply: reply, from: from)
                + (note.map { "\n\n" + steeringNoteSection($0, unseenBy: from) } ?? "")
        }
        return relayedReply(reply, from: from, noteBefore: echo, noteAfter: note)
    }

    /// The room the reply has under `cap` once the framing and the notes
    /// are in — negative when they alone exceed it.
    func replyRoom(cap: Int) -> Int {
        cap - assemble(reply: "").count
    }

    /// Whether the steering sections can travel whole under `cap` and still
    /// leave the reply at least its truncation mark.
    func carriesNotes(cap: Int) -> Bool {
        replyRoom(cap: cap) > relayTruncationMark.count
    }

    /// The text to send: the whole thing when it fits, otherwise the reply
    /// cut to the room left and marked as cut, so the message never exceeds
    /// `cap`. Callers judge the notes with `carriesNotes` first; if the
    /// framing alone leaves no room — a rules template longer than the cap
    /// — the plain cap applies as it always has.
    func text(reply: String, cap: Int) -> String {
        let whole = assemble(reply: reply)
        guard whole.count > cap else { return whole }
        let room = replyRoom(cap: cap) - relayTruncationMark.count
        guard room > 0 else { return String(whole.prefix(cap)) + relayTruncationMark }
        return assemble(reply: String(reply.prefix(room)) + relayTruncationMark)
    }
}

/// The transcript's line for one steering leg, written after the send it
/// rode (or in place of one), so the permanent record never implies that
/// an attempted handoff succeeded.
func steeringTranscriptLine(_ delivery: SteeringDelivery, recipientName: String) -> String {
    let line: String
    switch (delivery.leg, delivery.outcome) {
    case (.note, .delivered):
        line = "Steering note delivered to \(recipientName) with turn \(delivery.turn)."
    case (.note, .unconfirmed):
        line = "Steering note delivery to \(recipientName) unconfirmed — check the app."
    case (.note, .refused):
        line = "Steering note not sent: the relay could not type into \(recipientName)."
    case (.note, .tooLong):
        line = "Steering note not sent: too long to travel whole with the reply."
    case (.note, .runEnded):
        line = "Steering note not sent: the run ended with it still queued."
    case (.echo, .delivered):
        line = "Steering note shared with \(recipientName) at turn \(delivery.turn)."
    case (.echo, .unconfirmed):
        line = "Steering note sharing with \(recipientName) unconfirmed — check the app."
    case (.echo, .refused):
        line = "Steering note not shared with \(recipientName): the relay could not type into it."
    case (.echo, .tooLong):
        line = "Steering note not shared with \(recipientName): too long to travel whole with the reply."
    case (.echo, .runEnded):
        line = "Steering note not shared with \(recipientName): the run ended first."
    }
    return "_\(line)_\n\n"
}

extension SteeringOutcome {
    /// What a send's outcome means for the note that rode it.
    init(_ send: SendOutcome) {
        switch send {
        case .confirmed: self = .delivered
        case .unconfirmed, .abandoned: self = .unconfirmed
        case .refused: self = .refused
        }
    }
}

// MARK: - Run

/// Which side of the relay a message belongs to. Only the opening message
/// needs naming — every turn after it goes to whoever did not just speak —
/// so this is what `config.first` holds and what the panel nominates before
/// a run starts.
enum Speaker: String {
    case chatgpt
    case claude
}

/// Per-side conversation state during a relay run, shown under each side's
/// readiness card in the panel.
enum ConversationStatus: String {
    case notStarted = "Not started"
    case chatting = "Chatting\u{2026}"
    /// Finished writing, with the reply detected but not yet delivered. Capture
    /// may still be waiting for the steering editor to release focus. A normal
    /// handoff leaves this state after capture and delivery; a hold can park
    /// here without implying the agent is still composing.
    case replied = "Reply ready"
    case waiting = "Waiting"
    case ended = "Conversation ended"
}

/// The whole relay run. Runs on a worker thread while the main thread serves
/// the panel's event loop. Returns false on preflight or seeding failure.
func runRelay(chatgpt: TargetApp, claude: TargetApp,
              operationCompleted: (Bool) -> Void = {
                  _ = relayControl.endOperation(continuingRun: $0)
              }) -> Bool {
    // The app supplies a main-queue completion fence; command-line callers
    // have no steering editor and can release ownership directly.
    var operationActive = false
    func endOperation(continuingRun: Bool) {
        operationCompleted(continuingRun)
        operationActive = false
    }
    defer {
        if operationActive { endOperation(continuingRun: false) }
        relayControl.finishRun()
    }

    func beginOperation(_ kind: FocusOperation, waiting: String) -> Bool {
        var decision = relayControl.beginOperation(kind)
        if decision == .hold {
            log(waiting)
            relayEvents.post(.holding(true))
            repeat {
                usleep(200_000)
                decision = relayControl.beginOperation(kind)
            } while decision == .hold
            relayEvents.post(.holding(false))
        }
        guard decision == .proceed else { return false }
        operationActive = true
        return true
    }
    // nil = no cap: the run ends on the conversation's own close (mutual
    // sign-off, empty reply, timeout, or Stop).
    let turnCap = config.limitTurns ? config.turns : nil
    if let turnCap, turnCap < 1 {
        log("turns must be at least 1 when the turn limit is on")
        return false
    }

    // Preflight: refuse to run without a targetable window in each app — an
    // eligible chat window, or (where the selectors allow it) an excluded-
    // surface window with a composer, e.g. a Claude Code session in Claude
    // Desktop when no chat conversation is open.
    for target in [chatgpt, claude] {
        guard let window = chatWindow(in: target) else {
            log("ERROR: \(target.name): no targetable window found.")
            log("Open a chat conversation in \(target.name) and press Start again. (Inspect shows how each window was classified.)")
            return false
        }
        let title = (axAttribute(window, kAXTitleAttribute) as? String) ?? "untitled"
        log("\(target.name): targeting window \"\(title)\"")
        if isExcludedWindow(window, selectors: target.selectors) {
            // Not a fault, and on the current single-window Claude Desktop not
            // even unusual: the Code world replaces the chat inside the one
            // window instead of opening beside it, so this fires on every run
            // started while Code is up. Lead with what is being targeted; the
            // absent chat is the reason for it, not the news.
            log("\(target.name): NOTE: relaying into a \(target.selectors.excludedSurfaceName ?? "non-chat") session, since no chat conversation is open. Everything relayed lands in that session.")
        }
        if inputArea(in: target) == nil {
            log("ERROR: \(target.name): chat window has no composer text area.")
            return false
        }
    }

    var speaker = config.first == .claude ? claude : chatgpt
    var listener = speaker.app == chatgpt.app ? claude : chatgpt

    var chatgptConversation = ConversationStatus.notStarted
    var claudeConversation = ConversationStatus.notStarted
    func setConversation(_ target: TargetApp, _ status: ConversationStatus) {
        if target.app == chatgpt.app { chatgptConversation = status }
        else { claudeConversation = status }
        relayEvents.post(.conversation(chatgpt: chatgptConversation,
                                       claude: claudeConversation))
    }
    func side(_ target: TargetApp) -> Speaker {
        target.app == chatgpt.app ? .chatgpt : .claude
    }
    /// One steering leg's outcome, to the panel and the transcript alike.
    func reportSteering(_ leg: SteeringDelivery.Leg, _ note: String, to recipient: TargetApp,
                        turn: Int, outcome: SteeringOutcome) {
        let delivery = SteeringDelivery(leg: leg, note: note, recipient: side(recipient),
                                        turn: turn, outcome: outcome)
        appendTranscript(steeringTranscriptLine(delivery, recipientName: recipient.name))
        relayEvents.post(.steering(delivery))
    }

    appendTranscript("# Errol transcript, \(iso.string(from: Date()))\n\n")
    let opener = openingMessage()
    appendTranscript("## Opening message (to \(speaker.name))\n\n\(opener)\n\n")

    log("Seeding \(speaker.name)...")
    guard beginOperation(.delivery, waiting: "Paused — waiting before the opening message.") else {
        return false
    }
    var baseline = responseBaseline(in: speaker)
    let openingOutcome = send(opener, to: speaker)
    if openingOutcome.continuesRun {
        setConversation(speaker, .chatting)
        setConversation(listener, .waiting)
    }
    endOperation(continuingRun: openingOutcome.continuesRun)
    guard openingOutcome.continuesRun else { return false }
    baseline = absorbEchoIntoBaseline(in: speaker, preSend: baseline)

    // A sign-off is relayed like any reply so the peer sees it; the run ends
    // when two consecutive replies carry the stop sequence.
    var lastReplyEnded = false

    // A steering note travels twice: with the handoff it lands on, and —
    // echoed — with the next one, so the side whose reply it followed hears
    // of it too. This holds the note between those two handoffs, with the
    // turn it first rode, so the echo can be reported against it.
    var steeringEcho: (note: String, turn: Int)?

    var turn = 0
    while true {
        turn += 1
        relayEvents.post(.turn(turn))
        guard waitForResponse(in: speaker, baseline: baseline) else {
            if relayControl.isCancelled {
                log("Run stopped by user.")
                appendTranscript("_Run stopped by user._\n\n")
            } else {
                log("Stopping: no response activity detected from \(speaker.name).")
                appendTranscript("_Run stopped: no response activity detected from \(speaker.name) for \(Int(config.timeout))s._\n\n")
            }
            break
        }
        setConversation(speaker, .replied)
        guard beginOperation(.capture,
                             waiting: "Paused — \(speaker.name)'s reply is ready; waiting to copy it.") else {
            log("Run stopped by user.")
            break
        }
        guard let reply = copyLastResponse(from: speaker) else {
            log("Stopping: could not copy response from \(speaker.name) after a retry.")
            break
        }

        appendTranscript("## Turn \(turn): \(speaker.name)\n\n\(reply)\n\n")

        let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedReply.isEmpty {
            setConversation(speaker, .ended)
            log("\(speaker.name) ended the conversation (empty reply).")
            appendTranscript("_\(speaker.name) ended the conversation._\n\n")
            break
        }
        let signedOff = trimmedReply.localizedCaseInsensitiveContains(config.stopSequence)
        if signedOff {
            setConversation(speaker, .ended)
            appendTranscript("_\(speaker.name) ended the conversation._\n\n")
            if lastReplyEnded {
                log("\(speaker.name) ended the conversation too — both sides have signed off.")
                break
            }
            log("\(speaker.name) ended the conversation; relaying the sign-off so \(listener.name) can close out.")
        }
        lastReplyEnded = signedOff

        log("Turn \(turn)\(turnCap.map { "/\($0)" } ?? ""): \(speaker.name) -> \(listener.name) (\(reply.count) chars)")

        if let turnCap, turn >= turnCap {
            log("Turn cap reached.")
            break
        }
        endOperation(continuingRun: true)

        // The handoff's text: the listener's first message carries the rules
        // and full context; every later relay is the other agent's reply,
        // untouched unless a steering note frames it. The echo goes in
        // first, and one that cannot travel whole is dropped and reported
        // before the fresh note is judged against the room that is left.
        var payload = HandoffPayload(from: speaker.name, intro: turn == 1,
                                     echo: steeringEcho?.note, note: nil)
        if let echo = steeringEcho, !payload.carriesNotes(cap: config.maxChars) {
            log("The echoed steering note is too long to travel whole with this handoff; not sharing it.")
            payload.echo = nil
            reportSteering(.echo, echo.note, to: listener, turn: turn, outcome: .tooLong)
            steeringEcho = nil
        }

        // Pause parks the run here — the reply is safely captured and nothing
        // has been typed into the listener yet. Hold, end, or go is one
        // decision made under the mailbox's lock, so a claim from the panel
        // either wins the note and the hold together or loses both
        // (RelayControl.decideHandoff). Stop stays responsive throughout.
        func decide() -> HandoffDecision {
            relayControl.decideHandoff { note in
                var trial = payload
                trial.note = note
                return trial.carriesNotes(cap: config.maxChars)
            }
        }
        var decision = decide()
        if decision == .hold {
            log("Paused — holding \(speaker.name)'s captured reply before it reaches \(listener.name).")
            // The reply is in hand, so whoever wrote it has stopped. A
            // sign-off already put them in a state worth keeping.
            if !signedOff { setConversation(speaker, .replied) }
            relayEvents.post(.holding(true))
            repeat {
                usleep(200_000)
                decision = decide()
            } while decision == .hold
            relayEvents.post(.holding(false))
            if decision != .cancel { log("Resumed.") }
        }

        guard case .commit(let note, let unfit) = decision else {
            log("Run stopped by user.")
            appendTranscript("_Run stopped by user._\n\n")
            break
        }
        operationActive = true

        if let unfit {
            log("The human's steering note is too long to travel whole with this handoff; not sending it.")
            appendTranscript("## Steering note (from the human)\n\n\(unfit)\n\n")
            reportSteering(.note, unfit, to: listener, turn: turn, outcome: .tooLong)
        }
        // A note queued while the reply was being written — or while the
        // run stood held — rides this handoff, after the reply it answers.
        // Committing it is announced before the paste, so the panel lets
        // go of a note the courier already holds.
        if let note {
            payload.note = note
            log("Relaying the human's steering note with this handoff.")
            appendTranscript("## Steering note (from the human)\n\n\(note)\n\n")
            relayEvents.post(.steeringCommitted(note: note, recipient: side(listener), turn: turn))
        }

        baseline = responseBaseline(in: listener)
        let outcome = send(payload.text(reply: reply, cap: config.maxChars), to: listener)
        if let note {
            reportSteering(.note, note, to: listener, turn: turn, outcome: SteeringOutcome(outcome))
        }
        if let echo = payload.echo {
            reportSteering(.echo, echo, to: listener, turn: turn, outcome: SteeringOutcome(outcome))
        }
        // The note is echoed at the next handoff unless nothing was typed
        // at all; a send that may have landed still earns its echo.
        if let note, outcome != .refused {
            steeringEcho = (note, turn)
        } else {
            steeringEcho = nil
        }
        if outcome.continuesRun {
            if !signedOff { setConversation(speaker, .waiting) }
            setConversation(listener, .chatting)
        }
        endOperation(continuingRun: outcome.continuesRun)
        guard outcome.continuesRun else { break }
        baseline = absorbEchoIntoBaseline(in: listener, preSend: baseline)
        swap(&speaker, &listener)
    }

    // Close terminal capture paths before any editor grant can be delivered.
    if operationActive { endOperation(continuingRun: false) }
    relayControl.finishRun()

    // What the run left undelivered: a note still queued never rode a
    // handoff, and an echo still pending never reached the side whose reply
    // the note followed. Both are said outright, so nothing is assumed.
    if let left = relayControl.takeSteering() {
        reportSteering(.note, left, to: listener, turn: turn, outcome: .runEnded)
    }
    if let echo = steeringEcho {
        reportSteering(.echo, echo.note, to: listener, turn: echo.turn + 1, outcome: .runEnded)
    }

    // A side frozen mid-state by a cap, stop, or error is not in a
    // conversation anymore; only a real sign-off survives as "ended".
    if chatgptConversation != .ended { setConversation(chatgpt, .notStarted) }
    if claudeConversation != .ended { setConversation(claude, .notStarted) }

    log("Done. Transcript: \(config.transcriptPath)")
    return true
}
