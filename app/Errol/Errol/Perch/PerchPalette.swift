import AppKit

/// Each theme supplies the same semantic colors in both appearances. Dynamic
/// NSColors share that definition with SwiftUI, the native editors, and window
/// chrome; their provider uses the appearance passed by the drawing view.
struct PerchPalette {
    let paper, well, panelEdge, chipEdge, hairline: NSColor
    let ink, secondary, muted, placeholder, previewInk: NSColor
    let accent, accentText, accentBack, onAccent: NSColor
    let red, redBack: NSColor
    let chatgptFeather, claudeFeather: NSColor

    /// Warm-neutral surfaces leave each participant's fixed color distinct;
    /// teal marks Errol's controls and the transfer drawn over either app.
    static let chalkTeal = PerchPalette(
        light: Colors(
            paper: 0xFBFAF8, well: 0xF3F1EC,
            panelEdge: 0xE2DFD8, chipEdge: 0xDDDAD2, hairline: 0xE6E3DC,
            ink: 0x1C1B19, secondary: 0x4A4845, muted: 0x6F6C66,
            placeholder: 0x726F67, previewInk: 0x6F6C66,
            accent: 0x1F7A76, accentText: 0x176660, accentBack: 0xDDEEEC,
            onAccent: 0xFFFFFF,
            red: 0xA83E36, redBack: 0xF6E4E1),
        dark: Colors(
            paper: 0x1B1A18, well: 0x232220,
            panelEdge: 0x373532, chipEdge: 0x3C3A37, hairline: 0x302F2C,
            ink: 0xF2F0EB, secondary: 0xC8C5BE, muted: 0xA29F97,
            placeholder: 0x858279, previewInk: 0xA29F97,
            accent: 0x6FC9C2, accentText: 0x8AD6D0, accentBack: 0x214341,
            onAccent: 0x0B2624,
            red: 0xE7A79F, redBack: 0x4A2C28))

    static let warmStone = PerchPalette(
        light: Colors(
            paper: 0xFAF7F0, well: 0xEFECE4,
            panelEdge: 0xDBD7CB, chipEdge: 0xD6D2C5, hairline: 0xDCD8CC,
            ink: 0x33352B, secondary: 0x53554A, muted: 0x696B5E,
            placeholder: 0x6A6B5F, previewInk: 0x696B5E,
            accent: 0x73784F, accentText: 0x5B623C, accentBack: 0xE2E7D4,
            onAccent: 0xFFFFFF,
            red: 0xA04B3C, redBack: 0xF3E3DC),
        dark: Colors(
            paper: 0x282821, well: 0x303129,
            panelEdge: 0x45473A, chipEdge: 0x4C4F40, hairline: 0x45473A,
            ink: 0xEDEBE1, secondary: 0xCECDBF, muted: 0xB5B5A4,
            placeholder: 0xA3A590, previewInk: 0xB5B5A4,
            accent: 0xB5BF85, accentText: 0xCAD49D, accentBack: 0x3D442D,
            onAccent: 0x282E1B,
            red: 0xE3AD99, redBack: 0x4A332B))

    /// The original light palette remains available, with a warm dark variant.
    static let classicAmber = PerchPalette(
        light: Colors(
            paper: 0xFCFCFA, well: 0xF4F3EF,
            panelEdge: 0xE5E3DC, chipEdge: 0xE2E0D8, hairline: 0xE6E4DC,
            ink: 0x2C2B27, secondary: 0x4B4A44, muted: 0x8A887F,
            placeholder: 0xA09D92, previewInk: 0x75726A,
            accent: 0xD98E2B, accentText: 0xA06D14, accentBack: 0xF6EFDD,
            onAccent: 0xFFFFFF,
            red: 0xA4433C, redBack: 0xF6E3E0),
        dark: Colors(
            paper: 0x292722, well: 0x34312B,
            panelEdge: 0x474239, chipEdge: 0x4A443A, hairline: 0x474239,
            ink: 0xEEECE6, secondary: 0xCEC9BE, muted: 0xBBB5A8,
            placeholder: 0xAAA396, previewInk: 0xBBB5A8,
            accent: 0xE8B469, accentText: 0xECC487, accentBack: 0x4B3B25,
            onAccent: 0x332610,
            red: 0xE8AAA4, redBack: 0x4C302D))

    /// Candidates for a lighter, warmer console: near-white paper with a hint
    /// of warmth, neutral grays rather than tinted ones, and one accent with
    /// real saturation. Ink, secondary, accent text, and text on the accent
    /// clear 4.5:1 on paper in both appearances; muted text does so on the well.

    /// Ink as the accent: nothing here, the transfer's dot and prompt light
    /// included, is any color but ink.
    static let chalkGraphite = PerchPalette(
        light: Colors(
            paper: 0xFBFAF8, well: 0xF3F1EC,
            panelEdge: 0xE2DFD8, chipEdge: 0xDDDAD2, hairline: 0xE6E3DC,
            ink: 0x1C1B19, secondary: 0x4A4845, muted: 0x6F6C66,
            placeholder: 0x726F67, previewInk: 0x6F6C66,
            accent: 0x262523, accentText: 0x1C1B19, accentBack: 0xECE9E3,
            onAccent: 0xFFFFFF,
            red: 0xA83E36, redBack: 0xF6E4E1),
        dark: Colors(
            paper: 0x1B1A18, well: 0x232220,
            panelEdge: 0x373532, chipEdge: 0x3C3A37, hairline: 0x302F2C,
            ink: 0xF2F0EB, secondary: 0xC8C5BE, muted: 0xA29F97,
            placeholder: 0x858279, previewInk: 0xA29F97,
            accent: 0xF2F0EB, accentText: 0xF2F0EB, accentBack: 0x2F2E2B,
            onAccent: 0x1B1A18,
            red: 0xE7A79F, redBack: 0x4A2C28))

