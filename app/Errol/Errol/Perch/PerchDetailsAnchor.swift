// Details float in a panel of their own under the console: a paper card
// with an arrow on what opened it, like a popover. A note's receipt opens
// one from its line, with the note in full. A native popover would take
// key status whenever it appears, and with it the keyboard a copy or
// delivery needs, so this is a non-activating panel that becomes key only
// when the relay's focus contract allows it (ConsoleAccess.canTakeFocus).
//
// It fades in and out. A click anywhere else closes it, except on the
// control that opens and closes the details itself (the receipt line),
// which is left to toggle them. Esc closes it too, and so does the console
// going away: a child panel would otherwise stay on screen without it.

import AppKit
import Observation
import SwiftUI

struct PerchDetailsAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    var canTakeFocus: () -> Bool
    @ViewBuilder var content: () -> Content

    /// The anchor is the opening control's own region, so a click on that
    /// control toggles the details instead of closing and reopening them.
    func makeNSView(context: Context) -> NSView { DetailsToggleRegionView() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.dismiss = { isPresented = false }
        guard isPresented else { coordinator.close(); return }
        coordinator.show(from: view, content: content(), canTakeFocus: canTakeFocus)
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.close() }

    final class DetailsPanel: NSPanel {
        var permitsKey: () -> Bool = { false }
        var dismiss: (() -> Void)?
        override var canBecomeKey: Bool { permitsKey() }
        override func cancelOperation(_ sender: Any?) { dismiss?() }
    }

    final class DetailsHostingView: NSHostingView<PerchDetailsCallout<Content>> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    final class Coordinator {
        var dismiss: (() -> Void)?
        private var panel: DetailsPanel?
        private var host: DetailsHostingView?
        private weak var anchor: NSView?
        private let placement = PerchDetailsPlacement()
        /// The card's size as SwiftUI last laid it out, arrow included.
        private var size: CGSize?
        private var monitors: [Any] = []
        private var observers: [NSObjectProtocol] = []

        /// The arrow tip's gap from the console's edge.
        private static var gap: CGFloat { Perch.s(4) }
        /// How far in from the card's near end the arrow sits: the card runs
        /// from the anchor's end of the console toward its middle.
        private static var lead: CGFloat { Perch.s(50) }
        private static var screenMargin: CGFloat { 8 }

        func show(from anchor: NSView, content: Content, canTakeFocus: @escaping () -> Bool) {
            guard let parent = anchor.window else { return }
            self.anchor = anchor
            let callout = PerchDetailsCallout(placement: placement, content: content) { [weak self] size in
                // Reported mid-layout; the frame changes on the next turn.
                DispatchQueue.main.async { self?.resize(to: size) }
            }
            if let host, let panel {
                host.rootView = callout
                panel.permitsKey = canTakeFocus
                place()
                return
            }
            let panel = DetailsPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            // The shadow follows the card's silhouette, arrow and all.
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.level = NSWindow.Level(rawValue: parent.level.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.permitsKey = canTakeFocus
            panel.dismiss = { [weak self] in self?.dismiss?() }
            let host = DetailsHostingView(rootView: callout)
            host.sizingOptions = []
            panel.contentView = host
            self.panel = panel
            self.host = host
            size = host.fittingSize
            place()
            panel.alphaValue = 0
            parent.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            panel.displayIfNeeded()
            Self.refreshShadow(of: panel)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel.animator().alphaValue = 1
            }
            // Keyboard navigation can enter the details only while focus is
            // safe; a copy or delivery keeps the keyboard where it is.
            if canTakeFocus() { panel.makeKey() }
            watchForDismissal(in: parent)
        }

        func close() {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let panel else { return }
            self.panel = nil
            host = nil
            size = nil
            let parent = panel.parent
            let hadKeyboard = panel.isKeyWindow
            parent?.removeChildWindow(panel)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
            // The keyboard goes back to the console's field, if it may.
            if hadKeyboard, let parent, parent.isVisible, parent.canBecomeKey { parent.makeKey() }
        }

        deinit { close() }

        private func resize(to size: CGSize) {
            guard panel != nil, size.width > 0, size.height > 0, size != self.size else { return }
            self.size = size
            place()
        }

        /// Under the console with the arrow up at the anchor, or over it with
        /// the arrow down when the screen's bottom is too close. Kept on the
        /// screen; the arrow stays on the anchor wherever the card lands.
        private func place() {
            guard let panel, let anchor, let parent = anchor.window,
                  let size, size.width > 0, size.height > 0 else { return }
            let target = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let console = parent.frame
            let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? console
            let below = console.minY - Self.gap - size.height
            let pointsUp = below >= screen.minY + Self.screenMargin
            var x = target.midX < console.midX ? target.midX - Self.lead : target.midX + Self.lead - size.width
            x = min(max(x, screen.minX + Self.screenMargin), screen.maxX - size.width - Self.screenMargin)
            if placement.pointsUp != pointsUp { placement.pointsUp = pointsUp }
            if placement.arrowX != target.midX - x { placement.arrowX = target.midX - x }
            let frame = NSRect(x: x, y: pointsUp ? below : console.maxY + Self.gap,
                               width: size.width, height: size.height)
            guard panel.frame != frame else { return }
            panel.setFrame(frame, display: true)
            Self.refreshShadow(of: panel)
        }

        /// The shadow follows what the window has drawn, and SwiftUI draws the
        /// card after the frame changes, and animates a change in its height;
        /// so the shadow is traced again once it has drawn, and once it has
        /// settled.
        private static func refreshShadow(of panel: NSPanel) {
            panel.invalidateShadow()
            DispatchQueue.main.async { panel.invalidateShadow() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak panel] in panel?.invalidateShadow() }
        }

        private func watchForDismissal(in parent: NSWindow) {
            let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self, weak parent] event in
                guard let self, let panel = self.panel else { return event }
                if event.type == .keyDown {
                    // Esc closes the details first, from the console as well.
                    guard event.keyCode == 53, event.window === panel || event.window === parent else { return event }
                    self.dismiss?()
                    return nil
                }
                if event.window === panel { return event }
                if let window = event.window, DetailsToggleRegionView.contains(event.locationInWindow, in: window) {
                    return event
                }
                self.dismiss?()
                return event
            }
            let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.dismiss?()
            }
            monitors = [local, global].compactMap { $0 }
            // Ordering the console out changes its occlusion state, whichever
            // way it went: Esc, ⌘W, or the status item.
            observers = [NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: parent, queue: .main) { [weak self, weak parent] _ in
                guard let parent, !parent.isVisible || !parent.occlusionState.contains(.visible) else { return }
                self?.dismiss?()
            }]
        }
    }
}

