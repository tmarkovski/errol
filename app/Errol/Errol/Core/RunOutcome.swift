// How a run ended, recorded by the run itself rather than inferred from
// the counters it left behind. The panel's summary is rendered from this,
// so a timeout on the last permitted turn reads as a timeout and a failed
// start has a reason, whatever the turn count says.

import Foundation

/// The terminal result of a run. Every way the loop can exit maps to one
/// of these; a hold or a sign-off that preceded the end travels beside it
/// as context (RunReport), not as a second cause.
enum RunOutcome: Equatable {
    /// Both sides signed off in consecutive replies.
    case completed
    /// Stop was pressed and the run ended at its next safe point.
    case stopped
    /// The reply cap was reached.
    case turnLimitReached
    /// No reply activity from `side` within the inactivity allowance.
    case timedOut(side: Speaker)
    /// `side`'s reply could not be copied, after a retry.
    case copyFailed(side: Speaker)
    /// `side` could not be brought to the front, so nothing was typed.
    case sendRefused(side: Speaker)
    /// Delivery to `side` was interrupted after typing began; the message
    /// may or may not have been submitted.
    case sendAbandoned(side: Speaker)
    /// `side` replied with nothing, which ends the conversation.
    case emptyReply(side: Speaker)
    /// `side`'s conversation is gone for good: the app quit or the window
    /// closed.
    case destinationLost(side: Speaker, detail: String)
    /// The run never began, for the reason given.
    case failedStart(reason: String)

    var isFailedStart: Bool {
        if case .failedStart = self { return true }
        return false
    }
}

/// What the run reports when it ends.
struct RunReport: Equatable {
    var outcome: RunOutcome
    /// Replies actually copied out of a conversation — not the turn being
    /// awaited when the run ended.
    var repliesCaptured = 0
    /// The side whose sign-off the other never answered, when the run
    /// ended after a one-sided goodbye.
    var signedOffBy: Speaker?
    /// The hold the run was standing in when it ended.
    var block: RunBlock?

    private func name(_ side: Speaker, _ names: (chatgpt: String, claude: String)) -> String {
        side == .chatgpt ? names.chatgpt : names.claude
    }

    /// The summary's headline: the outcome, in the reading the human
    /// needs first.
    func headline(names: (chatgpt: String, claude: String)) -> String {
        switch outcome {
        case .completed: return "Run complete"
        case .stopped: return "Run stopped"
        case .turnLimitReached: return "Turn limit reached"
        case .timedOut(let side): return "\(name(side, names)) stopped responding"
        case .copyFailed(let side): return "Couldn't copy \(name(side, names))'s reply"
        case .sendRefused(let side): return "Couldn't type into \(name(side, names))"
        case .sendAbandoned(let side): return "Delivery to \(name(side, names)) interrupted"
        case .emptyReply(let side): return "\(name(side, names)) ended the conversation"
        case .destinationLost(let side, _): return "Lost \(name(side, names))'s conversation"
        case .failedStart: return "Couldn't start"
        }
    }

    /// The line under it: the count, the clock, and the context.
    func detail(names: (chatgpt: String, claude: String), duration: TimeInterval?,
                timeout: TimeInterval) -> String {
        var parts: [String] = []
        if case .failedStart(let reason) = outcome {
            return reason
        }
        parts.append("\(repliesCaptured) \(repliesCaptured == 1 ? "reply" : "replies") relayed")
        if let duration { parts.append("ran \(runClock(duration))") }
        switch outcome {
        case .completed:
            parts.append("both signed off")
        case .timedOut:
            parts.append("no reply activity for \(Int(timeout))s")
        case .sendRefused:
            parts.append("the send was called off before anything was typed")
        case .sendAbandoned:
            parts.append("focus was lost mid-send; check whether the message went")
        case .emptyReply:
            parts.append("empty reply")
        case .destinationLost(_, let detail):
            parts.append(detail)
        case .copyFailed:
            parts.append("see the log")
        default:
            break
        }
        if let block {
            parts.append("while paused: " + block.contextClause(names: names))
        } else if let side = signedOffBy, outcome != .completed, outcome != .emptyReply(side: side) {
            parts.append("after \(name(side, names)) signed off")
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// m:ss, or h:mm:ss past an hour.
func runClock(_ duration: TimeInterval) -> String {
    let total = Int(duration.rounded())
    let (hours, minutes, seconds) = (total / 3600, total / 60 % 60, total % 60)
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%d:%02d", minutes, seconds)
}

extension RunBlock {
    /// The block as a clause in the summary's context: what the run stood
    /// on when Stop was pressed.
    func contextClause(names: (chatgpt: String, claude: String)) -> String {
        let name = side == .chatgpt ? names.chatgpt : names.claude
        switch self {
        case .windowHidden: return "\(name)'s window was hidden"
        case .draft: return "\(name) had an unsent draft"
        case .attachments: return "\(name) had an unsent attachment"
        case .replying: return "\(name) was replying to something else"
        case .composerUnreadable: return "\(name)'s composer could not be read"
        case .historyChanged: return "\(name)'s conversation had moved on"
        case .notInFront: return "\(name) would not come to the front"
        }
    }
}
