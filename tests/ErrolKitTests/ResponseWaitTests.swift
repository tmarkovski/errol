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
