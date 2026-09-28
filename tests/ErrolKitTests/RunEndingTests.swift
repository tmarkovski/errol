// How a run ends on its own: the three endings, the cap each leaves in
// force, and the sign-off the agents are told about. These tests mutate the
// global config, so they restore it after each run.

import XCTest
@testable import ErrolKit

final class RunEndingTests: XCTestCase {
    var savedConfig: Config!

    override func setUp() {
        super.setUp()
        savedConfig = config
    }

    override func tearDown() {
        config = savedConfig
        super.tearDown()
    }

    func testOnlyTheTurnLimitCapsTheRun() {
        var settings = Config()
        settings.turns = 6
        XCTAssertNil(settings.turnCap, "the default ending is the mutual sign-off, with no cap")
        settings.ending = .turnLimit
        XCTAssertEqual(settings.turnCap, 6)
        settings.ending = .whenStopped
        XCTAssertNil(settings.turnCap, "a run that only Stop ends has no cap")
    }

    func testOnlyARunThatStopEndsIgnoresTheSignOff() {
        XCTAssertTrue(RunEnding.bothAgree.endsOnSignOff)
        XCTAssertTrue(RunEnding.turnLimit.endsOnSignOff,
                      "a turn limit is a maximum; the mutual sign-off can end the run sooner")
        XCTAssertFalse(RunEnding.whenStopped.endsOnSignOff)
    }

    func testTheDefaultEndingIsTheSignOffWithATenTurnCapReady() {
        // A fresh Config must leave the turn cap off: runs end on the
        // conversation's own close (mutual sign-off, empty reply, timeout,
        // or Stop), and the cap is the opt-in turn-limit ending.
        let defaults = Config()
        XCTAssertEqual(defaults.ending, .bothAgree)
        XCTAssertNil(defaults.turnCap)
        XCTAssertEqual(defaults.turns, 10, "the cap's value when enabled")
    }

    func testRulesForARunThatStopEndsLeaveOutTheSignOff() {
        config.ending = .whenStopped
        config.seed = "Plan a trip to Skye."
        for framing in [openingMessage(), introMessage(firstReply: "Start with the Quiraing.", from: "ChatGPT")] {
            XCTAssertFalse(framing.localizedCaseInsensitiveContains(config.stopSequence),
                           "a marker the loop ignores would only invite a loop of goodbyes")
            XCTAssertFalse(framing.contains(RelayRules.stopSequenceToken))
            XCTAssertFalse(framing.contains("empty message ends"),
                           "an empty reply still ends the run, but it is not offered as a way out")
            XCTAssertTrue(framing.contains("the human will end it"))
            XCTAssertTrue(framing.contains("not a one-shot answer"), "the framing is the same for every ending")
        }
    }

    func testRulesKeepTheSignOffForTheOtherEndings() {
        for ending in [RunEnding.bothAgree, .turnLimit] {
            config.ending = ending
            XCTAssertTrue(relayRules().contains(config.stopSequence), "\(ending)")
        }
    }
}
