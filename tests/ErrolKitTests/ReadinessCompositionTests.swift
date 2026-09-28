// The readiness sweep's decision layer: window choice across multiple
// windows, and composeSideStatus edge states driven by hand-built scans
// (states with no tree shape worth recording — no windows, no composer,
// nothing but excluded surfaces).

import XCTest
@testable import ErrolKit

final class ReadinessCompositionTests: XCTestCase {
    let selectors = config.claudeSelectors

    func testChatWindowBeatsClaudeCodeWindow() {
        // The older multi-window build: a chat conversation alongside a
        // Claude Code session. The chat window must win, and the sweep must
        // name the other surface.
        let d = detect(fixture: "claude-multiwindow", selectors: selectors, appName: "Claude")
        XCTAssertEqual(d.excluded, [false, true])
        XCTAssertEqual(d.chosenIndex, 0)
        XCTAssertEqual(d.status.state, .ready)
        XCTAssertEqual(d.status.surface, "Chat")
        XCTAssertEqual(d.status.detail, "\u{201C}Errol brand naming\u{201D}; Code also open")
        // Counts come from the chosen window only — the code session's copy
        // button must not leak into the chat window's baseline.
        XCTAssertEqual(d.affordanceLabels, ["Copy message", "Copy newest"])
    }

    func testNoWindowsReadsNotReady() {
        let status = composeSideStatus(appName: "Claude", scans: [], selectors: selectors)
        XCTAssertEqual(status.state, .notReady)
        XCTAssertEqual(status.headline, "No window")
    }

    func testWindowWithoutComposerIsNotFound() {
        var scan = WindowScan()
        scan.title = "Claude"
        let status = composeSideStatus(appName: "Claude", scans: [scan], selectors: selectors)
        XCTAssertEqual(status.state, .notReady)
        XCTAssertEqual(status.headline, "Not found")
        XCTAssertEqual(status.detail, "no composer")
    }

    func testOnlyExcludedWindowsWithoutComposers() {
        // Claude Desktop hosting only a composerless Claude Code surface:
        // nothing is targetable, but the sweep still names what it saw.
        var scan = WindowScan()
        scan.isExcluded = true
        scan.surfacePath = "epitaxy"
        let status = composeSideStatus(appName: "Claude", scans: [scan], selectors: selectors)
        XCTAssertEqual(status.state, .notReady)
        XCTAssertEqual(status.headline, "Not found")
        XCTAssertEqual(status.surface, "Code")
        XCTAssertEqual(status.detail, "no chat window")
    }

    func testSplitModelAndEffortCompose() {
        // Claude Code announces model and effort separately; the sweep
        // renders them the way the chat surfaces embed them.
        var scan = WindowScan()
        scan.hasComposer = true
        scan.model = "Fable 5"
        scan.effort = "Extra"
        let status = composeSideStatus(appName: "Claude", scans: [scan], selectors: selectors)
        XCTAssertEqual(status.model, "Fable 5 \u{00B7} Extra")
    }

    func testEffortAloneStillShows() {
        var scan = WindowScan()
        scan.hasComposer = true
        scan.effort = "Extra"
        let status = composeSideStatus(appName: "Claude", scans: [scan], selectors: selectors)
        XCTAssertEqual(status.model, "Extra")
    }

    func testTheEffortSplitsFromTheModelLineTheWayEachAppWritesIt() {
        // Claude's announcement and the Code pair's join put a dot between
        // them; ChatGPT folds the effort into the title as its last word.
        let claude = splitEffort("Fable 5 \u{00B7} Extra", selectors: selectors)
        XCTAssertEqual(claude.model, "Fable 5")
        XCTAssertEqual(claude.effort, "Extra")
        let chatgpt = splitEffort("5.6 Sol High", selectors: config.chatgptSelectors)
        XCTAssertEqual(chatgpt.model, "5.6 Sol")
        XCTAssertEqual(chatgpt.effort, "High")

        // A bare model, ChatGPT's default, and an effort with nothing
        // before it stay whole.
        XCTAssertNil(splitEffort("Fable 5", selectors: selectors).effort)
        XCTAssertNil(splitEffort("Default", selectors: config.chatgptSelectors).effort)
        XCTAssertEqual(splitEffort("Extra", selectors: selectors).model, "Extra")
        XCTAssertNil(splitEffort("High", selectors: config.chatgptSelectors).effort)
        // Only ChatGPT's own effort words count as one on its titles.
        XCTAssertNil(splitEffort("5.6 Sol", selectors: config.chatgptSelectors).effort)
    }
}
