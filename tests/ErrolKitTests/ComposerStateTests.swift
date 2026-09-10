// What the composer is judged to hold before a paste, against the values
// the apps actually report for an empty field: Claude a bare newline,
// ChatGPT its placeholder text (both from live captures in the fixtures).
// Only an empty composer admits a paste; everything else is the human's
// unsent work, a busy conversation, or a value nobody could read.

import XCTest
@testable import ErrolKit

final class ComposerStateTests: XCTestCase {
    private func classify(_ value: String?, label: String = "", attachments: Int = 0,
                          replying: Bool = false) -> ComposerState {
        classifyComposer(value: value, label: label, attachments: attachments, replying: replying)
    }

    func testEmptyValuesAreEmpty() {
        XCTAssertEqual(classify(""), .empty)
        XCTAssertEqual(classify("\n"), .empty, "Claude's idle composer reads as a newline")
        XCTAssertEqual(classify("\nMessage ChatGPT", label: "Message ChatGPT"), .empty,
                       "ChatGPT's idle composer reads as its placeholder, newline first")
        XCTAssertEqual(classify("Write your prompt to Claude"), .empty, "a known placeholder")
        XCTAssertEqual(classify("Ask anything new", label: "Ask anything new"), .empty,
                       "an unknown placeholder still matches the element's own label")
    }

    func testDraftsAttachmentsBusyAndUnreadableAreNotEmpty() {
        XCTAssertEqual(classify("half-typed reply"), .draft(characters: 16))
        XCTAssertEqual(classify("  half-typed reply\n"), .draft(characters: 16),
                       "the count is of the text, not its surrounding whitespace")
        XCTAssertEqual(classify("Message ChatGPT and more", label: "Message ChatGPT"), .draft(characters: 24),
                       "text that merely begins like the placeholder is a draft")
        XCTAssertEqual(classify("", attachments: 2), .attachments(2))
        XCTAssertEqual(classify("a draft", attachments: 1), .attachments(1),
                       "an attachment is reported ahead of the text beside it")
        XCTAssertEqual(classify("a draft", replying: true), .replying,
                       "a reply underway outranks everything: nothing is pasted into a busy conversation")
        XCTAssertEqual(classify(nil), .unreadable, "no value establishes nothing")
        XCTAssertFalse(ComposerState.unreadable.isEmpty)
    }

    func testFixtureComposersClassifyAsCaptured() throws {
        func state(of fixture: String, selectors: AppSelectors) throws -> ComposerState {
            let window = try XCTUnwrap(loadFixture(fixture).first)
            let composer = try XCTUnwrap(composerElement(under: window))
            return classifyComposer(value: composer.stringValue, label: composer.label,
                                    attachments: pastedTextAttachmentCount(under: window, selectors: selectors),
                                    replying: hasStopButton(under: window, selectors: selectors))
        }
        XCTAssertEqual(try state(of: "claude-chat-home", selectors: config.claudeSelectors), .empty)
        XCTAssertEqual(try state(of: "claude-code-collapsed", selectors: config.claudeSelectors), .empty)
        XCTAssertEqual(try state(of: "claude-virtualized-conversation", selectors: config.claudeSelectors), .empty)
        XCTAssertEqual(try state(of: "chatgpt-chat-home", selectors: config.chatgptSelectors), .empty)
        XCTAssertEqual(try state(of: "chatgpt-work-home", selectors: config.chatgptSelectors), .empty)
        XCTAssertEqual(try state(of: "chatgpt-chat-conversation", selectors: config.chatgptSelectors),
                       .draft(characters: 16), "the fixture's half-typed reply is a draft")
        XCTAssertEqual(try state(of: "chatgpt-chat-streaming", selectors: config.chatgptSelectors), .replying)
    }

    func testStatesMapToDeliveryBlocks() {
        XCTAssertNil(deliveryBlock(for: .empty, side: .claude))
        XCTAssertEqual(deliveryBlock(for: .draft(characters: 3), side: .claude), .draft(side: .claude, characters: 3))
        XCTAssertEqual(deliveryBlock(for: .attachments(1), side: .chatgpt), .attachments(side: .chatgpt, count: 1))
        XCTAssertEqual(deliveryBlock(for: .replying, side: .claude), .replying(side: .claude))
        XCTAssertEqual(deliveryBlock(for: .unreadable, side: .chatgpt), .composerUnreadable(side: .chatgpt))
    }
}