    /// Warm ivory with one saturated blue, well clear of ChatGPT's slate.
    static let ivoryCobalt = PerchPalette(
        light: Colors(
            paper: 0xFCFAF5, well: 0xF4F1EA,
            panelEdge: 0xE4E0D6, chipEdge: 0xDFDBD1, hairline: 0xE7E3DA,
            ink: 0x1B1D24, secondary: 0x474A55, muted: 0x6B6E78,
            placeholder: 0x6F727C, previewInk: 0x6B6E78,
            accent: 0x2E5BE0, accentText: 0x2449B8, accentBack: 0xE1E8FB,
            onAccent: 0xFFFFFF,
            red: 0xB03A33, redBack: 0xF7E3E0),
        dark: Colors(
            paper: 0x1C1B19, well: 0x24231F,
            panelEdge: 0x383632, chipEdge: 0x3D3B36, hairline: 0x33312D,
            ink: 0xF1EFE9, secondary: 0xC7C4BC, muted: 0xA19E96,
            placeholder: 0x838079, previewInk: 0xA19E96,
            accent: 0x7FA3FF, accentText: 0x9DB8FF, accentBack: 0x2A3550,
            onAccent: 0x0F1B3A,
            red: 0xE8A8A0, redBack: 0x4B2C29))

    /// The brand story's Messenger Blue, deepened toward teal so it does not
    /// read as ChatGPT's participant color.
    static let pearlTeal = PerchPalette(
        light: Colors(
            paper: 0xFAFAF7, well: 0xF1F1ED,
            panelEdge: 0xE0E0DA, chipEdge: 0xDCDCD5, hairline: 0xE4E4DE,
            ink: 0x1A242B, secondary: 0x46535B, muted: 0x617079,
            placeholder: 0x6B7780, previewInk: 0x617079,
            accent: 0x1F7A76, accentText: 0x176660, accentBack: 0xDDEEEC,
            onAccent: 0xFFFFFF,
            red: 0xAE3C35, redBack: 0xF6E3E0),
        dark: Colors(
            paper: 0x1B1C1A, well: 0x232523,
            panelEdge: 0x373937, chipEdge: 0x3C3E3C, hairline: 0x323432,
            ink: 0xEFF1EE, secondary: 0xC4C9C6, muted: 0x9EA6A3,
            placeholder: 0x7F8886, previewInk: 0x9EA6A3,
            accent: 0x6FC9C2, accentText: 0x8AD6D0, accentBack: 0x214341,
            onAccent: 0x0B2624,
            red: 0xE7A8A0, redBack: 0x4B2C29))

    /// The olive idea on lighter paper, with neutral grays and a greener,
    /// more saturated accent.
    static let linenMoss = PerchPalette(
        light: Colors(
            paper: 0xFBFAF6, well: 0xF2F0E9,
            panelEdge: 0xE1DED4, chipEdge: 0xDCD9CF, hairline: 0xE5E2D9,
            ink: 0x1D1E19, secondary: 0x484A42, muted: 0x6D6F65,
            placeholder: 0x70726A, previewInk: 0x6D6F65,
            accent: 0x4F7D2E, accentText: 0x3F6624, accentBack: 0xE3EDD8,
            onAccent: 0xFFFFFF,
            red: 0xAB3F36, redBack: 0xF6E3E0),
        dark: Colors(
            paper: 0x1B1C17, well: 0x24251F,
            panelEdge: 0x383A32, chipEdge: 0x3D3F36, hairline: 0x33352D,
            ink: 0xF0F0E8, secondary: 0xC6C7BC, muted: 0xA0A296,
            placeholder: 0x81837A, previewInk: 0xA0A296,
            accent: 0xA3D07E, accentText: 0xB6DC93, accentBack: 0x2E4423,
            onAccent: 0x152410,
            red: 0xE8A9A1, redBack: 0x4B2C29))

    private struct Colors {
        let paper, well, panelEdge, chipEdge, hairline: UInt32
        let ink, secondary, muted, placeholder, previewInk: UInt32
        let accent, accentText, accentBack, onAccent: UInt32
        let red, redBack: UInt32
    }

    private init(light: Colors, dark: Colors) {
        paper = Self.adaptive(light.paper, dark.paper)
        well = Self.adaptive(light.well, dark.well)
        panelEdge = Self.adaptive(light.panelEdge, dark.panelEdge)
        chipEdge = Self.adaptive(light.chipEdge, dark.chipEdge)
        hairline = Self.adaptive(light.hairline, dark.hairline)
        ink = Self.adaptive(light.ink, dark.ink)
        secondary = Self.adaptive(light.secondary, dark.secondary)
        muted = Self.adaptive(light.muted, dark.muted)
        placeholder = Self.adaptive(light.placeholder, dark.placeholder)
        previewInk = Self.adaptive(light.previewInk, dark.previewInk)
        accent = Self.adaptive(light.accent, dark.accent)
        accentText = Self.adaptive(light.accentText, dark.accentText)
        accentBack = Self.adaptive(light.accentBack, dark.accentBack)
        onAccent = Self.adaptive(light.onAccent, dark.onAccent)
        red = Self.adaptive(light.red, dark.red)
        redBack = Self.adaptive(light.redBack, dark.redBack)
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
        case .chalkTeal: .chalkTeal
        case .warmStone: .warmStone
        case .classicAmber: .classicAmber
        case .chalkGraphite: .chalkGraphite
        case .ivoryCobalt: .ivoryCobalt
        case .pearlTeal: .pearlTeal
        case .linenMoss: .linenMoss
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
