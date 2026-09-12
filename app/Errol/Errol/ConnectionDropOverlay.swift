// The areas drawn for the connection drag: one over each message field
// the dragged icon can be dropped on, on click-through panels a level
// under the console, the way the picker's highlight and the veil are
// drawn — Errol's own windows over another app's, needing no permission
// and touching nothing in the app. Each area says what the drop will do,
// so the gesture teaches where Errol writes: the field is where the relay
// pastes and sends, and the conversation above it is what it reads.

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

/// Main-thread API; the setup controller shows the areas once the engine
/// has read them, arms the one under the pointer, and hides them all when
/// the drag ends either way.
final class ConnectionDropOverlay {
    private var panels: [DropAreaPanel] = []
    private var areas: [ConnectionDropArea] = []

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

    /// The area over `window` reads as ready to take the drop; the rest
    /// invite. nil disarms them all.
    func arm(_ window: WindowID?) {
        for (index, area) in areas.enumerated() where index < panels.count {
            panels[index].show(area, armed: area.zone.window == window)
        }
    }

    func hide() {
        areas = []
        for panel in panels { panel.hide() }
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
