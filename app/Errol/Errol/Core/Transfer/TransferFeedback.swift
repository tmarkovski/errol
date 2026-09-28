// What crosses from the relay worker to the transfer overlay: the anchor a
// flight aims at and the wait for its window, the events, the path and clock.

import AppKit
import ApplicationServices
import Foundation

/// Geometry crosses the event stream, never live AX elements. Coordinates
/// use AX's top-left origin; the overlay converts them on the main thread.
struct TransferAnchor {
    let frame: CGRect
    /// The receiving composer shell, separate from the text field where
    /// the dot lands. Sources and unrecognized prompt layouts have no shell.
    let promptFrame: CGRect?
    let window: CGRect
    let pid: pid_t
    /// Native Errol panels can resize as their editor closes. Their window
    /// identity remains valid after launch even when that layout changes.
    let windowID: CGWindowID?

    init?(frame: CGRect, window: CGRect, pid: pid_t, windowID: CGWindowID? = nil,
          promptFrame: CGRect? = nil) {
        guard isUsableRect(frame, within: window) else { return nil }
        self.frame = frame
        self.promptFrame = promptFrame.flatMap {
            isUsableRect($0, within: window) && $0.contains(frame) ? $0 : nil
        }
        self.window = window
        self.pid = pid
        self.windowID = windowID
    }

    func matchesWindow(id: CGWindowID, pid: pid_t, frame: CGRect) -> Bool {
        guard self.pid == pid else { return false }
        if let windowID { return windowID == id }
        return frame.nearlyEquals(window)
    }
}

