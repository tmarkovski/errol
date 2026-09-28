// The console's compact wording for a run and a side: outcome symbols, chip
// statuses and the run clock, pure and apart from the views that show them.

import Foundation

extension RunOutcome {
    var symbol: String {
        switch self {
        case .completed: "checkmark.circle.fill"
        case .stopped: "stop.circle"
        case .turnLimitReached: "flag.checkered"
        default: "exclamationmark.triangle.fill"
        }
    }

    var needsAttention: Bool {
        switch self {
        case .completed, .stopped, .turnLimitReached: false
        default: true
        }
    }

    var attentionSide: Speaker? {
        switch self {
        case .timedOut(let side), .copyFailed(let side), .sendRefused(let side),
             .sendAbandoned(let side), .emptyReply(let side), .destinationLost(let side, _): side
        default: nil
        }
    }

    var shortStatus: String? {
        switch self {
        case .sendAbandoned, .sendRefused: "check delivery"
        case .timedOut: "no response"
        case .copyFailed: "copy failed"
        case .emptyReply: "empty reply"
        case .destinationLost: "window lost"
        default: nil
        }
    }
}

extension RunBlock {
    var shortStatus: String {
        switch self {
        case .windowHidden: "window hidden"
        case .draft: "unsent draft"
        case .attachments: "unsent attachment"
        case .replying: "replying"
        case .composerUnreadable: "check message field"
        case .historyChanged: "conversation changed"
        case .notInFront: "bring window forward"
        case .covered: "conversation covered"
        }
    }
}

extension DestinationReadiness {
    var shortStatus: String? {
        switch self {
        case .ready: nil
        case .unverified: "Last used"
        case .hidden(let reason): "window \(reason)"
        case .lost: "window lost"
        case .finishPreparing(let block): block.shortStatus
        }
    }
}

extension SideSetup {
    var destinationSurface: String? { connectedCandidate?.identity.surface ?? connection?.identity.surface }
    var destinationModel: String? { connectedCandidate?.model ?? connection?.model }
}

/// m:ss, or h:mm:ss past an hour.
func runClock(_ duration: TimeInterval) -> String {
    let total = Int(duration.rounded())
    let (hours, minutes, seconds) = (total / 3600, total / 60 % 60, total % 60)
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%d:%02d", minutes, seconds)
}
