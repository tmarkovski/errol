// The stuck-relay bug of Aug 28 2026, pinned. Claude Desktop virtualizes the
// message list: in a long conversation only the last few messages stay
// mounted, so the affordance count — the original completion signal — can
// plateau or FALL as responses land. The relay hung waiting for the count to
// exceed a baseline of 7 while the window, response and sign-off on screen,
// held 3. The fixture is the real capture of that exact stuck state
// (sanitized); the tests here pin the tree's shape, the "Message N" ordinal
// signal that survives virtualization, and the responseArrived verdicts that
// end the hang.

import XCTest
@testable import ErrolKit

final class VirtualizedConversationScenarioTests: XCTestCase {
    func testStuckStateDetection() {
        let detection = detect(fixture: "claude-virtualized-conversation",
                               selectors: config.claudeSelectors, appName: "Claude")
        XCTAssertEqual(detection.windows.count, 1)
        // A Claude Code session window ("Rewind to here" in a message action
        // bar) with no chat window open: excluded, but targeted as the
        // fallback — the surface the relay was deliberately run on.
        XCTAssertEqual(detection.excluded, [true])
        XCTAssertEqual(detection.chosenIndex, 0)
        XCTAssertEqual(detection.status.surface, "Code")

        // The virtualization trap itself: 8 messages exchanged, affordances
        // for only the last 3 mounted. The run's baseline was 7 — recorded
        // while more messages were mounted — so "count > baseline" was
        // unreachable and the old detector hung here forever.
        XCTAssertEqual(detection.affordanceLabels.count, 3)
        XCTAssertEqual(detection.lastOrdinal, 8,
                       "the newest message's ordinal is mounted even though five older messages are not")
        XCTAssertFalse(detection.streaming, "the response had completed; nothing was streaming")

        // What the affordances are: the assistant messages' bare "Copy" and
        // the user message's "Copy message" (not excluded on Claude, unlike
        // ChatGPT, where "message" marks the echo).
        XCTAssertTrue(detection.affordanceLabels[0].contains("Copy"))
        XCTAssertTrue(detection.affordanceLabels[1].contains("Copy message"))
        XCTAssertTrue(detection.affordanceLabels[2].contains("Copy"))
    }

    func testOrdinalUnlocksTheStuckWait() {
        // The regression test for the hang, end to end through the pure
        // verdict: the run's real numbers. Baseline before the final send:
        // 7 affordances, newest message 6. The stuck state: 3 affordances
        // (count fell — virtualization), newest message 8 (echo 7 +
        // response 8), not streaming. The old count-only detector said no
        // forever; the ordinal says done.
        let baseline = ResponseBaseline(affordances: 7, lastOrdinal: 6)
        let stuck = ResponseSighting(affordances: 3, lastOrdinal: 8, streaming: false)
        XCTAssertTrue(responseArrived(stuck, since: baseline, sawStreaming: false,
                                      selectors: config.claudeSelectors))
        XCTAssertFalse(stuck.affordances > baseline.affordances,
                       "proof the count signal alone still fails on this shape")
    }
}

final class MessageOrdinalTests: XCTestCase {
    private func group(_ title: String) -> FixtureElement {
        FixtureElement(role: "AXGroup", title: title)
    }

    func testParsesNumberedMessageGroups() {
        XCTAssertEqual(messageOrdinal(group("Message 8")), 8)
        XCTAssertEqual(messageOrdinal(group("Message 124")), 124)
        // The live shape: Chromium delivers the name in AXDescription (read
        // via the joined label), with AXTitle present but EMPTY — the label
        // join must drop it, or the label is "Message 6 " and the parse
        // fails live while capture-based fixtures (which omit empty strings)
        // pass. Both ElementNode faces share the filtered join for this.
        XCTAssertEqual(messageOrdinal(FixtureElement(
            role: "AXGroup", subrole: "AXDocumentArticle",
            axDescription: "Message 6", title: "")), 6)
    }

