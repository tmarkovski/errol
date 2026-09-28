// Adapted from PermissionFlow 2.9.1 (https://github.com/jaywcjlove/PermissionFlow),
// MIT License, Copyright (c) 2026 小弟调调. See THIRD_PARTY_NOTICES.txt.
//
// The window that holds the permission guide: a borderless panel that
// floats just under System Settings' window, lined up with the pane beside
// its sidebar, where the list is. It never becomes key or activates Errol,
// so System Settings keeps the focus while the user drags Errol from the
// panel into the list. PermissionGuide tells it where the Settings window
// is. The panel sizes itself to the card PermissionGuideView draws, rises
// into place under the window once the window is on screen, and steps
// aside while a drag is under way.

import AppKit
import QuartzCore
import SwiftUI

final class GuidePanel: NSPanel {
    /// Called when the panel is pressed, so System Settings comes along in
    /// front of other apps' windows.
    private let onPress: () -> Void
    private let hostingView: NSHostingView<GuideCard>
    /// A second copy of the card that is never shown. It measures the card
    /// at a width before the panel takes that width, which a hosting view's
    /// fitting size can't do: that measures at the card's widest, unwrapped
    /// width.
    private let sizingHost: NSHostingController<GuideCard>
    /// The Settings window's frame that the panel was last placed under.
    private var settingsFrame: CGRect?
    /// The displayed card's height, with the panel width it was laid out
    /// at. It is the most current measure, since the sizing copy picks up a
    /// change in the model a moment later than the displayed card does.
    private var displayedCard: (panelWidth: CGFloat, height: CGFloat)?
    private var isPassingThrough = false
    /// When the panel's entrance ends. Until then, a move of the Settings
    /// window steers the entrance to the new place instead of cutting it
    /// short.
    private var entranceEnds: CFTimeInterval = 0

    private static let initialWidth: CGFloat = 420
    /// System Settings' sidebar. The panel lines up with the pane beside
    /// it, which is what the user is working in, rather than with the
    /// whole window.
    private static let sidebarWidth: CGFloat = 230
    /// The narrowest the panel gets under a narrow Settings window.
    private static let minimumWidth: CGFloat = 240
    private static let screenInset: CGFloat = 12
    /// The space between the Settings window's bottom edge and the panel.
    private static let gapBelowSettings: CGFloat = 3
    /// The panel comes in the way a popover does, with a short rise and a
    /// fade, rather than traveling from the button that opened it. It has
    /// its final size the whole way, so the card is laid out once and
    /// nothing in it reflows while it moves.
    private static let entranceDuration: TimeInterval = 0.3
    private static let entranceRise: CGFloat = 16
    private static let draggingAlpha: CGFloat = 0.72

