// The courier on the permission guide's card: the lit dot that climbs from
// Errol's icon to the instruction and on toward the list, with the marks and
// measures the card places it by. Its own file so PermissionGuideView.swift
// keeps to the card's layout.

import SwiftUI

// MARK: - The courier

/// The courier dot, the same lit dot that flies a message to its app
/// (TransferDrawing), scaled from its 4.5-point radius to sit beside a
/// line of text: a core of the accent lightened with white, the accent's
/// glow around it, and a wake that tapers to nothing behind it. Here it
/// climbs rather than crosses the screen. Each loop it lifts out of Errol's
/// icon on the tile, rises to rest beside the instruction, waits there,
/// then leaves upward toward the list, speeding up and fading before the
/// card's top edge, and after a short pause the next one lifts off.
///
/// While the user drags the tile, the dot stays at rest and slowly swells
/// and settles, so the panel shows it noticed the drag without pulling the
/// eye from the list. When the drag ends, the loop picks up from the rest.
/// Under Reduce Motion there is no travel and no pulse: the dot stands lit
/// beside the words, and glows a little wider during a drag.
struct GuideCourier: View {
    let isDragging: Bool
    let track: CourierTrack
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the current loop began, or the pulse, during a drag.
    @State private var epoch = Date.now

    var body: some View {
        // Read here rather than inside the canvas, so a theme change
        // redraws the courier in the new accent.
        let colors = CourierColors(accent: Perch.accent,
                                   core: Perch.accent.mix(with: .white, by: 0.35, in: .device))
        Group {
            if reduceMotion {
                canvas(CourierPose(climb: 1, opacity: 1, swell: isDragging ? 1 : 0), colors)
            } else {
                // Capped at 60 frames a second, the rate the transfer's
                // own drawing runs at, which is plenty for a dot this size.
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                    canvas(CourierLoop.pose(age: timeline.date.timeIntervalSince(epoch),
                                            dragging: isDragging), colors)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isDragging) { _, dragging in
            // A drag starts the pulse from rest. Its end resumes the loop at
            // the rest, where the pulse left the dot, instead of wherever
            // the clock had got to.
            epoch = dragging ? .now : Date.now.addingTimeInterval(-CourierLoop.arrived)
        }
    }

    private func canvas(_ pose: CourierPose, _ colors: CourierColors) -> some View {
        Canvas { context, size in
            CourierLoop.draw(pose, colors, along: track, in: &context, size: size)
        }
    }
}

/// The two places the courier's track is measured from: the zero-height
/// mark on the instruction's first baseline, in the icon's column, and the
/// tile. The tile is drawn inside the drag source's own view, so the icon
/// can't report its place itself, but it sits at the middle of the tile's
/// height, in the same column as the mark.
struct CourierMarks: PreferenceKey {
    var rest: Anchor<CGRect>?
    var tile: Anchor<CGRect>?

    static let defaultValue = CourierMarks()

    static func reduce(value: inout CourierMarks, nextValue: () -> CourierMarks) {
        let next = nextValue()
        value.rest = value.rest ?? next.rest
        value.tile = value.tile ?? next.tile
    }
}

/// Where the climb runs, in the card's coordinates, which are the canvas's
/// too, since the canvas starts at the card's top edge. Along the climb, 0
/// is the start at the middle of Errol's icon, 1 the rest beside the
/// instruction's first line at the middle of its lowercase letters, and 2
/// the top at the card's edge, where the dot has faded out.
struct CourierTrack {
    var start: CGFloat
    var rest: CGFloat
    var top: CGFloat

    func y(_ climb: Double) -> CGFloat {
        climb <= 1 ? start + (rest - start) * climb : rest + (top - rest) * (climb - 1)
    }
}

/// The courier's canvas and the dot's measures.
enum CourierMetrics {
    /// Wide enough that the glow is never cut off at the canvas's sides.
    static let width = Perch.s(40)
    /// How far the canvas reaches below the start, for the glow of a dot
    /// that is still over the icon.
    static let reachBelow = Perch.s(12)
    /// The dot and its wake, the transfer's measures scaled by the same
    /// factor: the wake is a little narrower than the dot at the head, and
    /// the glow reaches about twice the dot's radius. Any smaller, and the
    /// lightened core on a light shell read as a smudge rather than a light.
    static let radius = Perch.s(3.6)
    static let glow = Perch.s(7)
    static let wakeWidth = Perch.s(2.5)
    static let wakeGlow = Perch.s(5.5)
}

/// The accent and the dot's lit core, resolved by the canvas for the
/// panel's appearance.
private struct CourierColors {
    let accent: Color
    let core: Color
}

/// One frame of the courier.
private struct CourierPose {
    /// Where the dot is along the climb (CourierTrack).
    var climb: Double
    var opacity: Double
    /// How far the pulse has swollen the dot and its glow, from 0 to 1.
    var swell: Double = 0
    /// The climb at the recent moments the wake is drawn through, oldest
    /// first. Empty when the dot has no wake.
    var wake: [Double] = []
}

/// The loop's clock and drawing. The timings are in seconds from the
/// loop's start: the dot rises into its rest by `arrived`, leaves it at
/// `departs`, is gone by `gone`, and the loop starts again at `period`.
private enum CourierLoop {
    static let period: TimeInterval = 3.0
    static let arrived: TimeInterval = 0.7
    static let departs: TimeInterval = 1.8
    static let gone: TimeInterval = 2.35
    /// The wake is the path of the recent past, as the transfer's is. The
    /// transfer looks back 0.18 seconds, but it crosses hundreds of points
    /// in that time and this dot climbs a few dozen, so the window is
    /// longer here to give the wake a length that reads.
    static let wakeSpan: TimeInterval = 0.24
    static let wakeSamples = 24
    /// One swell and settle of the pulse during a drag.
    static let pulse: TimeInterval = 1.1

