// The panel's constant tables: the palette and type helpers every part
// draws from, and the one window size the panel still names. Changing how
// large or how warm the panel reads is a change to this file alone. See
// PerchPanelView for what the panel is.

import AppKit
import SwiftUI

/// Soft native-macOS surfaces with one warm owl-amber accent. The grays are
/// warm — every neutral leans toward the amber rather than sitting at a pure
/// white point — and the two participants each get a feather color of their
/// own for the avatar, the one place the panel spends hue on identity.
enum Perch {
    // MARK: Palette

    /// The panel's own surface.
    static let paper = Color(red: 252 / 255, green: 252 / 255, blue: 250 / 255)
    /// The composer card set into it.
    static let well = Color(red: 244 / 255, green: 243 / 255, blue: 239 / 255)
    /// The shape tabs' track, set into the well a step darker than it, so
    /// the paper thumb that slides along it reads as lifted without a shadow.
    static let track = Color(red: 235 / 255, green: 234 / 255, blue: 228 / 255)
    static let panelEdge = Color(red: 229 / 255, green: 227 / 255, blue: 220 / 255)
    static let chipEdge = Color(red: 226 / 255, green: 224 / 255, blue: 216 / 255)
    /// The rule under the composer's setup zone.
    static let hairline = Color(red: 230 / 255, green: 228 / 255, blue: 220 / 255)
    /// Primary text and the filled state of a selected pill.
    static let ink = Color(red: 44 / 255, green: 43 / 255, blue: 39 / 255)
    /// Chip labels and other secondary text.
    static let secondary = Color(red: 75 / 255, green: 74 / 255, blue: 68 / 255)
    static let muted = Color(red: 138 / 255, green: 136 / 255, blue: 127 / 255)
    static let placeholder = Color(red: 160 / 255, green: 157 / 255, blue: 146 / 255)
    /// The instruction preview's ink: the shape's text under the pills, a
    /// step quieter than secondary so it reads as material, not a control.
    static let previewInk = Color(red: 117 / 255, green: 114 / 255, blue: 106 / 255)
    /// The flight path's dotted arc.
    static let path = Color(red: 213 / 255, green: 210 / 255, blue: 200 / 255)

    /// The accent: the primary button, the courier bead, and nothing else.
    static let amber = Color(red: 217 / 255, green: 142 / 255, blue: 43 / 255)
    /// The live-state pill, the hold notice, and the on state of the
    /// composer's option chips: the quiet amber.
    static let amberText = Color(red: 160 / 255, green: 109 / 255, blue: 20 / 255)
    static let amberBack = Color(red: 246 / 255, green: 239 / 255, blue: 221 / 255)
    static let green = Color(red: 47 / 255, green: 125 / 255, blue: 91 / 255)
    static let greenBack = Color(red: 233 / 255, green: 242 / 255, blue: 236 / 255)
    static let red = Color(red: 164 / 255, green: 67 / 255, blue: 60 / 255)
    static let redBack = Color(red: 246 / 255, green: 227 / 255, blue: 224 / 255)
    /// The presence dot on a ready avatar.
    static let presence = Color(red: 67 / 255, green: 163 / 255, blue: 115 / 255)

    /// The participants' feather colors, behind the avatar initials.
    static let chatgptFeather = Color(red: 93 / 255, green: 122 / 255, blue: 140 / 255)
    static let claudeFeather = Color(red: 201 / 255, green: 126 / 255, blue: 74 / 255)

    /// What the growing editors need in AppKit terms.
    static let inkNS = NSColor(calibratedRed: 44 / 255, green: 43 / 255,
                               blue: 39 / 255, alpha: 1)
    /// The turn count's ink, for the AppKit field inside its chip.
    static let amberTextNS = NSColor(calibratedRed: 160 / 255, green: 109 / 255,
                                     blue: 20 / 255, alpha: 1)

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

    /// The two corners the panel cuts: the panel's own edge, and the composer
    /// card set into it. The tabs' track and thumb and the option chips are
    /// capsules and name no radius.
    static let shellCorner = s(18)
    /// The composer card: a tight inset, so the words sit close to the edge
    /// the way they do in the chat apps' own composers, and a corner a step
    /// rounder than the shell's — enough to rhyme with the primary circle
    /// set into its foot without the card reading as a pill.
    static let boxInset = s(8)
    static let boxCorner = s(22)
    static let primaryDiameter = s(36)
    /// A step tighter than the card, for a well set inside a window: the
    /// log window's text area.
    static let insetCorner = s(10)

    /// The fixed card width, which is also the window's. Height is nobody's
    /// constant — the card is content-sized and the shell fits the window to
    /// what it reports (PerchPanelView, MenuBarController.fitPanel).
    static let cardWidth = s(464)
    /// The title bar's strip: the panel wears an attached unified toolbar,
    /// which grows the strip to the height Safari and Mail have — 52pt, the
    /// close button centered in it (MenuBarController.buildPanel) — so this
    /// is that height. Without the toolbar the bare strip is 28pt, which is
    /// what the settings and log windows clear.
    static let chromeBand: CGFloat = 52
    /// The card's top padding: the strip, plus breathing room before the
    /// avatars — the app icons' squircles read heavier than the initial
    /// circles did and crowded the wordmark with only a hair of gap.
    static let chromeInset = chromeBand + s(10)

    // MARK: The composer's measures

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

/// The one window frame the panel names: what it opens at before the card's
/// first size report lands. Every real size comes from the card itself —
/// content-sized in every state, the shell fitting the window to what it
/// reports (MenuBarController.fitPanel) — so this is a first-frame stand-in,
/// corrected the moment the card lays out.
enum PerchMetrics {
    static let initialPanel = CGSize(width: Perch.cardWidth, height: Perch.s(320))
}
