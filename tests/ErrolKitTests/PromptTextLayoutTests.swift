import AppKit
import XCTest
@testable import ErrolKit

final class PromptTextLayoutTests: XCTestCase {
    private let preferred = NSFont.systemFont(ofSize: 20.9)
    private let minimum: CGFloat = 16.5

    func testShrinksBeforeWrappingAndRestoresWhenTextIsDeleted() {
        let layout = PromptTextLayout()
        let draft = "Compare pricing by seat and usage"
        let width = (draft as NSString).size(withAttributes: [.font: preferred]).width * 0.9
        let fitted = layout.fittedFont(for: draft, width: width,
                                       preferred: preferred, minimumSize: minimum)
        XCTAssertLessThan(fitted.pointSize, preferred.pointSize)
        XCTAssertGreaterThan(fitted.pointSize, minimum)
        let height = layout.textHeight(NSAttributedString(string: draft, attributes: [.font: fitted]),
                                       width: width)
        XCTAssertLessThanOrEqual(height, ceil(NSLayoutManager().defaultLineHeight(for: fitted)))
        XCTAssertEqual(layout.fittedFont(for: "Compare", width: width,
                                         preferred: preferred, minimumSize: minimum), preferred)
    }

    func testLongPasteWrapsAtMinimumAndKeepsAllContent() {
        let layout = PromptTextLayout()
        let draft = String(repeating: "Compare the options and explain the tradeoffs. ", count: 100)
        let fitted = layout.fittedFont(for: draft, width: 450,
                                       preferred: preferred, minimumSize: minimum)
        XCTAssertEqual(fitted.pointSize, minimum)
        let height = layout.textHeight(NSAttributedString(string: draft, attributes: [.font: fitted]),
                                       width: 450)
        XCTAssertGreaterThan(height, NSLayoutManager().defaultLineHeight(for: fitted) * 3)
    }

    func testTrailingNewlineIncludesEmptyCaretLine() {
        let layout = PromptTextLayout()
        func height(_ text: String) -> CGFloat {
            layout.textHeight(NSAttributedString(string: text, attributes: [.font: preferred]), width: 450)
        }
        XCTAssertGreaterThan(height("A note\n"), height("A note"))
        XCTAssertGreaterThan(height("A note\n\n"), height("A note\n"))
    }

    func testFitsFallbackGlyphsAndRespondsToWidthChanges() {
        let layout = PromptTextLayout()
        for draft in ["一起比较这些方案的优点和缺点", "Plan 👩🏽‍💻 👨‍👩‍👧‍👦 café — مرحبا بالعالم", "WWWWWWWWWWWWWWWWWWWW"] {
            let width = (draft as NSString).size(withAttributes: [.font: preferred]).width * 0.9
            let fitted = layout.fittedFont(for: draft, width: width,
                                           preferred: preferred, minimumSize: minimum)
            XCTAssertGreaterThanOrEqual(fitted.pointSize, minimum)
            XCTAssertLessThan(fitted.pointSize, preferred.pointSize)
            XCTAssertLessThanOrEqual((draft as NSString).size(withAttributes: [.font: fitted]).width, width)
            XCTAssertEqual(layout.fittedFont(for: draft, width: width * 2,
                                             preferred: preferred, minimumSize: minimum), preferred)
        }
    }

    func testEmptyAndUnmeasuredEditorsKeepPreferredSize() {
        let layout = PromptTextLayout()
        for width: CGFloat in [0, .infinity, 450] {
            XCTAssertEqual(layout.fittedFont(for: "", width: width,
                                             preferred: preferred, minimumSize: minimum), preferred)
        }
        XCTAssertEqual(layout.fittedFont(for: "A long draft", width: 10,
                                         preferred: preferred, minimumSize: nil), preferred)
    }
}
