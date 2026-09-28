// The response wait and the capture gate read a conversation through one
// walk of the window (conversationSighting) where they once asked four
// finders for four walks. These tests are the proof that the one walk
// answers as the four did: every window of every recorded fixture, read
// both ways with its app's selectors, the covered image viewer and the
// collapsed Claude Code bars included.

import XCTest
@testable import ErrolKit

final class ConversationSightingTests: XCTestCase {
    private func fixtureNames() throws -> [String] {
        let urls = try XCTUnwrap(Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures"))
        return urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    func testTheSightingAnswersAsTheSeparateFindersDo() throws {
        let names = try fixtureNames()
        XCTAssertGreaterThan(names.count, 10, "the sweep should see the whole fixture set")
        for required in ["claude-code-image-viewer", "claude-code-collapsed"] {
            XCTAssertTrue(names.contains(required), "\(required) must be in the sweep")
        }
        for name in names {
            let selectors = name.hasPrefix("chatgpt") ? config.chatgptSelectors : config.claudeSelectors
            for (index, window) in loadFixture(name).enumerated() {
                let label = "\(name) window \(index)"
                let sighting = conversationSighting(under: window, selectors: selectors)
                XCTAssertEqual(sighting.affordances,
                               messageAffordances(under: window, selectors: selectors).count, label)
                XCTAssertEqual(sighting.lastOrdinal, lastMessageOrdinal(under: window), label)
                XCTAssertEqual(sighting.streaming, hasStopButton(under: window, selectors: selectors), label)
                XCTAssertEqual(sighting.hasComposer, hasTextArea(window), label)
                // And the cover check made from it names what the
                // standalone check names.
                XCTAssertEqual(coveringDialog(under: window, sighting: sighting).map(dialogName),
                               coveringDialog(under: window).map(dialogName), label)
            }
        }
    }

    func testTheCoveredViewerReadsAsNothingBehindADialog() throws {
        let selectors = config.claudeSelectors
        let window = try XCTUnwrap(loadFixture("claude-code-image-viewer").first)
        let sighting = conversationSighting(under: window, selectors: selectors)
        XCTAssertEqual(sighting, ConversationSighting())
        XCTAssertEqual(coveringDialog(under: window, sighting: sighting).map(dialogName), "Image preview")
    }

    func testTheCollapsedBarsCountAsMessages() throws {
        let selectors = config.claudeSelectors
        let windows = loadFixture("claude-code-collapsed")
        let chosen = try XCTUnwrap(chooseChatWindow(from: windows, selectors: selectors))
        let affordances = messageAffordances(under: chosen, selectors: selectors)
        XCTAssertTrue(affordances.contains { isMessageActionsToggle($0, selectors: selectors) },
                      "the fixture should carry collapsed action bars")
        let sighting = conversationSighting(under: chosen, selectors: selectors)
        XCTAssertEqual(sighting.affordances, affordances.count)
        XCTAssertTrue(sighting.hasComposer)
    }
}
