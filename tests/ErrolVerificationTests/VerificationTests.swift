import XCTest
import AppKit
import ApplicationServices
@testable import ErrolKit
@testable import ErrolVerification

final class VerificationTests: XCTestCase {
    func testDesktopLeaseRejectsConcurrentMutationAndReleases() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try DesktopLease(path: path)
        XCTAssertThrowsError(try DesktopLease(path: path))
        first.release()
        let next = try DesktopLease(path: path)
        next.release()
    }
    func testFullSuiteCoversEverySurfaceContextAndPayload() {
        let cases = DesktopSuite.full.scenarios
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count)
        for endpoint in Endpoint.all {
            for context in [ConversationSetup.new, .existing] {
                for payload in PayloadKind.allCases {
                    XCTAssertTrue(cases.contains { $0.endpoint == endpoint && $0.conversation == context && $0.payload == payload && $0.behavior == .message })
                }
            }
            for behavior in [ScenarioBehavior.draftGuard, .attachmentGuard, .busyGuard, .background, .wrongField, .streaming] {
                XCTAssertTrue(cases.contains { $0.endpoint == endpoint && $0.behavior == behavior })
            }
        }
        XCTAssertEqual(DesktopSuite.relay.scenarios.count, 18)
        XCTAssertEqual(DesktopSuite.smoke.scenarios.count, 12)
    }

    func testPayloadBoundarySizesAndDistinctReply() {
        for cap in [1024, 12000, 64000] {
            for (kind, delta) in [(PayloadKind.belowLimit, -1), (.atLimit, 0), (.aboveLimit, 1)] {
                let text = kind.text(nonce: "case-a7", cap: cap)
                XCTAssertEqual(text.count, cap + delta)
                XCTAssertTrue(text.hasSuffix("\nTAIL-DATA"))
                XCTAssertTrue(text.contains("case-a7"))
                XCTAssertFalse(text.contains("ACK case-a7"), "Copying the prompt cannot satisfy the response contract")
            }
        }
        XCTAssertTrue(PayloadKind.leadingNewline.text(nonce: "a", cap: 12000).hasPrefix("\n\n"))
        XCTAssertTrue(PayloadKind.multiline.text(nonce: "a", cap: 12000).contains("\n\ttab\n"))
    }

    func testSafetyRefusesUnreadableDraftWhitespaceAttachmentsAndBusy() {
        XCTAssertEqual(composerSafety(value: nil, attachments: 0, busy: false).status, .inconclusive)
        XCTAssertEqual(composerSafety(value: "draft", attachments: 0, busy: false).status, .blocked)
        XCTAssertEqual(composerSafety(value: " \n", attachments: 0, busy: false).status, .blocked)
        XCTAssertEqual(composerSafety(value: "", attachments: 1, busy: false).status, .blocked)
        XCTAssertEqual(composerSafety(value: "", attachments: 0, busy: true).status, .blocked)
        XCTAssertEqual(composerSafety(value: "", attachments: 0, busy: false).status, .passed)
    }

    func testPasteComparisonRejectsTruncationDuplicationAndUnicodeNormalization() {
        XCTAssertEqual(pasteChecks(expected: "head\ntail", value: "head", before: 0, after: 0, receipt: .text).first?.status, .failed)
        XCTAssertEqual(pasteChecks(expected: "hello", value: "hellohello", before: 0, after: 0, receipt: .text).first?.status, .failed)
        XCTAssertEqual(pasteChecks(expected: "é", value: "e\u{301}", before: 0, after: 0, receipt: .text).first?.status, .failed)
        XCTAssertEqual(pasteChecks(expected: "hello", value: "", before: 0, after: 2, receipt: .attachment).first?.status, .failed)
        let attachment = pasteChecks(expected: "hello", value: "", before: 0, after: 1, receipt: .attachment)
        XCTAssertTrue(attachment.contains { $0.name == "paste-integrity" && $0.status == .inconclusive })
        XCTAssertEqual(pasteChecks(expected: "\nhello\t\n", value: "\nhello\t\n", before: 0, after: 0, receipt: .text).first?.status, .passed)
    }

    func testNoReceiptFromEmptyNeedle() {
        XCTAssertNil(observedPasteReceipt(expecting: PasteExpectation(payload: "", valueBefore: ""),
                                          composerValue: "", attachmentsBefore: 0, attachmentsNow: 0))
        XCTAssertEqual(observedPasteReceipt(expecting: PasteExpectation(payload: "\nhello", valueBefore: ""),
                                            composerValue: "\nhello", attachmentsBefore: 0, attachmentsNow: 0), .text)
    }

    func testInspectionCanRefuseBeforeAnyPasteOrSubmission() {
        relayControl.reset()
        defer { relayControl.reset() }
        let target = TargetApp(name: "Test", app: NSRunningApplication.current, ax: AXUIElementCreateApplication(getpid()), selectors: config.chatgptSelectors)
        var events: [String] = []
        var inspected = false
        let inspection = SendInspection(event: { events.append($0) }, mayContinue: { false }, inspectPaste: { _, _, _, _, _ in inspected = true; return true })
        XCTAssertEqual(send("must not be pasted", to: target, inspection: inspection), .refused)
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(inspected)
    }

    func testNoGreenForSkippedUnconfirmedManualOrMissingAssertions() {
        let scenario = DesktopSuite.smoke.scenarios[0]
        var result = CaseResult(scenario: scenario, startedAt: Date(), finishedAt: Date(),
                                checks: scenario.requiredChecks.map { .init(name: $0, status: .passed, detail: "checked") })
        XCTAssertEqual(result.status, .passed)
        result.checks.removeLast()
        XCTAssertEqual(result.status, .notRun)
        result.checks.append(.init(name: "clipboard-restored", status: .inconclusive, detail: "unobservable"))
        XCTAssertEqual(result.status, .inconclusive)
        result.checks.append(.init(name: "setup", status: .blocked, detail: "skipped"))
        XCTAssertEqual(result.status, .blocked)
        result.checks.append(.init(name: "paste-integrity", status: .failed, detail: "wrong text"))
        XCTAssertEqual(result.status, .failed)
        let manual = DesktopSuite.controls.scenarios[0]
        XCTAssertEqual(CaseResult(scenario: manual, startedAt: Date(), finishedAt: Date(), checks: manual.requiredChecks.map {
            .init(name: $0, status: .manual, detail: "operator observed")
        }).status, .manual)
    }

    func testInvalidSelectionAndArgumentValuesCannotProduceEmptyPass() throws {
        for args in [["--app", "cluade"], ["--suite", "missing"], ["--filter", "nonexistent"],
                     ["--timeout", "nan"], ["--max-chars", "1"], ["--output"], ["--live"]] {
            XCTAssertThrowsError(try VerificationOptions.parse(args), "\(args)")
        }
        let options = try VerificationOptions.parse(["--suite", "desktop-full", "--filter", "claude.code.new", "--list"])
        XCTAssertEqual(options.selected.count, PayloadKind.allCases.count)
    }

    func testReportPersistsScopeComputedResultsAndJUnitEscaping() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var report = VerificationReport(runID: "run", suite: "desktop-smoke", filter: "chatgpt.chat", totalSuiteCases: 12,
            maxCharacters: 12000, caseTimeout: 180, environment: .init(macOS: "test", revision: "abc", dirty: false, applications: [:]),
            results: [CaseResult(scenario: DesktopSuite.smoke.scenarios[0])])
        XCTAssertEqual(report.exitCode, 2)
        try report.write(to: directory)
        let data = try Data(contentsOf: directory.appendingPathComponent("report.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["complete"] as? Bool, false)
        XCTAssertEqual(json["totalSuiteCases"] as? Int, 12)
        XCTAssertEqual((json["results"] as? [[String: Any]])?.first?["status"] as? String, "notRun")
        report.results[0].checks.append(.init(name: "failure", status: .failed, detail: "<wrong> & \"quote\""))
        XCTAssertEqual(report.exitCode, 1)
        XCTAssertTrue(report.junit.contains("&lt;wrong&gt; &amp; &quot;quote&quot;"))
    }

    func testClipboardRestoresMultipleTypesAndEmptyBoard() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("original", forType: .string)
        item.setData(Data([0, 1, 255]), forType: .init("test.binary"))
        guard board.writeObjects([item]), board.data(forType: .init("test.binary")) != nil else {
            throw XCTSkip("Named pasteboard service unavailable in this sandbox; clipboard integration requires a desktop session")
        }
        let lease = ClipboardLease(board)
        board.clearContents(); board.setString("test payload", forType: .string)
        XCTAssertTrue(lease.restore())
        XCTAssertEqual(board.data(forType: .init("test.binary")), Data([0, 1, 255]))
        board.clearContents()
        let empty = ClipboardLease(board)
        board.setString("probe", forType: .string)
        XCTAssertTrue(empty.restore())
        XCTAssertTrue(board.pasteboardItems?.isEmpty != false)
    }

    func testEvidenceDoesNotCountComposerOrSidebarAsMessageBody() {
        let tree = EvidenceNode(role: "AXWindow", children: [
            EvidenceNode(role: "AXTextArea", value: "ACK case"),
            EvidenceNode(role: "AXButton", title: "ACK case"),
            EvidenceNode(role: "AXGroup", description: "User message", children: [EvidenceNode(role: "AXStaticText", value: "prompt")]),
            EvidenceNode(role: "AXGroup", description: "Assistant message", children: [EvidenceNode(role: "AXStaticText", value: "ACK case")])
        ])
        XCTAssertEqual(tree.messages.count, 2)
        XCTAssertTrue(tree.messages[0].userMessage)
        XCTAssertTrue(tree.messages[1].assistantMessage)
        XCTAssertEqual(tree.messages[1].text, "ACK case")
        XCTAssertEqual(tree.text, "prompt\nACK case")
    }

    func testRecordedClaudeMessageRolesAndToolbarTimes() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ErrolKitTests/Fixtures/claude-virtualized-conversation.json")
        let roots = try JSONDecoder().decode([EvidenceNode].self, from: Data(contentsOf: fixtures))
        let messages = roots.flatMap(\.messages)
        let last = try XCTUnwrap(messages.last)
        XCTAssertEqual(last.ordinal, 8)
        XCTAssertTrue(last.assistantMessage, "The live-captured Claude responded heading is independent role evidence")
        XCTAssertTrue(messages.first(where: { $0.ordinal == 7 })?.userMessage == true)
        XCTAssertFalse(last.text.contains("4 minutes ago"), "Toolbar metadata must not corrupt copy comparison")
        let fixtureData = try JSONSerialization.data(withJSONObject: roots.map(\.fixture))
        XCTAssertNoThrow(try JSONDecoder().decode([FixtureElement].self, from: fixtureData))
    }
}
