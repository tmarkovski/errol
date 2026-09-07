import XCTest
@testable import ErrolKit

final class TransferFeedbackTests: XCTestCase {
    private var replyAnchor: TransferAnchor {
        TransferAnchor(frame: CGRect(x: 150, y: 200, width: 30, height: 20),
                       window: CGRect(x: 100, y: 100, width: 600, height: 800), pid: 1)!
    }

    func testFreshSteeringAddsSecondSourceButEchoDoesNot() {
        var payload = HandoffPayload(from: "Claude", intro: false, echo: "Earlier note", note: nil)
        XCTAssertEqual(payload.transferSources(reply: replyAnchor), [.captured(replyAnchor)])
        payload.note = "New direction"
        XCTAssertEqual(payload.transferSources(reply: replyAnchor), [.captured(replyAnchor), .userPrompt])
        XCTAssertEqual(payload.transferSources(reply: nil), [.userPrompt],
                       "A missing copy-button frame must not hide the human note's flight")
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
            XCTAssertEqual(payload.transferSources(reply: replyAnchor), [.captured(replyAnchor)])
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
        let native = TransferAnchor(frame: replyAnchor.frame, window: replyAnchor.window,
                                    pid: 7, windowID: 42)!
        let resized = CGRect(x: 100, y: 130, width: 600, height: 770)
        XCTAssertTrue(native.matchesWindow(id: 42, pid: 7, frame: resized))
        XCTAssertFalse(native.matchesWindow(id: 43, pid: 7, frame: resized))
        XCTAssertFalse(native.matchesWindow(id: 42, pid: 8, frame: resized))
        XCTAssertFalse(replyAnchor.matchesWindow(id: 42, pid: 1, frame: resized),
                       "External windows still require the captured frame to match")
    }

    func testArrivalWithoutPasteNeverHighlightsAndTimesOut() {
        let timing = TransferTiming(startedAt: 10, travels: true, reducedMotion: false)
        XCTAssertEqual(timing.progress(at: 11), 1)
        XCTAssertNil(timing.arrivalAge(at: 11), "Finishing the flight is not evidence of a paste")
        XCTAssertTrue(timing.isFinished(at: 13))
    }

    func testEarlyPasteWaitsForFlightBeforeDissolving() {
        var timing = TransferTiming(startedAt: 10, travels: true, reducedMotion: false)
        timing.confirmPaste(at: 10.1)
        XCTAssertNil(timing.arrivalAge(at: 10.3))
        XCTAssertEqual(timing.arrivalAge(at: 10.6)!, 0.05, accuracy: 0.001)
        XCTAssertTrue(timing.isFinished(at: 11.6))
    }

    func testLatePasteStartsHighlightAtReceiptAndFrameRefreshDoesNotRestartIt() {
        var timing = TransferTiming(startedAt: 10, travels: true, reducedMotion: false)
        XCTAssertNil(timing.arrivalAge(at: 11))
        timing.confirmPaste(at: 11.2)
        timing.confirmPaste(at: 11.5)
        XCTAssertEqual(timing.arrivalAge(at: 11.6)!, 0.4, accuracy: 0.001)
    }

    func testReducedMotionAndMissingSourceStillRequirePaste() {
        for timing in [TransferTiming(startedAt: 10, travels: true, reducedMotion: true),
                       TransferTiming(startedAt: 10, travels: false, reducedMotion: false)] {
            var timing = timing
            XCTAssertEqual(timing.flightDuration, 0)
            XCTAssertNil(timing.arrivalAge(at: 10.1))
            timing.confirmPaste(at: 10.1)
            XCTAssertEqual(timing.arrivalAge(at: 10.1), 0)
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

    func testVisibleCopyButtonKeepsItsExactSource() {
        XCTAssertEqual(replyTransferAnchor(copyFrame: replyAnchor.frame,
                                            window: replyAnchor.window, pid: replyAnchor.pid,
                                            screens: [CGRect(x: 0, y: 0, width: 1440, height: 1000)]),
                       replyAnchor)
    }

    func testMissingOrScrolledCopyGeometryLaunchesFromWindowCenter() throws {
        let window = replyAnchor.window
        for copyFrame in [nil, CGRect.zero,
                          CGRect(x: 150, y: 1100, width: 30, height: 20),
                          CGRect(x: 150, y: 890, width: 30, height: 20),
                          CGRect(x: CGFloat.infinity, y: 200, width: 30, height: 20)] {
            let source = try XCTUnwrap(replyTransferAnchor(copyFrame: copyFrame, window: window, pid: 1))
            XCTAssertEqual(source.frame.midX, window.midX)
            XCTAssertEqual(source.frame.midY, window.midY)
            XCTAssertTrue(window.contains(source.frame))
            let payload = HandoffPayload(from: "Claude", intro: false, echo: nil, note: nil)
            XCTAssertEqual(payload.transferSources(reply: source), [.captured(source)],
                           "Missing button geometry must still produce the reply's flight")
        }
    }

    func testOffDisplayCopyFallsBackToVisibleWindowPortion() throws {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 1000)
        let window = CGRect(x: -700, y: 100, width: 1000, height: 800)
        let copyFrame = CGRect(x: -600, y: 200, width: 30, height: 20)
        // The copy button is inside its window but outside the display.
        let source = try XCTUnwrap(replyTransferAnchor(copyFrame: copyFrame, window: window,
                                                        pid: 1, screens: [screen]))
        XCTAssertEqual(source.frame.midX, 150)
        XCTAssertEqual(source.frame.midY, 500)
        XCTAssertTrue(screen.contains(source.frame))
        XCTAssertEqual(source.window, window, "Keep the real window identity for visibility checks")
    }

    func testFallbackHandlesNegativeDisplaysAndMonitorGaps() throws {
        let left = CGRect(x: -1000, y: -200, width: 800, height: 1000)
        let right = CGRect(x: 0, y: 0, width: 1440, height: 1000)
        let window = CGRect(x: -400, y: 100, width: 500, height: 500)
        let source = try XCTUnwrap(replyTransferAnchor(copyFrame: nil, window: window,
                                                        pid: 1, screens: [left, right]))
        XCTAssertEqual(source.frame.midX, -300, "Choose the largest visible portion, not the monitor gap")
        XCTAssertEqual(source.frame.midY, 350)
        XCTAssertTrue(left.contains(source.frame))
    }

    func testMissingVisibleWindowDoesNotInventAnAnimationSource() {
        XCTAssertNil(replyTransferAnchor(copyFrame: nil, window: .zero, pid: 1))
        XCTAssertNil(replyTransferAnchor(copyFrame: nil, window: replyAnchor.window, pid: 1, screens: []))
        XCTAssertNil(replyTransferAnchor(copyFrame: nil, window: replyAnchor.window, pid: 1,
                                         screens: [CGRect(x: 2000, y: 0, width: 1440, height: 1000)]))
    }
}
