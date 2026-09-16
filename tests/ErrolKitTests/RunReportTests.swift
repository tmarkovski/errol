// The summary the panel renders from a run's report: the outcome is what
// the run recorded, the count is of replies actually relayed, and a hold
// or a sign-off the run ended on is context rather than a second cause.

import XCTest
@testable import ErrolKit

final class RunReportTests: XCTestCase {
    private let names = (chatgpt: "ChatGPT", claude: "Claude")

    private func detail(_ report: RunReport, duration: TimeInterval? = 272) -> String {
        report.detail(names: names, duration: duration, timeout: 300)
    }

    func testATimeoutOnTheLastPermittedTurnIsATimeout() {
        // The case the proposal singled out: the turn counter stands at the
        // cap when the wait fails, and the old summary read the cap.
        let report = RunReport(outcome: .timedOut(side: .claude), repliesCaptured: 5)
        XCTAssertEqual(report.headline(names: names), "Claude stopped responding")
        XCTAssertEqual(detail(report), "5 replies relayed \u{00B7} ran 4:32 \u{00B7} no reply activity for 300s")
    }

    func testCompletionCountsRepliesAndSaysBothSignedOff() {
        let report = RunReport(outcome: .completed, repliesCaptured: 6)
        XCTAssertEqual(report.headline(names: names), "Run complete")
        XCTAssertEqual(detail(report), "6 replies relayed \u{00B7} ran 4:32 \u{00B7} both signed off")
        XCTAssertEqual(detail(RunReport(outcome: .completed, repliesCaptured: 1), duration: nil),
                       "1 reply relayed \u{00B7} both signed off")
    }

    func testAStopDuringAHoldKeepsTheHoldAsContext() {
        let block = RunBlock.windowHidden(side: .claude, seen: "minimized")
        let report = RunReport(outcome: .stopped, repliesCaptured: 3, block: block)
        XCTAssertEqual(report.headline(names: names), "Run stopped")
        XCTAssertEqual(detail(report), "3 replies relayed \u{00B7} ran 4:32 \u{00B7} while paused: Claude's window was hidden")
    }

    func testAOneSidedSignOffIsContextNotACause() {
        let report = RunReport(outcome: .turnLimitReached, repliesCaptured: 4, signedOffBy: .chatgpt)
        XCTAssertEqual(report.headline(names: names), "Turn limit reached")
        XCTAssertEqual(detail(report), "4 replies relayed \u{00B7} ran 4:32 \u{00B7} after ChatGPT signed off")
        let empty = RunReport(outcome: .emptyReply(side: .chatgpt), repliesCaptured: 4, signedOffBy: .chatgpt)
        XCTAssertEqual(empty.headline(names: names), "ChatGPT ended the conversation")
        XCTAssertEqual(detail(empty), "4 replies relayed \u{00B7} ran 4:32 \u{00B7} empty reply",
                       "the empty reply is the sign-off; it is not said twice")
    }

    func testAFailedStartIsItsReasonAndNotAFinishedRun() {
        let report = RunReport(outcome: .failedStart(reason: "Claude has an unsent draft (12 characters). Finish or clear it, then Run again."))
        XCTAssertEqual(report.headline(names: names), "Couldn't start")
        XCTAssertEqual(detail(report), "Claude has an unsent draft (12 characters). Finish or clear it, then Run again.")
        XCTAssertTrue(report.outcome.isFailedStart)
        XCTAssertFalse(RunOutcome.stopped.isFailedStart)
    }

    func testTheOtherEndingsNameTheSide() {
        XCTAssertEqual(RunReport(outcome: .copyFailed(side: .claude)).headline(names: names),
                       "Couldn't copy Claude's reply")
        XCTAssertEqual(RunReport(outcome: .sendRefused(side: .chatgpt)).headline(names: names),
                       "Couldn't type into ChatGPT")
        XCTAssertEqual(RunReport(outcome: .sendAbandoned(side: .chatgpt)).headline(names: names),
                       "Delivery to ChatGPT interrupted")
        let lost = RunReport(outcome: .destinationLost(side: .claude, detail: "Claude quit"), repliesCaptured: 2)
        XCTAssertEqual(lost.headline(names: names), "Lost Claude's conversation")
        XCTAssertEqual(detail(lost, duration: nil), "2 replies relayed \u{00B7} Claude quit")
    }

    func testTheClockReadsMinutesAndHours() {
        XCTAssertEqual(runClock(59.4), "0:59")
        XCTAssertEqual(runClock(272), "4:32")
        XCTAssertEqual(runClock(3661), "1:01:01")
    }
}
