import XCTest
@testable import ErrolKit

final class ResponseWaitTests: XCTestCase {
    private let baseline = ResponseBaseline(affordances: 1, lastOrdinal: nil)
    private let working = ResponseSighting(affordances: 1, lastOrdinal: 1, streaming: true)
    private let idle = ResponseSighting(affordances: 1, lastOrdinal: nil, streaming: false)

    func testLongClaudeThinkingDoesNotHitTheOldFiveMinuteDeadline() {
        var wait = ResponseWaitState(timeout: 300, startedAt: 0)
        // The reported failure: no new copy affordance while Claude Code
        // gathers context, but its Stop control says it is still working.
        for time in stride(from: 0.0, through: 900.0, by: 1.2) {
            XCTAssertEqual(wait.observe(working, since: baseline,
                                        selectors: config.claudeSelectors, at: time), .waiting)
        }
        XCTAssertTrue(wait.sawStreaming)
        let reply = ResponseSighting(affordances: 2, lastOrdinal: 2, streaming: false)
        XCTAssertEqual(wait.observe(reply, since: baseline,
                                    selectors: config.claudeSelectors, at: 901.2), .waiting)
        XCTAssertEqual(wait.observe(reply, since: baseline,
                                    selectors: config.claudeSelectors, at: 902.4), .complete)
    }

    func testAHoldStartsTheConfirmingPairOver() {
        // Sep 24 2026, from the run log: Claude streaming, then one poll
        // taken as the image viewer opened over the conversation — nothing
        // mounted, Stop gone — which reads as the streaming transition. The
        // next poll finds the dialog and holds the wait; that dark poll must
        // not stand as half of the pair that completes it afterwards.
        let baseline = ResponseBaseline(affordances: 2, lastOrdinal: nil)
        let streaming = ResponseSighting(affordances: 2, lastOrdinal: 5, streaming: true)
        let covered = ResponseSighting(affordances: 0, lastOrdinal: nil, streaming: false)
        let finished = ResponseSighting(affordances: 3, lastOrdinal: 6, streaming: false)
        var wait = ResponseWaitState(timeout: 300, startedAt: 0)
        XCTAssertEqual(wait.observe(streaming, since: baseline,
                                    selectors: config.claudeSelectors, at: 0), .waiting)
        XCTAssertEqual(wait.observe(covered, since: baseline,
                                    selectors: config.claudeSelectors, at: 1.2), .waiting)
        wait.suspend(at: 2.4)
        wait.resume(at: 30)
        XCTAssertEqual(wait.observe(finished, since: baseline,
                                    selectors: config.claudeSelectors, at: 31.2), .waiting,
                       "one poll after the hold is not yet a finished reply")
        XCTAssertEqual(wait.observe(finished, since: baseline,
                                    selectors: config.claudeSelectors, at: 32.4), .complete)
    }

    // MARK: The capture gate

    func testAnOrdinalSurfacingAfterTheWaitIsNotAMessageSince() {
        // Sep 22 2026, from the run log: Claude read no "Message N" during
        // the wait, 12 affordances at completion against a baseline of 15;
        // held at the capture gate through a pause, the list read 2
        // affordances and "Message 16" — the same reply, rendered anew.
        let baseline = ResponseBaseline(affordances: 15, lastOrdinal: nil)
        let completed = ResponseSighting(affordances: 12, lastOrdinal: nil, streaming: false)
        let paused = ResponseSighting(affordances: 2, lastOrdinal: 16, streaming: false)
        XCTAssertFalse(conversationMovedOn(paused, since: completed, baseline: baseline))
        // The list mounting its older messages again is not new messages.
        let remounted = ResponseSighting(affordances: 15, lastOrdinal: nil, streaming: false)
        XCTAssertFalse(conversationMovedOn(remounted, since: completed, baseline: baseline))
        // A count past everything the wait knew is.
        let grown = ResponseSighting(affordances: 17, lastOrdinal: nil, streaming: false)
        XCTAssertTrue(conversationMovedOn(grown, since: completed, baseline: baseline))
    }

