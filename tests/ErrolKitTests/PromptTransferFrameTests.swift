import XCTest
@testable import ErrolKit

final class PromptTransferFrameTests: XCTestCase {
    private let window = CGRect(x: 100, y: 100, width: 800, height: 800)
    private let editor = CGRect(x: 150, y: 700, width: 650, height: 40)
    private let shell = CGRect(x: 130, y: 680, width: 710, height: 100)

    func testChatGPTEmptyPromptIncludesModelAndToolbarWithoutSend() {
        let input = Node(role: "AXTextArea", bounds: editor)
        let composer = Node(bounds: shell, children: [input, Node(role: "AXPopUpButton")])
        XCTAssertEqual(resolve(input, in: composer), shell)
    }

    func testClaudeNestedEditorResolvesTheShellContainingSend() {
        let input = Node(role: "AXTextArea", bounds: editor)
        let scroll = Node(role: "AXScrollArea", bounds: editor, children: [input])
        let inner = Node(bounds: editor.insetBy(dx: -4, dy: -4), children: [scroll])
        let composer = Node(bounds: shell, children: [inner, Node(role: "AXButton", label: "Send")])
        XCTAssertEqual(resolve(input, in: composer, selectors: Config().claudeSelectors), shell)
    }

    func testClaudeCodeStopsAtPromptBeforeRepositoryControlsAndConversation() {
        let input = Node(role: "AXTextArea", bounds: editor)
        let inner = Node(bounds: editor, children: [input])
        let compact = editor.insetBy(dx: -12, dy: -8)
        let composer = Node(bounds: compact, children: [inner, Node(role: "AXButton", label: "Stop")])
        let pane = Node(bounds: window, children: [composer, Node(role: "AXPopUpButton", label: "main")])
        XCTAssertEqual(resolve(input, in: pane, selectors: Config().claudeSelectors), compact)
    }

    func testOutlineTracksGrowthAndCollapseIncludingAttachmentRow() {
        let input = Node(role: "AXTextArea", bounds: editor)
        let composer = Node(bounds: shell, children: [input, Node(role: "AXButton", label: "Send")])
        XCTAssertEqual(resolve(input, in: composer), shell)
        input.bounds = CGRect(x: 150, y: 500, width: 650, height: 240)
        composer.bounds = CGRect(x: 130, y: 380, width: 710, height: 400)
        XCTAssertEqual(resolve(input, in: composer), composer.bounds)
        input.bounds = editor
        composer.bounds = shell
        XCTAssertEqual(resolve(input, in: composer), shell)
    }

    func testMissingPromptControlsDoesNotPromoteTheWholeConversation() {
        let input = Node(role: "AXTextArea", bounds: editor)
        let inner = Node(bounds: editor.insetBy(dx: -4, dy: -4), children: [input])
        let pane = Node(bounds: window, children: [inner, Node(role: "AXButton", label: "Send feedback")])
        XCTAssertNil(resolve(input, in: pane, selectors: Config().claudeSelectors))
    }

    func testLongPromptUsesItsScrollViewportInsteadOfTheFullTextHeight() {
        let viewport = CGRect(x: 150, y: 500, width: 650, height: 240)
        let expandedShell = CGRect(x: 130, y: 480, width: 710, height: 300)
        for top in [150.0, -200.0] {
            let input = Node(role: "AXTextArea",
                             bounds: CGRect(x: 150, y: top, width: 650, height: 740 - top))
            let scroll = Node(role: "AXScrollArea", bounds: viewport, children: [input])
            let composer = Node(bounds: expandedShell,
                                children: [scroll, Node(role: "AXButton", label: "Send")])
            XCTAssertEqual(resolve(input, in: composer), expandedShell)
            withExtendedLifetime(composer) {
                let geometry = promptTransferGeometry(around: input, window: window,
                                                       selectors: Config().chatgptSelectors,
                                                       parent: { $0.parent }, frame: { $0.bounds })
                XCTAssertEqual(geometry?.editor, viewport,
                               "The dot must land in the visible viewport, not the full document")
            }
        }
    }

