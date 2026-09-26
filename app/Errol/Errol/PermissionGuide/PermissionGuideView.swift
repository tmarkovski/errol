// The panel the permission guide docks under System Settings
// (PermissionGuide), drawn in Errol's own look so it reads as the companion
// of the permission screen that opened it rather than as a stranger's
// window. The window around it is transparent, so this view is the whole
// card: the shell's color, one line saying what to do, and a
// tile holding Errol's icon for the drag into the list above.
//
// Where a generic panel would point up with an arrow, the courier that
// carries Errol's messages between the two apps (TransferDrawing) rises
// out of Errol's icon on the tile, stops beside the instruction, and goes
// on toward the list, so the one moving thing on the panel is the one the
// console has already shown, and it traces the drag the user is asked to
// make. The header is laid out on the tile's measures, so the dot keeps to
// the icon's column and the words start where the name does.
//
// The window gives the card the width of the Settings window's content
// column and takes its height from the card, which sizes itself to what it
// holds: the instruction, wrapped to as many lines as that width needs,
// over the tile. At the usual widths that is one line or two. When System
// Settings goes behind other windows, the way back to it takes the
// instruction's place and keeps its room, so the card doesn't change
// height.

import AppKit
import SwiftUI

struct PermissionGuideView: View {
    let model: PermissionGuideModel
    /// Errol's icon as Finder shows it, so the tile carries the picture the
    /// list will show once Errol is in it. It is looked up once here rather
    /// than on every redraw, since the drag state redraws the panel.
    private let icon: NSImage

    init(model: PermissionGuideModel) {
        self.model = model
        icon = NSWorkspace.shared.icon(forFile: model.appURL.path)
    }

    var body: some View {
        // Read here, so a change in either redraws the courier, which is
        // built later, once the marks it hangs from are placed.
        let showsCourier = model.isSettingsFrontmost
        let isDragging = model.isDragging
        VStack(alignment: .leading, spacing: Perch.s(9)) {
            header
            // The closure reads the model's action when a drag reports in,
            // not when the panel is built, so an action PermissionGuide sets
            // after building the panel still hears about the drag.
            GuideDragArea(appURL: model.appURL,
                          onDragStateChange: { [model] dragging in model.dragStateChanged(dragging) },
                          content: AnyView(GuideTile(model: model, icon: icon)))
                .anchorPreference(key: CourierMarks.self, value: .bounds) { CourierMarks(tile: $0) }
        }
        .padding(.horizontal, GuideMetrics.cardInset)
        .padding(.top, Perch.s(10))
        .padding(.bottom, GuideMetrics.cardInset)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .overlayPreferenceValue(CourierMarks.self) { marks in
            courier(marks, shown: showsCourier, isDragging: isDragging)
        }
        // No border of its own: the window's shadow draws a rim around the
        // card, the same one the console wears, and a stroke inside it
        // would read as a second line.
        .background(GuideMetrics.card.fill(Perch.shell))
    }

