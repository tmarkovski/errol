// Opt-in integration tests. No app is touched by ordinary `swift test`.
// Prefer `tools/verify --guided --suite desktop-smoke` for interactive setup.
// A preconfigured desktop runner can select one exact case using:
// ERROL_LIVE=1 ERROL_LIVE_CASE=chatgpt.chat.new.short.message swift test --filter LiveRelay
// Live cases use the DISPLAYED conversations; they do not create new chats.

import AppKit
import ApplicationServices
import XCTest
@testable import ErrolKit
@testable import ErrolVerification

private func requireLiveOptIn() throws {
    guard ProcessInfo.processInfo.environment["ERROL_LIVE"] == "1" else {
        throw XCTSkip("live tests are opt-in: ERROL_LIVE=1 swift test --filter Live")
    }
    guard AXIsProcessTrusted() else {
        throw XCTSkip("ERROL_LIVE=1 is set but this process lacks the Accessibility grant — see tools/ax-dump.swift's header for the recipe, then rerun")
    }
}

private func liveTarget(bundleID: String, name: String,
                        selectors: AppSelectors) throws -> TargetApp {
    guard let target = findApp(bundleID: bundleID, name: name, selectors: selectors) else {
        throw XCTSkip("\(name) (\(bundleID)) is not running — launch it with a chat surface displayed and rerun")
    }
    enableElectronAccessibility(target)
    return target
}

/// Read-only live smoke: the readiness sweep must find both apps ready, the
/// same verdict the panel's strip and the run preflight reach. Fails when an
/// app is running without a usable chat surface; skips when one isn't up.
final class LiveReadinessTests: XCTestCase {
    override func setUpWithError() throws { try requireLiveOptIn() }

    func testBothSidesScanReady() throws {
        _ = try liveTarget(bundleID: config.chatgptBundleID, name: "ChatGPT",
                           selectors: config.chatgptSelectors)
        _ = try liveTarget(bundleID: config.claudeBundleID, name: "Claude",
                           selectors: config.claudeSelectors)
        usleep(700_000) // first contact after the Electron nudge can race an empty tree
        let sweep = scanBothSides()
        for side in [sweep.chatgpt, sweep.claude] {
            XCTAssertEqual(side.state, .ready,
                           "\(side.appName): \(side.headline)\(side.detail.map { " — \($0)" } ?? "") — display a chat surface and rerun")
            XCTAssertNotNil(side.surface, "\(side.appName): ready but no surface detected")
            print("live-readiness: \(side.appName): \(side.headline) — \(side.surface ?? "?") \u{00B7} \(side.model ?? "no model announced")")
        }
    }
}

/// The same strict runner and evidence format as the guided CLI. An explicit
/// case ID declares the expected surface before any real prompt is sent.
final class LiveRelayTests: XCTestCase {
    override func setUpWithError() throws { try requireLiveOptIn() }

    func testSelectedScenario() throws {
        guard let id = ProcessInfo.processInfo.environment["ERROL_LIVE_CASE"] else {
            throw XCTSkip("Set ERROL_LIVE_CASE to an exact ID from tools/verify --suite desktop-full --list, or use --guided")
        }
        guard let scenario = DesktopSuite.full.scenarios.first(where: { $0.id == id }), scenario.behavior != .appControls else {
            XCTFail("Unknown or manual-only live case: \(id)")
            return
        }
        let options = VerificationOptions()
        let runID = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("errol-live-" + runID)
        var report = VerificationReport(runID: runID, suite: "xctest-selected", filter: id, totalSuiteCases: DesktopSuite.full.scenarios.count,
            maxCharacters: options.cap, caseTimeout: options.timeout, environment: GuidedVerification.environment(),
            results: [CaseResult(scenario: scenario)])
        try report.write(to: directory)
        let evidence = try CaseEvidence(scenario: scenario, directory: directory.appendingPathComponent(scenario.id))
        report.results[0] = LiveScenarioRunner(options: options, evidence: evidence, nonce: runID).run()
        try report.write(to: directory)
        XCTAssertEqual(report.results[0].status, .passed, "Compatibility failed or incomplete. Report: \(directory.appendingPathComponent("report.md").path)")
    }
}
