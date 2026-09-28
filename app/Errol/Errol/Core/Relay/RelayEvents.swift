// The engine's outward event stream, and the bus that delivers it on the
// main thread in posting order; the log is one event among many here.

import Foundation

/// Everything the engine reports outward, in the order it happened.
enum RelayEvent {
    case log(String)
    case transfer(TransferFeedback)
    /// Both sides' conversation state (ChatGPT first), whenever either
    /// changes.
    case conversation(chatgpt: ConversationStatus, claude: ConversationStatus)
    /// Each turn as it begins (1-based).
    case turn(Int)
    /// A reply as it was copied from the side that wrote it, once it is
    /// in hand and before it is relayed. The panel's log sums it up
    /// (ReplySummarizer).
    case reply(side: Speaker, text: String)
    /// The run parking at a handoff to wait for Resume, and letting go.
    /// Asking for a pause and the run acting on it are different moments —
    /// the request lands mid-reply and takes effect only once that reply
    /// is ready to capture — and nothing else the app can see tells them apart.
    case holding(Bool)
    /// The run standing on a condition observed in the apps — a changed
    /// conversation, an unsent draft — and, with nil, standing on none.
    /// Separate from the steering hold above: the human asks for that one,
    /// the apps clear this one, and the two can coincide.
    case blocked(RunBlock?)
    /// The focus operation has finished and a pending steering editor may open.
    case steeringGranted
    /// The worker took the human's note off the mailbox for the handoff it
    /// is about to make. From here the note is the courier's — the panel
    /// can no longer take it back — and the paste is about to begin. The
    /// note rides along so the panel can tell it from one queued since.
    case steeringCommitted(note: String, recipient: Speaker, turn: Int)
    /// What became of a note, or of its echo, at the handoff it rode — or
    /// did not ride. Posted after the send, or in place of one.
    case steering(SteeringDelivery)
    /// How the run ended, from the run itself: the outcome, the replies it
    /// captured, and the hold or sign-off it ended on. Posted before
    /// `finished`, and on a failed start in place of any turn.
    case ended(RunReport)
    /// The run is over — however it ended — and its worker has stopped
    /// touching the apps.
    case finished
}

/// One leg of a steering note's journey and how it ended. A note travels
/// twice — to the side about to reply, then echoed to the other side a
/// handoff later — and each leg gets its own record, so "shared with the
/// other side" is something observed, never assumed.
struct SteeringDelivery: Equatable {
    enum Leg: Equatable {
        case note
        case echo
    }
    var leg: Leg
    /// The note itself, so the record is made from what travelled, not
    /// from whatever the field holds by the time the outcome lands.
    var note: String
    var recipient: Speaker
    /// The turn whose reply the note travelled with, or would have.
    var turn: Int
    var outcome: SteeringOutcome
}

/// How a steering leg ended.
enum SteeringOutcome: Equatable {
    /// The paste was verified in the composer and a submission signal was
    /// observed: the note is in the conversation.
    case delivered
    /// A submission was attempted, or may have been, without a signal that
    /// confirms it — the paste never verified, the composer never moved,
    /// or the foreground was lost mid-confirmation. Worth checking the app.
    case unconfirmed
    /// Nothing was typed: the send was called off (cancelled, or vetoed by
    /// an inspection) before the paste.
    case refused
    /// The framing and the steering sections alone would exceed the
    /// message cap, so the note could not travel whole and was not sent.
    case tooLong
    /// The run ended before the handoff this leg would have ridden.
    case runEnded
}

/// The engine's one outward channel. Posts come from the relay worker (and
/// the main thread, for app-side lines); delivery is serialized onto the
/// main thread in posting order, so state derived from the stream cannot
/// interleave — the reason this is one stream rather than the four
/// separate callbacks it replaced.
// The handler is protected by the lock and invoked only on the main queue.
final class RelayEventBus: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((RelayEvent) -> Void)?

    /// Main-thread delivery target; the app sets it once at startup.
    func onEvent(_ handler: @escaping (RelayEvent) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func post(_ event: RelayEvent) {
        lock.lock()
        let hasHandler = handler != nil
        lock.unlock()
        // With no handler (the CLI harness, tests) posting is a no-op
        // rather than an enqueue, so a process that never spins the main
        // run loop doesn't pile up blocks.
        guard hasHandler else { return }
        DispatchQueue.main.async {
            self.lock.lock()
            let handler = self.handler
            self.lock.unlock()
            handler?(event)
        }
    }
}

let relayEvents = RelayEventBus()