    /// The instruction and the close button, on the first line's baseline.
    /// The instruction starts after a column as wide as the icon, with the
    /// gap the tile leaves after the icon, so the header and the tile share
    /// one grid. The trailing edge is pulled out by the chips' wash margin,
    /// which puts the close glyph over the tile's grip.
    ///
    /// When System Settings has gone behind other windows, the list above
    /// has gone with it, so the instruction has nothing to point at. It
    /// fades out, the courier with it, and the way back fades in at the
    /// start of the line, in the accent because it is the thing to do
    /// next. The instruction keeps its room while it is hidden, so the card
    /// keeps its height and nothing under it moves.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: GuideMetrics.nameGap) {
            HStack(alignment: .firstTextBaseline, spacing: GuideMetrics.nameGap) {
                // A zero-height mark on the baseline, in the icon's column,
                // where the courier comes to rest (courier(_:shown:isDragging:)).
                Color.clear
                    .frame(width: GuideMetrics.iconSlot, height: 0)
                    .anchorPreference(key: CourierMarks.self, value: .bounds) { CourierMarks(rest: $0) }
                instruction
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(model.isSettingsFrontmost ? 1 : 0)
            .accessibilityHidden(!model.isSettingsFrontmost)
            .overlay(alignment: .leadingFirstTextBaseline) {
                if !model.isSettingsFrontmost {
                    // Pulled out by the wash margin, so the words start at
                    // the icon's edge.
                    showSettingsButton
                        .offset(x: -PerchChip.inset)
                        .transition(.opacity)
                }
            }
            .layoutPriority(1)
            closeButton
        }
        .animation(Perch.fade, value: model.isSettingsFrontmost)
        .padding(.leading, GuideMetrics.tileLead)
        .padding(.trailing, GuideMetrics.tileTrail - PerchChip.inset)
    }

    /// What to do, in the words System Settings uses for the list on this
    /// system. The two names the user looks for, Errol's and the list's,
    /// stand out in ink at medium weight against the secondary ink of the
    /// rest, the way the console sets a destination's name apart. The line
    /// wraps rather than truncating, and the card grows to fit it.
    private var instruction: some View {
        let name = Text(model.appName).fontWeight(.medium).foregroundStyle(Perch.ink)
        let list = Text(AccessPermission.listName).fontWeight(.medium).foregroundStyle(Perch.ink)
        return Text("Drag \(name) to the list above to enable \(list).")
            .font(Perch.text(13))
            .foregroundStyle(Perch.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The panel's controls are worn as the console's chips: text or a
    /// glyph with no fill at rest, and the panel's wash under the pointer.
    private var showSettingsButton: some View {
        Button { model.reopenSettings() } label: {
            HStack(spacing: Perch.s(3)) {
                Text("Show System Settings")
                // Symbols go in a text run, as the console's chips set
                // theirs, so they keep their ink.
                Text(Image(systemName: "arrow.up.right"))
                    .font(Perch.text(8, .semibold))
            }
            .font(Perch.text(11.5, .medium))
            .foregroundStyle(Perch.accentText)
            .lineLimit(1)
            .perchChip()
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("System Settings went behind another window. This brings it back.")
    }

    private var closeButton: some View {
        Button { model.close() } label: {
            Text(Image(systemName: "xmark"))
                .font(Perch.text(10, .semibold))
                .foregroundStyle(Perch.secondary)
                .perchChip()
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Close")
        .accessibilityLabel("Close the guide")
    }

    /// The courier, drawn over the whole card so it can rise out of the
    /// icon on the tile and pass the instruction on its way to the list.
    /// Its canvas keeps to the icon's column and runs from the card's top
    /// edge to a little below the icon's middle, enough for the glow. The
    /// track is measured from the rest mark in the header and from the
    /// tile, whose icon sits at the middle of its height.
    private func courier(_ marks: CourierMarks, shown: Bool, isDragging: Bool) -> some View {
        GeometryReader { proxy in
            if shown, let rest = marks.rest, let tile = marks.tile {
                let mark = proxy[rest]
                let track = CourierTrack(start: proxy[tile].midY,
                                         rest: mark.minY - Perch.s(3.8),
                                         top: Perch.s(2))
                GuideCourier(isDragging: isDragging, track: track)
                    .frame(width: CourierMetrics.width, height: track.start + CourierMetrics.reachBelow)
                    .offset(x: mark.midX - CourierMetrics.width / 2)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(Perch.fade, value: shown)
    }
}

/// The card's and the tile's measures. The header borrows the tile's, so
/// its dot keeps to the icon's column and its words start where the name
/// does.
private enum GuideMetrics {
    /// The Settings card's corner, which the guide shares as the other card
    /// Errol shows outside the console.
    static let card = RoundedRectangle(cornerRadius: Perch.shellCorner)
    static let cardInset = Perch.s(12)
    /// A step tighter than the card, as for any well set inside a window.
    static let tile = RoundedRectangle(cornerRadius: Perch.insetCorner)
    static let tileLead = Perch.s(8)
    static let tileTrail = Perch.s(12)
    static let iconSlot = Perch.s(30)
    static let nameGap = Perch.s(10)
}

// MARK: - The tile

/// Errol as something to pick up: its icon and name on the paper the
/// console's prompt box and transcript are made of, edged like them, with
/// "Drag" and a grip at the trailing end as the quiet hint. The whole tile
/// is the drag source (GuideDragArea), so its height is the drag area's.
/// While the icon is in the user's hand, the one left on the tile fades,
/// the way Finder dims an item that is being dragged.
///
/// The tile reads the model itself rather than taking the drag state as a
/// value, because it is hosted inside the drag source's own view and
/// redraws there when the model changes.
private struct GuideTile: View {
    let model: PermissionGuideModel
    let icon: NSImage

    var body: some View {
        let slot = GuideMetrics.iconSlot
        HStack(spacing: GuideMetrics.nameGap) {
            // An app icon keeps a transparent margin around its squircle,
            // which spans about 81% of the image, so the image is drawn
            // oversize to make the squircle itself fill the slot, as the
            // console's avatars do (PerchAvatar).
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: slot / 0.81, height: slot / 0.81)
                .frame(width: slot, height: slot)
                .opacity(model.isDragging ? 0.4 : 1)
                .animation(Perch.fade, value: model.isDragging)
            Text(model.appName)
                .font(Perch.text(13, .medium))
                .foregroundStyle(Perch.ink)
                .lineLimit(1)
            Spacer(minLength: Perch.s(8))
            HStack(spacing: Perch.s(6)) {
                Text("Drag").font(Perch.text(11))
                GuideGrip()
            }
            .foregroundStyle(Perch.muted)
        }
        .padding(.leading, GuideMetrics.tileLead)
        .padding(.trailing, GuideMetrics.tileTrail)
        .padding(.vertical, Perch.s(8))
        .frame(maxWidth: .infinity)
        .background(GuideMetrics.tile.fill(Perch.paper))
        .overlay(GuideMetrics.tile.strokeBorder(Perch.chipEdge, lineWidth: 1))
        .contentShape(GuideMetrics.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drag \(model.appName) into the \(AccessPermission.listName) list above")
    }
}

/// Six dots in two columns, the handle people know as something that moves.
/// Drawn rather than taken from a symbol, like the console's ··· menu, and
/// dots besides, like the courier above it.
private struct GuideGrip: View {
    var body: some View {
        let dot = Perch.s(2.4)
        let gap = Perch.s(2.2)
        VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: gap) {
                    Circle().frame(width: dot, height: dot)
                    Circle().frame(width: dot, height: dot)
                }
            }
        }
    }
}

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
private struct GuideCourier: View {
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
private struct CourierMarks: PreferenceKey {
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
private struct CourierTrack {
    var start: CGFloat
    var rest: CGFloat
    var top: CGFloat

    func y(_ climb: Double) -> CGFloat {
        climb <= 1 ? start + (rest - start) * climb : rest + (top - rest) * (climb - 1)
    }
}

/// The courier's canvas and the dot's measures.
private enum CourierMetrics {
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

#if DEBUG
#Preview("Permission guide") {
    PermissionGuideView(model: PermissionGuideModel())
        .frame(width: 520)
        .padding()
}

#Preview("Permission guide · System Settings behind other windows") {
    let model = PermissionGuideModel()
    model.isSettingsFrontmost = false
    return PermissionGuideView(model: model)
        .frame(width: 520)
        .padding()
}

#Preview("Permission guide · dragging") {
    let model = PermissionGuideModel()
    model.isDragging = true
    return PermissionGuideView(model: model)
        .frame(width: 520)
        .padding()
}
#endif
