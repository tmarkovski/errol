// The label heuristic's order, on both sides. The live axLabel cannot be
// exercised without a running app, but the order it reads in is the
// axLabelAttributes constant, which captureSubtree also zips the fixture keys
// against. So this pins that constant and the order FixtureElement.label joins
// a capture's keys in to the same sequence, which every fixture-based test
// relies on.

import ApplicationServices
import Foundation
import XCTest
@testable import ErrolKit

final class FixtureElementTests: XCTestCase {
    func testLabelJoinsDescriptionTitleHelpAndAXLabelInOrder() throws {
        let json = #"{"role": "AXButton", "description": "d", "title": "t", "help": "h", "label": "l"}"#
        let node = try JSONDecoder().decode(FixtureElement.self, from: Data(json.utf8))
        XCTAssertEqual(node.label, "d t h l")
        XCTAssertEqual(axLabelAttributes, [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute, "AXLabel"])
    }
}
