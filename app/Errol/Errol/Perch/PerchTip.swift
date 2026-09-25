// A tip that floats in a panel of its own under the console while the
// pointer rests on what it describes: a side's icon says what a click does
// and what the app is set to. It is plain black with white text, no edge,
// arrow, or shadow, and it never takes the pointer or the keyboard, so it
// can stand over the conversation summary without getting in the way.
//
// Its outer edge lines up with the anchor's, so a tip from an icon at the
// console's end runs inward. It flips above the console near the screen's
// bottom edge, and goes away with the console: a child panel would
// otherwise stay on screen without it.

import AppKit
import SwiftUI

struct PerchTipAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.dismiss = { isPresented = false }
        guard isPresented else { coordinator.close(); return }
        coordinator.show(from: view, content: content())
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.close() }

    final class Coordinator {
        var dismiss: (() -> Void)?
        private var panel: NSPanel?
        private var host: NSHostingView<PerchTip<Content>>?
        private weak var anchor: NSView?
        /// The tip's size as SwiftUI last laid it out.
        private var size: CGSize?
        private var observer: NSObjectProtocol?

        /// The tip's gap from the console's edge.
        static var gap: CGFloat { Perch.s(6) }
        private static var screenMargin: CGFloat { 8 }

        func show(from anchor: NSView, content: Content) {
            guard let parent = anchor.window else { return }
            self.anchor = anchor
            let tip = PerchTip(content: content) { [weak self] size in
                // Reported mid-layout; the frame changes on the next turn.
                DispatchQueue.main.async { self?.resize(to: size) }
            }
            if let host {
                host.rootView = tip
                place()
                return
            }
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = NSWindow.Level(rawValue: parent.level.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let host = NSHostingView(rootView: tip)
            host.sizingOptions = []
            panel.contentView = host
            self.panel = panel
            self.host = host
            size = host.fittingSize
            place()
            panel.alphaValue = 0
            parent.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
            // Ordering the console out changes its occlusion state, whichever
            // way it went: Esc, ⌘W, or the status item.
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: parent, queue: .main) { [weak self, weak parent] _ in
                guard let parent, !parent.isVisible || !parent.occlusionState.contains(.visible) else { return }
                self?.dismiss?()
            }
        }

        func close() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let panel else { return }
            self.panel = nil
            host = nil
            size = nil
            panel.parent?.removeChildWindow(panel)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.08
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }

        deinit { close() }

        private func resize(to size: CGSize) {
            guard panel != nil, size.width > 0, size.height > 0, size != self.size else { return }
            self.size = size
            place()
        }

        /// Under the console, or over it when the screen's bottom is too
        /// close, with its outer edge on the anchor's. Kept on the screen.
        private func place() {
            guard let panel, let anchor, let parent = anchor.window,
                  let size, size.width > 0, size.height > 0 else { return }
            let target = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let console = parent.frame
            let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? console
            let below = console.minY - Self.gap - size.height
            let y = below >= screen.minY + Self.screenMargin ? below : console.maxY + Self.gap
            var x = target.midX < console.midX ? target.minX : target.maxX - size.width
            x = min(max(x, screen.minX + Self.screenMargin), screen.maxX - size.width - Self.screenMargin)
            let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            guard panel.frame != frame else { return }
            panel.setFrame(frame, display: true)
        }
    }
}

/// The tip's face: its content in white on black, in a rounded rectangle
/// that hugs it, up to a width where longer lines wrap.
struct PerchTip<Content: View>: View {
    let content: Content
    var onSize: (CGSize) -> Void = { _ in }

    static var maxWidth: CGFloat { Perch.s(280) }
    static var corner: CGFloat { Perch.s(9) }

    var body: some View {
        PerchCappedWidth(maxWidth: Self.maxWidth) {
            content
                .padding(.horizontal, Perch.s(11))
                .padding(.vertical, Perch.s(9))
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background(RoundedRectangle(cornerRadius: Self.corner, style: .continuous).fill(.black))
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }
}

/// Lays its content out at the width it would take on one line, up to
/// `maxWidth`, where it wraps. A flexible frame can't do this for a view
/// that sizes itself: asked for its ideal size, it gets its child's full
/// width and lets the text run past its edge.
struct PerchCappedWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let width = min(view.sizeThatFits(.unspecified).width, maxWidth)
        return view.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