/// Where the details panel put its arrow, which only the panel's frame
/// decides: along the card from its leading edge, on the top edge or the
/// bottom one.
@Observable
final class PerchDetailsPlacement {
    var arrowX = Perch.s(50)
    var pointsUp = true
}

/// The details panel's card: paper, a hairline edge, and an arrow on the
/// edge that faces the console. The panel's shadow follows its outline.
struct PerchDetailsCallout<Content: View>: View {
    let placement: PerchDetailsPlacement
    let content: Content
    var onSize: (CGSize) -> Void = { _ in }

    static var corner: CGFloat { Perch.s(12) }
    static var arrowWidth: CGFloat { Perch.s(18) }
    static var arrowHeight: CGFloat { Perch.s(8) }

    var body: some View {
        let shape = PerchCalloutShape(arrowX: placement.arrowX, pointsUp: placement.pointsUp,
                                      corner: Self.corner, arrowWidth: Self.arrowWidth,
                                      arrowHeight: Self.arrowHeight)
        content
            .padding(.top, placement.pointsUp ? Self.arrowHeight : 0)
            .padding(.bottom, placement.pointsUp ? 0 : Self.arrowHeight)
            .background(shape.fill(Perch.paper))
            .overlay(shape.strokeBorder(Perch.chipEdge, lineWidth: 1))
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }
}

/// A rounded card with an arrow on its top edge, or its bottom one, at
/// `arrowX`. The arrow's base and tip are rounded, and it keeps clear of the
/// card's corners.
struct PerchCalloutShape: InsettableShape {
    var arrowX: CGFloat
    var pointsUp: Bool
    var corner: CGFloat
    var arrowWidth: CGFloat
    var arrowHeight: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: inset, dy: inset)
        let card = CGRect(x: bounds.minX, y: bounds.minY + arrowHeight,
                          width: bounds.width, height: bounds.height - arrowHeight)
        let half = arrowWidth / 2
        let x = min(max(arrowX, card.minX + corner + half), card.maxX - corner - half)
        let tip = CGPoint(x: x, y: bounds.minY)
        var path = Path()
        path.move(to: CGPoint(x: card.minX + corner, y: card.minY))
        path.addArc(tangent1End: CGPoint(x: x - half, y: card.minY), tangent2End: tip, radius: Perch.s(2.5))
        path.addArc(tangent1End: tip, tangent2End: CGPoint(x: x + half, y: card.minY), radius: Perch.s(2))
        path.addArc(tangent1End: CGPoint(x: x + half, y: card.minY),
                    tangent2End: CGPoint(x: card.maxX, y: card.minY), radius: Perch.s(2.5))
        path.addArc(tangent1End: CGPoint(x: card.maxX, y: card.minY),
                    tangent2End: CGPoint(x: card.maxX, y: card.maxY), radius: corner)
        path.addArc(tangent1End: CGPoint(x: card.maxX, y: card.maxY),
                    tangent2End: CGPoint(x: card.minX, y: card.maxY), radius: corner)
        path.addArc(tangent1End: CGPoint(x: card.minX, y: card.maxY),
                    tangent2End: CGPoint(x: card.minX, y: card.minY), radius: corner)
        path.addArc(tangent1End: CGPoint(x: card.minX, y: card.minY),
                    tangent2End: CGPoint(x: card.maxX, y: card.minY), radius: corner)
        path.closeSubpath()
        guard !pointsUp else { return path }
        // Drawn pointing up; mirrored top to bottom for the arrow below.
        return path.applying(CGAffineTransform(translationX: 0, y: rect.minY + rect.maxY).scaledBy(x: 1, y: -1))
    }

    func inset(by amount: CGFloat) -> PerchCalloutShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// Marks a control that opens and closes the details itself, so the
/// details' outside-click watch leaves that click to the control.
final class DetailsToggleRegionView: NSView {
    static func contains(_ point: NSPoint, in window: NSWindow) -> Bool {
        guard let root = window.contentView else { return false }
        return hits(point, under: root)
    }

    private static func hits(_ point: NSPoint, under view: NSView) -> Bool {
        for subview in view.subviews {
            if let region = subview as? DetailsToggleRegionView, !region.isHiddenOrHasHiddenAncestor,
               region.convert(region.bounds, to: nil).contains(point) { return true }
            if hits(point, under: subview) { return true }
        }
        return false
    }
}
