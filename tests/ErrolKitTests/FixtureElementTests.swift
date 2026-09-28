// The recorded side of the label heuristic. The live axLabel joins
// axLabelAttributes in order and cannot be exercised without a running app,
// so this pins the order FixtureElement.label joins a capture's keys in,
// which every fixture-based test relies on matching it.

import Foundation
import XCTest
@testable import ErrolKit

final class FixtureElementTests: XCTestCase {
    func testLabelJoinsDescriptionTitleHelpAndAXLabelInOrder() throws {
        let json = #"{"role": "AXButton", "description": "d", "title": "t", "help": "h", "label": "l"}"#
        let node = try JSONDecoder().decode(FixtureElement.self, from: Data(json.utf8))
        XCTAssertEqual(node.label, "d t h l")
    }
}
