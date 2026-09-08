// How a paste is recognized in the composer, and when a missed receipt may
// be retried — against the composer ChatGPT actually produced when a paste
// opened with a code fence (captured live Sep 8 2026), the case that had
// the relay pasting twice: the old receipt looked for the payload's first
// line, "```text", and the composer had rendered that line away.

import XCTest
@testable import ErrolKit

final class PasteRecognitionTests: XCTestCase {
    /// Claude's turn-6 reply from the Sep 8 2026 run, verbatim (717 chars).
    private let fencedReply = """
    ```text
    PASTE-TEST-3
    tabs:\tone\ttwo
    trailing-spaces:···
    unicode: café — naïve — 日本語
    ```

    Confirmed, matches exactly — tabs, unicode, and the trailing-spaces marker all intact this time.

    Good data point on test 2 though: curly quotes (U+201C/U+201D) getting normalized to straight quotes and em dash likely surviving suggests something in the relay path is doing smart-quote-to-ASCII substitution specifically, not a broad Unicode strip. Worth checking if that's happening on my send side, your receive side, or a shared transport layer in between — that's the kind of silent corruption that'd bite real paste content later. Good place to stop for now unless you want to isolate which hop does it. [[END-CONVERSATION]]
    """

    /// ChatGPT's empty Work composer, as its AXValue reads before a paste.
    private let chatgptPlaceholder = "\nWork with ChatGPT"

    /// The composer group captured by the paste-miss snapshot, one poll
    /// after the fenced reply was pasted: a fixture like the others, with
    /// the text area's AXValue as the app reported it.
    private func fencedComposer() throws -> FixtureElement {
        let root = try XCTUnwrap(loadFixture("chatgpt-work-composer-fenced-paste").first)
        return try XCTUnwrap(composerElement(under: root))
    }

    func testNeedleSkipsFenceLinesAndKeepsLettersAndDigits() {
        XCTAssertEqual(fencedReply.count, 717)
        XCTAssertEqual(pasteNeedle(for: fencedReply), "PASTETEST3tabsonetwotrai")
        XCTAssertEqual(pasteNeedle(for: "\n\nHello, world! 42"), "Helloworld42")
        XCTAssertEqual(pasteNeedle(for: "Ok.\n\nSecond paragraph starts here"), "OkSecondparagraphstartsh",
                       "a short first line runs on into the next")
        XCTAssertEqual(pasteNeedle(for: "    ```swift\nlet x = 1\n    ```"), "letx1",
                       "indented fences are fences")
        XCTAssertEqual(pasteNeedle(for: "```\n```\n---\n"), "")
        XCTAssertEqual(pasteNeedle(for: "“Quoted” — and dashed"), "Quotedanddashed",
                       "the characters composers swap are not part of the needle")
    }

    func testFencedReplyIsRecognizedInTheRenderedComposer() throws {
        let value = try XCTUnwrap(fencedComposer().stringValue)
        // What ChatGPT did to the paste: both fence lines are gone, the
        // block's text and the prose remain.
        XCTAssertEqual(value.count, 704)
        XCTAssertFalse(value.contains("```"))
        XCTAssertTrue(value.contains("PASTE-TEST-3"))
        XCTAssertTrue(value.contains("[[END-CONVERSATION]]"))

        let oldNeedle = String(fencedReply.split(whereSeparator: \.isNewline).first!.prefix(32))
        XCTAssertEqual(oldNeedle, "```text")
        XCTAssertFalse(value.contains(oldNeedle), "the receipt the relay used to wait for never came")

        let expectation = PasteExpectation(payload: fencedReply, valueBefore: chatgptPlaceholder)
        XCTAssertTrue(expectation.needleIsDistinctive)
        XCTAssertEqual(observedPasteReceipt(expecting: expectation, composerValue: value,
                                            attachmentsBefore: 0, attachmentsNow: 0), .text)
        // Growth would have vouched for it too: 704 chars over an empty baseline.
        XCTAssertEqual(expectation.growth(to: value), 704)
        XCTAssertGreaterThanOrEqual(704, expectation.growthRequired)
    }

