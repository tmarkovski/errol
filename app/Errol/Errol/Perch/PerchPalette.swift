import AppKit

/// Each theme supplies the same semantic colors in both appearances. Dynamic
/// NSColors share that definition with SwiftUI, the native editors, and window
/// chrome; their provider uses the appearance passed by the drawing view.
struct PerchPalette {
    let shell, well, paper, chipEdge, hairline: NSColor
    let ink, secondary, muted, placeholder: NSColor
    let accent, accentText, onAccent: NSColor
    let red: NSColor
    let chatgptFeather, claudeFeather: NSColor

    /// One palette per theme, built once so every access returns the same
    /// dynamic NSColors.
    fileprivate static let byTheme = Dictionary(uniqueKeysWithValues: AppTheme.allCases.map { ($0, PerchPalette($0.consolePalette)) })

    private init(_ palette: ConsolePalette) {
        let light = palette.light
        let dark = palette.dark
        shell = Self.adaptive(light.shell, dark.shell)
        well = Self.adaptive(light.well, dark.well)
        paper = Self.adaptive(light.paper, dark.paper)
        chipEdge = Self.adaptive(light.chipEdge, dark.chipEdge)
        hairline = Self.adaptive(light.hairline, dark.hairline)
        ink = Self.adaptive(light.ink, dark.ink)
        secondary = Self.adaptive(light.secondary, dark.secondary)
        muted = Self.adaptive(light.muted, dark.muted)
        placeholder = Self.adaptive(light.placeholder, dark.placeholder)
        accent = Self.adaptive(light.accent, dark.accent)
        accentText = Self.adaptive(light.accentText, dark.accentText)
        onAccent = Self.adaptive(light.onAccent, dark.onAccent)
        red = Self.adaptive(light.red, dark.red)
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
    var palette: PerchPalette { PerchPalette.byTheme[self]! }
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
