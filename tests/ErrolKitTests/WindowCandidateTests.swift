// What each app's windows are offered as in the picker, read from the
// recorded fixtures through the same scan the readiness sweep makes: which
// are eligible, how they are named, what their composers hold, and the
// order a run would prefer them in.

import XCTest
@testable import ErrolKit

final class WindowCandidateTests: XCTestCase {
    private let chatgpt = config.chatgptSelectors
    private let claude = config.claudeSelectors

    private func candidates(_ fixture: String, selectors: AppSelectors) -> [WindowCandidate] {
        let windows = loadFixture(fixture)
        let ids = windows.indices.map { WindowID(raw: UInt($0 + 1)) }
        return windowCandidates(windows, ids: ids, selectors: selectors)
    }

    func testAChatWindowOutranksACodeSessionAndBothAreOffered() throws {
        let found = candidates("claude-multiwindow", selectors: claude)
        XCTAssertEqual(found.map(\.id.raw), [1, 2])
        let chat = found[0], code = found[1]
        XCTAssertTrue(chat.isEligible)
        XCTAssertEqual(chat.name, "\u{201C}Errol brand naming\u{201D}")
        XCTAssertEqual(chat.stateLine, "Ready")
        XCTAssertTrue(code.isEligible, "the selectors allow a Code session as a deliberate choice")
        XCTAssertTrue(code.identity.excluded)
    }

    func testACodeSessionRanksBehindAChatWhateverTheWindowOrder() throws {
        // The same two windows, Code first: the chat still leads.
        let windows = loadFixture("claude-multiwindow").reversed().map { $0 }
        let found = windowCandidates(windows, ids: [WindowID(raw: 9), WindowID(raw: 8)], selectors: claude)
        XCTAssertEqual(found.map(\.id.raw), [8, 9])
    }

    func testAWindowWhoseTitleNamesNothingIsNotGuessedAt() throws {
        // Whether its chat is new can't be told reliably, empty or not.
        let fresh = try XCTUnwrap(candidates("claude-chat-home", selectors: claude).first)
        XCTAssertNil(fresh.name)
        XCTAssertFalse(fresh.identity.isDistinct)
        var scan = WindowScan()
        scan.title = "ChatGPT"
        scan.hasComposer = true
        let unnamed = WindowCandidate(id: WindowID(raw: 1), scan: scan, selectors: chatgpt)
        XCTAssertNil(unnamed.name)
    }

    func testTheComposerIsJudgedFromTheScan() throws {
        let drafted = try XCTUnwrap(candidates("chatgpt-chat-conversation", selectors: chatgpt).first)
        XCTAssertEqual(drafted.composer, .draft(characters: 16))
        XCTAssertEqual(drafted.stateLine, "Unsent draft (16 characters)")
        XCTAssertEqual(drafted.name, "\u{201C}Logo brainstorm\u{201D}")
        let streaming = try XCTUnwrap(candidates("chatgpt-chat-streaming", selectors: chatgpt).first)
        XCTAssertEqual(streaming.composer, .replying)
        XCTAssertEqual(streaming.stateLine, "Replying")
        let idle = try XCTUnwrap(candidates("chatgpt-chat-home", selectors: chatgpt).first)
        XCTAssertEqual(idle.composer, .empty, "the placeholder is not a draft")
    }

    func testTheScanSeesReplyingTheWayTheFindersDo() throws {
        for (fixture, selectors, name) in [("claude-multiwindow", claude, "Claude"),
                                           ("chatgpt-chat-conversation", chatgpt, "ChatGPT"),
                                           ("claude-code-collapsed", claude, "Claude"),
                                           ("chatgpt-chat-streaming", chatgpt, "ChatGPT"),
                                           ("claude-code-streaming", claude, "Claude")] {
            let detection = detect(fixture: fixture, selectors: selectors, appName: name)
            let chosen = try XCTUnwrap(detection.chosenIndex)
            XCTAssertEqual(detection.scans[chosen].isReplying, detection.streaming, fixture)
            // Both verdicts false would agree too, so the finder must also
            // see what the fixture was captured showing.
            XCTAssertEqual(detection.streaming, fixture.hasSuffix("-streaming"), fixture)
        }
    }

    func testAWindowWithoutAComposerIsListedButNotEligible() {
        var scan = WindowScan()
        scan.title = "Settings"
        let candidate = WindowCandidate(id: WindowID(raw: 1), scan: scan, selectors: chatgpt)
        XCTAssertFalse(candidate.isEligible)
        XCTAssertEqual(candidate.stateLine, "No message field")
        var minimized = WindowCandidate(id: WindowID(raw: 2), scan: scan, selectors: chatgpt, isMinimized: true)
        minimized.hasComposer = true
        XCTAssertEqual(minimized.stateLine, "Minimized")
    }

    func testModelAndEffortComposeAsTheStripShowsThem() {
        var scan = WindowScan()
        scan.hasComposer = true
        scan.model = "Fable 5"
        scan.effort = "Extra"
        let candidate = WindowCandidate(id: WindowID(raw: 1), scan: scan, selectors: claude)
        XCTAssertEqual(candidate.model, "Fable 5 \u{00B7} Extra")
    }
}
