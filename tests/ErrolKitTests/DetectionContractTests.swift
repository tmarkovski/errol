// Contract tests for the pure detection logic — the parts of ErrolKit that
// don't need a live app. Each test pins an invariant that was established
// against real trees (dates in the README's field notes); if a selector or
// parsing change breaks one, the harness tiers (tools/verify) are the next
// stop to find the new live shape.

import XCTest
@testable import ErrolKit

final class CopySelectorTests: XCTestCase {
    let chatgpt = config.chatgptSelectors
    let claude = config.claudeSelectors

    func testChatGPTResponseCopyIsBare() {
        XCTAssertTrue(isCopyButtonLabel("Copy", selectors: chatgpt))
    }

    func testChatGPTUserEchoAndQualifiedCopiesExcluded() {
        // "Copy message" belongs to user messages; counting it once cost a
        // debugging round (the relay copied its own message back), and its
        // exclusion is why echoCountsAsAffordance must be false below.
        XCTAssertFalse(isCopyButtonLabel("Copy message", selectors: chatgpt))
        XCTAssertFalse(isCopyButtonLabel("Copy table", selectors: chatgpt))
        XCTAssertFalse(isCopyButtonLabel("Copy code", selectors: chatgpt))
        XCTAssertFalse(isCopyButtonLabel("Copy link", selectors: chatgpt))
    }

    func testClaudeCopyLabels() {
        XCTAssertTrue(isCopyButtonLabel("Copy", selectors: claude))
        // Claude user messages carry "Copy message" and DO count (the echo
        // absorption on the Claude side depends on it).
        XCTAssertTrue(isCopyButtonLabel("Copy message", selectors: claude))
        XCTAssertFalse(isCopyButtonLabel("Copy code", selectors: claude))
        XCTAssertFalse(isCopyButtonLabel("Copy table", selectors: claude))
        XCTAssertFalse(isCopyButtonLabel("Copy link", selectors: claude))
    }
}

final class EchoAndAffordanceContractTests: XCTestCase {
    func testEchoRegistrationMatchesSelectors() {
        // The Codex-mode fast-reply race: ChatGPT's echo ("Copy message") is
        // excluded from the count, so absorption there could only ever
        // swallow a fast response into the baseline. These two flags are the
        // guard; if a selector change makes ChatGPT echoes countable (or
        // Claude echoes uncountable), this contract must be revisited.
        XCTAssertFalse(config.chatgptSelectors.echoCountsAsAffordance)
        XCTAssertTrue(config.claudeSelectors.echoCountsAsAffordance)
        XCTAssertFalse(isCopyButtonLabel("Copy message", selectors: config.chatgptSelectors),
                       "chatgpt echo label must stay excluded while echoCountsAsAffordance is false")
        XCTAssertTrue(isCopyButtonLabel("Copy message", selectors: config.claudeSelectors),
                      "claude echo label must stay counted while echoCountsAsAffordance is true")
    }

    func testClaudeCollapsedToggleIsTheAffordanceStandIn() {
        XCTAssertEqual(config.claudeSelectors.messageActionsLabel, "Show message actions")
        XCTAssertNil(config.chatgptSelectors.messageActionsLabel)
    }
}

final class SendSelectorTests: XCTestCase {
    func testClaudeSendFeedbackTrap() {
        // Claude Code's "Send feedback" button matches the bare keyword;
        // sendExcludeKeywords exists solely to dodge it.
        XCTAssertTrue(isSendButtonLabel("Send", selectors: config.claudeSelectors))
        XCTAssertFalse(isSendButtonLabel("Send feedback Send feedback", selectors: config.claudeSelectors))
    }

    func testChatGPTSendMatches() {
        XCTAssertTrue(isSendButtonLabel("Send", selectors: config.chatgptSelectors))
    }
}

final class AnnouncementParsingTests: XCTestCase {
    func testValueAfterPrefix() {
        XCTAssertEqual(ErrolKit.value(after: "Model:", in: "Model: Fable 5 · Extra"), "Fable 5 · Extra")
        XCTAssertNil(ErrolKit.value(after: "Model:", in: "no announcement here"))
    }

    func testValueAfterRepeatedAnnouncement() {
        // axLabel joins several AX attributes, so an announcement can appear
        // twice; only the text between occurrences counts.
        XCTAssertEqual(ErrolKit.value(after: "Effort: ", in: "Effort: Extra Effort: Extra"), "Extra")
    }
}

final class SurfaceNamePrecedenceTests: XCTestCase {
    let claude = config.claudeSelectors

    func testTabOutranksURL() {
        var scan = WindowScan()
        scan.surfacePath = "epitaxy"
        XCTAssertEqual(surfaceName(scan, selectors: claude), "Code")
        scan.surfaceTab = "Chat"
        XCTAssertEqual(surfaceName(scan, selectors: claude), "Chat",
                       "the selected composer tab must outrank the URL path")
    }

    func testUnmappedPathCapitalizes() {
        var scan = WindowScan()
        scan.surfacePath = "cowork"
        XCTAssertEqual(surfaceName(scan, selectors: claude), "Cowork")
    }

    func testComposerPlaceholderNamesChatGPTSurfaces() {
        var scan = WindowScan()
        scan.composerSurface = config.chatgptSelectors
            .composerSurfaceNames["Work with ChatGPT"]
        XCTAssertEqual(surfaceName(scan, selectors: config.chatgptSelectors), "Work")
    }
}
