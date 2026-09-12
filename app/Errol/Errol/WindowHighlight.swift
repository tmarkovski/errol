// The highlight over a candidate window while it is being chosen: an
// accent outline laid over the window's frame, with a chip naming what
// it shows, on a click-through panel a level under the console. The same
// mechanism as the veil and the transfer overlay — Errol's own window on
// top of another app's — so nothing here needs a permission, and nothing
// here touches the window it marks.

import AppKit

/// Main-thread API; the setup controller shows it over the picker's
/// current candidate and hides it when the choice is made or dropped.
final class WindowHighlight {
    private var panel: HighlightPanel?

    var windowNumber: UInt32? { panel.map { UInt32($0.windowNumber) } }

    /// Outline `frame` (AX coordinates) and name it.
    func show(frame: CGRect, label: String) {
        let panel = self.panel ?? HighlightPanel.make()
        self.panel = panel
        panel.label = label
        panel.show(at: axRect(frame))
    }

    func hide() {
        panel?.hide()
    }
}

private final class HighlightPanel: NSPanel {
    static let cornerRadius: CGFloat = 12
    static let fade: TimeInterval = 0.15

    var label: String {
        get { chip.stringValue }
        set { chip.stringValue = newValue }
    }
    private let outline = CAShapeLayer()
    private let chip = NSTextField(labelWithString: "")
    private let chipBack = NSView()
    private var shown = false

    static func make() -> HighlightPanel {
        let panel = HighlightPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
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
        panel.outline.fillColor = nil
        panel.outline.lineWidth = 3
        content.layer?.addSublayer(panel.outline)

        panel.chipBack.wantsLayer = true
        panel.chipBack.layer?.cornerRadius = 8
        panel.chipBack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(panel.chipBack)
        panel.chip.font = .systemFont(ofSize: 13, weight: .semibold)
        panel.chip.alignment = .center
        panel.chip.translatesAutoresizingMaskIntoConstraints = false
        panel.chipBack.addSubview(panel.chip)
        NSLayoutConstraint.activate([
            panel.chipBack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            panel.chipBack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            panel.chip.leadingAnchor.constraint(equalTo: panel.chipBack.leadingAnchor, constant: 12),
            panel.chip.trailingAnchor.constraint(equalTo: panel.chipBack.trailingAnchor, constant: -12),
            panel.chip.topAnchor.constraint(equalTo: panel.chipBack.topAnchor, constant: 6),
            panel.chip.bottomAnchor.constraint(equalTo: panel.chipBack.bottomAnchor, constant: -6),
        ])
        return panel
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(at frame: NSRect) {
        // The console's accent, resolved for the current appearance.
        let accent = AppearanceStore.shared.theme.palette.accent
        outline.strokeColor = accent.cgColor
        chipBack.layer?.backgroundColor = accent.cgColor
        chip.textColor = AppearanceStore.shared.theme.palette.onAccent
        let inset = outline.lineWidth / 2
        let bounds = NSRect(origin: .zero, size: frame.size).insetBy(dx: inset, dy: inset)
        outline.path = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius,
                              transform: nil)
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
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fade
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !shown else { return }
            orderOut(nil)
        })
    }
}
