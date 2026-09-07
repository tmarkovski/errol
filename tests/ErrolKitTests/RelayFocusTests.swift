import XCTest
@testable import ErrolKit

final class RelayFocusTests: XCTestCase {
    func testEditorHoldsBothGatesUntilExplicitRelease() {
        let control = RelayControl()
        XCTAssertEqual(control.requestHold(), .now)
        XCTAssertTrue(control.canOpenSteering)
        control.postSteering("Keep this note.")
        for _ in 0..<3 {
            XCTAssertEqual(control.beginOperation(.capture), .hold)
            XCTAssertEqual(control.decideHandoff { _ in true }, .hold)
            XCTAssertTrue(control.hasSteering)
        }
        control.finishSteering(note: "Revised note.")
        XCTAssertEqual(control.beginOperation(.capture), .proceed)
        XCTAssertTrue(control.hasSteering, "capture must not commit a note")
        XCTAssertFalse(control.endOperation(continuingRun: true))
        XCTAssertEqual(control.decideHandoff { _ in true },
                       .commit(note: "Revised note.", unfit: nil))
        XCTAssertFalse(control.endOperation(continuingRun: true))
    }

    func testPauseDuringCaptureSteersTheCurrentHandoff() {
        let control = RelayControl()
        XCTAssertEqual(control.beginOperation(.capture), .proceed)
        XCTAssertEqual(control.requestHold(), .afterOperation)
        XCTAssertFalse(control.canOpenSteering)
        XCTAssertTrue(control.endOperation(continuingRun: true))
        XCTAssertTrue(control.canOpenSteering)
        XCTAssertEqual(control.decideHandoff { _ in true }, .hold)
        control.finishSteering(note: "Use this on the reply just copied.")
        XCTAssertEqual(control.decideHandoff { _ in true },
                       .commit(note: "Use this on the reply just copied.", unfit: nil))
        XCTAssertFalse(control.endOperation(continuingRun: true))
    }

    func testPauseDuringDeliveryCannotTakeTheCommittedNoteBack() {
        let control = RelayControl()
        control.postSteering("Already committed.")
        XCTAssertEqual(control.decideHandoff { _ in true },
                       .commit(note: "Already committed.", unfit: nil))
        let claim = control.claimSteering()
        XCTAssertNil(claim.note)
        XCTAssertEqual(claim.grant, .afterOperation)
        XCTAssertFalse(control.canOpenSteering)
        XCTAssertTrue(control.endOperation(continuingRun: true))
        XCTAssertTrue(control.canOpenSteering)
        XCTAssertEqual(control.beginOperation(.capture), .hold)
    }

    func testOpenerDoesNotConsumeTheFirstHandoffNote() {
        let control = RelayControl()
        XCTAssertEqual(control.requestHold(), .now)
        control.finishSteering(note: "First handoff only.")
        XCTAssertEqual(control.beginOperation(.delivery), .proceed)
        XCTAssertTrue(control.hasSteering)
        XCTAssertFalse(control.endOperation(continuingRun: true))
        XCTAssertEqual(control.decideHandoff { _ in true },
                       .commit(note: "First handoff only.", unfit: nil))
        XCTAssertFalse(control.endOperation(continuingRun: true))
    }

    func testStopInvalidatesPendingGrantAndNeverOpensEitherGate() {
        let control = RelayControl()
        XCTAssertEqual(control.beginOperation(.capture), .proceed)
        XCTAssertEqual(control.requestHold(), .afterOperation)
        control.postSteering("Unsent.")
        control.cancel()
        XCTAssertTrue(control.isPaused, "Stop must not transiently release the hold")
        XCTAssertFalse(control.endOperation(continuingRun: true))
        XCTAssertFalse(control.canOpenSteering)
        XCTAssertEqual(control.beginOperation(.capture), .cancel)
        XCTAssertEqual(control.decideHandoff { _ in true }, .cancel)
        XCTAssertEqual(control.requestHold(), .cancelled)
        XCTAssertEqual(control.takeSteering(), "Unsent.")
    }

