import AppKit
import QuartzCore

/// Short-lived, click-through decoration driven by the relay's ordered events.
/// AX stays on the worker; drawing never acquires focus. The flight uses
/// the same start time as the worker's short, bounded pre-paste beat.
final class TransferOverlay {
    private struct Flight {
        let id: UUID
        let sources: [TransferAnchor]
        var destination: TransferAnchor
        var timing: TransferTiming
    }

    private var flight: Flight?
    private var panels: [TransferPanel] = []
    private var timer: Timer?
    private var lastVisibilityCheck: TimeInterval = 0
    var promptSource: PromptTransferSource?

    func handle(_ event: TransferFeedback) {
        switch event {
        case .began(let id, let sources, let destination, let startedAt):
            stop()
            let windows = visibleWindows()
            guard isVisible(destination, in: windows) else { return }
            let screens = NSScreen.screens.map { axRect($0.frame) }
            let origins = sources.compactMap { source -> TransferAnchor? in
                let anchor: TransferAnchor?
                switch source {
                case .captured(let captured):
                    anchor = replyTransferAnchor(copyFrame: captured.frame,
                                                 window: captured.window, pid: captured.pid,
                                                 screens: screens)
                case .userPrompt: anchor = promptSource?.anchor()
                }
                return anchor.flatMap { isVisible($0, in: windows) ? $0 : nil }
            }
            let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            flight = Flight(id: id, sources: origins, destination: destination,
                            timing: TransferTiming(startedAt: startedAt,
                                                   travels: !origins.isEmpty, reducedMotion: reduced))
            // One surface per display avoids a giant backing store across
            // gaps between monitors and gives each display its native scale.
            for screen in NSScreen.screens {
                let panel = TransferPanel(screen: screen)
                panels.append(panel)
            }
            let clock = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.draw() }
            timer = clock
            RunLoop.main.add(clock, forMode: .common)
            draw()
        case .pasted(let id, let destination):
            guard flight?.id == id else { return }
            flight?.destination = destination
            flight?.timing.confirmPaste(at: ProcessInfo.processInfo.systemUptime)
            draw()
        case .cancelled(let id):
            if flight?.id == id { stop() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        flight = nil
        for panel in panels { panel.close() }
        panels.removeAll()
        lastVisibilityCheck = 0
    }

    private func draw() {
        guard let flight else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard !flight.timing.isFinished(at: now) else { stop(); return }
        if now - lastVisibilityCheck > 0.15 {
            lastVisibilityCheck = now
            let windows = visibleWindows()
            // Hide if a chat window moves, closes, minimizes, or changes Space.
            // Errol's source panel may finish resizing after its dot launches.
            guard isVisible(flight.destination, in: windows),
                  flight.sources.allSatisfy({ isVisible($0, in: windows) }) else {
                stop()
                return
            }
        }
        let destination = axRect(flight.destination.frame)
        let starts = flight.sources.map { axRect($0.frame).center }
        for panel in panels {
            panel.drawing.render(starts: starts, destination: destination,
                                 timing: flight.timing, now: now, screenOrigin: panel.frame.origin)
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    private func visibleWindows() -> [(id: CGWindowID, pid: pid_t, frame: CGRect)] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap {
            // Include floating windows: Errol's native prompt is in a panel.
            guard let id = $0[kCGWindowNumber as String] as? CGWindowID,
                  let pid = $0[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = $0[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return (id, pid, frame)
        }
    }

    private func isVisible(_ anchor: TransferAnchor,
                           in windows: [(id: CGWindowID, pid: pid_t, frame: CGRect)]) -> Bool {
        windows.contains { id, pid, frame in
            anchor.matchesWindow(id: id, pid: pid, frame: frame)
        }
    }
}

private final class TransferPanel: NSPanel {
    let drawing = TransferDrawing()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .floating
        collectionBehavior = [.transient, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = drawing
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Core Animation layers keep the short golden wake, the dissolving dot, and
/// the receiving border on the same clock. No particles or continuous idle work.
final class TransferDrawing: NSView {
    private let tails = [CAShapeLayer(), CAShapeLayer()]
    private let dots = [CAShapeLayer(), CAShapeLayer()]
    private let bloom = CAShapeLayer()
    private let outline = CAShapeLayer()
    private let gold = NSColor(srgbRed: 1, green: 0.77, blue: 0.20, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        for shape in tails + [bloom] + dots + [outline] {
            shape.actions = ["path": NSNull(), "opacity": NSNull(), "bounds": NSNull(),
                             "position": NSNull(), "shadowPath": NSNull()]
            shape.fillColor = gold.cgColor
            shape.shadowColor = gold.cgColor
            shape.shadowOffset = .zero
            layer?.addSublayer(shape)
        }
        for tail in tails {
            tail.shadowRadius = 7
            tail.shadowOpacity = 0.65
        }
        for dot in dots {
            dot.shadowRadius = 9
            dot.shadowOpacity = 0.95
            dot.fillColor = NSColor(srgbRed: 1, green: 0.90, blue: 0.52, alpha: 1).cgColor
        }
        bloom.fillColor = nil
        bloom.strokeColor = gold.cgColor
        bloom.lineWidth = 1.5
        outline.fillColor = nil
        outline.strokeColor = gold.cgColor
        outline.lineWidth = 2
        outline.shadowRadius = 8
        outline.shadowOpacity = 0.8
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(starts: [CGPoint], destination: CGRect, timing: TransferTiming,
                now: TimeInterval, screenOrigin: CGPoint) {
        func local(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x - screenOrigin.x, y: point.y - screenOrigin.y)
        }
        let to = local(destination.center)
        let arrival = timing.arrivalAge(at: now)
        let dissolve = min(1, max(0, (arrival ?? 0) / 0.24))
        let moving = timing.travels && !timing.reducedMotion
        let fadeIn = min(1, max(0, (now - timing.startedAt) / 0.07))
        let opacity = moving ? fadeIn * (1 - dissolve) : 0
        let radius = 4.5 * (1 - dissolve * 0.75)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in dots.indices {
            let dot = dots[index]
            let tail = tails[index]
            guard index < starts.count else {
                dot.opacity = 0
                tail.opacity = 0
                continue
            }
            let trajectory = TransferTrajectory(start: local(starts[index]), end: to, lane: index)
            func point(at time: TimeInterval) -> CGPoint {
                trajectory.point(at: timing.progress(at: time))
            }
            let head = point(at: now)
            dot.path = CGPath(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius,
                                              width: radius * 2, height: radius * 2), transform: nil)
            dot.opacity = Float(opacity)

            // Recent positions form a tapered wake. As the dot stops, its tail
            // catches up and disappears rather than leaving a line across the apps.
            let points = (0...24).map { point(at: now - 0.18 + Double($0) / 24 * 0.18) }
            var left: [CGPoint] = []
            var right: [CGPoint] = []
            for index in points.indices {
                let a = points[max(0, index - 1)]
                let b = points[min(points.count - 1, index + 1)]
                let length = max(0.001, hypot(b.x - a.x, b.y - a.y))
                let width = 3.2 * pow(Double(index) / 24, 1.5)
                let dx = -(b.y - a.y) / length * width
                let dy = (b.x - a.x) / length * width
                left.append(CGPoint(x: points[index].x + dx, y: points[index].y + dy))
                right.append(CGPoint(x: points[index].x - dx, y: points[index].y - dy))
            }
            let wake = CGMutablePath()
            wake.addLines(between: left + right.reversed())
            wake.closeSubpath()
            tail.path = wake
            tail.opacity = Float(opacity * 0.55)
        }

        let bloomRadius = 5 + dissolve * 19
        bloom.path = CGPath(ellipseIn: CGRect(x: to.x - bloomRadius, y: to.y - bloomRadius,
                                             width: bloomRadius * 2, height: bloomRadius * 2), transform: nil)
        bloom.opacity = arrival != nil && moving ? Float((1 - dissolve) * 0.65) : 0

        let prompt = destination.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
            .insetBy(dx: -5, dy: -5)
        let corner = min(16, prompt.height / 2)
        outline.path = CGPath(roundedRect: prompt, cornerWidth: corner, cornerHeight: corner, transform: nil)
        if let age = arrival {
            let rise = min(1, age / 0.09)
            let fall = max(0, 1 - max(0, age - 0.18) / 0.77)
            outline.opacity = timing.reducedMotion ? 0.85 : Float(rise * fall * fall)
        } else {
            outline.opacity = 0
        }
        CATransaction.commit()
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
