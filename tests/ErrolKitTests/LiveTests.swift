// The "live" test category: integration tests that require both chat apps
// running on this machine, opted into by environment so a plain `swift test`
// stays side-effect-free (they report as skipped):
//
//   ERROL_LIVE=1 swift test --filter Live        # the whole live category
//   ERROL_LIVE=1 swift test --filter LiveRelay   # just the actual-chat test
//
// The invoking process needs the Accessibility grant, like ax-dump (see its
// header for the recipe; from a Claude Code shell, run with the Bash sandbox
// disabled). LiveReadinessTests is read-only. LiveRelayTests is the real
// thing: it seizes focus and the clipboard and runs a genuine short relay
// conversation between ChatGPT and Claude in fresh chats (Cmd+N in both) —
// the machine is unusable while it runs, typically one to three minutes, and
// it costs a handful of real messages on both accounts. Run it deliberately,
// hands off the keyboard; every guard that protects a human draft or a busy
// conversation reports as a skip with instructions.

import AppKit
import ApplicationServices
import XCTest
@testable import ErrolKit

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

/// The actual-chat test: a real relay conversation through the production
/// runRelay — seeding, framing, echo absorption, completion detection, copy,
/// turn alternation, and (models willing) the mutual sign-off — in fresh
/// chats on both apps. Everything the fixture suite proves about detection,
/// this proves against the living apps.
final class LiveRelayTests: XCTestCase {
    override func setUpWithError() throws { try requireLiveOptIn() }

    func testRelayConversation() throws {
        let chatgpt = try liveTarget(bundleID: config.chatgptBundleID, name: "ChatGPT",
                                     selectors: config.chatgptSelectors)
        let claude = try liveTarget(bundleID: config.claudeBundleID, name: "Claude",
                                    selectors: config.claudeSelectors)
        usleep(700_000)

        for target in [chatgpt, claude] {
            if let draft = composerDraft(in: target) {
                throw XCTSkip("\(target.name): composer holds text (\"\(draft.prefix(30))\") — refusing to touch a possible draft; clear it and rerun")
            }
            guard let window = chatWindow(in: target) else {
                throw XCTSkip("\(target.name): no targetable window — open a chat conversation and rerun")
            }
            if isExcludedWindow(window, selectors: target.selectors) {
                throw XCTSkip("\(target.name): only an excluded surface (a Claude Code session) is targetable — the test must not land in a working session; open a chat conversation and rerun")
            }
            if hasStopButton(in: target) {
                throw XCTSkip("\(target.name): displayed conversation is mid-run — rerun when it is idle")
            }
        }

        let savedConfig = config
        let pasteboard = NSPasteboard.general
        let savedClipboard = pasteboard.string(forType: .string)
        defer {
            config = savedConfig
            if let savedClipboard {
                pasteboard.clearContents()
                pasteboard.setString(savedClipboard, forType: .string)
            }
        }
        // The seed asks for a few exchanges before the sign-off so the run
        // exercises the steady-state relay branch (turn 3 and later relay
        // the reply verbatim, without the intro framing) — the first live
        // run ended after two turns because both models signed off
        // immediately when merely told to be brief.
        config.seed = """
            You are taking part in a brief automated integration test of this \
            relay. Greet the other assistant and keep a light small-talk \
            exchange going: each of you should send at least three replies \
            before anyone ends the conversation, so do not include the end \
            marker before your third reply. Then end politely following the \
            rules above. Keep every reply to one or two sentences.
            """
        // The default end condition is the mutual sign-off with no cap; the
        // test opts into the cap as its guard against a runaway conversation.
        config.limitTurns = true
        config.turns = 8
        config.timeout = 120
        config.first = .chatgpt
        config.transcriptPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("errol-live-relay-transcript.md").path
        try? FileManager.default.removeItem(atPath: config.transcriptPath)
        relayControl.reset()

        // The relay no longer opens chats of its own, so this runs in whatever
        // conversations happen to be open. Open a fresh one on each side first,
        // or the test seeds its small talk into the middle of real work.
        print("live-relay: running a real \(config.turns)-turn relay in the open chats — hands off until it finishes")
        XCTAssertTrue(runRelay(chatgpt: chatgpt, claude: claude),
                      "runRelay preflight or seeding failed — see the log above")

        let transcript = (try? String(contentsOfFile: config.transcriptPath,
                                      encoding: .utf8)) ?? ""
        let turns = transcript.components(separatedBy: "## Turn ").count - 1
        // Four turns guarantees each side took a steady-state turn beyond
        // the framed opening exchange. Reaching it depends on the models
        // honoring the seed's three-replies-first instruction; a failure
        // here with 2-3 clean turns means the models cut the chat short,
        // not that the relay broke — the transcript tells them apart.
        XCTAssertGreaterThanOrEqual(turns, 4,
            "need two replies from each side; transcript: \(config.transcriptPath)")
        XCTAssertTrue(transcript.contains("## Turn 1: ChatGPT"),
                      "the first captured turn should be ChatGPT's reply to the seed")
        XCTAssertTrue(transcript.contains("## Turn 2: Claude"),
                      "the second captured turn should be Claude's reply")
        // The mutual sign-off depends on the models following the rules, so
        // it is reported rather than asserted; the turn cap ending the run is
        // not a harness failure.
        let signoffs = transcript.components(separatedBy: "ended the conversation").count - 1
        print("live-relay: \(turns) turn(s), \(signoffs) sign-off note(s); transcript kept at \(config.transcriptPath)")
    }
}
