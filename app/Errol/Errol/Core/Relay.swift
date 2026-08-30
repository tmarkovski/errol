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

/// A steering note as first delivered, to the side about to reply: it reads
/// after the message it was written in response to, and says the peer has
/// not seen it yet — the echo on the next turn is what closes that gap.
func steeringNoteSection(_ note: String, unseenBy otherName: String) -> String {
    """
    --- Steering note from the human ---

    The human paused the relay and wrote this note after \(otherName)'s \
    message above. \(otherName) has not seen it yet; it will be shared with \
    \(otherName) alongside your reply. Take it into account as you continue.

    \(note)
    """
}

/// A relayed reply, framed only when the human has steered. `noteAfter` is
/// a note posted at this handoff: it reads after the reply it was written
/// in response to. `noteBefore` is the note consumed at the previous
/// handoff, echoed to the side whose reply it followed: it reads before
/// the reply, because that is the order they happened in — the sender read
/// it first and wrote the reply in its light. With neither, the reply
/// passes through verbatim, which is the everyday case.
func relayedReply(_ reply: String, from otherName: String,
                  noteBefore: String? = nil, noteAfter: String? = nil) -> String {
    guard noteBefore != nil || noteAfter != nil else { return reply }
    var sections: [String] = []
    if let note = noteBefore {
        sections.append("""
        --- Steering note from the human ---

        After your last reply, the human paused the relay and wrote this \
        note. \(otherName) read it before writing the reply below. Take it \
        into account as you continue.

        \(note)
        """)
    }
    sections.append("--- \(otherName)'s reply ---\n\n\(reply)")
    if let note = noteAfter {
        sections.append(steeringNoteSection(note, unseenBy: otherName))
    }
    return sections.joined(separator: "\n\n")
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
    /// Finished writing, with the reply captured but not yet delivered. In an
    /// uninterrupted run a side is never seen in this state — the handoff
    /// follows immediately — but a pause parks the run here, and a side shown
    /// as still composing through a hold is simply wrong.
    case replied = "Reply ready"
    case waiting = "Waiting"
    case ended = "Conversation ended"
}

/// The whole relay run. Runs on a worker thread while the main thread serves
/// the panel's event loop. Returns false on preflight or seeding failure.
func runRelay(chatgpt: TargetApp, claude: TargetApp) -> Bool {
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

    appendTranscript("# Errol transcript, \(iso.string(from: Date()))\n\n")
    let opener = openingMessage()
    appendTranscript("## Opening message (to \(speaker.name))\n\n\(opener)\n\n")

    log("Seeding \(speaker.name)...")
    var baseline = responseBaseline(in: speaker)
    guard send(opener, to: speaker) else { return false }
    baseline = absorbEchoIntoBaseline(in: speaker, preSend: baseline)
    setConversation(speaker, .chatting)
    setConversation(listener, .waiting)

    // A sign-off is relayed like any reply so the peer sees it; the run ends
    // when two consecutive replies carry the stop sequence.
    var lastReplyEnded = false

    // A steering note travels twice: with the handoff it lands on, and —
    // echoed — with the next one, so the side whose reply it followed hears
    // of it too. This holds the note between those two handoffs.
    var steeringEcho: String?

    var turn = 0
    while true {
        turn += 1
        relayEvents.post(.turn(turn))
        guard waitForResponse(in: speaker, baseline: baseline) else {
            if relayControl.isCancelled {
                log("Run stopped by user.")
                appendTranscript("_Run stopped by user._\n\n")
            } else {
                log("Stopping: no response from \(speaker.name).")
            }
            break
        }
        guard let reply = copyLastResponse(from: speaker) else {
            log("Stopping: could not copy response from \(speaker.name).")
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

        // Pause parks the run here — the reply is safely captured and nothing
        // has been typed into the listener yet. Stop stays responsive.
        if relayControl.isPaused, !relayControl.isCancelled {
            log("Paused — holding \(speaker.name)'s reply before it reaches \(listener.name).")
            // The reply is in hand, so whoever wrote it has stopped. A
            // sign-off already put them in a state worth keeping.
            if !signedOff { setConversation(speaker, .replied) }
            relayEvents.post(.holding(true))
            while relayControl.isPaused, !relayControl.isCancelled { usleep(200_000) }
            relayEvents.post(.holding(false))
            if !relayControl.isCancelled { log("Resumed.") }
        }

        if relayControl.isCancelled {
            log("Run stopped by user.")
            appendTranscript("_Run stopped by user._\n\n")
            break
        }

        // A note posted while the reply was being written — or while the
        // run stood held — rides this handoff, after the reply it answers.
        let note = relayControl.takeSteering()
        if let note {
            log("Relaying the human's steering note with this handoff.")
            appendTranscript("## Steering note (from the human)\n\n\(note)\n\n")
        }

        // The listener's first message carries the rules and full context;
        // every later relay is the other agent's reply, untouched unless a
        // steering note framed it.
        let payload: String
        if turn == 1 {
            payload = introMessage(firstReply: reply, from: speaker.name)
                + (note.map { "\n\n" + steeringNoteSection($0, unseenBy: speaker.name) } ?? "")
        } else {
            payload = relayedReply(reply, from: speaker.name,
                                   noteBefore: steeringEcho, noteAfter: note)
        }
        steeringEcho = note
        baseline = responseBaseline(in: listener)
        guard send(payload, to: listener) else { break }
        baseline = absorbEchoIntoBaseline(in: listener, preSend: baseline)
        if !signedOff { setConversation(speaker, .waiting) }
        setConversation(listener, .chatting)
        swap(&speaker, &listener)
    }

    // A side frozen mid-state by a cap, stop, or error is not in a
    // conversation anymore; only a real sign-off survives as "ended".
    if chatgptConversation != .ended { setConversation(chatgpt, .notStarted) }
    if claudeConversation != .ended { setConversation(claude, .notStarted) }

    log("Done. Transcript: \(config.transcriptPath)")
    return true
}