    func testTerminalOperationRejectsPendingAndFreshEditorRequests() {
        for kind in [FocusOperation.capture, .delivery] {
            let control = RelayControl()
            XCTAssertEqual(control.beginOperation(kind), .proceed)
            XCTAssertEqual(control.requestHold(), .afterOperation)
            XCTAssertFalse(control.endOperation(continuingRun: false))
            XCTAssertFalse(control.hasFocusOperation)
            XCTAssertFalse(control.canOpenSteering)
            XCTAssertEqual(control.requestHold(), .cancelled)
            XCTAssertEqual(control.claimSteering().grant, .cancelled)
            XCTAssertEqual(control.beginOperation(.delivery), .cancel)
            XCTAssertEqual(control.decideHandoff { _ in true }, .cancel)
        }
    }

    func testFinishingDuringReadOnlyWaitInvalidatesAnAlreadyPostedGrant() {
        let control = RelayControl()
        XCTAssertEqual(control.beginOperation(.delivery), .proceed)
        XCTAssertEqual(control.requestHold(), .afterOperation)
        XCTAssertTrue(control.endOperation(continuingRun: true))
        control.finishRun()
        XCTAssertFalse(control.canOpenSteering, "a delayed UI grant must be ignored")
        XCTAssertEqual(control.requestHold(), .cancelled)
        control.reset()
        XCTAssertFalse(control.isPaused)
        XCTAssertFalse(control.hasFocusOperation)
        XCTAssertEqual(control.beginOperation(.capture), .proceed)
        XCTAssertFalse(control.endOperation(continuingRun: true))
    }

    func testSecondOperationCannotStartBeforeFirstCompletes() {
        let control = RelayControl()
        XCTAssertEqual(control.beginOperation(.capture), .proceed)
        control.postSteering("Keep queued.")
        XCTAssertEqual(control.beginOperation(.delivery), .hold)
        XCTAssertEqual(control.decideHandoff { _ in true }, .hold)
        XCTAssertTrue(control.hasSteering)
        XCTAssertFalse(control.endOperation(continuingRun: true))
    }

    func testCompetingHoldAndCaptureAlwaysHaveOneOwner() {
        for _ in 0..<100 {
            let control = RelayControl()
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "focus-race", attributes: .concurrent)
            group.enter()
            queue.async {
                _ = control.requestHold()
                group.leave()
            }
            group.enter()
            queue.async {
                _ = control.beginOperation(.capture)
                group.leave()
            }
            group.wait()
            XCTAssertTrue(control.isPaused)
            if control.hasFocusOperation {
                XCTAssertFalse(control.canOpenSteering)
                XCTAssertTrue(control.endOperation(continuingRun: true))
            } else {
                XCTAssertTrue(control.canOpenSteering)
            }
            XCTAssertEqual(control.beginOperation(.capture), .hold)
        }
    }

    @MainActor
    func testCompletionFenceDrainsCallbacksBeforeFreshRequestCanOpenEditor() async {
        let control = RelayControl()
        let events = RelayEventBus()
        let callback = expectation(description: "queued focus callback")
        let grant = expectation(description: "editor grant")
        let workerFinished = expectation(description: "worker completed fence")
        XCTAssertEqual(control.beginOperation(.capture), .proceed)
        events.onEvent { event in
            if case .steeringGranted = event {
                XCTAssertFalse(control.hasFocusOperation)
                XCTAssertTrue(control.canOpenSteering)
                grant.fulfill()
            }
        }
        Thread.detachNewThread {
            DispatchQueue.main.async {
                // Simulates deactivation queued by makeFrontmost. Even a
                // fresh request here must wait until the completion fence.
                XCTAssertTrue(control.hasFocusOperation)
                XCTAssertEqual(control.requestHold(), .afterOperation)
                XCTAssertFalse(control.canOpenSteering)
                callback.fulfill()
            }
            completeFocusOperation(control: control, events: events, continuingRun: true)
            XCTAssertFalse(control.hasFocusOperation)
            XCTAssertEqual(control.beginOperation(.delivery), .hold)
            workerFinished.fulfill()
        }
        await fulfillment(of: [callback, grant, workerFinished], timeout: 3)
    }
}
