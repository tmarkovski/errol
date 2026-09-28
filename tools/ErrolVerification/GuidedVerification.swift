import AppKit
import ApplicationServices
@testable import ErrolKit

enum GuidedVerification {
    static let help = """
    Guided desktop compatibility suites (real prompts in disposable conversations):
      tools/verify --guided --suite desktop-smoke
      tools/verify --guided --suite desktop-full
      tools/verify --guided --suite relay-full
      tools/verify --guided --suite app-controls

    Selection and evidence:
      --list                       List cases; no Accessibility grant or app interaction
      --dry-run                    Write a NOT RUN coverage report without touching apps
      --filter TEXT                Select matching case IDs (report retains selection scope)
      --app chatgpt|claude          Restrict endpoints; relay pairs include both apps
      --output DIRECTORY           Unique output directory (must not already contain a report)
      --screenshots                Save target-window screenshots if already permitted
      --timeout SECONDS             Overall per-case deadline, 15–1800 (default 180)
      --countdown SECONDS           Time to focus the prepared app, 3–30 (default 5)
      --max-chars COUNT             Test relay cap, 1024–100000 (default 12000)

    Exit 0: all selected cases passed automatically. Exit 1: a check failed.
    Exit 2: incomplete coverage, manual checks, invalid options, or missing setup.
    Exit 124: hard deadline (report stays incomplete; inspect leftover test content).
    """

    static func run(arguments: [String]) -> Int32 {
        do {
            let options = try VerificationOptions.parse(arguments)
            if options.list {
                for scenario in options.selected { print(scenario.id) }
                print("\(options.selected.count) selected / \(options.suite.scenarios.count) cases in \(options.suite.rawValue)")
                return 0
            }
            let id = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(8)
            let output = URL(fileURLWithPath: options.output ?? ".artifacts/verify/\(id)", isDirectory: true).standardizedFileURL
            guard !FileManager.default.fileExists(atPath: output.appendingPathComponent("report.json").path) else {
                throw VerificationError("Report already exists at \(output.path); choose a new output directory so evidence is not overwritten")
            }
            var report = VerificationReport(runID: id, suite: options.suite.rawValue, filter: options.filter,
                totalSuiteCases: options.suite.scenarios.count, maxCharacters: options.cap, caseTimeout: options.timeout,
                environment: environment(), results: options.selected.map { CaseResult(scenario: $0) })
            try report.write(to: output)
            print("Report: \(output.appendingPathComponent("report.md").path)")
            if options.dryRun {
                print("Dry run: \(report.results.count) cases planned; every case is NOT RUN. No app interaction.")
                return 2
            }
            guard AXIsProcessTrusted() else {
                for index in report.results.indices {
                    report.results[index].checks = [.init(name: "accessibility", status: .blocked,
                        detail: "Invoking process needs Accessibility permission. See docs/desktop-verification.md.")]
                    report.results[index].finishedAt = Date()
                }
                try report.write(to: output)
                print("Accessibility unavailable. All selected cases are BLOCKED; report saved.")
                return 2
            }
            print("""

            This suite sends real prompts using the shared clipboard and keyboard focus.
            Use disposable conversations. Coding/work modes must use a disposable empty project.
            Evidence contains displayed conversation text; keep reports local and anonymize fixtures before committing.
            At each setup: Enter = ready, s REASON = skip, q = stop. Focus the requested app during the countdown.
            Do not type during an active case. Ctrl+C stops an active case; q stops at a setup prompt.
            """)
            for index in report.results.indices {
                let scenario = report.results[index].scenario
                print("\n[\(index + 1)/\(report.results.count)] \(scenario.id)\n\(scenario.setup)")
                print("Ready / s REASON / q:", terminator: " ")
                fflush(stdout)
                guard let answer = readLine() else { break }
                if answer.lowercased() == "q" { break }
                if answer.lowercased().hasPrefix("s") {
                    report.results[index].checks = [.init(name: "operator-setup", status: .blocked, detail: String(answer.dropFirst()).trimmingCharacters(in: .whitespaces).isEmpty ? "Skipped by operator" : String(answer.dropFirst()))]
                    report.results[index].finishedAt = Date()
                    try report.write(to: output)
                    continue
                }
                guard answer.isEmpty else { throw VerificationError("Unrecognized setup response. Evidence saved; rerun selected remaining cases with --filter.") }
                let evidence = try CaseEvidence(scenario: scenario, directory: output.appendingPathComponent(scenario.id))
                // Checkpoint before any side effect, including countdown. A crash,
                // SIGKILL, or blocked AX call leaves an unfinished case, never PASS.
                report.results[index] = evidence.result
                try report.write(to: output)
                if scenario.behavior == .switchedConversation {
                    // A transition that was not observed ends only its own
                    // case; the next case has its own setup prompt. Only the
                    // operator's q (or end of input) stops the suite.
                    let setup = prepareTransition(evidence, screenshots: options.screenshots)
                    if setup != .passed {
                        report.results[index] = evidence.finish()
                        try report.write(to: output)
                        if setup == .stopped { break }
                        print("Case result: \(report.results[index].status.rawValue.uppercased())")
                        continue
                    }
                }
                if scenario.behavior == .appControls {
                    report.results[index] = runAppControls(evidence: evidence, screenshots: options.screenshots)
                } else {
                    let returnFocus = currentFrontmostApp()
                    print("Focus the prepared app now. Starting in \(options.countdown) seconds...")
                    for _ in 0..<options.countdown { Thread.sleep(forTimeInterval: 1) }
                    let runner = LiveScenarioRunner(options: options, evidence: evidence, nonce: makeNonce(), returnFocus: returnFocus)
                    report.results[index] = runner.run()
                    try report.write(to: output)
                    if runner.shouldStop { break }
                }
                try report.write(to: output)
                print("Case result: \(report.results[index].status.rawValue.uppercased())")
            }
            let current = environment()
            if current != report.environment {
                // Do not combine app versions or working-tree revisions silently.
                for index in report.results.indices where report.results[index].startedAt != nil {
                    report.results[index].checks.append(.init(name: "environment-stable", status: .inconclusive, detail: "Application versions, OS, or repository state changed during the suite; rerun under one environment"))
                }
            }
            try report.write(to: output)
            let passed = report.results.filter { $0.status == .passed }.count
            print("\n\(passed)/\(report.results.count) selected cases passed automatically. \(report.complete ? "PASS" : "Coverage incomplete or failed").")
            print("Report: \(output.appendingPathComponent("report.md").path)")
            return report.exitCode
        } catch {
            fputs("Verification error: \(error)\n", stderr)
            return 2
        }
    }

