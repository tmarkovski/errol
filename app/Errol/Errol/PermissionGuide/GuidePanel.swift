// Adapted from PermissionFlow 2.9.1 (https://github.com/jaywcjlove/PermissionFlow),
// MIT License, Copyright (c) 2026 小弟调调. See THIRD_PARTY_NOTICES.txt.
//
// The window that holds the permission guide: a borderless panel that
// floats just under System Settings' window, lined up with the pane beside
// its sidebar, where the list is. It never becomes key or activates Errol,
// so System Settings keeps the focus while the user drags Errol from the
// panel into the list. PermissionGuide tells it where the Settings window
// is. The panel sizes itself to the card PermissionGuideView draws, flies
// in from the button that opened it, and steps aside while a drag is under
// way.

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
    /// Whether the panel is waiting at the button that opened it for the
    /// Settings window to appear.
    private var isWaitingAtSource = false
    private var isPassingThrough = false

    private var launchTimer: Timer?
    private var launchStart: CFTimeInterval = 0
    private var launchFrom = NSRect.zero
    private var launchTo = NSRect.zero
    private var isLaunching = false

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
    /// The fly-in is quick enough to feel like a response to the click and
    /// long enough to show where the panel went. It never overshoots, so it
    /// doesn't jitter while the Settings window is still settling.
    private static let launchDuration: TimeInterval = 0.72
    private static let springResponse: Double = 0.72
    private static let launchAlpha: CGFloat = 0.9
    /// The panel starts the fly-in at this fraction of its size.
    private static let launchScale: CGFloat = 0.58
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

    /// Stops the fly-in with the panel, whose timer would otherwise keep
    /// running after it closed mid-flight.
    override func close() {
        stopLaunch()
        super.close()
    }

    // MARK: Placement

    /// Shows the panel where it is.
    func show() {
        orderFrontRegardless()
    }

    /// Shows the panel at the button that opened it, where it waits until
    /// the Settings window appears and it can fly there.
    func show(at source: CGRect) {
        stopLaunch()
        isLaunching = false
        alphaValue = 1
        setContentSize(NSSize(width: frame.width, height: cardHeight(for: frame.width)))
        setFrame(launchSourceFrame(around: source), display: false)
        isWaitingAtSource = true
        orderFrontRegardless()
    }

    /// Flies the panel from the button that opened it to its place under
    /// the Settings window.
    func present(from source: CGRect, to settingsFrame: CGRect) {
        stopLaunch()
        self.settingsFrame = settingsFrame
        let target = targetFrame(for: settingsFrame)
        let startsWhereItWaits = isWaitingAtSource
        isWaitingAtSource = false

        guard !source.isEmpty else {
            isLaunching = false
            alphaValue = 1
            setFrame(target, display: false)
            orderFrontRegardless()
            return
        }

        isLaunching = true
        // A panel already waiting at the button starts from there, so it
        // doesn't jump to a new size as it sets off.
        launchFrom = startsWhereItWaits ? frame : launchSourceFrame(around: source)
        launchTo = target
        launchStart = CACurrentMediaTime()
        alphaValue = Self.launchAlpha
        setFrame(launchFrom, display: false)
        orderFrontRegardless()
        stepLaunch()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            // The timer runs on the main run loop, where it was added.
            MainActor.assumeIsolated { self?.stepLaunch() }
        }
        RunLoop.main.add(timer, forMode: .common)
        launchTimer = timer
    }

    /// Moves the panel under the Settings window's latest frame. During
    /// the fly-in, only the destination changes, so the motion carries on
    /// toward wherever the window went.
    func snap(to settingsFrame: CGRect) {
        self.settingsFrame = settingsFrame
        isWaitingAtSource = false
        let target = targetFrame(for: settingsFrame)
        if isLaunching {
            launchTo = target
            return
        }
        stopLaunch()
        setFrame(target, display: false)
        if !isPassingThrough { orderFrontRegardless() }
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
    /// screen the window is on. Near the bottom of the screen, the panel
    /// stays on screen and overlaps the window instead.
    private func targetFrame(for settingsFrame: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(settingsFrame) }?.visibleFrame ?? settingsFrame
        let width = min(max(Self.minimumWidth, settingsFrame.width - Self.sidebarWidth),
                        screen.width - Self.screenInset * 2)
        let height = cardHeight(for: width)
        var origin = CGPoint(x: settingsFrame.minX + Self.sidebarWidth,
                             y: settingsFrame.minY - Self.gapBelowSettings - height)
        origin.x = max(screen.minX + Self.screenInset, min(origin.x, screen.maxX - width - Self.screenInset))
        origin.y = max(screen.minY + Self.screenInset, min(origin.y, screen.maxY - height - Self.screenInset))
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    /// The panel shrunk around the button that opened it, where the fly-in
    /// starts.
    private func launchSourceFrame(around source: CGRect) -> CGRect {
        let size = CGSize(width: max(source.width, frame.width * Self.launchScale),
                          height: max(source.height, frame.height * Self.launchScale))
        return CGRect(x: source.midX - size.width / 2, y: source.midY - size.height / 2,
                      width: size.width, height: size.height)
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

    /// Only a panel that has arrived under the Settings window refits. On
    /// the way there, the card is laid out at the fly-in's sizes.
    private func refit() {
        guard !isLaunching, !isWaitingAtSource, let settingsFrame, let displayedCard,
              abs(displayedCard.panelWidth - frame.width) < 0.5,
              abs(displayedCard.height - frame.height) >= 0.5 else { return }
        snap(to: settingsFrame)
    }

    // MARK: The fly-in

    /// Advances the fly-in by one frame, and ends it once the panel has
    /// arrived.
    private func stepLaunch() {
        let elapsed = max(0, CACurrentMediaTime() - launchStart)
        guard elapsed < Self.launchDuration else {
            isLaunching = false
            stopLaunch()
            alphaValue = 1
            setFrame(launchTo, display: true)
            return
        }
        let progress = springProgress(at: elapsed)
        alphaValue = Self.launchAlpha + (1 - Self.launchAlpha) * progress
        setFrame(curvedFrame(from: launchFrom, to: launchTo, progress: progress), display: true)
    }

    private func stopLaunch() {
        launchTimer?.invalidate()
        launchTimer = nil
    }

    /// A critically damped spring: the panel speeds away and settles
    /// without a hard stop or an overshoot.
    private func springProgress(at elapsed: TimeInterval) -> CGFloat {
        let omega = 2 * Double.pi / Self.springResponse
        let progress = 1 - exp(-omega * elapsed) * (1 + omega * elapsed)
        return min(max(progress, 0), 1)
    }

    /// The frame at a point along the fly-in. The center follows a
    /// quadratic curve that bows upward over the straight line, which reads
    /// as the panel being thrown to its place rather than slid there, and
    /// the size grows from the start's to the end's along the way.
    private func curvedFrame(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        let size = CGSize(width: start.width + (end.width - start.width) * progress,
                          height: start.height + (end.height - start.height) * progress)
        let startCenter = CGPoint(x: start.midX, y: start.midY)
        let endCenter = CGPoint(x: end.midX, y: end.midY)
        let distance = hypot(endCenter.x - startCenter.x, endCenter.y - startCenter.y)
        let lift = min(140, max(44, distance * 0.18))
        let control = CGPoint(x: (startCenter.x + endCenter.x) / 2,
                              y: max(startCenter.y, endCenter.y) + lift)
        let rest = 1 - progress
        let center = CGPoint(
            x: rest * rest * startCenter.x + 2 * rest * progress * control.x + progress * progress * endCenter.x,
            y: rest * rest * startCenter.y + 2 * rest * progress * control.y + progress * progress * endCenter.y)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
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
