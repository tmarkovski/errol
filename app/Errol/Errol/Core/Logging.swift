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
    /// The run is over — however it ended — and its worker has stopped
    /// touching the apps.
    case finished
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

    /// The steering mailbox: posted from the panel's Steer editor and
    /// consumed at the next handoff boundary — the note rides to the side
    /// about to reply and is echoed to the other side a turn later.
    /// `takeSteering` consumes.
    func postSteering(_ text: String) { lock.lock(); note = text; lock.unlock() }
    func takeSteering() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let taken = note
        note = nil
        return taken
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
