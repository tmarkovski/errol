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

    func testCapturedChatGPTScrollingPromptStopsAtItsImmediateGroup() throws {
        // User capture, 2026-09-07: no AXScrollArea; the text document extends
        // above and below the composer, whose action buttons are direct children.
        let capturedWindow = CGRect(x: 0, y: 34, width: 855, height: 1017)
        let capturedShell = CGRect(x: 60, y: 727, width: 736, height: 308)
        let input = Node(role: "AXTextArea", label: "Do anything",
                         bounds: CGRect(x: 72, y: 289, width: 712, height: 762))
        let composer = Node(bounds: capturedShell, children: [
            input,
            Node(role: "AXButton", label: "Add files and more",
                 bounds: CGRect(x: 68, y: 999, width: 28, height: 28)),
            Node(role: "AXPopUpButton", label: "Change permissions",
                 bounds: CGRect(x: 101, y: 999, width: 127, height: 28)),
            Node(role: "AXPopUpButton", label: "GPT-5.6 Sol Medium",
                 bounds: CGRect(x: 560, y: 999, width: 164, height: 28)),
            Node(role: "AXButton", label: "Dictate",
                 bounds: CGRect(x: 724, y: 999, width: 28, height: 28)),
            Node(role: "AXButton", label: "Send",
                 bounds: CGRect(x: 760, y: 999, width: 28, height: 28))
        ])
        let parent2 = Node(bounds: capturedShell, children: [composer])
        let parent3 = Node(bounds: capturedShell, children: [parent2])
        let parent4 = Node(bounds: CGRect(x: 44, y: 727, width: 768, height: 308), children: [parent3])
        let parent5 = Node(bounds: CGRect(x: 1, y: 727, width: 854, height: 324), children: [parent4])
        let pane = Node(bounds: CGRect(x: 1, y: 81, width: 854, height: 970), children: [parent5])
        try withExtendedLifetime(pane) {
            // First frame is captured. Also cover a longer document scrolled
            // off-window, and the original document scrolled back to its top.
            for (top, height) in [(289.0, 762.0), (-200.0, 1500.0), (739.0, 762.0)] {
                input.bounds = CGRect(x: 72, y: top, width: 712, height: height)
                let geometry = try XCTUnwrap(promptTransferGeometry(
                    around: input, window: capturedWindow, selectors: Config().chatgptSelectors,
                    parent: { $0.parent }, frame: { $0.bounds }))
                XCTAssertEqual(geometry.shell, capturedShell)
                // The landing area ends above the toolbar, not at the bottom
                // of the long text document or the surrounding conversation.
                let visibleTop = max(top, capturedShell.minY)
                XCTAssertEqual(geometry.editor,
                               CGRect(x: 72, y: visibleTop, width: 712, height: 999 - visibleTop))
            }
        }
    }

    func testUnframedOrHiddenControlsCannotJustifyClippingAnOverflowingGroup() {
        let narrowShell = CGRect(x: 138, y: 680, width: 674, height: 100)
        for buttonFrame in [nil, CGRect(x: 160, y: 750, width: 0, height: 28),
                            CGRect(x: 160, y: 790, width: 28, height: 28)] as [CGRect?] {
            let input = Node(role: "AXTextArea", bounds: CGRect(x: 150, y: -200, width: 650, height: 940))
            let composer = Node(bounds: narrowShell, children: [
                input, Node(role: "AXPopUpButton", label: "main"),
                Node(role: "AXButton", label: "Add files and more", bounds: buttonFrame),
                Node(role: "AXButton", label: "Send", bounds: buttonFrame)
            ])
            withExtendedLifetime(composer) {
                XCTAssertNil(promptTransferGeometry(around: input, window: window,
                    selectors: Config().chatgptSelectors, parent: { $0.parent }, frame: { $0.bounds }))
            }
        }
    }

    func testOffWindowTextWithoutViewportEvidenceCannotProduceALandingPoint() {
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
