// verify: a guided harness that checks Errol's detection contract against
// the live apps on this machine. It links ErrolKit — the SwiftPM library
// built from the app's own Core sources (see Package.swift) — so every
// check runs the production selectors and finders; there is no copy of the
// detection logic to drift out of sync.
//
//   tools/verify                     # static tier: read-only tree checks
//   tools/verify --nudge             # + reversible UI nudges (paste & revert,
//                                    #   expand one Claude Code action bar)
//   tools/verify --live claude       # + send ONE probe message through the
//   tools/verify --live all          #   full relay path in the DISPLAYED
//                                    #   conversation and copy the reply
//   tools/verify --app chatgpt       # restrict any tier to one app
//
// Guided use: open both apps with a throwaway conversation displayed (the
// live tier types into whatever conversation is visible — it announces the
// window title and waits 3 seconds before sending). Static and nudge tiers
// report SKIP with instructions when a check's precondition isn't met, so
// the loop is: run, follow the SKIP guidance, run again.
//
// Permission: like ax-dump, the invoking process needs the Accessibility
// grant (and the nudge/live tiers post keystrokes). Exit code is nonzero
// when any check FAILs.

import AppKit
import ApplicationServices
// Debug builds enable testability, which lets the harness reach ErrolKit's
// internal API without the library growing a public surface it doesn't
// otherwise need. The `tools/verify` wrapper always builds debug.
@testable import ErrolKit
@testable import ErrolVerification

@main
struct Verify {
    static var failures = 0
    static var incomplete = 0

