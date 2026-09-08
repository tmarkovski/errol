// Timestamped logging to stdout, the engine's outward event stream, the
// app's inward control mailbox, the per-run debug log on disk, and the
// incremental markdown transcript.

import Foundation

let iso = ISO8601DateFormatter()

/// Millisecond timestamps for the debug log file, where the order of two
/// reads a few hundred milliseconds apart is often the whole question.
let isoMillis: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

/// Everything the engine reports outward, in the order it happened.
enum RelayEvent {
    case log(String)
    case transfer(TransferFeedback)
    /// Both sides' conversation state (ChatGPT first), whenever either
    /// changes.
    case conversation(chatgpt: ConversationStatus, claude: ConversationStatus)
    /// Each turn as it begins (1-based).
    case turn(Int)
    /// The run parking at a handoff to wait for Resume, and letting go.
    /// Asking for a pause and the run acting on it are different moments —
    /// the request lands mid-reply and takes effect only once that reply
    /// is ready to capture — and nothing else the app can see tells them apart.
    case holding(Bool)
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

func log(_ message: String) {
    let line = "[\(iso.string(from: Date()))] \(message)"
    print(line)
    relayEvents.post(.log(line))
    RunLog.write(message, detail: false)
}

/// A line for the debug log file only: the per-poll observations, element
/// descriptions, and focus reports that explain a `log` line but would bury
/// the panel's run log (a 500-line tail meant to be read at a glance). A
/// no-op when no run log is open — the CLI harness and the tests.
func trace(_ message: String) {
    RunLog.write(message, detail: true)
}

// MARK: - Debug log file

/// The run's debug log on disk: every `log` line plus the `trace` detail
/// behind it, one file per run under ~/Library/Logs/Errol, kept for the last
/// `RunLog.keep` runs. The panel's in-memory log is cleared at each Start and
/// capped, and stdout goes nowhere for an app launched from Finder, so
/// without this file an intermittent failure — a paste seen once in ten
/// turns to land twice — leaves nothing to read afterwards. Snapshots taken
/// at a failure (`sidecar`) sit beside the log under the run's own prefix.
///
/// One log is open at a time, process-wide, like the event bus the `log`
/// lines ride; writes come from the relay worker and the main thread, and
/// the lock covers the handle and the current log alike.
final class RunLog: @unchecked Sendable {
    /// How many runs' files survive a prune.
    static let keep = 20
    static let filePrefix = "errol-run-"

    /// Where the files go. Tests point this at a scratch folder so pruning
    /// can be exercised without touching a real run's logs.
    static var directoryOverride: URL?

    static var directory: URL {
        if let directoryOverride { return directoryOverride }
        return (FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"))
            .appendingPathComponent("Logs/Errol", isDirectory: true)
    }

    private static let lock = NSLock()
    private static var current: RunLog?
    private static var last: URL?

    /// The open log's file path, for the run's first `log` line.
    static var currentPath: String? {
        lock.lock()
        defer { lock.unlock() }
        return current?.url.path
    }

    /// The newest log this process opened, open or closed, for the menu
    /// item that reveals it.
    static var lastPath: String? {
        lock.lock()
        defer { lock.unlock() }
        return last?.path
    }

    /// Open a fresh log for the run starting now, pruning old runs' files.
    /// Returns nil (and logs nothing to disk for this run) when the folder
    /// cannot be created or the file cannot be opened.
    @discardableResult
    static func begin(at date: Date = Date()) -> RunLog? {
        end()
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("debug log: cannot create \(directory.path): \(error)")
            return nil
        }
        prune()
        // Colons are legal in APFS names but unfriendly in Finder and in
        // shells, so the timestamp in the name swaps them for dashes.
        let stamp = iso.string(from: date).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("\(filePrefix)\(stamp).log")
        guard manager.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else {
            print("debug log: cannot open \(url.path)")
            return nil
        }
        let log = RunLog(url: url, handle: handle)
        lock.lock()
        current = log
        last = url
        lock.unlock()
        log.append("\(isoMillis.string(from: date))  Debug log for the run starting now. "
            + "Lines flush left are the run log as the panel shows it; indented lines are detail.")
        return log
    }

    /// Close the current log, if any. Later `log` and `trace` calls go to
    /// stdout and the panel only, until the next `begin`.
    static func end() {
        lock.lock()
        let closing = current
        current = nil
        lock.unlock()
        closing?.close()
    }

    static func write(_ message: String, detail: Bool) {
        lock.lock()
        let log = current
        lock.unlock()
        guard let log else { return }
        let stamp = isoMillis.string(from: Date())
        log.append(detail ? "\(stamp)    · \(message)" : "\(stamp)  \(message)")
    }

    /// A file beside the current log for a capture too large or too
    /// structured for a log line (an AX subtree as fixture JSON). Named
    /// under the run's prefix so pruning removes it with the run, and
    /// numbered in the order asked for, so two captures with the same tag
    /// in one run — the same failure at two turns — both survive. nil when
    /// no log is open.
    static func sidecar(_ tag: String, extension ext: String) -> URL? {
        lock.lock()
        let log = current
        let sequence = log.map { $0.nextSidecar() } ?? 0
        lock.unlock()
        guard let log else { return nil }
        let base = log.url.deletingPathExtension().lastPathComponent
        let number = String(format: "%02d", sequence)
        return log.url.deletingLastPathComponent()
            .appendingPathComponent("\(base).\(number)-\(tag).\(ext)")
    }

