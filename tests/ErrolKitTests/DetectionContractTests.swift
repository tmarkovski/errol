// Contract tests for the pure detection logic — the parts of ErrolKit that
// don't need a live app. Each test pins an invariant that was established
// against real trees (dates in docs/how-it-works.md's field notes); if a selector or
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

    func testChatGPTQualifiedCopiesExcluded() {
        XCTAssertFalse(isCopyButtonLabel("Copy table", selectors: chatgpt))
        XCTAssertFalse(isCopyButtonLabel("Copy code", selectors: chatgpt))
        XCTAssertFalse(isCopyButtonLabel("Copy link", selectors: chatgpt))
    }

    func testClaudeCopyLabels() {
        XCTAssertTrue(isCopyButtonLabel("Copy", selectors: claude))
        XCTAssertFalse(isCopyButtonLabel("Copy code", selectors: claude))
        XCTAssertFalse(isCopyButtonLabel("Copy table", selectors: claude))
        XCTAssertFalse(isCopyButtonLabel("Copy link", selectors: claude))
    }

    // The button shapes both apps showed live on Sep 28 2026: a copy button
    // is an icon the app names (AXDescription) and draws no text in; a row
    // that mentions copying is named by, or shows, text someone wrote.

    func testCommandsTheAppNamesAreCopyButtons() {
        let button = kAXButtonRole as String
        XCTAssertTrue(isCopyButton(FixtureElement(role: button, axDescription: "Copy"), selectors: claude),
                      "Claude's message Copy: the name in AXDescription alone")
        XCTAssertTrue(isCopyButton(FixtureElement(role: button, axDescription: "Copy", title: "Copy"),
                                   selectors: chatgpt),
                      "ChatGPT's response Copy: the same name in AXDescription and AXTitle")
        XCTAssertTrue(isCopyButton(FixtureElement(role: button, axDescription: "Copy",
                                                  children: [FixtureElement(role: "AXImage")]),
                                   selectors: claude),
                      "an icon the app exposes as an image is still no text")
    }

    func testRowsThatMentionCopyingAreNot() {
        let button = kAXButtonRole as String
        let text = kAXStaticTextRole as String
        XCTAssertFalse(isCopyButton(FixtureElement(role: button, title: "Checked the copy on the release page"),
                                    selectors: claude),
                       "a finished Claude Code step: named by the text it shows, nothing under it")
        XCTAssertFalse(isCopyButton(FixtureElement(role: button, title: "Checking the copy on the release page…",
                                                   children: [FixtureElement(role: text, value: .string("Checking the copy on the release page…")),
                                                              FixtureElement(role: text, value: .string("running"))]),
                                    selectors: claude),
                       "a running Claude Code step shows its summary as text")
        XCTAssertFalse(isCopyButton(FixtureElement(role: button, title: "Idle Copy edits for the landing page",
                                                   children: [FixtureElement(role: "AXImage", axDescription: "Idle"),
                                                              FixtureElement(role: "AXGroup", children: [
                                                                  FixtureElement(role: text, value: .string("Copy edits for the landing page"))])]),
                                    selectors: claude),
                       "a Claude session row")
        XCTAssertFalse(isCopyButton(FixtureElement(role: button, axDescription: "Copy editing tips", title: "Copy editing tips",
                                                   children: [FixtureElement(role: "AXGroup", children: [
                                                       FixtureElement(role: text, value: .string("Copy editing tips"))])]),
                                    selectors: chatgpt),
                       "a ChatGPT conversation row: named by the app after its title, which it also shows")
    }
}

