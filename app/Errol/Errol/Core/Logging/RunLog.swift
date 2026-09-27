// The per-run debug log on disk, its sidecar captures and the pruning of
// old runs: the one piece of logging that owns a file, apart from `log`.

import Foundation

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
