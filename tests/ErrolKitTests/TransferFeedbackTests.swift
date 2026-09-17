import XCTest
@testable import ErrolKit

final class TransferFeedbackTests: XCTestCase {
    private var chatAnchor: TransferAnchor {
        TransferAnchor(frame: CGRect(x: 150, y: 200, width: 30, height: 20),
                       window: CGRect(x: 100, y: 100, width: 600, height: 800), pid: 1)!
    }

    func testTheReplyLeavesItsSendersIconAndFreshSteeringAddsASecondSourceButEchoDoesNot() {
        var payload = HandoffPayload(from: "Claude", intro: false, echo: "Earlier note", note: nil)
        XCTAssertEqual(payload.transferSources(from: .claude), [.reply(.claude)])
        XCTAssertEqual(payload.transferSources(from: .chatgpt), [.reply(.chatgpt)])
        payload.note = "New direction"
        XCTAssertEqual(payload.transferSources(from: .claude), [.reply(.claude), .userPrompt])
    }

    func testRejectedOrWithdrawnNoteHasNoHumanFlight() {
        for withdraw in [false, true] {
            let control = RelayControl()
            control.postSteering("A direction")
            if withdraw { _ = control.takeSteering() }
            guard case .commit(let note, _) = control.decideHandoff(carries: { _ in false }) else {
                return XCTFail("The handoff should proceed without the note")
            }
            let payload = HandoffPayload(from: "Claude", intro: false, echo: nil, note: note)
            XCTAssertEqual(payload.transferSources(from: .claude), [.reply(.claude)])
        }
    }

    func testBothDotsMeetAtTheSameTimeDespiteDifferentDistances() {
        let destination = CGPoint(x: 1000, y: 100)
        let paths = [TransferTrajectory(start: CGPoint(x: 100, y: 500), end: destination),
                     TransferTrajectory(start: CGPoint(x: 740, y: 700), end: destination, lane: 1)]
        let timing = TransferTiming(startedAt: 10, travels: true, reducedMotion: false)
        let mid = timing.progress(at: 10.275)
        XCTAssertNotEqual(paths[0].point(at: mid), paths[1].point(at: mid))
        for path in paths {
            XCTAssertEqual(path.point(at: timing.progress(at: 10)), path.start)
            XCTAssertEqual(path.point(at: timing.progress(at: 10.56)), destination)
        }
    }

    func testNativePromptWindowCanResizeDuringFlightWithoutMatchingAnotherWindow() {
        let native = TransferAnchor(frame: chatAnchor.frame, window: chatAnchor.window,
                                    pid: 7, windowID: 42)!
        let resized = CGRect(x: 100, y: 130, width: 600, height: 770)
        XCTAssertTrue(native.matchesWindow(id: 42, pid: 7, frame: resized))
        XCTAssertFalse(native.matchesWindow(id: 43, pid: 7, frame: resized))
        XCTAssertFalse(native.matchesWindow(id: 42, pid: 8, frame: resized))
        XCTAssertFalse(chatAnchor.matchesWindow(id: 42, pid: 1, frame: resized),
                       "External windows still require the captured frame to match")
    }

    func testTheLightPlaysOnArrivalAndThePasteWaitsForItToFade() {
        let timing = TransferTiming(startedAt: 10, travels: true, reducedMotion: false)
        XCTAssertEqual(timing.progress(at: 11), 1)
        XCTAssertNil(timing.arrivalAge(at: 10.3), "The prompt does not light before the dot lands")
        XCTAssertEqual(timing.arrivalAge(at: 10.6)!, 0.05, accuracy: 0.001)
        XCTAssertEqual(timing.pasteTime, 11.5, accuracy: 0.001,
                       "The paste waits for the whole light, so the border it traced does not move under it")
        XCTAssertFalse(timing.isFinished(at: 11.49))
        XCTAssertTrue(timing.isFinished(at: 11.5))
    }