    static func report(_ status: String, _ name: String, _ detail: String) {
        print("\(status.padding(toLength: 5, withPad: " ", startingAt: 0)) \(name) — \(detail)")
        if status == "FAIL" { failures += 1 }
        if status == "SKIP" { incomplete += 1 }
    }

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") || arguments.contains("-h") {
            print(GuidedVerification.help)
            print("Legacy probes: tools/verify [--nudge] [--live chatgpt|claude|all] [--app chatgpt|claude]")
            exit(0)
        }
        if arguments.contains(where: { ["--guided", "--suite", "--list", "--dry-run", "--filter", "--output"].contains($0) }) {
            exit(GuidedVerification.run(arguments: arguments))
        }
        var tiers: Set<String> = ["static"]
        var apps: Set<String> = ["chatgpt", "claude"]
        var args = Array(CommandLine.arguments.dropFirst())
        while !args.isEmpty {
            switch args.removeFirst() {
            case "--nudge": tiers.insert("nudge")
            case "--live":
                tiers.insert("nudge")
                tiers.insert("live")
                if let pick = args.first, !pick.hasPrefix("-") {
                    args.removeFirst()
                    if pick != "all" { apps = [pick] }
                }
            case "--app":
                guard let pick = args.first else { usageAndExit() }
                args.removeFirst()
                apps = [pick]
            case "--help", "-h": usageAndExit()
            default: usageAndExit()
            }
        }
        guard !apps.isEmpty, apps.isSubset(of: ["chatgpt", "claude"]) else { usageAndExit() }

        guard AXIsProcessTrusted() else {
            print("FAIL: this process is not trusted for Accessibility (see tools/ax-dump.swift header for the grant recipe).")
            exit(1)
        }

        let targets: [(String, TargetApp?)] = [
            ("chatgpt", findApp(bundleID: config.chatgptBundleID, name: "Codex",
                                selectors: config.chatgptSelectors)),
            ("claude", findApp(bundleID: config.claudeBundleID, name: "Claude",
                               selectors: config.claudeSelectors)),
        ].filter { apps.contains($0.0) }

        for (key, target) in targets {
            print("== \(key) ==")
            guard let target else {
                report("FAIL", "running", "app is not running — launch it and rerun")
                continue
            }
            enableElectronAccessibility(target)
            usleep(700_000)
            let failuresBefore = failures
            runStatic(target, key: key)
            guard failures == failuresBefore else { continue }
            if tiers.contains("nudge") { runNudge(target, key: key) }
            guard failures == failuresBefore else { continue }
            if tiers.contains("live") { runLive(target) }
        }
        exit(failures > 0 ? 1 : incomplete > 0 ? 2 : 0)
    }

    static func usageAndExit() -> Never {
        print("usage: tools/verify [--nudge] [--live chatgpt|claude|all] [--app chatgpt|claude]")
        exit(2)
    }

    // MARK: static tier — read-only

    static func runStatic(_ target: TargetApp, key: String) {
        report("PASS", "running", "pid \(target.app.processIdentifier)")

        let windows = axWindows(target)
        guard !windows.isEmpty else {
            report("FAIL", "window", "no AX windows — is the app showing a window?")
            return
        }
        guard let window = chatWindow(in: target) else {
            report("FAIL", "chat-window", "no targetable window (every window excluded, no composer fallback)")
            return
        }
        let title = (axAttribute(window, kAXTitleAttribute) as? String) ?? "untitled"
        let excluded = isExcludedWindow(window, selectors: target.selectors)
        report("PASS", "chat-window", "\"\(title)\"\(excluded ? " [excluded-surface fallback]" : "")")

        if inputArea(in: target) != nil {
            let value = composerValue(in: target) ?? "<unreadable>"
            report("PASS", "composer", "value \"\(value.prefix(40))\"")
        } else {
            report("FAIL", "composer", "no text area found — send would refuse")
        }

        if let button = sendButton(in: target) {
            let enabled = (axAttribute(button, kAXEnabledAttribute) as? Bool) ?? false
            report("PASS", "send-control", "present, enabled=\(enabled)")
        } else {
            // Neither chat surface mounts a send control over an empty
            // composer (captured Aug 27 2026); only Claude Code keeps a
            // persistent disabled one. The nudge tier proves it mounts and
            // enables once text lands.
            report("INFO", "send-control", "absent — normal with an empty composer on the chat surfaces")
        }

        let affordances = messageAffordances(in: target).count
        if affordances > 0 {
            report("PASS", "affordances", "\(affordances) message affordance(s) counted")
        } else {
            report("SKIP", "affordances", "0 counted — display a conversation with at least one exchange to verify counting")
        }

        if hasStopButton(in: target) {
            report("FAIL", "idle-stop", "a stop button is visible — the displayed conversation is mid-run; completion detection would wait it out")
        } else {
            report("PASS", "idle-stop", "no stop button while idle")
        }

        let side = scanSide(bundleID: target.app.bundleIdentifier ?? "", name: target.name,
                            selectors: target.selectors)
        report(side.state == .ready ? "PASS" : "FAIL", "readiness",
               "\(side.headline)\(side.surface.map { " — \($0)" } ?? "")\(side.model.map { " · \($0)" } ?? "")")

        if key == "claude" {
            var toggles: [AXUIElement] = []
            findAll(in: window, where: { isMessageActionsToggle($0, selectors: target.selectors) },
                    into: &toggles)
            report("INFO", "action-toggles", "\(toggles.count) collapsed \"Show message actions\" toggle(s)")

            var states: [AXUIElement] = []
            findAll(in: window, where: { el in
                guard axAttribute(el, kAXRoleAttribute) as? String == kAXButtonRole as String,
                      let t = axAttribute(el, kAXTitleAttribute) as? String else { return false }
                return t.hasPrefix("Running ") || t.hasPrefix("Idle ") || t.hasPrefix("Awaiting ")
            }, into: &states)
            if states.isEmpty {
                report("INFO", "sidebar-state", "no session-state buttons — sidebar collapsed? (signal unavailable until opened)")
            } else {
                report("PASS", "sidebar-state", "\(states.count) session-state button(s) (Running/Idle prefixes)")
            }
        }
    }

    // The draft guard (composerDraft / composerPlaceholders) lives in
    // ErrolKit now, shared with the live test category.

    // MARK: nudge tier — reversible UI touches

    static func runNudge(_ target: TargetApp, key: String) {
        let desktopLease: DesktopLease
        do { desktopLease = try DesktopLease() }
        catch { report("SKIP", "desktop-ownership", String(describing: error)); return }
        defer { desktopLease.release() }
        let pasteboard = NSPasteboard.general
        let clipboard = ClipboardLease()
        defer {
            if !clipboard.restore() { report("FAIL", "clipboard", "could not restore clipboard") }
        }
        // Never touch a composer that already holds the user's text: the
        // revert step clears the WHOLE composer, so running over a human
        // draft would destroy it (this happened once — hence the guard).
        guard let originalInput = inputArea(in: target) else {
            report("FAIL", "nudge-paste", "no composer")
            return
        }
        guard let binding = TargetBinding(target, context: .existing) else { report("FAIL", "nudge-window", "no stable window"); return }
        let safe = composerSafety(value: axAttribute(originalInput, kAXValueAttribute) as? String,
                                  attachments: attachmentControls(originalInput, target: target).count,
                                  busy: hasStopButton(in: target))
        guard safe.status == .passed else { report("SKIP", "nudge-paste", safe.detail); return }
        // A conversation mid-run morphs the composer controls (Send becomes
        // Stop/Queue), so the checks below would report app breakage that is
        // really just a busy conversation.
        guard !hasStopButton(in: target) else {
            report("SKIP", "nudge-paste", "displayed conversation is mid-run — rerun when it is idle")
            return
        }
        let needle = "errol-verify probe text"
        pasteboard.clearContents()
        pasteboard.setString(needle, forType: .string)

        guard makeFrontmost(target) else {
            report("FAIL", "nudge-activate", "could not bring the app frontmost")
            return
        }
        guard let input = inputArea(in: target), CFEqual(input, originalInput), binding.valid() else {
            report("FAIL", "nudge-paste", "no composer to paste into")
            return
        }
        AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        usleep(200_000)
        // Keystrokes follow focus; on a machine the user is actively using,
        // focus can move between any two of our steps. Re-verify frontmost
        // immediately before every synthesized keystroke and bail rather
        // than type into someone else's window (send() applies the same
        // rule to its escalation keystrokes).
        guard isFrontmost(target) else {
            report("SKIP", "nudge-paste", "lost frontmost before pasting — machine in use; rerun when idle")
            return
        }
        keystroke(keyV, flags: .maskCommand)
        usleep(500_000)
        let landed = composerValue(in: target) == needle
        report(landed ? "PASS" : "FAIL", "nudge-paste",
               landed ? "probe text visible in composer" : "paste did not land (key-window routing?)")

        if landed {
            if let button = sendButton(in: target) {
                let enabled = (axAttribute(button, kAXEnabledAttribute) as? Bool) ?? false
                report(enabled ? "PASS" : "FAIL", "nudge-send-enables",
                       "send control enabled with text = \(enabled)")
            } else {
                report("FAIL", "nudge-send-enables", "no send control mounted despite composer text")
            }
        }

        // Revert with a focus-independent AXValue write (verified to work on
        // both apps' composers) — never destructive keystrokes first: a
        // select-all + delete that chases moved focus can destroy content in
        // whatever window the user switched to (nearly happened once).
        guard binding.valid(), axAttribute(input, kAXValueAttribute) as? String == needle else {
            report("FAIL", "nudge-revert", "composer changed; retaining content for inspection")
            return
        }
        AXUIElementSetAttributeValue(input, kAXValueAttribute as CFString, "" as CFString)
        usleep(400_000)
        let reverted = composerValue(in: target).map { composerPlaceholders.contains($0) } == true
        report(reverted ? "PASS" : "FAIL", "nudge-revert",
               reverted ? "composer cleared" : "probe text still in composer — clear it by hand")

        if key == "claude" {
            let before = copyButtons(in: target).count
            guard let last = messageAffordances(in: target).last,
                  isMessageActionsToggle(last, selectors: target.selectors) else {
                report("INFO", "nudge-expand", "newest affordance is not a collapsed toggle (already expanded, or no messages)")
                return
            }
            expandLastMessageActions(in: target)
            let after = copyButtons(in: target).count
            report(after > before ? "PASS" : "FAIL", "nudge-expand",
                   "copy buttons \(before) -> \(after) after pressing \"Show message actions\" (bar stays expanded until a conversation switch)")
        }
    }

    // MARK: live tier — one probe message through the production relay path

    static func runLive(_ target: TargetApp) {
        let side = scanSide(bundleID: target.app.bundleIdentifier ?? "", name: target.name, selectors: target.selectors)
        let app: DesktopApp = target.app.bundleIdentifier == config.chatgptBundleID ? .chatgpt : .claude
        guard let endpoint = Endpoint.all.first(where: { $0.app == app && $0.surface == side.surface }) else {
            report("FAIL", "live-surface", "unrecognized surface; use the guided suite to inspect it")
            return
        }
        var options = VerificationOptions()
        options.timeout = 180
        let scenario = DesktopScenario(endpoint: endpoint, conversation: messageAffordances(in: target).isEmpty ? .new : .existing)
        let runID = UUID().uuidString
        let directory = URL(fileURLWithPath: ".artifacts/verify/" + runID)
        do {
            var result = VerificationReport(runID: runID, suite: "legacy-live", totalSuiteCases: 1,
                maxCharacters: options.cap, caseTimeout: options.timeout,
                environment: GuidedVerification.environment(), results: [CaseResult(scenario: scenario)])
            try result.write(to: directory)
            let evidence = try CaseEvidence(scenario: scenario, directory: directory.appendingPathComponent(scenario.id))
            print("Sending one real test prompt to the displayed conversation in 3 seconds. Ctrl+C aborts.")
            sleep(3)
            result.results[0] = LiveScenarioRunner(options: options, evidence: evidence, nonce: runID).run()
            try result.write(to: directory)
            if result.exitCode == 1 { failures += 1 }
            else if result.exitCode != 0 { incomplete += 1 }
            print("Live report: \(directory.appendingPathComponent("report.md").path)")
        } catch { report("FAIL", "live-report", String(describing: error)) }
    }
}
