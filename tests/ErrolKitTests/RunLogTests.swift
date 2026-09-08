// The per-run debug log file: what reaches it from `log` and `trace`, the
// sidecar naming, and the pruning that keeps the folder to the last runs.
// Everything runs in a scratch directory; the real ~/Library/Logs/Errol is
// never touched.

import Foundation
import XCTest
@testable import ErrolKit

final class RunLogTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("errol-runlog-tests-\(UUID().uuidString)", isDirectory: true)
        RunLog.directoryOverride = scratch
    }

    override func tearDownWithError() throws {
        RunLog.end()
        RunLog.directoryOverride = nil
        try? FileManager.default.removeItem(at: scratch)
    }

    private func runNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: scratch.path)
            .filter { $0.hasPrefix(RunLog.filePrefix) }.sorted()
    }

    func testLogAndTraceLinesReachTheFileUntilItCloses() throws {
        XCTAssertNil(RunLog.currentPath)
        XCTAssertNotNil(RunLog.begin(at: Date(timeIntervalSince1970: 1_800_000_000)))
        let path = try XCTUnwrap(RunLog.currentPath)
        XCTAssertTrue(path.hasPrefix(scratch.path))
        XCTAssertTrue(path.hasSuffix(".log"))
        XCTAssertFalse(URL(fileURLWithPath: path).lastPathComponent.contains(":"),
                       "the timestamp in the name should not carry colons")

        log("ChatGPT: sent via send button")
        trace("paste watch +120ms, poll 2: value 40 chars")
        RunLog.end()
        XCTAssertNil(RunLog.currentPath)
        XCTAssertEqual(RunLog.lastPath, path, "the last path survives the close, for the menu")
        log("after the close")
        trace("after the close, detail")

        let text = try String(contentsOfFile: path, encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3, "header, one log line, one trace line: \(lines)")
        XCTAssertTrue(lines[1].hasSuffix("  ChatGPT: sent via send button"), lines[1])
        XCTAssertTrue(lines[2].contains("    · paste watch +120ms, poll 2: value 40 chars"), lines[2])
        XCTAssertFalse(text.contains("after the close"))
        // Millisecond timestamps, unlike the panel's second-precision ones.
        XCTAssertNotNil(lines[1].range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z  "#,
                                       options: .regularExpression), lines[1])
    }

    func testSidecarsShareTheRunPrefixAndAreNumbered() throws {
        XCTAssertNil(RunLog.sidecar("paste-miss-1-chatgpt-container", extension: "json"),
                     "no sidecar without an open log")
        RunLog.begin()
        let path = try XCTUnwrap(RunLog.currentPath)
        let first = try XCTUnwrap(RunLog.sidecar("paste-miss-1-chatgpt-container", extension: "json"))
        let second = try XCTUnwrap(RunLog.sidecar("paste-miss-1-chatgpt-container", extension: "json"))
        let logBase = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        XCTAssertEqual(first.lastPathComponent, "\(logBase).01-paste-miss-1-chatgpt-container.json")
        XCTAssertEqual(second.lastPathComponent, "\(logBase).02-paste-miss-1-chatgpt-container.json",
                       "the same failure at a later turn must not overwrite the earlier capture")
        XCTAssertEqual(first.deletingLastPathComponent().path, URL(fileURLWithPath: path).deletingLastPathComponent().path)
        // The number sits after the run prefix, so pruning still groups the
        // sidecar with its run.
        XCTAssertEqual(first.lastPathComponent.split(separator: ".", maxSplits: 1).first.map(String.init), logBase)
    }

    func testPruneKeepsTheNewestRunsWithTheirSidecars() throws {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        // Thirty older runs, each with a sidecar, plus an unrelated file.
        for index in 0..<30 {
            let stamp = String(format: "2026-08-%02dT10-00-00Z", index + 1)
            for name in ["\(RunLog.filePrefix)\(stamp).log", "\(RunLog.filePrefix)\(stamp).paste-miss-1-claude-container.json"] {
                FileManager.default.createFile(atPath: scratch.appendingPathComponent(name).path, contents: Data())
            }
        }
        FileManager.default.createFile(atPath: scratch.appendingPathComponent("notes.txt").path, contents: Data())

        RunLog.begin(at: Date(timeIntervalSince1970: 1_800_000_000))
        RunLog.end()

        let names = try runNames()
        let runs = Set(names.map { String($0.split(separator: ".", maxSplits: 1).first ?? "") })
        XCTAssertEqual(runs.count, RunLog.keep, "the new run plus the newest \(RunLog.keep - 1) old ones")
        XCTAssertFalse(names.contains { $0.contains("2026-08-01T") }, "the oldest run went")
        XCTAssertTrue(names.contains { $0.contains("2026-08-30T") && $0.hasSuffix(".log") })
        XCTAssertTrue(names.contains { $0.contains("2026-08-30T") && $0.hasSuffix(".json") },
                      "a kept run keeps its sidecar")
        XCTAssertFalse(names.contains { $0.contains("2026-08-11T") }, "run 11 is the 20th newest old run and goes")
        XCTAssertTrue(names.contains { $0.contains("2026-08-12T") }, "run 12 is the 19th newest old run and stays")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("notes.txt").path),
                      "pruning touches only the run prefix")
    }
}
