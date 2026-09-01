// The skin's two constant tables: the palette and type scale every part
// draws from, and the window sizes the panel asks AppKit for. Changing how
// large or how gray the instrument reads is a change to this file alone.
// See WireframePanelView for what the skin is.

import SwiftUI

/// The skin draws from four grays, plus the lens colors the two signal
/// lamps burn — the muted red, jade green, and orange of old equipment
/// panels rather than screen primaries.
/// Internal, not private: the settings card (SettingsView) speaks the same
/// idiom from these tokens.
enum Wire {
    static let ink = Color(white: 0.20)
    static let faint = Color(white: 0.52)
    static let paper = Color(white: 0.94)
    static let well = Color(white: 0.885)

    /// Every length and type size on the card is a study measurement put
    /// through `s`, so this one number sets how large the instrument reads.
    /// The study drew at 1.0 and came out cramped on a laptop display.
    static let scale: CGFloat = 1.2
    static func s(_ points: CGFloat) -> CGFloat { points * scale }
    /// Instrument type: monospaced, scaled with everything else.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: s(size), weight: weight, design: .monospaced)
    }
    /// The few proportional strings — what a person types, and the topic.
    static func text(_ size: CGFloat) -> Font { .system(size: s(size)) }

    /// The two corners the skin cuts. The shell is the panel's own edge;
    /// the box is every well set into it — the participant cards today.
    /// The shell stays the rounder of the two so the card reads as the
    /// thing the boxes are sitting in rather than as one more box, and the
    /// box radius is named because three places have to agree on it: the
    /// well's fill, the border drawn over it, and the rings that border
    /// throws (WireSpeakerBorder), which are that same corner opened out.
    ///
    /// The shell corner is drawn, not inherited: a window whose background
    /// is clear has no theme frame painting a rounded one, so a card that
    /// leaves its corners to AppKit gets square ones.
    static let shellCorner = s(16)
    static let boxCorner = s(12)

    /// The fixed card width, which is also the window's: the card fills
    /// the panel edge to edge. Height is nobody's constant — the card is
    /// content-sized in every console state, and the shell fits the window
    /// to what it reports (WireframePanelView, MenuBarController.fitPanel).
    static let cardWidth = s(480)
    /// The title bar's strip. The panel is a titled window with its content
    /// run up under the title bar (MenuBarController.buildPanel), so AppKit
    /// puts its close button here and paints nothing around it — and the
    /// skin paints nothing either, deliberately: the button stands directly
    /// on the paper, chrome blended into the card rather than banded across
    /// it. The height still matters, twice over — it is the room the button
    /// needs, and the strip the title bar claims clicks in, so the card's
    /// own rows must start below it. Everywhere else the card pads by s(16).
    ///
    /// A raw point figure, not an s() measurement: it mirrors the height of
    /// the title bar AppKit draws, which does not scale with the skin. The
    /// panel wears an empty unified toolbar for the roomier strip Safari
    /// and Mail have (MenuBarController.buildPanel) — 52pt, close button
    /// centered in it — so this is that height. Without the toolbar the
    /// bare strip is 28pt.
    static let chromeBand: CGFloat = 52
    /// The card's top padding: the strip, plus a small gap.
    static let chromeInset = chromeBand + s(5)
}

/// The one window frame the skin still names: what the panel opens at
/// before the card's first size report lands. Every real size comes from
/// the card itself — content-sized in every console state, with the shell
/// fitting the window to what it reports (MenuBarController.fitPanel) — so
/// this is a first-frame stand-in, corrected the moment the skin lays out.
enum WireframeMetrics {
    static let initialPanel = CGSize(width: Wire.cardWidth, height: Wire.s(320))
}
