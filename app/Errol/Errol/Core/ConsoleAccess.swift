/// The console and native windows share these rules. A requested pause
/// confers no focus permission until the worker has granted it.
struct ConsoleAccess {
    var running: Bool
    var steering: Bool
    var pending: Bool
    var stopping: Bool
    var showingWindow: Bool
    var focusOperationActive = false

    var pauseGranted: Bool { running && steering && !pending && !stopping }
    // Reading controls between handoffs is safe. A copy or delivery owns
    // the keyboard until its completion fence; showing an external window
    // still requires the stronger, persistent steering hold.
    var canTakeFocus: Bool { !showingWindow && (!running || !focusOperationActive) }
    var canShowWindow: Bool { (!running || pauseGranted) && !stopping && !showingWindow }
    var canChangeDestination: Bool { !running && !showingWindow }
    var canResume: Bool { pauseGranted && !showingWindow }
}

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
