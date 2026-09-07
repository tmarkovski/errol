import AppKit
import ApplicationServices
import Foundation

/// Geometry crosses the event stream, never live AX elements. Coordinates
/// use AX's top-left origin; the overlay converts them on the main thread.
struct TransferAnchor: Equatable {
    let frame: CGRect
    let window: CGRect
    let pid: pid_t
    /// Native Errol panels can resize as their editor closes. Their window
    /// identity remains valid after launch even when that layout changes.
    let windowID: CGWindowID?

    init?(frame: CGRect, window: CGRect, pid: pid_t, windowID: CGWindowID? = nil) {
        func usable(_ rect: CGRect) -> Bool {
            [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
                && rect.width > 0 && rect.height > 0
        }
        guard usable(frame), usable(window), window.contains(frame) else { return nil }
        self.frame = frame
        self.window = window
        self.pid = pid
        self.windowID = windowID
    }

    func matchesWindow(id: CGWindowID, pid: pid_t, frame: CGRect) -> Bool {
        guard self.pid == pid else { return false }
        if let windowID { return windowID == id }
        return abs(frame.minX - window.minX) < 2 && abs(frame.minY - window.minY) < 2
            && abs(frame.width - window.width) < 2 && abs(frame.height - window.height) < 2
    }
}

/// Called on the relay worker, where all other reads of the target occur.
/// Missing or off-window geometry only suppresses decoration.
func transferAnchor(for element: AXUIElement?, in target: TargetApp) -> TransferAnchor? {
    guard let element,
          let frame = windowFrame(element),
          let windowValue = axAttribute(element, kAXWindowAttribute),
          CFGetTypeID(windowValue) == AXUIElementGetTypeID(),
          let window = windowFrame(windowValue as! AXUIElement) else { return nil }
    return TransferAnchor(frame: frame, window: window, pid: target.app.processIdentifier)
}

/// A copied reply still gets a flight when its copy control has scrolled out
/// of view or exposes no geometry. Only the source may use this approximation;
/// the destination continues to identify the actual receiving prompt.
func replyTransferAnchor(copyFrame: CGRect?, window: CGRect, pid: pid_t,
                         screens: [CGRect]? = nil) -> TransferAnchor? {
    // Validate before taking intersections or computing a fallback center.
    guard TransferAnchor(frame: window, window: window, pid: pid) != nil else { return nil }
    if let copyFrame,
       let exact = TransferAnchor(frame: copyFrame, window: window, pid: pid),
       screens?.contains(where: { $0.contains(copyFrame) }) ?? true {
        return exact
    }
    // Avoid launching outside a display when the window straddles a screen
    // edge or a gap between monitors. Prefer its largest visible portion.
    let visible = screens.map { frames in
        frames.map { window.intersection($0) }
            .filter { !$0.isNull && !$0.isEmpty }
            .max { $0.width * $0.height < $1.width * $1.height }
    } ?? window
    guard let visible else { return nil }
    let width = min(18, visible.width)
    let height = min(18, visible.height)
    let source = CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2,
                        width: width, height: height)
    return TransferAnchor(frame: source, window: window, pid: pid)
}

/// Capture the window while the source app is active; the copy button itself
/// can be off screen and may unmount when focus moves to the recipient.
func replyTransferAnchor(for element: AXUIElement?, in target: TargetApp) -> TransferAnchor? {
    let elementWindow = element.flatMap { axAttribute($0, kAXWindowAttribute) }
        .flatMap { value -> AXUIElement? in
            CFGetTypeID(value) == AXUIElementGetTypeID() ? (value as! AXUIElement) : nil
        }
    guard let windowElement = elementWindow ?? chatWindow(in: target),
          let window = windowFrame(windowElement) else { return nil }
    return replyTransferAnchor(copyFrame: element.flatMap(windowFrame), window: window,
                               pid: target.app.processIdentifier)
}

enum TransferSource: Equatable {
    case captured(TransferAnchor)
    /// Resolve the prompt on the main thread at launch, after its editor
    /// has closed. No UI references or stale panel coordinates cross threads.
    case userPrompt
}

enum TransferFeedback {
    case began(id: UUID, sources: [TransferSource], destination: TransferAnchor,
               startedAt: TimeInterval)
    /// Confirms only the paste, not submission or a reply from the other app.
    case pasted(id: UUID, destination: TransferAnchor)
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

/// A receipt can arrive before or after the dot. Neither travel completion
/// nor a timeout can light the prompt without an actual paste receipt.
struct TransferTiming {
    static let flightDuration: TimeInterval = 0.55
    let startedAt: TimeInterval
    let travels: Bool
    let reducedMotion: Bool
    private(set) var pastedAt: TimeInterval?

    mutating func confirmPaste(at time: TimeInterval) {
        if pastedAt == nil { pastedAt = time }
    }

    var flightDuration: TimeInterval {
        travels && !reducedMotion ? Self.flightDuration : 0
    }

    func progress(at time: TimeInterval) -> Double {
        guard flightDuration > 0 else { return 1 }
        return min(1, max(0, (time - startedAt) / flightDuration))
    }

    func arrivalAge(at time: TimeInterval) -> TimeInterval? {
        guard let pastedAt else { return nil }
        let arrival = max(startedAt + flightDuration, pastedAt)
        return time >= arrival ? time - arrival : nil
    }

    func isFinished(at time: TimeInterval) -> Bool {
        if let age = arrivalAge(at: time) { return age >= 0.95 }
        return time - startedAt >= 3
    }
}
