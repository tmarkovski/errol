// Timestamped logging to stdout plus an optional UI sink, the incremental
// markdown transcript, and the cross-thread cancellation flag.

import Foundation

let iso = ISO8601DateFormatter()

/// Extra destination for log lines (the control panel's log view).
var logSink: ((String) -> Void)?

func log(_ message: String) {
    let line = "[\(iso.string(from: Date()))] \(message)"
    print(line)
    logSink?(line)
}

/// Set from the Stop button (main thread) and polled by the relay's wait
/// loops (worker thread), so a run can end without killing the process.
final class CancelFlag {
    private let lock = NSLock()
    private var flag = false
    func set(_ value: Bool) { lock.lock(); flag = value; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

let relayCancelled = CancelFlag()

/// Set from the panel's Pause control (main thread) and polled by the relay
/// loop (worker thread). While set, the run parks at the next handoff
/// boundary — after a reply has been captured, before it is delivered — so
/// neither app is touched while held.
let relayPaused = CancelFlag()

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
