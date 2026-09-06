// Timestamped logging to stdout, the engine's outward event stream, the
// app's inward control mailbox, and the incremental markdown transcript.

import Foundation

let iso = ISO8601DateFormatter()

/// Everything the engine reports outward, in the order it happened.
enum RelayEvent {
    case log(String)
    /// Both sides' conversation state (ChatGPT first), whenever either
    /// changes.
    case conversation(chatgpt: ConversationStatus, claude: ConversationStatus)
    /// Each turn as it begins (1-based).
    case turn(Int)
    /// The run parking at a handoff to wait for Resume, and letting go.
    /// Asking for a pause and the run acting on it are different moments —
    /// the request lands mid-reply and takes effect only once that reply
    /// is captured — and nothing else the app can see tells them apart.
    case holding(Bool)
    /// The worker took the human's note off the mailbox for the handoff it
    /// is about to make. From here the note is the courier's — the panel
    /// can no longer take it back — and the paste is about to begin. The
    /// note rides along so the panel can tell it from one queued since.
    case steeringCommitted(note: String, recipient: Speaker, turn: Int)
    /// What became of a note, or of its echo, at the handoff it rode — or
    /// did not ride. Posted after the send, or in place of one.
    case steering(SteeringDelivery)
    /// The run is over — however it ended — and its worker has stopped
    /// touching the apps.
    case finished
    /// The Tile chip's answer: the chat windows stand tiled (true) or where
    /// they were (false) — false also when a tiling was asked for and could
    /// not be done, so the chip lets go.
    case arranged(tiled: Bool)
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
    /// Nothing was typed: the relay could not take the foreground.
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
final class RelayEventBus {
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

func log(_ message: String) {
    let line = "[\(iso.string(from: Date()))] \(message)"
    print(line)
    relayEvents.post(.log(line))
}

/// The worker's verdict at a handoff boundary, reached under RelayControl's
/// lock in the same step as the mailbox: hold, end, or go — and if go, with
/// whatever note the mailbox held at that instant.
enum HandoffDecision: Equatable {
    case hold
    case cancel
    /// The handoff goes ahead. `note` rides it whole. `unfit` is a note
    /// taken off the mailbox because it could not travel whole; it is
    /// reported not sent rather than trimmed.
    case commit(note: String?, unfit: String?)
}

/// The app's inward channel to a run in flight: the cancel and pause flags
/// the relay's wait loops poll — so a run can end or hold without killing
/// the process — and the steering-note mailbox. Set from the main thread,
/// read on the relay worker; one lock covers the lot.
final class RelayControl {
    private let lock = NSLock()
    private var cancelled = false
    private var paused = false
    private var note: String?

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }

    /// While set, the run parks at the next handoff boundary — after a
    /// reply has been captured, before it is delivered — so neither app is
    /// touched while held.
    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }
    func setPaused(_ value: Bool) { lock.lock(); paused = value; lock.unlock() }

    /// The steering mailbox: one slot. The panel posts the human's note
    /// here and the worker takes it at the next handoff boundary — the note
    /// rides to the side about to reply and is echoed to the other side a
    /// turn later. Posting is a set, never an append: the panel keeps one
    /// note at a time, so a second post replaces the first.
    func postSteering(_ text: String) { lock.lock(); note = text; lock.unlock() }

    /// Withdraw the queued note. nil when the slot is empty — including
    /// when the worker has already committed the note to a handoff, in
    /// which case the withdrawal lost the race and the note is on its way.
    func takeSteering() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let taken = note
        note = nil
        return taken
    }

    /// Whether a note is waiting for its handoff.
    var hasSteering: Bool { lock.lock(); defer { lock.unlock() }; return note != nil }

    /// Typing into a queued note takes it back and requests the hold in
    /// one locked step, so the handoff it was queued for cannot slip
    /// through between the two. Returns the note when the claim won. When
    /// the worker has already committed it, returns nil and leaves the
    /// pause flag alone — the note is the courier's now.
    func claimSteering() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let claimed = note else { return nil }
        note = nil
        paused = true
        return claimed
    }

    /// The worker's one decision at a handoff boundary. It reads the cancel
    /// and pause flags and, when the handoff goes ahead, takes the note in
    /// the same locked step: checking the pause and then taking the note
    /// separately left a gap in which a claim from the panel could win the
    /// mailbox and still lose the handoff. `carries` says whether a note
    /// can travel whole with this handoff; one that cannot is taken off the
    /// mailbox and returned as `unfit`, because a note that long has no
    /// handoff that carries it, and leaving it would only report the same
    /// failure at the next one.
    func decideHandoff(carries: (String) -> Bool) -> HandoffDecision {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { return .cancel }
        if paused { return .hold }
        guard let pending = note else { return .commit(note: nil, unfit: nil) }
        note = nil
        return carries(pending)
            ? .commit(note: pending, unfit: nil)
            : .commit(note: nil, unfit: pending)
    }

    /// Run start: clear everything, so a stale cancel or pause — or a note
    /// that never found its handoff — cannot leak into the new run.
    func reset() {
        lock.lock()
        cancelled = false
        paused = false
        note = nil
        lock.unlock()
    }
}

let relayControl = RelayControl()

func appendTranscript(_ text: String) {
    let url = URL(fileURLWithPath: config.transcriptPath)
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(text.data(using: .utf8)!)
        try? handle.close()
    }
}