    /// Delete every file of every run except the newest `keep - 1`, so that
    /// with the run about to be opened `keep` remain. Files group into runs
    /// by the part of the name before the first dot, which the log and its
    /// sidecars share.
    private static func prune() {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
        let runs = Set(names.filter { $0.hasPrefix(filePrefix) }
            .map { String($0.split(separator: ".", maxSplits: 1).first ?? "") })
        // The prefix carries an ISO timestamp, so lexical order is time order.
        let stale = Set(runs.sorted().dropLast(max(keep - 1, 0)))
        guard !stale.isEmpty else { return }
        for name in names where stale.contains(String(name.split(separator: ".", maxSplits: 1).first ?? "")) {
            try? manager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    let url: URL
    private let handle: FileHandle
    private let writeLock = NSLock()
    /// Sidecars issued so far; read and advanced under the class lock.
    private var sidecars = 0

    private init(url: URL, handle: FileHandle) {
        self.url = url
        self.handle = handle
    }

    private func nextSidecar() -> Int {
        sidecars += 1
        return sidecars
    }

    private func append(_ line: String) {
        writeLock.lock()
        defer { writeLock.unlock() }
        handle.write((line + "\n").data(using: .utf8) ?? Data())
    }

    private func close() {
        writeLock.lock()
        defer { writeLock.unlock() }
        try? handle.synchronize()
        try? handle.close()
    }
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

enum HoldGrant: Equatable { case now, afterOperation, cancelled }
enum OperationDecision: Equatable { case proceed, hold, cancel }
enum FocusOperation: Equatable { case capture, delivery }

/// The app's inward channel to a run in flight: the cancel and pause flags
/// the relay's wait loops poll — so a run can end or hold without killing
/// the process — and the steering-note mailbox. Set from the main thread,
/// read on the relay worker; one lock covers the lot.
// Every stored value is protected by lock, including operation ownership.
final class RelayControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var paused = false
    private var note: String?
    private var operation: FocusOperation?
    private var pendingEditor = false
    private var finished = false

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() {
        lock.lock()
        cancelled = true
        pendingEditor = false
        lock.unlock()
    }

    /// Both capture and delivery wait while the steering editor owns focus.
    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }

    var hasFocusOperation: Bool { lock.lock(); defer { lock.unlock() }; return operation != nil }
    var canOpenSteering: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused && operation == nil && !cancelled && !finished
    }

    func requestHold() -> HoldGrant {
        lock.lock()
        defer { lock.unlock() }
        return requestHoldLocked()
    }

    private func requestHoldLocked() -> HoldGrant {
        guard !cancelled, !finished else { return .cancelled }
        paused = true
        pendingEditor = operation != nil
        return pendingEditor ? .afterOperation : .now
    }

    /// Used for capture and the opener. Neither consumes the note mailbox.
    func beginOperation(_ kind: FocusOperation) -> OperationDecision {
        lock.lock()
        defer { lock.unlock() }
        if cancelled || finished { return .cancel }
        if paused || operation != nil { return .hold }
        operation = kind
        return .proceed
    }

    /// The app calls this inside its synchronous main-queue completion fence.
    /// Keep the hold set when granting, so the next operation cannot race the
    /// controller's receipt of steeringGranted.
    func endOperation(continuingRun: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        precondition(operation != nil, "No focus operation to end")
        operation = nil
        if !continuingRun { finished = true }
        let grant = pendingEditor && !cancelled && !finished
        pendingEditor = false
        return grant
    }

    /// Seal terminal paths before the finished event reaches the controller.
    /// Preserve the hold for the end-of-run focus restoration decision.
    func finishRun() {
        lock.lock()
        defer { lock.unlock() }
        precondition(operation == nil, "Finish the focus operation first")
        finished = true
        pendingEditor = false
    }

    /// The editor must stop accepting input before the controller calls this.
    func finishSteering(note text: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, !finished else { return }
        note = text
        paused = false
        pendingEditor = false
    }

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

    /// Claim the note and ask for editor ownership together. A lost claim
    /// still holds the next operation, opening a new, empty note after send.
    func claimSteering() -> (note: String?, grant: HoldGrant) {
        lock.lock()
        defer { lock.unlock() }
        let grant = requestHoldLocked()
        guard grant != .cancelled else { return (nil, grant) }
        let claimed = note
        note = nil
        return (claimed, grant)
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
        if cancelled || finished { return .cancel }
        if paused || operation != nil { return .hold }
        operation = .delivery
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
        operation = nil
        pendingEditor = false
        finished = false
        lock.unlock()
    }
}

let relayControl = RelayControl()

/// Drain the operation's queued main-thread focus work before releasing its
/// ownership. The live worker waits here; the main thread must never join it.
/// Main-thread preview/test callers can complete directly.
func completeFocusOperation(control: RelayControl, events: RelayEventBus,
                            continuingRun: Bool) {
    let complete = {
        if control.endOperation(continuingRun: continuingRun) {
            events.post(.steeringGranted)
        }
    }
    if Thread.isMainThread { complete() }
    else { DispatchQueue.main.sync(execute: complete) }
}

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
