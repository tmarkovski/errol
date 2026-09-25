import AppKit

/// The status item's image. While nothing runs, it is the Errol symbol as a
/// template, drawn by macOS in the menu bar's own ink. For as long as a run
/// lasts, paused included, the symbol is lit the way macOS lights the
/// microphone's indicator while the mic is in use: the mark on a rounded
/// rect of the theme's accent, colored like the console's prominent button.
enum StatusIcon {
    /// The lit rect fills the width of the square status item (the bar's
    /// thickness, 22 pt) and stands a little taller than the idle mark.
    /// Whole points keep the rect and the mark on the pixel grid at 1x.
    private static let litSize = NSSize(width: 22, height: 18)
    private static let litRadius: CGFloat = 6
    /// Inside the rect the mark drops to 14 pt; at 12 its strokes thinned
    /// past reading.
    private static let litMark: CGFloat = 14

    static func image(running: Bool, palette: PerchPalette) -> NSImage? {
        // Keep the original owl as a fallback; ErrolSymbol is the default mark.
        guard let mark = NSImage(named: "ErrolSymbol") ?? NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: nil),
            let image = running ? lit(mark, palette: palette) : idle(mark) else { return nil }
        image.accessibilityDescription = running ? "Errol is running" : "Errol"
        return image
    }

    /// The two bubbles make a square mark, and at 16 pt it stands as tall
    /// as the system's own menu bar glyphs; 18 pt towered over them.
    private static func idle(_ mark: NSImage) -> NSImage? {
        guard let image = mark.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }

    /// Not a template, so macOS keeps its colors. They are resolved each
    /// time the image is drawn, for the appearance it is drawn in, so the
    /// rect follows the menu bar between light and dark the way the
    /// console's accent does.
    private static func lit(_ mark: NSImage, palette: PerchPalette) -> NSImage? {
        NSImage(size: litSize, flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            palette.accent.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: litRadius, yRadius: litRadius).fill()
            let box = bounds.insetBy(dx: (bounds.width - litMark) / 2, dy: (bounds.height - litMark) / 2)
            // The mark is recolored in a layer of its own, so the ink
            // lands on its strokes and not on the rect under them.
            context.beginTransparencyLayer(in: box, auxiliaryInfo: nil)
            mark.draw(in: box)
            palette.onAccent.setFill()
            box.fill(using: .sourceAtop)
            context.endTransparencyLayer()
            return true
        }
    }
}
