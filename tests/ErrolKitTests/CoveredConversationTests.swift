// A dialog over the conversation: Claude's image viewer, captured live on
// Sep 25 2026 (claude-code-image-viewer) — the state that ended a run on
// Sep 24 2026 with "Couldn't copy Claude's reply". While the viewer is
// open, Chromium exposes nothing behind it, so the tree reads as a reply
// that has finished and left nothing to copy. These tests pin the
// detection that holds the run instead, and that no screen already
// classified reads as covered.

import XCTest
@testable import ErrolKit

final class CoveredConversationTests: XCTestCase {
    let selectors = config.claudeSelectors

    private func viewerWindow(file: StaticString = #filePath, line: UInt = #line) throws -> FixtureElement {
        try XCTUnwrap(loadFixture("claude-code-image-viewer", file: file, line: line).first)
    }

    func testTheImageViewerHidesTheConversationBehindADialog() throws {
        let window = try viewerWindow()
        let dialog = try XCTUnwrap(coveringDialog(under: window))
        XCTAssertEqual(dialog.subrole, "AXApplicationDialog")
        // The viewer's title, not its joined label ("Image preview Image
        // preview", from the description and the title together).
        XCTAssertEqual(dialogName(dialog), "Image preview")
        // Everything the relay reads is gone: the composer, the copy
        // buttons and collapsed toggles, the ordinal, the Stop button.
        XCTAssertNil(composerElement(under: window))
        XCTAssertTrue(copyButtons(under: window, selectors: selectors).isEmpty)
        XCTAssertTrue(messageAffordances(under: window, selectors: selectors).isEmpty)
        XCTAssertNil(lastMessageOrdinal(under: window))
        XCTAssertFalse(hasStopButton(under: window, selectors: selectors))
        // Which, read as a sighting after streaming was seen, is a finished
        // reply: why the wait must not look while the dialog is open.
        let dark = ResponseSighting(affordances: messageAffordances(under: window, selectors: selectors).count,
                                    lastOrdinal: lastMessageOrdinal(under: window),
                                    streaming: hasStopButton(under: window, selectors: selectors))
        XCTAssertTrue(responseArrived(dark, since: ResponseBaseline(affordances: 2, lastOrdinal: nil),
                                      sawStreaming: true, selectors: selectors))
    }

    func testTheScanAndTheCandidateNameWhatCoversIt() throws {
        let window = try viewerWindow()
        let scan = scanWindow(window, selectors: selectors)
        XCTAssertFalse(scan.hasComposer)
        XCTAssertEqual(scan.coveredBy, "Image preview")
        let candidate = WindowCandidate(id: WindowID(raw: 1), scan: scan, selectors: selectors)
        XCTAssertEqual(candidate.composer, .covered(by: "Image preview"))
        XCTAssertEqual(candidate.stateLine, "Covered by \u{201C}Image preview\u{201D}")
        // A connected side reads as something to finish first, with the
        // start refusal naming what to close.
        let observation = BindingObservation(window: candidate.id, check: .same, identity: candidate.identity,
                                             composer: candidate.composer)
        let readiness = destinationReadiness(observation, side: .claude)
        XCTAssertEqual(readiness, .finishPreparing(.covered(side: .claude, by: "Image preview")))
        XCTAssertEqual(readiness.problem(name: "Claude"),
                       "\u{201C}Image preview\u{201D} is open over Claude's conversation. Close it, then send again.")
    }

    func testNoOtherFixtureReadsAsCovered() throws {
        let urls = try XCTUnwrap(Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures"))
        let names = urls.map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0 != "claude-code-image-viewer" }
        XCTAssertGreaterThan(names.count, 10, "the sweep should see the whole fixture set")
        for name in names {
            let selectors = name.hasPrefix("chatgpt") ? config.chatgptSelectors : config.claudeSelectors
            for (index, window) in loadFixture(name).enumerated() {
                XCTAssertNil(coveringDialog(under: window), "\(name) window \(index)")
                XCTAssertNil(scanWindow(window, selectors: selectors).coveredBy, "\(name) window \(index)")
            }
        }
    }

    func testADialogOverAReadableConversationIsNotCover() {
        // A popover carries role="dialog" too, and leaves the conversation
        // in the tree: the composer is there, and a copy would work.
        let popover = FixtureElement(role: "AXGroup", subrole: "AXApplicationDialog", title: "Model")
        let composer = FixtureElement(role: "AXTextArea", axDescription: "Prompt", value: .string(""))
        let readable = FixtureElement(role: "AXWindow", children: [composer, popover])
        XCTAssertNotNil(openDialog(under: readable))
        XCTAssertNil(coveringDialog(under: readable))
        // And a window that has lost its composer with no dialog in it is
        // not something the human could close.
        let bare = FixtureElement(role: "AXWindow", children: [FixtureElement(role: "AXGroup")])
        XCTAssertNil(coveringDialog(under: bare))
        // An unnamed dialog is still cover, named as a dialog.
        let unnamed = FixtureElement(role: "AXWindow",
                                     children: [FixtureElement(role: "AXGroup", subrole: "AXApplicationAlertDialog")])
        XCTAssertEqual(coveringDialog(under: unnamed).map(dialogName), "")
    }

    func testTheHoldSaysWhatToClose() {
        let names = SideNames(chatgpt: "ChatGPT", claude: "Claude")
        let named = RunBlock.covered(side: .claude, by: "Image preview")
        XCTAssertEqual(named.side, .claude)
        XCTAssertEqual(named.headline(names: names), "Paused: Claude's conversation is covered")
        XCTAssertTrue(named.recovery(names: names).hasPrefix("Close \u{201C}Image preview\u{201D} in Claude to continue"))
        XCTAssertTrue(named.logLine(name: "Claude").hasPrefix("Paused — \u{201C}Image preview\u{201D} is open over Claude's conversation"))
        XCTAssertEqual(named.contextClause(names: names), "Claude's conversation was covered")
        let unnamed = RunBlock.covered(side: .chatgpt, by: "")
        XCTAssertTrue(unnamed.recovery(names: names).hasPrefix("Close the dialog in ChatGPT"))
        XCTAssertEqual(unnamed.startRefusal(name: "ChatGPT"),
                       "A dialog is open over ChatGPT's conversation. Close it, then send again.")
        XCTAssertEqual(deliveryBlock(for: .covered(by: "Image preview"), side: .claude), named)
    }
}
