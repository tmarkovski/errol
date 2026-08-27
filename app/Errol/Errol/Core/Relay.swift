// Message framing and the orchestration loop.

import ApplicationServices
import Foundation

// MARK: - Message framing

/// Ground rules given to each agent once, at the start of its side of the
/// conversation. Everything after these two framing messages passes through
/// verbatim.
func relayRules() -> String {
    """
    This is an automated agent-to-agent conversation: your replies are relayed \
    to another AI assistant, and its replies are relayed back to you. The human \
    who set this up is not taking part in the conversation. When you want to \
    end the conversation, include \(config.stopSequence) anywhere in a reply. \
    When the other assistant does so, reply with your own goodbye containing \
    \(config.stopSequence) — the conversation closes once both sides have sent \
    it. Replying with an empty message ends the conversation immediately.
    """
}

/// What the first agent receives: the rules plus the human's initial message.
func openingMessage() -> String {
    relayRules()
        + "\n\nThe initial message from the human user follows.\n\n---\n\n"
        + config.seed
}

/// What the second agent receives on its first turn: the rules, the human's
/// initial message, and the first agent's response to it.
func introMessage(firstReply: String, from other: TargetApp) -> String {
    relayRules() + """
    \n
    Below are the human's initial message and \(other.name)'s response to it, \
    so you have the full context. Continue the conversation by replying to \
    \(other.name).

    --- Initial message from the human ---

    \(config.seed)

    --- \(other.name)'s response ---

    \(firstReply)
    """
}

// MARK: - Run

/// Per-side conversation state during a relay run, shown under each side's
/// readiness card in the panel.
enum ConversationStatus: String {
    case notStarted = "Not started"
    case chatting = "Chatting\u{2026}"
    case waiting = "Waiting"
    case ended = "Conversation ended"
}

/// Set by the app layer; called on the relay worker thread with both sides'
/// statuses (ChatGPT first) whenever either changes.
var conversationStatusSink: ((ConversationStatus, ConversationStatus) -> Void)?

/// The whole relay run. Runs on a worker thread while the main thread serves
/// the panel's event loop. Returns false on preflight or seeding failure.
func runRelay(chatgpt: TargetApp, claude: TargetApp) -> Bool {
    guard config.turns >= 1 else {
        log("turns must be at least 1")
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
            log("\(target.name): NOTE: no chat window is open; targeting a \(target.selectors.excludedSurfaceName ?? "non-chat") window instead. Everything relayed will land in that session.")
        }
        if inputArea(in: target) == nil {
            log("ERROR: \(target.name): chat window has no composer text area.")
            return false
        }
    }

    if config.newChats {
        for target in [chatgpt, claude] {
            guard startNewChat(in: target) else {
                log("ERROR: \(target.name): could not start a new chat.")
                return false
            }
        }
    }

    var speaker = config.first.lowercased() == "claude" ? claude : chatgpt
    var listener = speaker.app == chatgpt.app ? claude : chatgpt

    var chatgptConversation = ConversationStatus.notStarted
    var claudeConversation = ConversationStatus.notStarted
    func setConversation(_ target: TargetApp, _ status: ConversationStatus) {
        if target.app == chatgpt.app { chatgptConversation = status }
        else { claudeConversation = status }
        conversationStatusSink?(chatgptConversation, claudeConversation)
    }

    appendTranscript("# Errol transcript, \(iso.string(from: Date()))\n\n")
    let opener = openingMessage()
    appendTranscript("## Opening message (to \(speaker.name))\n\n\(opener)\n\n")

    log("Seeding \(speaker.name)...")
    var baseline = messageAffordances(in: speaker).count
    guard send(opener, to: speaker) else { return false }
    baseline = absorbEchoIntoBaseline(in: speaker, preSend: baseline)
    setConversation(speaker, .chatting)
    setConversation(listener, .waiting)

    // A sign-off is relayed like any reply so the peer sees it; the run ends
    // when two consecutive replies carry the stop sequence.
    var lastReplyEnded = false

    for turn in 1...config.turns {
        guard waitForResponse(in: speaker, baselineCopyCount: baseline) else {
            if relayCancelled.isSet {
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

        log("Turn \(turn)/\(config.turns): \(speaker.name) -> \(listener.name) (\(reply.count) chars)")

        if turn == config.turns {
            log("Turn cap reached.")
            break
        }

        if relayCancelled.isSet {
            log("Run stopped by user.")
            appendTranscript("_Run stopped by user._\n\n")
            break
        }

        // The listener's first message carries the rules and full context;
        // every later relay is the other agent's reply, untouched.
        let payload = turn == 1 ? introMessage(firstReply: reply, from: speaker) : reply
        baseline = messageAffordances(in: listener).count
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
