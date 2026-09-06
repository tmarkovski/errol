import AppKit

/// Each theme supplies the same semantic colors in both appearances. Dynamic
/// NSColors share that definition with SwiftUI, the native editors, and window
/// chrome; their provider uses the appearance passed by the drawing view.
struct PerchPalette {
    let paper, well, track, panelEdge, chipEdge, hairline: NSColor
    let ink, secondary, muted, placeholder, previewInk, path: NSColor
    let accent, accentText, accentBack, onAccent: NSColor
    let green, greenBack, red, redBack, presence: NSColor
    let chatgptFeather, claudeFeather: NSColor

    static let creamBlue = PerchPalette(
        light: Colors(
            paper: 0xFAF7EF, well: 0xEEEFEF, track: 0xE2E5E5,
            panelEdge: 0xDEDFD9, chipEdge: 0xDEDFD9, hairline: 0xDEDFD9,
            ink: 0x293545, secondary: 0x485565, muted: 0x5F6C7D,
            placeholder: 0x6A717A, previewInk: 0x5F6C7D, path: 0xD1CEC3,
            accent: 0x5273A4, accentText: 0x42618E, accentBack: 0xDCE6F4,
            onAccent: 0xFFFFFF,
            green: 0x38694C, greenBack: 0xE5EDE6,
            red: 0xA4433C, redBack: 0xF6E3E0, presence: 0x438F65),
        dark: Colors(
            paper: 0x292722, well: 0x313333, track: 0x3C3F40,
            panelEdge: 0x44423C, chipEdge: 0x44423C, hairline: 0x44423C,
            ink: 0xEEECE6, secondary: 0xCDD0D2, muted: 0xB9BDC2,
            placeholder: 0xA8ADB3, previewInk: 0xB9BDC2, path: 0x625E54,
            accent: 0xA5BFE8, accentText: 0xB5CDF1, accentBack: 0x34445D,
            onAccent: 0x212D40,
            green: 0xA4CDB1, greenBack: 0x2E4036,
            red: 0xE8AAA4, redBack: 0x4C302D, presence: 0x8BC3A0))

    /// The original light palette remains available, with a warm dark variant.
    static let classicAmber = PerchPalette(
        light: Colors(
            paper: 0xFCFCFA, well: 0xF4F3EF, track: 0xEBEAE4,
            panelEdge: 0xE5E3DC, chipEdge: 0xE2E0D8, hairline: 0xE6E4DC,
            ink: 0x2C2B27, secondary: 0x4B4A44, muted: 0x8A887F,
            placeholder: 0xA09D92, previewInk: 0x75726A, path: 0xD5D2C8,
            accent: 0xD98E2B, accentText: 0xA06D14, accentBack: 0xF6EFDD,
            onAccent: 0xFFFFFF,
            green: 0x2F7D5B, greenBack: 0xE9F2EC,
            red: 0xA4433C, redBack: 0xF6E3E0, presence: 0x43A373),
        dark: Colors(
            paper: 0x292722, well: 0x34312B, track: 0x403C34,
            panelEdge: 0x474239, chipEdge: 0x4A443A, hairline: 0x474239,
            ink: 0xEEECE6, secondary: 0xCEC9BE, muted: 0xBBB5A8,
            placeholder: 0xAAA396, previewInk: 0xBBB5A8, path: 0x686051,
            accent: 0xE8B469, accentText: 0xECC487, accentBack: 0x4B3B25,
            onAccent: 0x332610,
            green: 0xA4CDB1, greenBack: 0x2E4036,
            red: 0xE8AAA4, redBack: 0x4C302D, presence: 0x8BC3A0))

    private struct Colors {
        let paper, well, track, panelEdge, chipEdge, hairline: UInt32
        let ink, secondary, muted, placeholder, previewInk, path: UInt32
        let accent, accentText, accentBack, onAccent: UInt32
        let green, greenBack, red, redBack, presence: UInt32
    }

    private init(light: Colors, dark: Colors) {
        paper = Self.adaptive(light.paper, dark.paper)
        well = Self.adaptive(light.well, dark.well)
        track = Self.adaptive(light.track, dark.track)
        panelEdge = Self.adaptive(light.panelEdge, dark.panelEdge)
        chipEdge = Self.adaptive(light.chipEdge, dark.chipEdge)
        hairline = Self.adaptive(light.hairline, dark.hairline)
        ink = Self.adaptive(light.ink, dark.ink)
        secondary = Self.adaptive(light.secondary, dark.secondary)
        muted = Self.adaptive(light.muted, dark.muted)
        placeholder = Self.adaptive(light.placeholder, dark.placeholder)
        previewInk = Self.adaptive(light.previewInk, dark.previewInk)
        path = Self.adaptive(light.path, dark.path)
        accent = Self.adaptive(light.accent, dark.accent)
        accentText = Self.adaptive(light.accentText, dark.accentText)
        accentBack = Self.adaptive(light.accentBack, dark.accentBack)
        onAccent = Self.adaptive(light.onAccent, dark.onAccent)
        green = Self.adaptive(light.green, dark.green)
        greenBack = Self.adaptive(light.greenBack, dark.greenBack)
        red = Self.adaptive(light.red, dark.red)
        redBack = Self.adaptive(light.redBack, dark.redBack)
        presence = Self.adaptive(light.presence, dark.presence)
        // Participant identity is independent of the chosen app theme.
        chatgptFeather = Self.rgb(0x5D7A8C)
        claudeFeather = Self.rgb(0xC97E4A)
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            rgb(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension AppTheme {
    var palette: PerchPalette {
        switch self {
        case .creamBlue: .creamBlue
        case .classicAmber: .classicAmber
        }
    }
}

extension AppAppearance {
    /// Nil lets macOS keep tracking system appearance, including later changes.
    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