    static func pose(age: TimeInterval, dragging: Bool) -> CourierPose {
        if dragging {
            return CourierPose(climb: 1, opacity: 1, swell: (1 - cos(2 * .pi * age / pulse)) / 2)
        }
        let now = stage(at: age)
        let wake = (0...wakeSamples).map { index in
            stage(at: age - wakeSpan + wakeSpan * Double(index) / Double(wakeSamples)).climb
        }
        return CourierPose(climb: now.climb, opacity: now.opacity, wake: wake)
    }

    /// The climb and opacity at a moment in the loop. The rise starts
    /// slowly and lights up quickly, so the dot is seen coming out of the
    /// icon, and it slows into the rest. The departure eases in, so the dot
    /// leaves the way a launch does, and its wake lengthens as it speeds
    /// up. Between loops the dot waits, unseen, on the icon, so the wake of
    /// the next rise trails from there.
    private static func stage(at age: TimeInterval) -> (climb: Double, opacity: Double) {
        var t = age.truncatingRemainder(dividingBy: period)
        if t < 0 { t += period }
        switch t {
        case ..<arrived:
            return (smoothstep(0, 1, t / arrived), min(1, t / 0.18))
        case ..<departs:
            return (1, 1)
        case ..<gone:
            let progress = (t - departs) / (gone - departs)
            return (1 + pow(progress, 2.2), 1 - smoothstep(0.4, 1, progress))
        default:
            return (0, 0)
        }
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// Draws the wake, then the dot over it, each with its glow, in the
    /// transfer's proportions: the wake at a little over half the dot's
    /// opacity with a softer glow, and the dot with a strong one.
    static func draw(_ pose: CourierPose, _ colors: CourierColors, along track: CourierTrack,
                     in context: inout GraphicsContext, size: CGSize) {
        guard pose.opacity > 0.001 else { return }
        let x = size.width / 2
        let head = track.y(pose.climb)

        if let wake = wakePath(pose.wake, x: x, along: track) {
            context.drawLayer { layer in
                layer.opacity = pose.opacity * 0.55
                layer.addFilter(.shadow(color: colors.accent.opacity(0.65), radius: CourierMetrics.wakeGlow))
                layer.fill(wake, with: .color(colors.accent))
            }
        }

        let radius = CourierMetrics.radius * (1 + 0.22 * pose.swell)
        let glow = CourierMetrics.glow * (1 + 0.5 * pose.swell)
        context.drawLayer { layer in
            layer.opacity = pose.opacity
            layer.addFilter(.shadow(color: colors.accent.opacity(0.95), radius: glow))
            layer.fill(Path(ellipseIn: CGRect(x: x - radius, y: head - radius,
                                              width: radius * 2, height: radius * 2)),
                       with: .color(colors.core))
        }
    }

    /// The wake as the transfer builds it: the recent positions, widened on
    /// both sides by an amount that grows from nothing at the oldest to the
    /// full width at the head. The climb is straight up, so the sides are
    /// plain horizontal offsets. A dot at rest has no wake.
    private static func wakePath(_ climbs: [Double], x: CGFloat, along track: CourierTrack) -> Path? {
        guard let first = climbs.first, let last = climbs.last,
              abs(track.y(last) - track.y(first)) > 0.5
        else { return nil }
        let steps = Double(climbs.count - 1)
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for (index, climb) in climbs.enumerated() {
            let y = track.y(climb)
            let width = CourierMetrics.wakeWidth * pow(Double(index) / steps, 1.5)
            left.append(CGPoint(x: x - width, y: y))
            right.append(CGPoint(x: x + width, y: y))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }
}