final class EchoAndAffordanceContractTests: XCTestCase {
    func testEchoRegistrationMatchesSelectors() {
        // "Copy message" belongs to user messages. On ChatGPT, counting it
        // once cost a debugging round (the relay copied its own message
        // back), so it is excluded there; Claude's user messages carry it
        // too, and there it counts, because the Claude side's echo
        // absorption depends on it.
        //
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

final class WorldSwitcherTests: XCTestCase {
    let claude = config.claudeSelectors

    /// A world-switcher option: the name arrives in AXDescription, and the
    /// selected one carries AXValue 1.
    private func world(_ description: String, selected: Bool) -> FixtureElement {
        FixtureElement(role: "AXRadioButton", axDescription: description,
                       value: .number(selected ? 1 : 0))
    }

    private func isMarker(_ element: FixtureElement) -> Bool {
        isExclusionMarker(element, role: element.role ?? "", selectors: claude)
    }

    func testLiveSessionStateIsStrippedFromTheOptionName() {
        // Claude appends the session's state to the Code option's description
        // and, in at least one capture, to the chat option's too; all four
        // spellings are live-observed in the fixtures.
        XCTAssertEqual(worldName("Code"), "Code")
        XCTAssertEqual(worldName("Code, idle"), "Code")
        XCTAssertEqual(worldName("Code, awaiting your input"), "Code")
        XCTAssertEqual(worldName("Chat and Cowork, awaiting your input"), "Chat and Cowork")
    }

    func testSelectedCodeWorldExcludesTheWindow() {
        XCTAssertTrue(isMarker(world("Code, running", selected: true)))
        XCTAssertTrue(isMarker(world("Code", selected: true)))
    }

    func testUnselectedCodeWorldDoesNot() {
        // Both options are always mounted — only AXValue tells them apart, so
        // matching on the label alone would exclude every Claude window.
        XCTAssertFalse(isMarker(world("Code, idle", selected: false)))
        XCTAssertFalse(isMarker(world("Chat and Cowork", selected: true)))
    }

    func testComposerSurfaceRadiosAreNotWorldOptions() {
        // The Chat/Cowork pair sits at the composer, names itself in AXTitle
        // rather than AXDescription, and must never read as a world.
        XCTAssertFalse(isMarker(FixtureElement(role: "AXRadioButton", title: "Chat",
                                               value: .number(1))))
        XCTAssertFalse(isMarker(FixtureElement(role: "AXRadioButton", title: "Cowork",
                                               value: .number(1))))
    }

    func testFurnitureMarkersStillExcludeOnTheirOwn() {
        // The backstop for builds with no switcher: the old multi-window
        // layout is classified entirely by these.
        XCTAssertTrue(isMarker(FixtureElement(role: "AXButton",
                                             axDescription: "Rewind to here")))
        XCTAssertTrue(isMarker(FixtureElement(role: "AXTextField",
                                             axDescription: "Terminal input")))
        XCTAssertFalse(isMarker(FixtureElement(role: "AXButton", axDescription: "Copy")))
    }

    func testChatGPTHasNoWorldSwitcher() {
        XCTAssertNil(config.chatgptSelectors.excludedWorldName)
        XCTAssertFalse(isExclusionMarker(world("Code", selected: true), role: "AXRadioButton",
                                         selectors: config.chatgptSelectors))
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

final class PasteReceiptTests: XCTestCase {
    let chatgpt = config.chatgptSelectors

    func testChatGPTLongPasteAttachmentSelector() {
        XCTAssertEqual(chatgpt.pastedTextAttachmentRemoveLabel,
                       "Remove pasted text attachment")
        XCTAssertEqual(chatgpt.pastedTextAttachmentAncestorLevels, 1)

        let composer = FixtureElement(role: "AXGroup", children: [
            FixtureElement(role: "AXButton",
                           axDescription: "Remove pasted text attachment"),
            FixtureElement(role: "AXTextArea", axDescription: "Do anything",
                           value: .string("\nDo anything")),
        ])
        XCTAssertEqual(pastedTextAttachmentCount(under: composer, selectors: chatgpt), 1)
        XCTAssertEqual(attachmentCount(in: composer, selectors: chatgpt), 1)
        XCTAssertEqual(pastedTextAttachmentCount(under: composer,
                                                 selectors: config.claudeSelectors), 0)
    }

    /// Replays the live parent walk, rather than handing the counter an
    /// already-selected container (which missed Claude's nesting regression).
    private func attachmentCount(in root: FixtureElement, selectors: AppSelectors) -> Int {
        func parent(of node: FixtureElement, under ancestor: FixtureElement) -> FixtureElement? {
            if ancestor.children.contains(node) { return ancestor }
            return ancestor.children.lazy.compactMap { parent(of: node, under: $0) }.first
        }
        guard let input = composerElement(under: root) else { return 0 }
        return pastedTextAttachmentCount(around: input, selectors: selectors) {
            parent(of: $0, under: root)
        }
    }

    /// Shape observed in Claude Desktop on Sep 7 2026. Payload previews are
    /// anonymized; labels, empty AXValue, and nesting match the open draft.
    private func claudeWindow(lineCounts: [Int]) -> FixtureElement {
        let attachments = lineCounts.map { lines in
            FixtureElement(role: "AXGroup", children: [
                FixtureElement(role: "AXButton", axDescription: "Pasted text, pasted, \(lines) lines",
                               children: [FixtureElement(role: "AXStaticText", value: .string("PASTED"))]),
                FixtureElement(role: "AXButton", axDescription: "Remove Pasted text, pasted, \(lines) lines"),
            ])
        }
        let input = FixtureElement(role: "AXTextArea", axDescription: "Write your prompt to Claude",
                                   value: .string(""))
        let composer = FixtureElement(role: "AXGroup", children: attachments + [
            FixtureElement(role: "AXGroup", children: [
                FixtureElement(role: "AXGroup", children: [input]),
                FixtureElement(role: "AXPopUpButton", axDescription: "Add files, connectors, and more"),
                FixtureElement(role: "AXButton", axDescription: "Send message"),
            ]),
        ])
        return FixtureElement(role: "AXWindow", children: [
            FixtureElement(role: "AXGroup", axDescription: "Chat messages", children: [
                FixtureElement(role: "AXButton", axDescription: "Pasted text, pasted, 149 lines"),
                FixtureElement(role: "AXButton", axDescription: "Pasted text, pasted, 149 lines"),
                // Even a matching control elsewhere must not count.
                FixtureElement(role: "AXButton", axDescription: "Remove Pasted text, pasted, 149 lines"),
            ]),
            composer,
        ])
    }

    func testClaudeLongPasteConfirmsWithEmptyTextAreaAndNestedAttachment() {
        let selectors = config.claudeSelectors
        let before = attachmentCount(in: claudeWindow(lineCounts: []), selectors: selectors)
        let after = attachmentCount(in: claudeWindow(lineCounts: [95]), selectors: selectors)
        XCTAssertEqual(before, 0)
        XCTAssertEqual(after, 1, "count the remove control once, not the preview as well")
        XCTAssertEqual(observedPasteReceipt(expecting: expectation, composerValue: "",
                                             attachmentsBefore: before, attachmentsNow: after), .attachment)
    }

    func testClaudeCountsVariableLineLabelsAndRequiresANewAttachment() {
        let selectors = config.claudeSelectors
        let before = attachmentCount(in: claudeWindow(lineCounts: [95]), selectors: selectors)
        XCTAssertNil(observedPasteReceipt(expecting: expectation, composerValue: "",
                                          attachmentsBefore: before, attachmentsNow: before))
        let after = attachmentCount(in: claudeWindow(lineCounts: [95, 149]), selectors: selectors)
        XCTAssertEqual(after, 2)
        XCTAssertEqual(observedPasteReceipt(expecting: expectation, composerValue: "",
                                             attachmentsBefore: before, attachmentsNow: after), .attachment)
    }

    func testClaudeDoesNotEscapeToWindowWhenComposerAncestorsAreMissing() {
        let window = FixtureElement(role: "AXWindow", children: [
            FixtureElement(role: "AXButton", axDescription: "Remove Pasted text, pasted, 95 lines"),
            FixtureElement(role: "AXGroup", children: [
                FixtureElement(role: "AXTextArea", value: .string("")),
            ]),
        ])
        XCTAssertEqual(attachmentCount(in: window, selectors: config.claudeSelectors), 0)
    }

    /// The payload the receipt tests expect, pasted into an empty composer.
    private var expectation: PasteExpectation {
        PasteExpectation(payload: "The first words of the payload", valueBefore: "")
    }

    func testOrdinaryTextConfirmsPaste() {
        XCTAssertEqual(observedPasteReceipt(
            expecting: expectation, composerValue: "The first words of the payload",
            attachmentsBefore: 0, attachmentsNow: 0), .text)
    }

    func testNewAttachmentConfirmsPasteWhenComposerKeepsPlaceholder() {
        let placeholder = PasteExpectation(payload: "The first words of the payload",
                                           valueBefore: "\nDo anything")
        XCTAssertEqual(observedPasteReceipt(
            expecting: placeholder, composerValue: "\nDo anything",
            attachmentsBefore: 0, attachmentsNow: 1), .attachment)
    }

    func testExistingAttachmentDoesNotConfirmAnotherPaste() {
        let placeholder = PasteExpectation(payload: "The first words of the payload",
                                           valueBefore: "\nDo anything")
        XCTAssertNil(observedPasteReceipt(
            expecting: placeholder, composerValue: "\nDo anything",
            attachmentsBefore: 1, attachmentsNow: 1))
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