    /// The identifier a case's prompts carry and its replies must echo:
    /// 32 lowercase hex characters, the same from every entry point, since
    /// reply-contract compares the echoed text exactly.
    static func makeNonce() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// One case outside the guided loop, for `errol-verify --live` and the
    /// opt-in XCTest: no setup prompt, no transition setup, no stop between
    /// cases. The report is written before the case starts, so a crash leaves
    /// it unfinished rather than passed, and again when it ends; its run ID is
    /// the directory's name. `beforeRun` is the caller's last word to the
    /// operator (the CLI's countdown) before a real prompt is sent.
    static func runSingle(_ scenario: DesktopScenario, suite: String, filter: String?, totalSuiteCases: Int,
                          options: VerificationOptions, directory: URL,
                          beforeRun: () -> Void = {}) throws -> VerificationReport {
        var report = VerificationReport(runID: directory.lastPathComponent, suite: suite, filter: filter,
            totalSuiteCases: totalSuiteCases, maxCharacters: options.cap, caseTimeout: options.timeout,
            environment: environment(), results: [CaseResult(scenario: scenario)])
        try report.write(to: directory)
        let evidence = try CaseEvidence(scenario: scenario, directory: directory.appendingPathComponent(scenario.id))
        beforeRun()
        report.results[0] = LiveScenarioRunner(options: options, evidence: evidence, nonce: makeNonce()).run()
        try report.write(to: directory)
        return report
    }