/// A rect that can be drawn at: every coordinate finite, and some width and
/// height to it.
func isUsableRect(_ rect: CGRect) -> Bool {
    [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
        && rect.width > 0 && rect.height > 0
}

/// A usable rect wholly inside another usable one: an anchor's frame inside
/// its window, or a candidate for the prompt inside the group it came from.
func isUsableRect(_ rect: CGRect, within outer: CGRect) -> Bool {
    isUsableRect(rect) && isUsableRect(outer) && outer.contains(rect)
}

/// Called on the relay worker, where all other reads of the target occur.
/// Missing or off-window geometry only suppresses decoration.
func transferAnchor(for element: AXUIElement?, in target: TargetApp) -> TransferAnchor? {
    guard let element,
          let windowValue = axAttribute(element, kAXWindowAttribute),
          CFGetTypeID(windowValue) == AXUIElementGetTypeID(),
          let window = windowFrame(windowValue as! AXUIElement) else { return nil }
    guard let geometry = promptTransferGeometry(around: LiveElement(ax: element), window: window,
                                    selectors: target.selectors, parent: { node in
        guard let value = axAttribute(node.ax, kAXParentAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return LiveElement(ax: value as! AXUIElement)
    }, frame: { windowFrame($0.ax) }) else { return nil }
    return TransferAnchor(frame: geometry.editor, window: window, pid: target.app.processIdentifier,
                          promptFrame: geometry.shell)
}

/// Whether the window server shows the anchor's window where AX says it
/// stands. Stage Manager makes the two disagree (live Sep 17 2026, macOS
/// 27): AX goes on reporting the frame a window has on its stage, while
/// the window server has a parked window as its thumbnail off the screen's
/// edge — 205 × 156 at x −307, for a window of 2560 × 1348 — and a window
/// changing places at every size in between.
func isShowing(_ anchor: TransferAnchor, among windows: [WindowHitRegion]) -> Bool {
    windows.contains { anchor.matchesWindow(id: $0.number, pid: $0.owner, frame: $0.frame) }
}

/// Wait for the receiving window to stand where its anchor says before a
/// flight is launched at it. Bringing an app forward under Stage Manager
/// swaps the stages over about two thirds of a second, and the overlay
/// draws only over a window that is in its place, so a flight begun inside
/// the swap was dropped whole, light and all. A window already in place
/// answers at once. One that never arrives — another Space, a frame the
/// two sides disagree on — costs the bound, and the send goes on with no
/// decoration, which is what the overlay would have made of it anyway.
func awaitArrival(of anchor: TransferAnchor, within seconds: TimeInterval = 1,
                  onScreen: () -> [WindowHitRegion] = onScreenWindowRegions,
                  isCancelled: () -> Bool = { relayControl.isCancelled }) -> Bool {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    while !isShowing(anchor, among: onScreen()) {
        guard ProcessInfo.processInfo.systemUptime < deadline, !isCancelled() else { return false }
        Thread.sleep(forTimeInterval: 0.03)
    }
    return true
}

/// Where a flight sets off. Both are in Errol's console, which carries
/// every message: a reply leaves its sender's icon there, whatever the
/// sender's own window is doing — under Stage Manager it is parked in the
/// strip by the time the receiver is forward — and the human's words leave
/// the prompt they were typed in. Each is resolved on the main thread at
/// launch, so no UI references or stale panel coordinates cross threads.
enum TransferSource: Equatable {
    case reply(Speaker)
    case userPrompt
}

enum TransferFeedback {
    case began(id: UUID, sources: [TransferSource], destination: TransferAnchor,
               startedAt: TimeInterval)
    /// The handoff stopped before the paste — Stop, a switched app, a lost
    /// composer — and the flight ends where it is.
    case cancelled(id: UUID)
}

/// Every source follows the same progress clock to the same endpoint,
/// regardless of distance. Separate bends keep the two wakes distinguishable.
struct TransferTrajectory {
    let start: CGPoint
    let end: CGPoint
    var lane: Int = 0

    func point(at progress: Double) -> CGPoint {
        let p = min(1, max(0, progress))
        let eased = p * p * (3 - 2 * p)
        let q = 1 - eased
        let distance = hypot(end.x - start.x, end.y - start.y)
        let bend = min(100, distance * 0.18) * (lane == 0 ? 1 : 0.55)
        let control = CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + bend)
        return CGPoint(x: q * q * start.x + 2 * q * eased * control.x + eased * eased * end.x,
                       y: q * q * start.y + 2 * q * eased * control.y + eased * eased * end.y)
    }
}

/// One clock for the dot, the prompt's light, and the paste. The light
/// plays when the dot lands, and the worker pastes only once it has faded
/// (pasteTime), so the border the light traces is the one the dot landed
/// on: the text going in can grow the composer and move that border.
/// Under Reduce Motion there is no flight: the light plays at once, and the
/// paste still waits for it.
/// The worker's clock assumes a flight whenever sources were asked for; when
/// the overlay can see none of them (the console put away, or on another
/// Space) it lights at once and finishes early, while the paste still waits
/// out the full flight and the light. The worker never depends on what the
/// renderer can see, so the gap is dead time, the safe direction: the other
/// way round the paste would land under the light.
struct TransferTiming {
    static let flightDuration: TimeInterval = 0.55
    /// The light's quick rise, short hold, and long fall (TransferDrawing).
    static let lightDuration: TimeInterval = 0.95
    /// How long the light takes to rise to full.
    static let lightRise: TimeInterval = 0.09
    /// When the light starts to fall; it is out at lightDuration.
    static let lightHold: TimeInterval = 0.18
    let startedAt: TimeInterval
    let travels: Bool
    let reducedMotion: Bool

    var flightDuration: TimeInterval {
        travels && !reducedMotion ? Self.flightDuration : 0
    }

    var arrivalTime: TimeInterval { startedAt + flightDuration }

    /// When the paste may go in: the light has faded.
    var pasteTime: TimeInterval { arrivalTime + Self.lightDuration }

    func progress(at time: TimeInterval) -> Double {
        guard flightDuration > 0 else { return 1 }
        return min(1, max(0, (time - startedAt) / flightDuration))
    }

    func arrivalAge(at time: TimeInterval) -> TimeInterval? {
        time >= arrivalTime ? time - arrivalTime : nil
    }

    func isFinished(at time: TimeInterval) -> Bool {
        time >= pasteTime
    }
}
