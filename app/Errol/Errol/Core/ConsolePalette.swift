/// Shared, testable sRGB values. Native views adapt these to the current appearance.
struct ConsolePalette {
    let light: Colors
    let dark: Colors

    /// Warm-neutral surfaces leave each participant's fixed color distinct;
    /// teal marks Errol's controls and the transfer drawn over either app.
    static let chalkTeal = ConsolePalette(
        light: Colors(
            shell: 0xEBE8E3, well: 0xF3F1EC, paper: 0xFBFAF8,
            panelEdge: 0xE2DFD8, chipEdge: 0xDDDAD2, hairline: 0xDEDAD2,
            ink: 0x1C1B19, secondary: 0x4A4845, muted: 0x6A6761,
            placeholder: 0x726F67, previewInk: 0x6F6C66,
            accent: 0x1F7A76, accentText: 0x176660, accentBack: 0xDDEEEC,
            onAccent: 0xFFFFFF,
            red: 0xA83E36, redBack: 0xF6E4E1),
        dark: Colors(
            shell: 0x1B1A18, well: 0x232220, paper: 0x2C2A28,
            panelEdge: 0x373532, chipEdge: 0x3C3A37, hairline: 0x302F2C,
            ink: 0xF2F0EB, secondary: 0xC8C5BE, muted: 0xA29F97,
            placeholder: 0x959288, previewInk: 0xA29F97,
            accent: 0x6FC9C2, accentText: 0x8AD6D0, accentBack: 0x214341,
            onAccent: 0x0B2624,
            red: 0xE7A79F, redBack: 0x4A2C28))

    static let warmStone = ConsolePalette(
        light: Colors(
            shell: 0xE7E3DA, well: 0xEFECE4, paper: 0xFAF7F0,
            panelEdge: 0xDBD7CB, chipEdge: 0xD6D2C5, hairline: 0xDAD5C8,
            ink: 0x33352B, secondary: 0x53554A, muted: 0x64665A,
            placeholder: 0x6A6B5F, previewInk: 0x696B5E,
            accent: 0x73784F, accentText: 0x5B623C, accentBack: 0xE2E7D4,
            onAccent: 0xFFFFFF,
            red: 0xA04B3C, redBack: 0xF3E3DC),
        dark: Colors(
            shell: 0x282821, well: 0x303129, paper: 0x393A31,
            panelEdge: 0x45473A, chipEdge: 0x4C4F40, hairline: 0x45473A,
            ink: 0xEDEBE1, secondary: 0xCECDBF, muted: 0xB5B5A4,
            placeholder: 0xA3A590, previewInk: 0xB5B5A4,
            accent: 0xB5BF85, accentText: 0xCAD49D, accentBack: 0x3D442D,
            onAccent: 0x282E1B,
            red: 0xE3AD99, redBack: 0x4A332B))

    /// The original light palette remains available, with a warm dark variant.
    static let classicAmber = ConsolePalette(
        light: Colors(
            shell: 0xECEAE6, well: 0xF4F3EF, paper: 0xFCFCFA,
            panelEdge: 0xE5E3DC, chipEdge: 0xE2E0D8, hairline: 0xDEDCD5,
            ink: 0x2C2B27, secondary: 0x4B4A44, muted: 0x6C6960,
            placeholder: 0x706D64, previewInk: 0x75726A,
            accent: 0xD98E2B, accentText: 0x865A10, accentBack: 0xF6EFDD,
            onAccent: 0x2C2112,
            red: 0xA4433C, redBack: 0xF6E3E0),
        dark: Colors(
            shell: 0x292722, well: 0x34312B, paper: 0x3D3A33,
            panelEdge: 0x474239, chipEdge: 0x4A443A, hairline: 0x474239,
            ink: 0xEEECE6, secondary: 0xCEC9BE, muted: 0xBBB5A8,
            placeholder: 0xABA497, previewInk: 0xBBB5A8,
            accent: 0xE8B469, accentText: 0xECC487, accentBack: 0x4B3B25,
            onAccent: 0x332610,
            red: 0xE8AAA4, redBack: 0x4C302D))

    /// Candidates for a lighter, warmer console: near-white paper with a hint
    /// of warmth, neutral grays rather than tinted ones, and one accent with
    /// real saturation.

    /// Ink as the accent: nothing here, the transfer's dot and prompt light
    /// included, is any color but ink.
    static let chalkGraphite = ConsolePalette(
        light: Colors(
            shell: 0xEBE8E3, well: 0xF3F1EC, paper: 0xFBFAF8,
            panelEdge: 0xE2DFD8, chipEdge: 0xDDDAD2, hairline: 0xDEDAD2,
            ink: 0x1C1B19, secondary: 0x4A4845, muted: 0x6A6761,
            placeholder: 0x726F67, previewInk: 0x6F6C66,
            accent: 0x262523, accentText: 0x1C1B19, accentBack: 0xECE9E3,
            onAccent: 0xFFFFFF,
            red: 0xA83E36, redBack: 0xF6E4E1),
        dark: Colors(
            shell: 0x1B1A18, well: 0x232220, paper: 0x2C2A28,
            panelEdge: 0x373532, chipEdge: 0x3C3A37, hairline: 0x302F2C,
            ink: 0xF2F0EB, secondary: 0xC8C5BE, muted: 0xA29F97,
            placeholder: 0x959288, previewInk: 0xA29F97,
            accent: 0xF2F0EB, accentText: 0xF2F0EB, accentBack: 0x2F2E2B,
            onAccent: 0x1B1A18,
            red: 0xE7A79F, redBack: 0x4A2C28))

