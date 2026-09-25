import AppKit

/// The status item's image. While nothing runs, it is the Errol symbol as a
/// template, drawn by macOS in the menu bar's own ink. For as long as a run
/// lasts, paused included, the item is lit the way macOS lights its
/// microphone indicator while the mic is in use: the mark turns white, on
/// a capsule of the theme's accent (StatusItemLight) that fills the item.
enum StatusIcon {
    static func image(running: Bool) -> NSImage? {
        // Keep the original owl as a fallback; ErrolSymbol is the default mark.
        guard let mark = NSImage(named: "ErrolSymbol") ?? NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: nil),
            let image = running ? lit(mark) : idle(mark) else { return nil }
        image.accessibilityDescription = running ? "Errol is running" : "Errol"
        return image
    }

    /// The two bubbles make a square mark, and at 16 pt it stands as tall
    /// as the system's own menu bar glyphs; 18 pt towered over them.
    private static let size = NSSize(width: 16, height: 16)

    private static func idle(_ mark: NSImage) -> NSImage? {
        guard let image = mark.copy() as? NSImage else { return nil }
        image.size = size
        image.isTemplate = true
        return image
    }

    /// White whatever the menu bar's appearance, since it stands on the
    /// capsule rather than on the bar. Not a template, so macOS keeps it
    /// white.
    private static func lit(_ mark: NSImage) -> NSImage? {
        NSImage(size: size, flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // The mark is recolored in a layer of its own, so the white
            // lands on its strokes alone.
            context.beginTransparencyLayer(in: bounds, auxiliaryInfo: nil)
            mark.draw(in: bounds)
            NSColor.white.setFill()
            bounds.fill(using: .sourceAtop)
            context.endTransparencyLayer()
            return true
        }
    }
}

/// The lit item's capsule, which fills the same place as the system's
/// pressed highlight. The status item's button is only the 22-pt square at
/// the middle of the item's window, and the highlight spans the whole
/// window, so the capsule lives in the window's content view, under the
/// button. It is as wide as the window and 2 pt taller than the button.
/// Measured on macOS 27 in a 30-pt menu bar: the window is 38 × 30 and the
/// highlight a 42 × 24 capsule, 2 pt wider than the window on each side,
/// where nothing in the window can draw.
final class StatusItemLight: NSView {
    private var fill: CGColor?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .minYMargin, .maxYMargin]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// Lights the item that holds `button`, or puts the light out. The
    /// capsule takes the accent as the light appearance has it, the deeper
    /// of the theme's two, over a light menu bar or a dark one, so the
    /// white mark reads on it either way, as the microphone's white glyph
    /// reads on its orange.
    func show(_ lit: Bool, accent: NSColor, behind button: NSStatusBarButton?) {
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { fill = accent.cgColor }
        // Joined at the first lighting, and again if the item's window was
        // ever made anew.
        if lit, let button, let content = button.window?.contentView, superview !== content {
            removeFromSuperview()
            let square = content.convert(button.bounds, from: button)
            frame = NSRect(x: 0, y: square.midY - square.height / 2 - 1,
                           width: content.bounds.width, height: square.height + 2)
            content.addSubview(self, positioned: .below, relativeTo: nil)
        }
        isHidden = !lit
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fill
        layer?.cornerRadius = bounds.height / 2
    }

    /// Clicks go to the status item as if the capsule weren't there.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
