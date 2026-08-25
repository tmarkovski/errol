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
    who set this up is not taking part in the conversation. You can end the \
    conversation at any time by replying with an empty message or by including \
    \(config.stopSequence) anywhere in a reply.
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

/// The agents' side of the stop protocol.
func isStopReply(_ reply: String) -> Bool {
    let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed.localizedCaseInsensitiveContains(config.stopSequence)
}

// MARK: - Run

/// The whole relay run. Runs on a worker thread while the main thread serves
/// the panel's event loop. Returns false on preflight or seeding failure.
func runRelay(chatgpt: TargetApp, claude: TargetApp) -> Bool {
    guard config.turns >= 1 else {
        log("turns must be at least 1")
        return false
    }

    // Preflight: refuse to run without an eligible chat window in each app.
    // (A Claude Code session window inside Claude Desktop does not count.)
    for target in [chatgpt, claude] {
        guard let window = chatWindow(in: target) else {
            log("ERROR: \(target.name): no eligible chat window found.")
            log("Open a regular chat conversation in \(target.name) and press Start again. (Inspect shows how each window was classified.)")
            return false
        }
        let title = (axAttribute(window, kAXTitleAttribute) as? String) ?? "untitled"
        log("\(target.name): targeting window \"\(title)\"")
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

    appendTranscript("# Errol transcript, \(iso.string(from: Date()))\n\n")
    let opener = openingMessage()
    appendTranscript("## Opening message (to \(speaker.name))\n\n\(opener)\n\n")

    log("Seeding \(speaker.name)...")
    var baseline = copyButtons(in: speaker).count
    guard send(opener, to: speaker) else { return false }
    baseline = absorbEchoIntoBaseline(in: speaker, preSend: baseline)

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

        if isStopReply(reply) {
            log("\(speaker.name) ended the conversation (empty reply or stop sequence).")
            appendTranscript("_\(speaker.name) ended the conversation._\n\n")
            break
        }

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
        baseline = copyButtons(in: listener).count
        guard send(payload, to: listener) else { break }
        baseline = absorbEchoIntoBaseline(in: listener, preSend: baseline)
        swap(&speaker, &listener)
    }

    log("Done. Transcript: \(config.transcriptPath)")
    return true
}
