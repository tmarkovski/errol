// Claude Desktop fixture scenarios for the claude.ai surfaces: Chat and
// Cowork (home and open conversation), a project chat, and a sidebar title
// that mentions stopping. Trees are synthesized from the live-verified
// shapes in the field notes of docs/how-it-works.md (Aug 2026); recapture with
// `tools/ax-dump.swift claude --capture` when an update moves them. The
// Claude Code surface has its own scenario file.

import XCTest
@testable import ErrolKit

final class ClaudeScenarioTests: XCTestCase {
    let selectors = config.claudeSelectors

    func detectClaude(_ fixture: String, file: StaticString = #filePath,
                      line: UInt = #line) -> Detection {
        detect(fixture: fixture, selectors: selectors, appName: "Claude",
               file: file, line: line)
    }

    // MARK: New chats (home screens)

    func testChatHomeIsReadyWithZeroAffordances() {
        // Real capture (Aug 27 2026), sidebar titles anonymized: the one
        // fixture in this file recorded from a live tree rather than
        // synthesized. It also proves two facts the synthesized tree had
        // wrong or untested: the chat surface mounts NO send button over an
        // empty composer (only Claude Code's persists disabled), and the
        // window's outer file:// web area is correctly ignored by the
        // claude.ai host filter.
        let d = detectClaude("claude-chat-home")
        XCTAssertEqual(d.status.state, .ready)
        // The composer-level Chat/Cowork radio pair is the only direct signal
        // (the two views share the window and the claude.ai/new URL); the
        // active tab must outrank the URL's "New chat" mapping.
        XCTAssertEqual(d.status.surface, "Chat")
        XCTAssertEqual(d.status.model, "Opus 5 \u{00B7} High")
        XCTAssertEqual(d.excluded, [false])
        XCTAssertTrue(d.affordanceLabels.isEmpty)
        XCTAssertNil(d.sendLabel, "empty composer mounts no send control on the chat surface")
        XCTAssertEqual(d.composerLabel, "Write your prompt to Claude")
        XCTAssertFalse(d.streaming)
    }

    func testCoworkHomeNamesSurfaceAndModel() {
        let d = detectClaude("claude-cowork-home")
        XCTAssertEqual(d.status.state, .ready)
        XCTAssertEqual(d.status.surface, "Cowork")
        XCTAssertEqual(d.status.model, "Opus 5 \u{00B7} Extra")
        // "Clear active" (the Cowork-only marker) must not trip any selector.
        XCTAssertTrue(d.affordanceLabels.isEmpty)
        XCTAssertFalse(d.streaming)
    }

    // MARK: Existing conversations (plugging into an open chat)

    func testChatConversationCountsEchoesAndResponses() {
        let d = detectClaude("claude-chat-conversation")
        XCTAssertEqual(d.status.state, .ready)
        // No tab pair in this tree: the surface falls through to the window's
        // claude.ai URL path ("chat", capitalized by the fallback).
        XCTAssertEqual(d.status.surface, "Chat")
        XCTAssertEqual(d.status.model, "Fable 5 \u{00B7} Extra")
        XCTAssertEqual(d.status.detail, "\u{201C}Errol brand naming\u{201D}")
        // Claude gives user messages counted copy buttons too — two exchanges
        // register four affordances (echo absorption depends on this), while
        // "Copy code" stays excluded.
        XCTAssertEqual(d.affordanceLabels, ["Copy message", "Copy", "Copy message", "Copy newest"])
        // Depth-first order: the last copy button belongs to the newest
        // message — after a response completes, that is the response.
        XCTAssertTrue(d.copyLabels.last?.contains("newest") == true)
        XCTAssertEqual(d.sendLabel, "Send")
        XCTAssertFalse(d.streaming)
    }

    func testCoworkConversationKeepsTabSurface() {
        let d = detectClaude("claude-cowork-conversation")
        XCTAssertEqual(d.status.surface, "Cowork")
        XCTAssertEqual(d.status.model, "Opus 5 \u{00B7} Extra")
        XCTAssertEqual(d.affordanceLabels, ["Copy message", "Copy newest"])
    }

    func testProjectChatNamesSurfaceFromURLPath() {
        let d = detectClaude("claude-project-chat")
        XCTAssertEqual(d.status.state, .ready)
        // "project" is in surfacePathNames; an unmapped path would show up
        // capitalized raw — the cue to extend the map in Core/Settings/Config.swift.
        XCTAssertEqual(d.status.surface, "Project chat")
        XCTAssertEqual(d.affordanceLabels, ["Copy newest"])
    }

    // MARK: Sidebar titles

    func testSidebarTitleContainingStopIsNotAReply() throws {
        // A conversation titled "Stop ..." meets the stop rule by its label,
        // and it once made an idle chat read as replying: the console said
        // so, the start was refused, and the response wait would have sat at
        // "streaming" until the timeout (live Oct 15 2026). Its row sits in
        // the sidebar, a complementary landmark far from the composer's area,
        // where the real Stop sits (StopEvidence).
        let d = detectClaude("claude-sidebar-stop-trap")
        XCTAssertFalse(d.streaming)
        let chosen = try XCTUnwrap(d.chosenIndex)
        XCTAssertFalse(d.scans[chosen].isReplying)
        XCTAssertEqual(d.status.state, .ready)
        XCTAssertEqual(d.affordanceLabels, ["Copy newest"])
        let row = try XCTUnwrap(firstMatch(in: d.windows[chosen]) {
            $0.role == kAXButtonRole as String && $0.title == "Stop procrastinating plan"
        })
        XCTAssertTrue(isStopButtonLabel(row.label, selectors: selectors),
                      "the label alone still meets the rule; where the row sits is what rules it out")
    }
}
