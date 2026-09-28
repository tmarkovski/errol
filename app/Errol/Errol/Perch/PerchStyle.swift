// Shared type, geometry, and semantic color access. Theme values live in
// ConsolePalette, adapted to each appearance by PerchPalette;
// AppearanceStore persists the selection.

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
    static var chipEdge: Color { Color(nsColor: palette.chipEdge) }
    static var hairline: Color { Color(nsColor: palette.hairline) }
    static var ink: Color { Color(nsColor: palette.ink) }
    static var secondary: Color { Color(nsColor: palette.secondary) }
    static var muted: Color { Color(nsColor: palette.muted) }
    static var placeholder: Color { Color(nsColor: palette.placeholder) }
    static var accent: Color { Color(nsColor: palette.accent) }
    static var accentText: Color { Color(nsColor: palette.accentText) }
    static var onAccent: Color { Color(nsColor: palette.onAccent) }
    static var red: Color { Color(nsColor: palette.red) }
    static var chatgptFeather: Color { Color(nsColor: palette.chatgptFeather) }
    static var claudeFeather: Color { Color(nsColor: palette.claudeFeather) }
    static func feather(for side: Speaker) -> Color { side == .chatgpt ? chatgptFeather : claudeFeather }

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
    /// mono. The one exception asks for `mono` by name: the log window's
    /// text.
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: s(size), weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: s(size), weight: weight, design: .monospaced)
    }

    // MARK: Motion

    /// The fade every state-driven line of text takes when it changes — the
    /// turn line, the context row and the hold notice, the composer's
    /// hint — so nothing snaps.
    static let fade = Animation.easeInOut(duration: 0.2)

    /// The spring behind every control that moves rather than fades: an
    /// option chip growing its label, and a destination line springing to
    /// its new width.
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.82)

    // MARK: Depth

    /// The ink of the console's soft shadows, the same in every theme: a
    /// faint darkening on a light shell, and a deeper one on a dark shell,
    /// where a faint one would not show.
    static var shadow: Color { Color(nsColor: shadowNS) }
    private static let shadowNS = NSColor(name: nil) { appearance in
        NSColor.black.withAlphaComponent(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.5 : 0.12)
    }

    /// The corner of a rounded card on the theme's shell: the permission
    /// guide's card, and the About window in the console-preview render.
    /// The console itself is a capsule (PanelWindowSurface).
    static let shellCorner = s(18)
    /// The console's circular actions.
    static let actionDiameter = s(32)
    /// The labeled pills' height, which the prompt box's mic shares as its
    /// diameter.
    static let capsuleHeight = s(29)
    /// A step tighter than the card, for a well set inside a window: the
    /// log window's text area.
    static let insetCorner = s(10)

    /// The capsule's footprint: the reference is 860 × 156 CSS pixels at
    /// full desktop width, taken as points and not put through `s` — here
    /// the mockup's own measure is the panel's, and every screen from
    /// permission to the ending shares it.
    static let widgetWidth: CGFloat = 860
    static let widgetHeight: CGFloat = 156
    /// A participant's column: the app's icon over the app's name, kept to
    /// one line.
    static let participantWidth = s(72)

    // MARK: The composer's measures

    /// The oval's editors shrink before wrapping, then scroll after three
    /// lines. The editor's type is the console's ordinary size, a step
    /// over the lines around the box, not a display size; both go through
    /// `s` like every other size here.
    static let promptFont = NSFont.systemFont(ofSize: s(13))
    static let promptMinimumFontSize = s(12)
    static let promptMaximumLines = 3
}

/// The console and permission screen keep this height through every state.
enum PerchMetrics {
    static let initialPanel = CGSize(width: Perch.widgetWidth, height: Perch.widgetHeight)
}
