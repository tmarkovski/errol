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

    static let chalkTeal = PerchPalette(ConsolePalette.chalkTeal)
    static let warmStone = PerchPalette(ConsolePalette.warmStone)
    static let classicAmber = PerchPalette(ConsolePalette.classicAmber)
    static let chalkGraphite = PerchPalette(ConsolePalette.chalkGraphite)
    static let ivoryCobalt = PerchPalette(ConsolePalette.ivoryCobalt)
    static let pearlTeal = PerchPalette(ConsolePalette.pearlTeal)
    static let linenMoss = PerchPalette(ConsolePalette.linenMoss)

    private init(_ palette: ConsolePalette) {
        let light = palette.light
        let dark = palette.dark
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