    init(model: PermissionGuideModel, onPress: @escaping () -> Void) {
        self.onPress = onPress
        hostingView = NSHostingView(rootView: GuideCard(model: model))
        sizingHost = NSHostingController(rootView: GuideCard(model: model))
        sizingHost.sizingOptions = []
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.initialWidth, height: 1),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        level = .floating
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        hostingView.rootView = GuideCard(model: model) { [weak self] size in
            self?.cardDidResize(to: size)
        }
        // The panel's frame is set in one place, from the measured card, and
        // the hosting view must not push a size of its own onto the window.
        // Left to its default, NSHostingView advertises the SwiftUI view's
        // intrinsic size to the window on every layout pass. That size can
        // differ from the one measured for the card, so the window grows
        // past the size it was given, and each later setFrame from snap(to:)
        // is undone on the next layout pass, which can leave the panel stuck
        // off screen. With no sizing options, the measured height is the
        // only source of the panel's geometry.
        hostingView.sizingOptions = []
        contentView = hostingView
        setContentSize(NSSize(width: Self.initialWidth, height: cardHeight(for: Self.initialWidth)))
    }

    // MARK: Staying out of the way

    /// The panel never takes the focus, so System Settings stays the window
    /// the user is working in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// If the system makes the panel key anyway, System Settings is brought
    /// back in front.
    override func becomeKey() {
        super.becomeKey()
        onPress()
    }

    override func becomeMain() {
        super.becomeMain()
        onPress()
    }

    /// A press on the panel brings System Settings along, then goes on to
    /// the panel's content as usual.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            onPress()
        }
        super.sendEvent(event)
    }

    // MARK: Placement

    /// Brings the panel in under the Settings window the first time it is
    /// placed there: it appears a little low and clear, and rises into
    /// place as it fades in. Under Reduce Motion it only fades in.
    func present(under settingsFrame: CGRect) {
        self.settingsFrame = settingsFrame
        let target = targetFrame(for: settingsFrame)
        let rise = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.entranceRise
        alphaValue = 0
        setFrame(target.offsetBy(dx: 0, dy: -rise), display: true)
        orderFrontRegardless()
        glide(to: target, over: Self.entranceDuration)
    }

    /// Moves the panel under the Settings window's latest frame. During
    /// the entrance, the panel glides on to the new place in the time the
    /// entrance has left, since the window can still be settling as it
    /// opens.
    func snap(to settingsFrame: CGRect) {
        self.settingsFrame = settingsFrame
        let target = targetFrame(for: settingsFrame)
        let remaining = entranceEnds - CACurrentMediaTime()
        if remaining > 0 {
            glide(to: target, over: remaining)
            return
        }
        setFrame(target, display: false)
        if !isPassingThrough { orderFrontRegardless() }
    }

    /// Animates the panel to a frame and to full opacity, quick off the
    /// mark and slowing into place. AppKit runs the animation at the
    /// display's rate. The shadow is taken again at the end, from the card
    /// drawn whole, since the panel came in before its first frame had
    /// drawn.
    private func glide(to target: CGRect, over duration: TimeInterval) {
        entranceEnds = CACurrentMediaTime() + duration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            animator().setFrame(target, display: true)
            animator().alphaValue = isPassingThrough ? Self.draggingAlpha : 1
        }, completionHandler: { [weak self] in self?.invalidateShadow() })
    }

    /// While the tile is dragged, the pointer passes through the panel so
    /// the list under it can take the drop, and the panel dims to show it
    /// is out of the way.
    func setDraggingPassthrough(_ isDragging: Bool) {
        isPassingThrough = isDragging
        ignoresMouseEvents = isDragging
        alphaValue = isDragging ? Self.draggingAlpha : 1
        if isDragging {
            orderBack(nil)
        } else {
            orderFrontRegardless()
        }
    }

    /// Under the Settings window and as wide as its pane, kept on the
    /// screen that holds most of the window, the one GuideWindowTracker
    /// also converts its frame through. Near the bottom of the screen, the
    /// panel stays on screen and overlaps the window instead.
    private func targetFrame(for settingsFrame: CGRect) -> CGRect {
        func overlap(_ s: NSScreen) -> CGFloat {
            let r = s.frame.intersection(settingsFrame)
            return r.isNull ? 0 : r.width * r.height
        }
        let screen = NSScreen.screens.filter { $0.frame.intersects(settingsFrame) }
            .max { overlap($0) < overlap($1) }?.visibleFrame ?? settingsFrame
        let width = min(max(Self.minimumWidth, settingsFrame.width - Self.sidebarWidth),
                        screen.width - Self.screenInset * 2)
        let height = cardHeight(for: width)
        var origin = CGPoint(x: settingsFrame.minX + Self.sidebarWidth,
                             y: settingsFrame.minY - Self.gapBelowSettings - height)
        origin.x = max(screen.minX + Self.screenInset, min(origin.x, screen.maxX - width - Self.screenInset))
        origin.y = max(screen.minY + Self.screenInset, min(origin.y, screen.maxY - height - Self.screenInset))
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    // MARK: Sizing

    /// The card's height at a panel width. The displayed card's own report
    /// wins when it was laid out at that width; otherwise the sizing copy
    /// measures it.
    private func cardHeight(for width: CGFloat) -> CGFloat {
        if let displayedCard, abs(displayedCard.panelWidth - width) < 0.5 {
            return displayedCard.height
        }
        return sizingHost.sizeThatFits(in: CGSize(width: width, height: .infinity)).height
    }

    /// The displayed card reports its size after each layout pass. When
    /// its height no longer matches the panel's, its content changed, and
    /// the panel resizes around it.
    private func cardDidResize(to size: CGSize) {
        displayedCard = (hostingView.bounds.width, size.height)
        // Reported mid-layout; the frame changes on the next turn.
        DispatchQueue.main.async { [weak self] in self?.refit() }
    }

    /// Only a panel that has been placed under the Settings window refits.
    private func refit() {
        guard let settingsFrame, let displayedCard,
              abs(displayedCard.panelWidth - frame.width) < 0.5,
              abs(displayedCard.height - frame.height) >= 0.5 else { return }
        snap(to: settingsFrame)
    }
}

/// The card as the panel hosts it: PermissionGuideView at its own height for
/// the panel's width, reporting its size whenever that changes.
private struct GuideCard: View {
    let model: PermissionGuideModel
    var onSize: ((CGSize) -> Void)?

    var body: some View {
        PermissionGuideView(model: model)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize?($0) }
    }
}