    func testGrowthVouchesWhenTheOpeningTextIsRewrittenPastRecognition() {
        // A link first: a rendering composer keeps the label and drops the URL.
        let payload = "[Report](https://example.com/q/12345678901234567890)\nrest of the message goes on for a bit"
        let expectation = PasteExpectation(payload: payload, valueBefore: chatgptPlaceholder)
        let rendered = "Report\nrest of the message goes on for a bit"
        XCTAssertFalse(alphanumerics(of: rendered).contains(expectation.needle))
        XCTAssertEqual(expectation.baselineCount, 0, "a placeholder is not text the paste adds to")
        XCTAssertEqual(expectation.growthRequired, payload.count / 3)
        XCTAssertEqual(observedPasteReceipt(expecting: expectation, composerValue: rendered,
                                            attachmentsBefore: 0, attachmentsNow: 0), .growth)
    }

    func testAPlaceholderThatStaysIsNotGrowth() {
        let expectation = PasteExpectation(payload: String(repeating: "word ", count: 10),
                                           valueBefore: chatgptPlaceholder)
        XCTAssertNil(expectation.growth(to: chatgptPlaceholder))
        XCTAssertNil(observedPasteReceipt(expecting: expectation, composerValue: chatgptPlaceholder,
                                          attachmentsBefore: 0, attachmentsNow: 0))
    }

    func testSmallGrowthDoesNotVouchForALongPayload() {
        let payload = String(repeating: "Lorem ipsum dolor sit amet. ", count: 20)
        let expectation = PasteExpectation(payload: payload, valueBefore: "")
        XCTAssertNil(observedPasteReceipt(expecting: expectation, composerValue: "Lorem ipsum",
                                          attachmentsBefore: 0, attachmentsNow: 0))
    }

    func testANeedleTheComposerAlreadyHeldDoesNotVouch() {
        let draft = "Hello there friend"
        let expectation = PasteExpectation(payload: draft, valueBefore: draft)
        XCTAssertFalse(expectation.needleIsDistinctive)
        XCTAssertNil(observedPasteReceipt(expecting: expectation, composerValue: draft,
                                          attachmentsBefore: 0, attachmentsNow: 0))
        // The paste landing after the draft shows as growth over the draft.
        XCTAssertEqual(expectation.baselineCount, draft.count)
        XCTAssertEqual(observedPasteReceipt(expecting: expectation, composerValue: draft + draft,
                                            attachmentsBefore: 0, attachmentsNow: 0), .growth)
    }

    func testRetryIsSafeOnlyWhileTheComposerStandsStill() {
        XCTAssertTrue(pasteRetryIsSafe(valueBefore: chatgptPlaceholder, valueNow: chatgptPlaceholder,
                                       attachmentsBefore: 0, attachmentsNow: 0))
        XCTAssertTrue(pasteRetryIsSafe(valueBefore: nil, valueNow: nil, attachmentsBefore: 0, attachmentsNow: 0))
        XCTAssertFalse(pasteRetryIsSafe(valueBefore: chatgptPlaceholder, valueNow: "\nPASTE-TEST-3\ntabs:",
                                        attachmentsBefore: 0, attachmentsNow: 0),
                       "the Sep 8 2026 case: rewritten past recognition, but in the composer")
        XCTAssertFalse(pasteRetryIsSafe(valueBefore: "", valueNow: "", attachmentsBefore: 0, attachmentsNow: 1),
                       "a chip mounted, even with the text area unchanged")
    }

    func testTheCapturedComposerStillReadsAsAComposer() throws {
        // The capture is a fixture like any other: the finders that pick the
        // composer and the send button agree with the live run's log.
        let root = try XCTUnwrap(loadFixture("chatgpt-work-composer-fenced-paste").first)
        XCTAssertTrue(composerElement(under: root)?.label.contains("Work with ChatGPT") == true)
        XCTAssertTrue(sendButton(under: root, selectors: config.chatgptSelectors)?.label.contains("Send") == true)
        XCTAssertEqual(pastedTextAttachmentCount(under: root, selectors: config.chatgptSelectors), 0)
    }
}
