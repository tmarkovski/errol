import XCTest
@testable import ErrolKit

final class WindowHitTestingTests: XCTestCase {
    private let conversation = WindowHitRegion(number: 10, owner: 100,
                                               frame: CGRect(x: 0, y: 20, width: 700, height: 800))

    func testCoveringAppWinsOverConversationBehindIt() {
        let covering = WindowHitRegion(number: 20, owner: 200,
                                       frame: CGRect(x: 50, y: 50, width: 200, height: 200))
        let windows = [covering, conversation]
        XCTAssertEqual(frontmostWindow(at: CGPoint(x: 100, y: 100), among: windows)?.owner, 200)
        XCTAssertEqual(frontmostWindow(at: CGPoint(x: 400, y: 100), among: windows)?.number, 10)
    }

    func testOnlyTheHighlightIsIgnoredAndErrolStillBlocksADrop() {
        let highlight = WindowHitRegion(number: 30, owner: 300, frame: conversation.frame)
        let capsule = WindowHitRegion(number: 31, owner: 300,
                                      frame: CGRect(x: 100, y: 40, width: 500, height: 156))
        let windows = [capsule, highlight, conversation]
        XCTAssertEqual(frontmostWindow(at: CGPoint(x: 150, y: 80), among: windows, ignoring: [30])?.number, 31)
        XCTAssertEqual(frontmostWindow(at: CGPoint(x: 150, y: 300), among: windows, ignoring: [30])?.number, 10)
    }

    func testOverlappingWindowsOfTheSameAppKeepTheirOrder() {
        let other = WindowHitRegion(number: 11, owner: 100, frame: conversation.frame)
        XCTAssertEqual(frontmostWindow(at: CGPoint(x: 100, y: 100), among: [other, conversation])?.number, 11)
    }

    func testDesktopIsNotAWindowAndOtherDisplaysUseTheirOwnCoordinates() {
        let leftDisplay = WindowHitRegion(number: 40, owner: 100,
                                          frame: CGRect(x: -900, y: -200, width: 800, height: 700))
        let windows = [leftDisplay, conversation]
        XCTAssertEqual(frontmostWindow(at: CGPoint(x: -500, y: -100), among: windows)?.number, 40)
        XCTAssertNil(frontmostWindow(at: CGPoint(x: 900, y: 900), among: windows))
        XCTAssertNil(frontmostWindow(at: CGPoint(x: 100, y: 100), among: []))
    }
}
