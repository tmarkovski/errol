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
// the icon's column and the words start where the name does. The courier
// itself is drawn in GuideCourier.swift; this file places it.
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
