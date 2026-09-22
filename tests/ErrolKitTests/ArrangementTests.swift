// The pure half of window arrangement: the frames each layout gives two
// windows, and the two judgements a restore and a fit check rest on.

import XCTest
@testable import ErrolKit

final class ArrangementTests: XCTestCase {
    private let area = CGRect(x: 0, y: 25, width: 1440, height: 875)

    func testSideBySideSplitsTheWidthAndKeepsTheHeight() throws {
        let frames = try XCTUnwrap(layoutFrames(.sideBySide, in: area))
        XCTAssertEqual(frames.first, CGRect(x: 0, y: 25, width: 720, height: 875))
        XCTAssertEqual(frames.second, CGRect(x: 720, y: 25, width: 720, height: 875))
    }

    func testStackedSplitsTheHeightAndKeepsTheWidth() throws {
        let frames = try XCTUnwrap(layoutFrames(.stacked, in: area))
        XCTAssertEqual(frames.first, CGRect(x: 0, y: 25, width: 1440, height: 437))
        XCTAssertEqual(frames.second, CGRect(x: 0, y: 462, width: 1440, height: 438),
                       "the odd point goes to the second window, so nothing is left uncovered")
    }

    func testFullScreenGivesBothWindowsTheWholeArea() throws {
        let frames = try XCTUnwrap(layoutFrames(.fullScreen, in: area))
        XCTAssertEqual(frames.first, area)
        XCTAssertEqual(frames.second, area, "one over the other; the app being written to comes forward")
        XCTAssertTrue(LayoutChoice.fullScreen.movesWindows)
    }

    func testAnOddWidthLeavesNoGap() throws {
        let frames = try XCTUnwrap(layoutFrames(.sideBySide, in: CGRect(x: 10, y: 0, width: 1001, height: 600)))
        XCTAssertEqual(frames.first.maxX, frames.second.minX)
        XCTAssertEqual(frames.second.maxX, 1011)
    }

    func testKeepPositionsMovesNothing() {
        XCTAssertNil(layoutFrames(.keepPositions, in: area))
        XCTAssertFalse(LayoutChoice.keepPositions.movesWindows)
        XCTAssertTrue(LayoutChoice.stacked.movesWindows)
    }

    func testAWindowHeldLargerThanAskedDidNotTakeTheFrame() {
        let asked = CGRect(x: 0, y: 0, width: 640, height: 875)
        XCTAssertTrue(windowTookFrame(CGRect(x: 0, y: 0, width: 642, height: 875), asked: asked),
                      "a couple of points of rounding is the frame taken")
        XCTAssertFalse(windowTookFrame(CGRect(x: 0, y: 0, width: 800, height: 875), asked: asked),
                       "a minimum width above the half is the layout not fitting")
        XCTAssertTrue(windowTookFrame(CGRect(x: 0, y: 0, width: 600, height: 875), asked: asked),
                      "smaller than asked is the app's own clamp, not a refusal")
    }

    func testARestoreLeavesAWindowTheHumanMovedSince() {
        let applied = CGRect(x: 0, y: 25, width: 720, height: 875)
        XCTAssertTrue(windowStandsWhereLeft(applied.offsetBy(dx: 2, dy: -1), applied: applied))
        XCTAssertFalse(windowStandsWhereLeft(applied.offsetBy(dx: 120, dy: 0), applied: applied))
        XCTAssertFalse(windowStandsWhereLeft(CGRect(x: 0, y: 25, width: 900, height: 875), applied: applied))
    }
}