    /// Warm ivory with one saturated blue, well clear of ChatGPT's slate.
    static let ivoryCobalt = ConsolePalette(
        light: Colors(
            shell: 0xECE9E0, well: 0xF4F1EA, paper: 0xFCFAF5,
            panelEdge: 0xE4E0D6, chipEdge: 0xDFDBD1, hairline: 0xDEDBD1,
            ink: 0x1B1D24, secondary: 0x474A55, muted: 0x656872,
            placeholder: 0x6F727C, previewInk: 0x6B6E78,
            accent: 0x2E5BE0, accentText: 0x2449B8, accentBack: 0xE1E8FB,
            onAccent: 0xFFFFFF,
            red: 0xB03A33, redBack: 0xF7E3E0),
        dark: Colors(
            shell: 0x1C1B19, well: 0x24231F, paper: 0x2D2C27,
            panelEdge: 0x383632, chipEdge: 0x3D3B36, hairline: 0x33312D,
            ink: 0xF1EFE9, secondary: 0xC7C4BC, muted: 0xA19E96,
            placeholder: 0x96938C, previewInk: 0xA19E96,
            accent: 0x7FA3FF, accentText: 0x9DB8FF, accentBack: 0x2A3550,
            onAccent: 0x0F1B3A,
            red: 0xE8A8A0, redBack: 0x4B2C29))

    /// The brand story's Messenger Blue, deepened toward teal so it does not
    /// read as ChatGPT's participant color.
    static let pearlTeal = ConsolePalette(
        light: Colors(
            shell: 0xE9E9E4, well: 0xF1F1ED, paper: 0xFAFAF7,
            panelEdge: 0xE0E0DA, chipEdge: 0xDCDCD5, hairline: 0xDBDBD4,
            ink: 0x1A242B, secondary: 0x46535B, muted: 0x5B6A73,
            placeholder: 0x65717A, previewInk: 0x617079,
            accent: 0x1F7A76, accentText: 0x176660, accentBack: 0xDDEEEC,
            onAccent: 0xFFFFFF,
            red: 0xAE3C35, redBack: 0xF6E3E0),
        dark: Colors(
            shell: 0x1B1C1A, well: 0x232523, paper: 0x2B2E2B,
            panelEdge: 0x373937, chipEdge: 0x3C3E3C, hairline: 0x323432,
            ink: 0xEFF1EE, secondary: 0xC4C9C6, muted: 0x9EA6A3,
            placeholder: 0x8D9794, previewInk: 0x9EA6A3,
            accent: 0x6FC9C2, accentText: 0x8AD6D0, accentBack: 0x214341,
            onAccent: 0x0B2624,
            red: 0xE7A8A0, redBack: 0x4B2C29))

    /// The olive idea on lighter paper, with neutral grays and a greener,
    /// more saturated accent.
    static let linenMoss = ConsolePalette(
        light: Colors(
            shell: 0xEAE8DF, well: 0xF2F0E9, paper: 0xFBFAF6,
            panelEdge: 0xE1DED4, chipEdge: 0xDCD9CF, hairline: 0xDDD9CF,
            ink: 0x1D1E19, secondary: 0x484A42, muted: 0x66685E,
            placeholder: 0x70726A, previewInk: 0x6D6F65,
            accent: 0x4F7D2E, accentText: 0x3F6624, accentBack: 0xE3EDD8,
            onAccent: 0xFFFFFF,
            red: 0xAB3F36, redBack: 0xF6E3E0),
        dark: Colors(
            shell: 0x1B1C17, well: 0x24251F, paper: 0x2C2D27,
            panelEdge: 0x383A32, chipEdge: 0x3D3F36, hairline: 0x33352D,
            ink: 0xF0F0E8, secondary: 0xC6C7BC, muted: 0xA0A296,
            placeholder: 0x93958C, previewInk: 0xA0A296,
            accent: 0xA3D07E, accentText: 0xB6DC93, accentBack: 0x2E4423,
            onAccent: 0x152410,
            red: 0xE8A9A1, redBack: 0x4B2C29))

    /// Three surfaces, darker to lighter in both appearances, so whatever
    /// holds text stands lighter than the window around it. The shell is the
    /// window's own solid fill. The well is a step up: the prompt box while
    /// the relay has it, buttons, fields, and the log. Paper is the lightest:
    /// the prompt box while you type, the conversation summary, and the cards
    /// over the console. Ink, secondary, muted, accent text, and red clear
    /// 4.5:1 on all three; placeholder and preview ink, which only sit on
    /// paper, clear it there.
    struct Colors {
        let shell, well, paper, panelEdge, chipEdge, hairline: UInt32
        let ink, secondary, muted, placeholder, previewInk: UInt32
        let accent, accentText, accentBack, onAccent: UInt32
        let red, redBack: UInt32
    }

}

extension AppTheme {
    var consolePalette: ConsolePalette {
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