    func testAnOrdinalPastTheCompletedReplyIsAMessageSince() {
        let baseline = ResponseBaseline(affordances: 15, lastOrdinal: 14)
        let completed = ResponseSighting(affordances: 12, lastOrdinal: 16, streaming: false)
        let since = ResponseSighting(affordances: 2, lastOrdinal: 18, streaming: false)
        XCTAssertTrue(conversationMovedOn(since, since: completed, baseline: baseline))
        // The same newest message, however many older ones are mounted.
        let same = ResponseSighting(affordances: 15, lastOrdinal: 16, streaming: false)
        XCTAssertFalse(conversationMovedOn(same, since: completed, baseline: baseline))
    }

    func testNoActivityStillTimesOut() {
        var wait = ResponseWaitState(timeout: 300, startedAt: 100)
        XCTAssertEqual(wait.observe(idle, since: baseline,
                                    selectors: config.claudeSelectors, at: 399.9), .waiting)
        XCTAssertEqual(wait.observe(idle, since: baseline,
                                    selectors: config.claudeSelectors, at: 400), .timedOut)
    }

    func testBusySightingAtTheDeadlineKeepsWaiting() {
        var wait = ResponseWaitState(timeout: 300, startedAt: 0)
        XCTAssertEqual(wait.observe(working, since: baseline,
                                    selectors: config.claudeSelectors, at: 300), .waiting)
        XCTAssertEqual(wait.observe(working, since: baseline,
                                    selectors: config.claudeSelectors, at: 600), .waiting)
    }

    func testReplyAtTheDeadlineGetsItsConfirmationPoll() {
        var wait = ResponseWaitState(timeout: 300, startedAt: 0)
        let reply = ResponseSighting(affordances: 2, lastOrdinal: nil, streaming: false)
        XCTAssertEqual(wait.observe(reply, since: baseline,
                                    selectors: config.chatgptSelectors, at: 300), .waiting)
        XCTAssertEqual(wait.observe(reply, since: baseline,
                                    selectors: config.chatgptSelectors, at: 301.2), .complete)
    }

    func testTimeOutOfViewDoesNotCountAgainstTheReply() {
        // The window showed another conversation from 100s to 500s: nothing
        // seen there is about this reply, and the inactivity allowance
        // resumes where it stood, so the timeout lands at 700s, not 300s.
        var wait = ResponseWaitState(timeout: 300, startedAt: 0)
        XCTAssertEqual(wait.observe(idle, since: baseline,
                                    selectors: config.claudeSelectors, at: 99), .waiting)
        wait.suspend(at: 100)
        wait.suspend(at: 250)
        XCTAssertTrue(wait.isSuspended, "a second suspend keeps the first moment")
        wait.resume(at: 500)
        wait.resume(at: 900)
        XCTAssertFalse(wait.isSuspended, "a second resume adds nothing")
        XCTAssertEqual(wait.observe(idle, since: baseline,
                                    selectors: config.claudeSelectors, at: 699.9), .waiting)
        XCTAssertEqual(wait.observe(idle, since: baseline,
                                    selectors: config.claudeSelectors, at: 700), .timedOut)
    }

    func testAReplyThatCompletedOutOfViewIsSeenOnReturn() {
        // The baseline is kept through the suspension, so the reply that
        // landed while the window showed something else counts on return.
        var wait = ResponseWaitState(timeout: 300, startedAt: 0)
        wait.suspend(at: 10)
        wait.resume(at: 400)
        let reply = ResponseSighting(affordances: 2, lastOrdinal: nil, streaming: false)
        XCTAssertEqual(wait.observe(reply, since: baseline,
                                    selectors: config.chatgptSelectors, at: 400), .waiting)
        XCTAssertEqual(wait.observe(reply, since: baseline,
                                    selectors: config.chatgptSelectors, at: 401.2), .complete)
    }

    func testBriefIdlePollBetweenWorkDoesNotCompleteTheResponse() {
        var wait = ResponseWaitState(timeout: 300, startedAt: 0)
        for (time, sighting) in [(0.0, working), (299.0, idle), (300.2, working), (601.0, idle)] {
            XCTAssertEqual(wait.observe(sighting, since: baseline,
                                        selectors: config.claudeSelectors, at: time), .waiting)
        }
        XCTAssertEqual(wait.observe(idle, since: baseline,
                                    selectors: config.claudeSelectors, at: 602.2), .complete)
    }
}
