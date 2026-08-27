// Claude Code fixture scenarios: the fallback surface with hover-gated
// action bars. Collapsed vs expanded matters twice over — the affordance
// count leans on the collapsed "Show message actions" toggles, and the
// window-exclusion marker ("Rewind to here") only exists while a bar is
// expanded, which is the classification flap recorded in the README. Both
// sides of that flap are pinned here; if either assertion moves, the flap
// changed shape.

import XCTest
@testable import ErrolKit

final class ClaudeCodeScenarioTests: XCTestCase {
    let selectors = config.claudeSelectors

    func detectClaude(_ fixture: String, file: StaticString = #filePath,
                      line: UInt = #line) -> Detection {
        detect(fixture: fixture, selectors: selectors, appName: "Claude",
               file: file, line: line)
    }

    func testCollapsedBarsCountTogglesAsAffordances() {
        let d = detectClaude("claude-code-collapsed")
        // Flap, benign side: with every action bar collapsed the exclusion
        // marker is unmounted, so the window classifies as a plain chat
        // window and is chosen directly (harmless on the single-window build).
        XCTAssertEqual(d.excluded, [false])
        XCTAssertEqual(d.chosenIndex, 0)
        XCTAssertEqual(d.status.state, .ready)
        XCTAssertEqual(d.status.surface, "Claude Code")
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
        // Flap, other side: the expanded bar mounts "Rewind to here", so the
        // same window now carries the exclusion marker...
        XCTAssertEqual(d.excluded, [true])
        // ...and is still targeted, through the excluded-surface fallback
        // (no chat window exists in this app).
        XCTAssertEqual(d.chosenIndex, 0)
        XCTAssertEqual(d.status.state, .ready)
        XCTAssertEqual(d.status.surface, "Claude Code")
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

    func testStreamingShowsStopWhileEchoToggleCounts() {
        let d = detectClaude("claude-code-streaming")
        XCTAssertTrue(d.streaming)
        // Mid-turn: two prior messages plus the just-sent echo's toggle
        // (Claude echoes count — absorbEchoIntoBaseline depends on it); the
        // in-flight response contributes nothing until the Stop button goes.
        XCTAssertEqual(d.affordanceLabels.count, 3)
        XCTAssertTrue(d.copyLabels.isEmpty)
        XCTAssertEqual(d.status.surface, "Claude Code")
    }
}
