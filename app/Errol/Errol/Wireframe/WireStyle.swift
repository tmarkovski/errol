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
    static let shellCorner = s(16)
    static let boxCorner = s(12)

    /// The fixed card size; the panel adds the outer padding. Expanded, the
    /// card height is pinned and the log absorbs the difference between the
    /// topic field and the taller custom-instructions editor; compact, the
    /// card hugs the head unit.
    static let cardWidth = s(480)
    static let expandedCardHeight = s(560)
    /// The shadow's room around the card, a side.
    static let cardMargin = s(14)
}

/// The window frames the skin needs, derived from the card itself so the
/// panel grows with `Wire.scale` instead of drifting from it. PanelLayout
/// hands these straight through. The compact card is content-sized, so its
/// height carries slack.
enum WireframeMetrics {
    static let expandedPanel = CGSize(width: Wire.cardWidth + 2 * Wire.cardMargin,
                                      height: Wire.expandedCardHeight + 2 * Wire.cardMargin)
    static let compactPanel = CGSize(width: expandedPanel.width, height: Wire.s(252))
    /// The compact window with the steering editor's row added — sized for
    /// the field at its three-line tallest. Expanded needs no counterpart:
    /// the card height is pinned and the log absorbs the editor's row.
    static let compactSteeringPanel = CGSize(width: expandedPanel.width,
                                             height: Wire.s(318))
}
