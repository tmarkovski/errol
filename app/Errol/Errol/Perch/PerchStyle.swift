// Shared type, geometry, and semantic color access. Theme definitions live
// in PerchPalette; AppearanceStore persists the selection.

import AppKit
import SwiftUI

/// Shared geometry and semantic colors. Reading the observable theme here
/// makes existing SwiftUI readers update in place when the selection changes.
enum Perch {
    // MARK: Palette

    private static var palette: PerchPalette { AppearanceStore.shared.theme.palette }

    static var shell: Color { Color(nsColor: palette.shell) }
    static var well: Color { Color(nsColor: palette.well) }
    static var paper: Color { Color(nsColor: palette.paper) }
    static var panelEdge: Color { Color(nsColor: palette.panelEdge) }
    static var chipEdge: Color { Color(nsColor: palette.chipEdge) }
    static var hairline: Color { Color(nsColor: palette.hairline) }
    static var ink: Color { Color(nsColor: palette.ink) }
    static var secondary: Color { Color(nsColor: palette.secondary) }
    static var muted: Color { Color(nsColor: palette.muted) }
    static var placeholder: Color { Color(nsColor: palette.placeholder) }
    static var previewInk: Color { Color(nsColor: palette.previewInk) }
    static var accent: Color { Color(nsColor: palette.accent) }
    static var accentText: Color { Color(nsColor: palette.accentText) }
    static var accentBack: Color { Color(nsColor: palette.accentBack) }
    static var onAccent: Color { Color(nsColor: palette.onAccent) }
    static var red: Color { Color(nsColor: palette.red) }
    static var redBack: Color { Color(nsColor: palette.redBack) }
    static var chatgptFeather: Color { Color(nsColor: palette.chatgptFeather) }
    static var claudeFeather: Color { Color(nsColor: palette.claudeFeather) }

    static var shellNS: NSColor { palette.shell }
    static var inkNS: NSColor { palette.ink }
    static var accentTextNS: NSColor { palette.accentText }
    static var placeholderNS: NSColor { palette.placeholder }

    // MARK: Type and measure

    /// Every length and type size is a mockup measurement put through `s`,
    /// so this one number sets how large the panel reads. The converged
    /// mockup drew at 1.0 for a 464-point card; 1.1 enlarges it slightly for
    /// laptop displays.
    static let scale: CGFloat = 1.1
    static func s(_ points: CGFloat) -> CGFloat { points * scale }
    /// System type throughout — Perch speaks native macOS, not instrument
    /// mono. The one exception asks for `mono` by name: the instruction
    /// preview, where the template's text reads as material, not chrome.
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: s(size), weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: s(size), weight: weight, design: .monospaced)
    }

    // MARK: Motion

    /// The fade every state-driven line of text takes when it changes — the
    /// turn line, the perches' sublines, the context row and the hold
    /// notice, the composer's hint — so nothing snaps.
    static let fade = Animation.easeInOut(duration: 0.2)

    /// The spring behind every control that moves rather than fades: the
    /// tab thumb sliding to the chosen shape, and an option chip growing
    /// its label.
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// The window is the composer's only outer edge. Shape tabs use a
    /// smaller radius so their selection reads as a rounded rectangle.
    static let shellCorner = s(18)
    static let tabCorner = s(6)
    /// One inset for the head and the full-width composer's contents.
    static let contentInset = s(12)
    static let primaryDiameter = s(36)
    /// The console's circular actions.
    static let actionDiameter = s(32)
    /// A step tighter than the card, for a well set inside a window: the
    /// log window's text area.
    static let insetCorner = s(10)
    /// The toolbar's segmented controls — the Send pill and the window
    /// arrangement — at their height read as rounded rectangles, like the
    /// prompt box around them, not as capsules. A thumb inside one takes
    /// this less its inset, so the two corners are concentric.
    static let controlCorner = s(10)

    /// Settings keeps its separate content-sized card.
    static let cardWidth = s(464)
    /// The capsule's footprint: the reference is 860 × 156 CSS pixels at
    /// full desktop width, taken as points and not put through `s` — here
    /// the mockup's own measure is the panel's, and every screen from
    /// permission to the ending shares it. Settings keeps its card width.
    static let widgetWidth: CGFloat = 860
    static let widgetHeight: CGFloat = 156
    /// A participant's column: the app's icon over a destination name,
    /// kept to one line and truncated in the middle.
    static let participantWidth = s(72)
    /// The content header keeps the familiar 52pt height of a unified
    /// toolbar. The borderless panel draws its controls here (PerchChrome).
    static let chromeBand: CGFloat = 52
    /// The card's top padding: the strip, plus breathing room before the
    /// avatars — the app icons' squircles read heavier than the initial
    /// circles did and crowded the wordmark with only a hair of gap.
    static let chromeInset = chromeBand + s(10)

    // MARK: The composer's measures

    /// The oval's editors shrink before wrapping, then scroll after three
    /// lines. The editor's type is the console's ordinary size, a step
    /// over the lines around the box, not a display size; both go through
    /// `s` like every other size here.
    static let promptFont = NSFont.systemFont(ofSize: s(13))
    static let promptMinimumFontSize = s(12)
    static let promptMaximumLines = 3

    /// The gap between the composer's rows: tabs, preview, hairline, editor,
    /// foot. Named because the preview zone's height is summed from it.
    static let cardGap = s(8)

    /// The instruction preview is held to two lines of its mono whatever the
    /// shape says, so the zone it sits in has one height — and Free chat,
    /// which has no instructions to preview, hands exactly that height to
    /// the editor instead (PerchComposer). The card keeps its size across
    /// every selection; only the words move. `previewSize` is the mockup
    /// size the SwiftUI font is asked for by name; the NSFont here is the
    /// same face at the same scaled size, measured the way the growing
    /// editor measures its own lines. It is a reservation, not a limit: the
    /// Text lays out its own two lines inside it, and a pixel of overrun
    /// spills into the gap below rather than costing the second line.
    static let previewSize: CGFloat = 10
    static let previewLineSpacing = s(2)
    static let previewHeight: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: s(previewSize), weight: .regular)
        let line = NSLayoutManager().defaultLineHeight(for: font)
        return ceil(2 * line + previewLineSpacing) + 1
    }()
    /// What the preview adds to the card: itself, the hairline under it, and
    /// the gap above each — the amount the editor takes back under Free chat.
    static let previewZoneHeight = previewHeight + 2 * cardGap + 1
}

/// The console and permission screen keep this height through every state.
/// Settings reports its own content size to MenuBarController.fitPanel.
enum PerchMetrics {
    static let initialPanel = CGSize(width: Perch.widgetWidth, height: Perch.widgetHeight)
}
