// What the connection drag draws: a lead out of the icon to the pointer,
// and an area over each message field the icon can be dropped on. Both
// are click-through panels of Errol's own, the way the picker's highlight
// and the veil are drawn — Errol's windows over another app's, needing no
// permission and touching nothing in the app. The areas sit a level under
// the console; the lead a level over it, so it leaves the icon itself and
// the gesture reads as running a cable from the app's perch to its field.
// Each area says what the drop will do, so the gesture teaches where
// Errol writes: the field is where the relay pastes and sends, and the
// conversation above it is what it reads.

import AppKit

/// One area with its words: the invitation while the pointer is elsewhere,
/// and what releasing will do once the pointer is over it.
struct ConnectionDropArea: Equatable {
    let zone: ConnectionDropZone
    let invitation: String
    let explanation: String
    let armedHeadline: String
    let armedDetail: String
}

/// Main-thread API; the setup controller starts the lead as the drag
/// begins, moves it with the pointer, shows the areas once the engine has
/// read them, arms the one under the pointer, and hides it all when the
/// drag ends either way. Points and frames are AX coordinates.
final class ConnectionDropOverlay {
    private var panels: [DropAreaPanel] = []
    private var areas: [ConnectionDropArea] = []
    private var leads: [DragLeadPanel] = []
    private var lead: (icon: CGRect, point: CGPoint, armed: Bool)?

    /// The lead out of `icon`, on every display, from here until `hide`.
    func beginLead(from icon: CGRect) {
        lead = (icon, CGPoint(x: icon.midX, y: icon.midY), false)
        for panel in leads { panel.close() }
        leads = NSScreen.screens.map(DragLeadPanel.init(screen:))
        drawLead()
    }

    func moveLead(to point: CGPoint) {
        guard lead != nil else { return }
        lead?.point = point
        drawLead()
    }

    func show(_ areas: [ConnectionDropArea]) {
        self.areas = areas
        while panels.count < areas.count { panels.append(DropAreaPanel.make()) }
        for (index, panel) in panels.enumerated() {
            if index < areas.count {
                panel.show(areas[index], armed: false)
            } else {
                panel.hide()
            }
        }
    }

    /// The area over `window` reads as ready to take the drop, and the
    /// lead's plug with it; the rest invite. nil disarms them all.
    func arm(_ window: WindowID?) {
        for (index, area) in areas.enumerated() where index < panels.count {
            panels[index].show(area, armed: area.zone.window == window)
        }
        if lead != nil, lead?.armed != (window != nil) {
            lead?.armed = window != nil
            drawLead()
        }
    }

    func hide() {
        areas = []
        for panel in panels { panel.hide() }
        lead = nil
        for panel in leads { panel.close() }
        leads = []
    }

    private func drawLead() {
        guard let lead else { return }
        for panel in leads {
            panel.drawing.render(icon: axRect(lead.icon), to: axRect(CGRect(origin: lead.point, size: .zero)).origin,
                                 armed: lead.armed, screenOrigin: panel.frame.origin)
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }
}

/// The lead's surface: one per display, the display's size, so the line
/// never crosses a gap between monitors on one backing store. A level
/// over the console, and click-through, so it leaves the icon itself
/// without taking a single event from the drag.
private final class DragLeadPanel: NSPanel {
    let drawing = DragLeadDrawing()

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
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.transient, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = drawing
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The lead: a line from the icon's edge to the pointer with a plug at
/// its end, sagging a little between the way a cable hangs. Implicit
/// animations are off — the line follows the pointer, and a quarter-second
/// lag on every move would read as drag. Nothing shows while the pointer
/// is still over the icon.
final class DragLeadDrawing: NSView {
    private let line = CAShapeLayer()
    private let plug = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        for shape in [line, plug] {
            shape.actions = ["path": NSNull(), "opacity": NSNull(), "lineWidth": NSNull(),
                             "strokeColor": NSNull(), "fillColor": NSNull(), "shadowColor": NSNull()]
            shape.opacity = 0
            layer?.addSublayer(shape)
        }
        line.fillColor = nil
        line.lineCap = .round
        line.shadowOffset = .zero
        line.shadowRadius = 5
        line.shadowOpacity = 0.45
        plug.lineWidth = 2
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `icon` and `end` in Cocoa screen coordinates; `screenOrigin` this
    /// display's, which the layers' coordinates are relative to.
    func render(icon: CGRect, to end: CGPoint, armed: Bool, screenOrigin: CGPoint) {
        func local(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x - screenOrigin.x, y: point.y - screenOrigin.y)
        }
        let center = local(CGPoint(x: icon.midX, y: icon.midY))
        let end = local(end)
        let radius = min(icon.width, icon.height) / 2
        let dx = end.x - center.x
        let dy = end.y - center.y
        let distance = hypot(dx, dy)
        let palette = AppearanceStore.shared.theme.palette

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard distance > radius else {
            line.opacity = 0
            plug.opacity = 0
            return
        }
        // Out of the icon's edge toward the pointer, with a sag that grows
        // with the reach and stops short of looking slack.
        let start = CGPoint(x: center.x + dx / distance * radius, y: center.y + dy / distance * radius)
        let sag = min(36, distance * 0.12)
        let control = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - sag)
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        line.path = path
        line.strokeColor = palette.accent.cgColor
        line.shadowColor = palette.accent.cgColor
        line.lineWidth = armed ? 3 : 2.5
        line.opacity = 1

