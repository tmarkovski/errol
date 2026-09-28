// Timestamped logging: `log` lines to stdout, the panel and the run's
// debug log, and `trace` detail to the debug log alone.

import Foundation

let iso = ISO8601DateFormatter()

/// Millisecond timestamps for the debug log file, where the order of two
/// reads a few hundred milliseconds apart is often the whole question.
let isoMillis: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

/// A `log` line as stdout and the panel show it: the message behind a
/// second-precision timestamp in brackets. Its own function so a run that
/// posts to a bus other than `relayEvents` (the preview engine's) formats
/// its lines the same way.
func timestampedLogLine(_ message: String) -> String {
    "[\(iso.string(from: Date()))] \(message)"
}

func log(_ message: String) {
    let line = timestampedLogLine(message)
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
