// The per-operation clipboard lease: what was there comes back after the
// relay's own write, a newer copy by the human stays, and nothing is ever
// put back in part. On a private pasteboard, so the suite never touches the
// general one; skipped where the pasteboard service is unavailable, the way
// the harness's clipboard test is.

import AppKit
import XCTest
@testable import ErrolKit

final class ClipboardLeaseTests: XCTestCase {
    private var board: NSPasteboard!
    private let binary = NSPasteboard.PasteboardType("test.binary")

    override func setUpWithError() throws {
        board = NSPasteboard.withUniqueName()
        let item = NSPasteboardItem()
        item.setString("the human's copy", forType: .string)
        item.setData(Data([0, 1, 255]), forType: binary)
        guard board.writeObjects([item]), board.data(forType: binary) != nil else {
            throw XCTSkip("Named pasteboard service unavailable in this sandbox; clipboard integration requires a desktop session")
        }
    }

    override func tearDown() {
        board?.releaseGlobally()
        super.tearDown()
    }

    func testTheCaptureComesBackAfterTheLeasesOwnWrite() {
        let lease = ClipboardLease(board)
        lease.write("relayed message")
        XCTAssertTrue(lease.isOwned)
        XCTAssertEqual(lease.text, "relayed message")
        XCTAssertEqual(board.string(forType: .string), "relayed message")
        XCTAssertEqual(lease.release(), .restored)
        XCTAssertEqual(board.string(forType: .string), "the human's copy")
        XCTAssertEqual(board.data(forType: binary), Data([0, 1, 255]), "every representation comes back")
        XCTAssertEqual(lease.release(), .nothingOwned, "a second release does nothing")
    }

    func testANewerCopyByTheHumanIsPreserved() {
        let lease = ClipboardLease(board)
        lease.write("relayed message")
        board.clearContents()
        board.setString("copied meanwhile", forType: .string)
        XCTAssertFalse(lease.isOwned)
        XCTAssertNil(lease.text)
        XCTAssertEqual(lease.release(), .preservedNewer)
        XCTAssertEqual(board.string(forType: .string), "copied meanwhile")
    }

    func testAnEmptyClipboardIsRestoredToEmpty() {
        board.clearContents()
        let lease = ClipboardLease(board)
        lease.write("relayed message")
        XCTAssertEqual(lease.release(), .restored)
        XCTAssertTrue(board.pasteboardItems?.isEmpty != false)
    }

    func testAClaimedWriteIsOwnedLikeTheLeasesOwn() {
        // The copy button's write: made by the app, owned by the lease once
        // the change count has moved.
        let lease = ClipboardLease(board)
        XCTAssertFalse(lease.isOwned)
        board.clearContents()
        board.setString("the reply, copied by the app", forType: .string)
        lease.claim()
        XCTAssertTrue(lease.isOwned)
        XCTAssertEqual(lease.text, "the reply, copied by the app")
        XCTAssertEqual(lease.release(), .restored)
        XCTAssertEqual(board.string(forType: .string), "the human's copy")
    }

    func testALeaseThatNeverWroteLeavesTheClipboardAlone() {
        let lease = ClipboardLease(board)
        XCTAssertEqual(lease.release(), .nothingOwned)
        XCTAssertEqual(board.string(forType: .string), "the human's copy")
        XCTAssertEqual(board.data(forType: binary), Data([0, 1, 255]))
    }

    func testAnIncompleteCaptureIsNeverPutBackInPart() {
        // A byte limit under the capture's size marks it incomplete; the
        // lease's write then stays rather than half of the earlier contents.
        let lease = ClipboardLease(board, byteLimit: 4)
        lease.write("relayed message")
        guard case .leftInPlace(let reason) = lease.release() else {
            return XCTFail("an incomplete capture must not be restored")
        }
        XCTAssertTrue(reason.contains("exceed"))
        XCTAssertEqual(board.string(forType: .string), "relayed message")
    }

    func testTheHarnessRestorePutsTheCaptureBackRegardless() {
        let lease = ClipboardLease(board)
        board.clearContents()
        board.setString("something else entirely", forType: .string)
        XCTAssertTrue(lease.restore())
        XCTAssertEqual(board.string(forType: .string), "the human's copy")
        XCTAssertEqual(board.data(forType: binary), Data([0, 1, 255]))
    }
}