    func testOffWindowTextWithoutScrollEvidenceCannotProduceALandingPoint() {
        let input = Node(role: "AXTextArea", bounds: CGRect(x: 150, y: -200, width: 650, height: 940))
        let composer = Node(bounds: shell, children: [input, Node(role: "AXButton", label: "Send")])
        withExtendedLifetime(composer) {
            XCTAssertNil(promptTransferGeometry(around: input, window: window,
                                                selectors: Config().chatgptSelectors,
                                                parent: { $0.parent }, frame: { $0.bounds }))
        }
    }

    func testFullDocumentWrapperDoesNotHideTheScrollViewport() {
        let input = Node(role: "AXTextArea", bounds: CGRect(x: 150, y: -200, width: 650, height: 940))
        let document = Node(bounds: input.bounds, children: [input])
        let scroll = Node(role: "AXScrollArea", bounds: editor, children: [document])
        let composer = Node(bounds: shell, children: [scroll, Node(role: "AXButton", label: "Send")])
        XCTAssertEqual(resolve(input, in: composer), shell)
    }

    func testTextOutsideItsScrollViewportDoesNotProduceAnOutline() {
        let input = Node(role: "AXTextArea", bounds: CGRect(x: 150, y: 200, width: 650, height: 40))
        let scroll = Node(role: "AXScrollArea", bounds: editor, children: [input])
        let composer = Node(bounds: shell, children: [scroll, Node(role: "AXButton", label: "Send")])
        XCTAssertNil(resolve(input, in: composer))
    }

    func testMissingWrapperGeometryCanBeSkippedButOffWindowShellIsRejected() {
        let input = Node(role: "AXTextArea", bounds: editor)
        let inner = Node(children: [input])
        let composer = Node(bounds: shell, children: [inner, Node(role: "AXButton", label: "Dictate")])
        XCTAssertEqual(resolve(input, in: composer), shell)
        composer.bounds = CGRect(x: 130, y: 680, width: 810, height: 100)
        XCTAssertNil(resolve(input, in: composer))
    }

    func testWindowAndWebAreaAreNeverPromptShells() {
        for role in ["AXWindow", "AXWebArea"] {
            let input = Node(role: "AXTextArea", bounds: editor)
            let root = Node(role: role, bounds: shell, children: [input, Node(role: "AXButton", label: "Send")])
            XCTAssertNil(resolve(input, in: root))
        }
    }

    func testPromptShellNeverMovesTheDotOutOfTheEditor() throws {
        let anchor = try XCTUnwrap(TransferAnchor(frame: editor, window: window, pid: 1, promptFrame: shell))
        XCTAssertEqual(anchor.frame, editor)
        XCTAssertEqual(anchor.promptFrame, shell)
        let invalid = TransferAnchor(frame: editor, window: window, pid: 1,
                                     promptFrame: CGRect(x: 200, y: 200, width: 100, height: 100))
        XCTAssertNotNil(invalid, "Bad shell geometry must not suppress a valid flight")
        XCTAssertNil(invalid?.promptFrame)
    }

    private func resolve(_ input: Node, in root: Node,
                         selectors: AppSelectors = Config().chatgptSelectors) -> CGRect? {
        // Keep the entire tree alive while walking weak parent references.
        withExtendedLifetime(root) {
            promptTransferGeometry(around: input, window: window, selectors: selectors,
                                   parent: { $0.parent }, frame: { $0.bounds })?.shell
        }
    }
}

private final class Node: ElementNode {
    let role: String?
    let label: String
    var bounds: CGRect?
    weak var parent: Node?
    let children: [Node]
    var title: String? { nil }
    var stringValue: String? { nil }
    var numberValue: Int? { nil }
    var url: URL? { nil }

    init(role: String = "AXGroup", label: String = "", bounds: CGRect? = nil, children: [Node] = []) {
        self.role = role
        self.label = label
        self.bounds = bounds
        self.children = children
        for child in children { child.parent = self }
    }
}
