// Claude Code fixture scenarios: the fallback surface with hover-gated
// action bars. Collapsed vs expanded still matters for the affordance count,
// which leans on the collapsed "Show message actions" toggles — but it no
// longer moves the window's classification. It used to: the exclusion rested
// on "Rewind to here", which lives inside an expanded action bar, so the same
// Code session read as a chat window whenever no bar happened to be open.
// Reading the world switcher instead settles it the same way in both states,
// and these tests pin that agreement.

import XCTest
@testable import ErrolKit

final class ClaudeCodeScenarioTests: XCTestCase {
    let selectors = config.claudeSelectors

    func detectClaude(_ fixture: String, file: StaticString = #filePath,
                      line: UInt = #line) -> Detection {
        detect(fixture: fixture, selectors: selectors, appName: "Claude",
               file: file, line: line)
    }

    func testStepRowsAndSessionTitlesAreNotCopyButtons() throws {
        // A Claude Code transcript lists each tool step as a button labelled
        // with the step's summary, and the sidebar lists sessions by title;
        // either can mention copying. Live Sep 28 2026, a step row ("Applied
        // the rule to the readiness scan and the copy press") was the last
        // copy match in the window, so replyCopyButton picked it over every
        // message's Copy, and a session title ("Idle Claude copy message
        // overlay issue") counted as a message. Both are rows named by the
        // text they show (AXTitle); the messages' Copy buttons are icons in a
        // "Message actions" toolbar, named "Copy" by the app (AXDescription).
        let d = detectClaude("claude-code-step-rows")
        XCTAssertEqual(d.excluded, [true])
        XCTAssertEqual(d.chosenIndex, 0)
        // The user message's Copy and the reply's: the echo counts on Claude.
        XCTAssertEqual(d.copyLabels, ["Copy", "Copy newest"])
        XCTAssertEqual(d.affordanceLabels, ["Copy", "Copy newest"])
        let window = try XCTUnwrap(d.windows.first)
        XCTAssertEqual(replyCopyButton(under: window, selectors: selectors)?.label, "Copy newest")
        for title in ["Idle Copy edits for the landing page", "Checked the copy on the release page",
                      "Fixed two typos in the copy"] {
            let row = try XCTUnwrap(firstMatch(in: window) { $0.title == title }, title)
            XCTAssertTrue(isCopyButtonLabel(row.label, selectors: selectors), title)
            XCTAssertFalse(isCopyButton(row, selectors: selectors), title)
        }
    }

    func testCollapsedBarsCountTogglesAsAffordances() {
        let d = detectClaude("claude-code-collapsed")
        // Every action bar is collapsed, so no "Rewind to here" is mounted
        // anywhere in this tree; the world switcher ("Code, idle", selected)
        // is the only thing saying what this window is, and it is enough.
        XCTAssertEqual(d.excluded, [true])
        // Still targeted, through the excluded-surface fallback.
        XCTAssertEqual(d.chosenIndex, 0)
        XCTAssertEqual(d.status.state, .ready)
        XCTAssertEqual(d.status.surface, "Code")
        // The composer announces the model as a bare-titled popup followed by
        // the "Effort:" popup; the pair composes like the chat surfaces.
        XCTAssertEqual(d.status.model, "Fable 5 \u{00B7} Extra")
        // Three messages, all bars collapsed: three toggles, zero copy
        // buttons. Counting copy buttons alone would sit at 0 forever here.
        XCTAssertEqual(d.affordanceLabels.count, 3)
        XCTAssertTrue(d.copyLabels.isEmpty)
        // The newest message's affordance is the collapsed toggle — exactly
        // the state expandLastMessageActions presses through before copying.
        XCTAssertTrue(d.lastAffordanceIsToggle)
        // "Send feedback" matches the bare send keyword and must lose to the
        // real send control.
        XCTAssertEqual(d.sendLabel, "Send")
        XCTAssertEqual(d.composerLabel, "Prompt")
        XCTAssertFalse(d.streaming)
    }

    func testExpandedBarMountsCopyAndTheExclusionMarker() {
        let d = detectClaude("claude-code-expanded")
        // The expanded bar mounts "Rewind to here" on top of the switcher's
        // "Code, awaiting your input" — two independent markers now, and the
        // verdict matches the collapsed tree's above, which is the point.
        XCTAssertEqual(d.excluded, [true])
        // Still targeted, through the excluded-surface fallback (no chat
        // window exists in this app).
        XCTAssertEqual(d.chosenIndex, 0)
        XCTAssertEqual(d.status.state, .ready)
        XCTAssertEqual(d.status.surface, "Code")
        // Two collapsed toggles plus the expanded bar's copy button: still
        // one affordance per message.
        XCTAssertEqual(d.affordanceLabels.count, 3)
        XCTAssertEqual(d.copyLabels, ["Copy newest"])
        // Bar already expanded: the nudge-expand step has nothing to press.
        XCTAssertFalse(d.lastAffordanceIsToggle)
        // The expanded sidebar's session buttons ("Running ...", "Idle ...",
        // "Awaiting input ...") must not read as stop, copy, or send.
        XCTAssertFalse(d.streaming)
        XCTAssertEqual(d.sendLabel, "Send")
    }

    func testClassificationSurvivesTheHoverState() {
        // The regression this guards: whether a message's action bar happens
        // to be expanded is a hover artifact, and it used to decide whether
        // Errol saw a Claude Code session at all. On the older multi-window
        // build that meant a collapsed Code window could be picked as the
        // chat window and relayed into. All three trees are the same world.
        for fixture in ["claude-code-collapsed", "claude-code-expanded",
                        "claude-code-streaming"] {
            XCTAssertEqual(detectClaude(fixture).excluded, [true], fixture)
        }
    }

    func testStreamingShowsStopWhileEchoToggleCounts() {
        let d = detectClaude("claude-code-streaming")
        XCTAssertTrue(d.streaming)
        // Mid-turn: two prior messages plus the just-sent echo's toggle
        // (Claude echoes count — absorbEchoIntoBaseline depends on it); the
        // in-flight response contributes nothing until the Stop button goes.
        XCTAssertEqual(d.affordanceLabels.count, 3)
        XCTAssertTrue(d.copyLabels.isEmpty)
        XCTAssertEqual(d.status.surface, "Code")
    }
}