    func testReducedMotionAndMissingSourceLightAtOnceAndStillWaitForTheLight() {
        for timing in [TransferTiming(startedAt: 10, travels: true, reducedMotion: true),
                       TransferTiming(startedAt: 10, travels: false, reducedMotion: false)] {
            XCTAssertEqual(timing.flightDuration, 0)
            XCTAssertEqual(timing.progress(at: 10), 1)
            XCTAssertEqual(timing.arrivalAge(at: 10), 0)
            XCTAssertEqual(timing.pasteTime, 10.95, accuracy: 0.001)
        }
    }

    func testOffWindowAndInvalidFramesAreRejectedButNegativeDisplayCoordinatesWork() {
        let window = CGRect(x: -1200, y: -300, width: 800, height: 900)
        XCTAssertNotNil(TransferAnchor(frame: CGRect(x: -1150, y: 400, width: 600, height: 80),
                                       window: window, pid: 1))
        for frame in [CGRect.zero, CGRect(x: -1150, y: 800, width: 600, height: 80),
                      CGRect(x: CGFloat.infinity, y: 0, width: 50, height: 50)] {
            XCTAssertNil(TransferAnchor(frame: frame, window: window, pid: 1))
        }
    }

    /// The window server's account of a 2560 × 1348 window under Stage
    /// Manager (live Sep 17 2026): parked in the strip, on its way to the
    /// stage, and there. AX reports the last of these throughout.
    func testAWindowParkedOrChangingPlacesUnderStageManagerIsNotShowing() throws {
        let window = CGRect(x: 0, y: 30, width: 2560, height: 1348)
        let anchor = try XCTUnwrap(TransferAnchor(frame: CGRect(x: 900, y: 1200, width: 700, height: 60),
                                                  window: window, pid: 7))
        func listed(_ frame: CGRect, owner: Int32 = 7) -> [WindowHitRegion] {
            [WindowHitRegion(number: 3, owner: 9, frame: window),
             WindowHitRegion(number: 1011, owner: owner, frame: frame)]
        }
        XCTAssertFalse(isShowing(anchor, among: listed(CGRect(x: -307, y: 747, width: 205, height: 156))))
        XCTAssertFalse(isShowing(anchor, among: listed(CGRect(x: 23, y: 73, width: 2306, height: 1287))))
        XCTAssertTrue(isShowing(anchor, among: listed(CGRect(x: -1, y: 30, width: 2561, height: 1348))),
                      "The swap's last frames land within the rounding between AX and the window server")
        XCTAssertFalse(isShowing(anchor, among: listed(window, owner: 8)),
                       "Another app's window at the same frame is not this one")
    }

    func testTheFlightWaitsForItsWindowToArriveAndGivesUpOnOneThatDoesNot() throws {
        let window = CGRect(x: 0, y: 30, width: 2560, height: 1348)
        let anchor = try XCTUnwrap(TransferAnchor(frame: CGRect(x: 900, y: 1200, width: 700, height: 60),
                                                  window: window, pid: 7))
        var swap = [CGRect(x: -55, y: 602, width: 555, height: 403),
                    CGRect(x: 58, y: 127, width: 2050, height: 1203), window]
        var reads = 0
        XCTAssertTrue(awaitArrival(of: anchor, onScreen: {
            reads += 1
            return [WindowHitRegion(number: 1011, owner: 7, frame: swap.count > 1 ? swap.removeFirst() : swap[0])]
        }, isCancelled: { false }))
        XCTAssertEqual(reads, 3)

        let parked = [WindowHitRegion(number: 1011, owner: 7, frame: CGRect(x: -307, y: 747, width: 205, height: 156))]
        XCTAssertFalse(awaitArrival(of: anchor, within: 0.1, onScreen: { parked }, isCancelled: { false }))
        var asked = 0
        XCTAssertFalse(awaitArrival(of: anchor, within: 5, onScreen: { asked += 1; return parked },
                                    isCancelled: { true }), "Stop ends the wait")
        XCTAssertEqual(asked, 1)
    }
}