    func testRejectsNearMisses() {
        XCTAssertNil(messageOrdinal(group("Message actions")),
                     "the per-message toolbar is also titled with the Message prefix")
        XCTAssertNil(messageOrdinal(group("Message 8 draft")))
        XCTAssertNil(messageOrdinal(group("Messages")))
        XCTAssertNil(messageOrdinal(FixtureElement(role: "AXButton", title: "Message 8")),
                     "only group articles are messages — a button with the title is something else")
        XCTAssertNil(messageOrdinal(FixtureElement(
            role: "AXButton", title: "Idle Message actions button streaming response test")),
            "a sidebar session row whose name starts with 'Message' must not read as a message")
    }

    func testLastOrdinalIsTheMaxAcrossMountedMessages() {
        let window = FixtureElement(role: "AXWindow", children: [
            group("Message 6"), group("Message 7"), group("Message 8"),
        ])
        XCTAssertEqual(lastMessageOrdinal(under: window), 8)
        XCTAssertNil(lastMessageOrdinal(under: group("Message actions")),
                     "no numbered messages, no ordinal — ChatGPT's normal state")
    }
}

final class ResponseArrivedTests: XCTestCase {
    func testStreamingBlocksEverySignal() {
        let baseline = ResponseBaseline(affordances: 2, lastOrdinal: 3)
        let mid = ResponseSighting(affordances: 9, lastOrdinal: 9, streaming: true)
        XCTAssertFalse(responseArrived(mid, since: baseline, sawStreaming: true,
                                       selectors: config.claudeSelectors))
    }

    func testCountRiseIsTheFastPath() {
        let baseline = ResponseBaseline(affordances: 2, lastOrdinal: nil)
        let after = ResponseSighting(affordances: 3, lastOrdinal: nil, streaming: false)
        XCTAssertTrue(responseArrived(after, since: baseline, sawStreaming: false,
                                      selectors: config.chatgptSelectors))
    }

    func testEchoAloneDoesNotComplete() {
        // On Claude the sent message mounts as its own numbered message; the
        // ordinal must advance past it (baseline + 2) before the movement can
        // be the response.
        let baseline = ResponseBaseline(affordances: 7, lastOrdinal: 6)
        let echoOnly = ResponseSighting(affordances: 7, lastOrdinal: 7, streaming: false)
        XCTAssertFalse(responseArrived(echoOnly, since: baseline, sawStreaming: false,
                                       selectors: config.claudeSelectors))
    }

    func testOrdinalDeltaIsOneWhereEchoCannotRegister() {
        // ChatGPT exposes no ordinals today, but the contract follows the
        // echo flag, not the app: no echo in the count, no echo message.
        let baseline = ResponseBaseline(affordances: 0, lastOrdinal: 5)
        let after = ResponseSighting(affordances: 0, lastOrdinal: 6, streaming: false)
        XCTAssertTrue(responseArrived(after, since: baseline, sawStreaming: false,
                                      selectors: config.chatgptSelectors))
        XCTAssertFalse(responseArrived(after, since: baseline, sawStreaming: false,
                                       selectors: config.claudeSelectors))
    }

    func testNilBaselineOrdinalDisablesTheOrdinalSignal() {
        // A baseline read that raced an unpopulated tree must not turn a
        // later ordinal into instant completion — the echo would read as the
        // response. No baseline ordinal, no ordinal verdict.
        let baseline = ResponseBaseline(affordances: 7, lastOrdinal: nil)
        let after = ResponseSighting(affordances: 3, lastOrdinal: 8, streaming: false)
        XCTAssertFalse(responseArrived(after, since: baseline, sawStreaming: false,
                                       selectors: config.claudeSelectors))
    }

    func testStreamingTransitionCompletesWhenCountersFail(){
        // The app-agnostic backstop: streaming was observed and has ended,
        // so the response the stop button belonged to is complete even if
        // virtualization ate every counter movement.
        let baseline = ResponseBaseline(affordances: 7, lastOrdinal: nil)
        let after = ResponseSighting(affordances: 3, lastOrdinal: nil, streaming: false)
        XCTAssertTrue(responseArrived(after, since: baseline, sawStreaming: true,
                                      selectors: config.claudeSelectors))
        XCTAssertFalse(responseArrived(after, since: baseline, sawStreaming: false,
                                       selectors: config.claudeSelectors),
                       "with no signal at all, keep waiting")
    }
}