        let plugRadius: CGFloat = armed ? 7 : 5
        plug.path = CGPath(ellipseIn: CGRect(x: end.x - plugRadius, y: end.y - plugRadius,
                                             width: plugRadius * 2, height: plugRadius * 2), transform: nil)
        plug.fillColor = palette.accent.cgColor
        plug.strokeColor = palette.paper.cgColor
        plug.opacity = 1
    }
}

/// One area: the field's outline and tint, with a chip in it saying what
/// the drop does. Never key or main, off Mission Control, and able to
/// stand on a full-screen Space when the window it marks is there.
private final class DropAreaPanel: NSPanel {
    /// Around the area, for the stroke that straddles its edge.
    static let margin: CGFloat = 4
    static let fade: TimeInterval = 0.15

    private let field = CAShapeLayer()
    private let chip = NSView()
    private let headline = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var shown = false
    private var showing: (area: ConnectionDropArea, armed: Bool)?

    static func make() -> DropAreaPanel {
        let panel = DropAreaPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        panel.collectionBehavior = [.transient, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let content = NSView()
        content.wantsLayer = true
        panel.contentView = content
        content.layer?.addSublayer(panel.field)

        panel.chip.wantsLayer = true
        panel.chip.layer?.cornerRadius = 8
        panel.chip.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(panel.chip)
        panel.headline.font = .systemFont(ofSize: 13, weight: .semibold)
        panel.detail.font = .systemFont(ofSize: 11)
        let lines = NSStackView(views: [panel.headline, panel.detail])
        lines.orientation = .vertical
        lines.alignment = .centerX
        lines.spacing = 1
        lines.translatesAutoresizingMaskIntoConstraints = false
        panel.chip.addSubview(lines)
        for label in [panel.headline, panel.detail] {
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        NSLayoutConstraint.activate([
            panel.chip.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            panel.chip.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            panel.chip.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor,
                                              constant: -Self.margin * 2 - 16),
            lines.topAnchor.constraint(equalTo: panel.chip.topAnchor, constant: 6),
            lines.bottomAnchor.constraint(equalTo: panel.chip.bottomAnchor, constant: -6),
            lines.leadingAnchor.constraint(equalTo: panel.chip.leadingAnchor, constant: 12),
            lines.trailingAnchor.constraint(equalTo: panel.chip.trailingAnchor, constant: -12),
        ])
        return panel
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Put the panel over the area (AX coordinates) with the words for the
    /// state: fading in if it is not up, moving it if it is. Arming only
    /// deepens the tint, thickens the stroke, and swaps the words.
    func show(_ area: ConnectionDropArea, armed: Bool) {
        let frame = axRect(area.zone.frame).insetBy(dx: -Self.margin, dy: -Self.margin)
        if shown, let showing, showing.area == area, showing.armed == armed, frame == self.frame { return }
        showing = (area, armed)
        // The console's accent, resolved for the current appearance.
        let palette = AppearanceStore.shared.theme.palette
        field.fillColor = palette.accent.withAlphaComponent(armed ? 0.24 : 0.12).cgColor
        field.strokeColor = palette.accent.cgColor
        field.lineWidth = armed ? 3 : 2
        chip.layer?.backgroundColor = palette.accent.cgColor
        headline.textColor = palette.onAccent
        detail.textColor = palette.onAccent.withAlphaComponent(0.85)
        headline.stringValue = armed ? area.armedHeadline : area.invitation
        detail.stringValue = armed ? area.armedDetail : area.explanation
        // A one-line field has room for the headline alone.
        detail.isHidden = area.zone.frame.height < 64
        let bounds = NSRect(origin: .zero, size: frame.size).insetBy(dx: Self.margin, dy: Self.margin)
        let corner = min(16, bounds.height / 2)
        field.path = CGPath(roundedRect: bounds, cornerWidth: corner, cornerHeight: corner, transform: nil)
        if shown {
            if frame != self.frame { setFrame(frame, display: true) }
            return
        }
        shown = true
        if !isVisible {
            alphaValue = 0
            setFrame(frame, display: false)
            orderFrontRegardless()
        } else if frame != self.frame {
            setFrame(frame, display: true)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard shown else { return }
        shown = false
        showing = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fade
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !shown else { return }
            orderOut(nil)
        })
    }
}
