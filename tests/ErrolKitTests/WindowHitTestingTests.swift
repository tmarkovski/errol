// The areas a dragged icon can be dropped on: one over each message field
// the window server shows, front to back, and none where the drawn area
// would float over a window covering the field.

import XCTest
@testable import ErrolKit

final class WindowHitTestingTests: XCTestCase {
    private let owner: Int32 = 100
    private let conversation = CGRect(x: 0, y: 20, width: 700, height: 800)
    private let prompt = CGRect(x: 40, y: 700, width: 620, height: 90)
    private let conversationID = WindowID(raw: 1)

    private func region(_ number: UInt32, owner: Int32? = nil, _ frame: CGRect) -> WindowHitRegion {
        WindowHitRegion(number: number, owner: owner ?? self.owner, frame: frame)
    }

    func testTheAreaIsTheFieldOfAWindowTheServerShows() {
        let candidates = [ConnectionDropCandidate(window: conversationID, frame: conversation, prompt: prompt)]
        let zones = dropZones(for: candidates, owner: owner, onScreen: [region(10, conversation)])
        XCTAssertEqual(zones, [ConnectionDropZone(window: conversationID, frame: prompt, marksPrompt: true)])
        XCTAssertEqual(dropZone(at: CGPoint(x: 100, y: 750), among: zones)?.window, conversationID)
        XCTAssertNil(dropZone(at: CGPoint(x: 100, y: 100), among: zones),
                     "the conversation above the field is not a drop")
    }

    func testAWindowNotOnScreenHasNoArea() {
        // Minimized, hidden, or on another Space: the server does not list it.
        let candidates = [ConnectionDropCandidate(window: conversationID, frame: conversation, prompt: prompt)]
        XCTAssertTrue(dropZones(for: candidates, owner: owner, onScreen: []).isEmpty)
        // Another app's window at the same frame is not this one.
        XCTAssertTrue(dropZones(for: candidates, owner: owner,
                                          onScreen: [region(10, owner: 200, conversation)]).isEmpty)
    }

    func testAnUnreadFieldLeavesTheWholeWindowAsTheArea() {
        let candidates = [ConnectionDropCandidate(window: conversationID, frame: conversation, prompt: nil)]
        let zones = dropZones(for: candidates, owner: owner, onScreen: [region(10, conversation)])
        XCTAssertEqual(zones, [ConnectionDropZone(window: conversationID, frame: conversation, marksPrompt: false)])
    }

    func testAreasFollowTheServersOrderAndTouchingEdgesCoverNothing() {
        let right = conversation.offsetBy(dx: conversation.width, dy: 0)
        let candidates = [ConnectionDropCandidate(window: WindowID(raw: 1), frame: conversation, prompt: prompt),
                          ConnectionDropCandidate(window: WindowID(raw: 2), frame: right,
                                                  prompt: prompt.offsetBy(dx: conversation.width, dy: 0))]
        let zones = dropZones(for: candidates, owner: owner,
                                        onScreen: [region(11, right), region(10, conversation)])
        XCTAssertEqual(zones.map(\.window), [WindowID(raw: 2), WindowID(raw: 1)], "the front window first")
        XCTAssertEqual(dropZone(at: CGPoint(x: 100, y: 750), among: zones)?.window, WindowID(raw: 1))
        XCTAssertEqual(dropZone(at: CGPoint(x: 800, y: 750), among: zones)?.window, WindowID(raw: 2))
    }

    func testAFieldUnderAWindowInFrontHasNoArea() {
        // Cascaded windows of the same app: the front one's body covers the
        // field behind it, and a drawn area would float over that body.
        let front = conversation.offsetBy(dx: 60, dy: 60)
        let candidates = [ConnectionDropCandidate(window: WindowID(raw: 1), frame: conversation, prompt: prompt),
                          ConnectionDropCandidate(window: WindowID(raw: 2), frame: front,
                                                  prompt: prompt.offsetBy(dx: 60, dy: 60))]
        let zones = dropZones(for: candidates, owner: owner,
                                        onScreen: [region(11, front), region(10, conversation)])
        XCTAssertEqual(zones.map(\.window), [WindowID(raw: 2)])
    }

    func testAnotherAppsWindowOverTheFieldBlocksTheDrop() {
        // The app did not come forward: a drop there would connect a window
        // the human cannot see.
        let covering = region(20, owner: 200, CGRect(x: 0, y: 650, width: 300, height: 200))
        let candidates = [ConnectionDropCandidate(window: conversationID, frame: conversation, prompt: prompt)]
        XCTAssertTrue(dropZones(for: candidates, owner: owner,
                                          onScreen: [covering, region(10, conversation)]).isEmpty)
        // Behind the conversation it covers nothing.
        XCTAssertEqual(dropZones(for: candidates, owner: owner,
                                           onScreen: [region(10, conversation), covering]).count, 1)
    }

    func testAWindowOverTheHistoryLeavesTheFieldItsArea() {
        // A small window (a Claude Code session, say) in front of the
        // conversation's history, clear of its field.
        let small = region(12, CGRect(x: 100, y: 100, width: 300, height: 300))
        let candidates = [ConnectionDropCandidate(window: conversationID, frame: conversation, prompt: prompt)]
        XCTAssertEqual(dropZones(for: candidates, owner: owner,
                                           onScreen: [small, region(10, conversation)]).map(\.frame), [prompt])
    }
}