    static func environment() -> RunEnvironment {
        var apps: [String: String] = [:]
        for (name, id) in [("chatgpt", config.chatgptBundleID), ("claude", config.claudeBundleID)] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id), let bundle = Bundle(url: url) {
                apps[name] = "\(id) \(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?") (\(bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?"))"
            } else { apps[name] = "\(id) unavailable" }
        }
        return .init(macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                     revision: shell("/usr/bin/git", ["rev-parse", "HEAD"]),
                     dirty: !shell("/usr/bin/git", ["status", "--porcelain"]).isEmpty, applications: apps,
                     sourceHash: sourceHash())
    }

    private static func sourceHash() -> String {
        let paths = shell("/usr/bin/git", ["ls-files", "--cached", "--others", "--exclude-standard"])
            .split(separator: "\n").map(String.init).filter {
                $0 == "Package.swift" || $0.hasPrefix("tools/") || $0.hasPrefix("app/") || $0.hasPrefix("tests/")
            }.sorted()
        return sha256(paths.map { path in
            let data = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
            return path + ":" + sha256(data)
        }.joined(separator: "\n"))
    }

    private static func shell(_ path: String, _ arguments: [String]) -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        } catch { return "unknown" }
    }

    private static func runAppControls(evidence: CaseEvidence, screenshots: Bool) -> CaseResult {
        let instructions: [(String, String)] = [
            ("start", "In Errol, start a short test relay between the prepared conversations. Check that the opening prompt reaches the correct app once."),
            ("pause", "Pause while a response is being generated. Let it finish. Verify the response is held before the next capture/delivery and that the apps receive no next message."),
            ("steering-editor", "Open the steering editor. Type, select, paste multiline text, and use IME composition if available. Verify focus stays in the editor for the entire editing session."),
            ("resume", "Send a clearly marked test steering note. Verify it arrives once with the next handoff and is echoed once to the other side."),
            ("stop", "Start another disposable run, request steering during a handoff, then Stop. Verify no delayed editor opens and no additional prompt is delivered."),
            ("reopen", "Close and reopen Errol. Verify a saved draft survives, the stopped run does not resume, and input focus works.")
        ]
        for (stage, instruction) in instructions {
            print("\nManual app check: \(instruction)\nEnter p + observation, f + failure, or s + reason; q stops:", terminator: " ")
            fflush(stdout)
            guard let answer = readLine(), answer != "q" else {
                evidence.check("app-\(stage)", .notRun, "Manual sequence ended before this check")
                break
            }
            let detail = String(answer.dropFirst()).trimmingCharacters(in: .whitespaces)
            let status: CheckStatus = answer.hasPrefix("f") ? .failed : answer.hasPrefix("p") && !detail.isEmpty ? .manual : .blocked
            evidence.check("app-\(stage)", status, detail.isEmpty ? "No operator evidence supplied" : detail)
            for endpoint in [evidence.result.scenario.endpoint, evidence.result.scenario.peer].compactMap({ $0 }) {
                if let target = resolve(endpoint) { evidence.capture(target, stage: "manual-\(stage)-\(endpoint.app.rawValue)", screenshots: screenshots) }
            }
        }
        evidence.check("native-control-automation", .inconclusive, "Operator observations are retained separately. This CLI does not instrument a running Errol UI process.", required: false)
        return evidence.finish()
    }

    /// How the conversation-switch setup ended: `failed` ends only this case
    /// (identity unavailable, or the switch was not observed), `stopped` is
    /// the operator's q or end of input and ends the suite.
    private enum TransitionSetup { case passed, failed, stopped }

    private static func prepareTransition(_ evidence: CaseEvidence, screenshots: Bool) -> TransitionSetup {
        guard let target = resolve(evidence.result.scenario.endpoint), let window = chatWindow(in: target),
              let original = TargetBinding.identity(window) else {
            evidence.check("conversation-transition", .inconclusive, "Cannot identify the original conversation independently")
            return .failed
        }
        // Enter continues; anything else, or end of input, stops the suite.
        func operatorContinued() -> Bool {
            fflush(stdout)
            guard readLine() == "" else {
                evidence.check("conversation-transition", .notRun, "Operator stopped at transition setup")
                return false
            }
            return true
        }
        evidence.capture(target, stage: "transition-original", screenshots: screenshots)
        print("Switch to a DIFFERENT disposable conversation in this app, then return here and press Enter. q stops:", terminator: " ")
        guard operatorContinued() else { return .stopped }
        guard let otherWindow = chatWindow(in: target), let other = TargetBinding.identity(otherWindow), other != original else {
            evidence.check("conversation-transition", .blocked, "Did not observe a different conversation")
            return .failed
        }
        evidence.capture(target, stage: "transition-away", screenshots: screenshots)
        print("Switch BACK to the original conversation, then return here and press Enter. q stops:", terminator: " ")
        guard operatorContinued() else { return .stopped }
        guard let restored = chatWindow(in: target), TargetBinding.identity(restored) == original else {
            evidence.check("conversation-transition", .blocked, "Original conversation was not restored")
            return .failed
        }
        evidence.capture(target, stage: "transition-restored", screenshots: screenshots)
        evidence.check("conversation-transition", .passed, "Observed original → different → original conversation identities")
        return .passed
    }
}
