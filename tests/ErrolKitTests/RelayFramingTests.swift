// The relay's pure message plumbing: the framing each side receives, the
// per-message length cap, and the stop-sequence contract. These tests mutate
// the global config, so they restore it after each run.

import XCTest
@testable import ErrolKit

final class RelayFramingTests: XCTestCase {
    var savedConfig: Config!

    override func setUp() {
        super.setUp()
        savedConfig = config
    }

    override func tearDown() {
        config = savedConfig
        super.tearDown()
    }

    func testOpeningMessageCarriesRulesAndSeed() {
        config.seed = "Plan a trip to Skye."
        let opener = openingMessage()
        XCTAssertTrue(opener.contains(config.stopSequence),
                      "the rules must tell the agent how to end the conversation")
        XCTAssertTrue(opener.hasSuffix(config.seed),
                      "the seed passes through verbatim, after the framing")
    }

    func testIntroMessageCarriesSeedReplyAndPeerName() {
        config.seed = "Plan a trip to Skye."
        let intro = introMessage(firstReply: "Start with the Quiraing.", from: "ChatGPT")
        XCTAssertTrue(intro.contains(config.stopSequence))
        XCTAssertTrue(intro.contains(config.seed))
        XCTAssertTrue(intro.contains("Start with the Quiraing."))
        XCTAssertTrue(intro.contains("replying to ChatGPT"))
    }

    func testLengthCapTruncatesAndMarks() {
        config.maxChars = 100
        let long = String(repeating: "x", count: 500)
        let capped = truncatedForRelay(long)
        XCTAssertTrue(capped.hasPrefix(String(repeating: "x", count: 100)))
        XCTAssertTrue(capped.hasSuffix("[truncated by relay]"),
                      "the peer must see that the message was cut, not a silent ellipsis")
        XCTAssertEqual(capped.count, 100 + "\n\n[truncated by relay]".count)
        XCTAssertEqual(truncatedForRelay("short"), "short",
                       "messages under the cap pass through untouched")
    }

    func testDefaultEndConditionIsTheSignoff() {
        // A fresh Config must leave the turn cap off: runs end on the
        // conversation's own close (mutual sign-off, empty reply, timeout,
        // or Stop), and the cap is the opt-in "Limit turns" checkbox.
        let defaults = Config()
        XCTAssertFalse(defaults.limitTurns)
        XCTAssertEqual(defaults.turns, 10, "the cap's value when enabled")
    }

    func testStopSequenceDetectionIsCaseInsensitive() {
        // The run loop checks replies with localizedCaseInsensitiveContains;
        // a model lowercasing the marker must still end the conversation.
        let reply = "It was a pleasure. [[end-conversation]]"
        XCTAssertTrue(reply.localizedCaseInsensitiveContains(config.stopSequence))
        XCTAssertFalse("no marker here".localizedCaseInsensitiveContains(config.stopSequence))
    }
}
