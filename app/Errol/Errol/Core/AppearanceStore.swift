import Foundation
import Observation

/// Stable identifiers keep a saved selection independent of its display name.
enum AppTheme: String, CaseIterable, Identifiable {
    case chalkTeal = "chalk-teal"
    case warmStone = "warm-stone"
    case classicAmber = "classic-amber"
    // Lighter, warm candidates under evaluation; see PerchPalette for intent.
    case chalkGraphite = "chalk-graphite"
    case ivoryCobalt = "ivory-cobalt"
    case pearlTeal = "pearl-teal"
    case linenMoss = "linen-moss"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chalkTeal: "Chalk & Teal"
        case .warmStone: "Warm Stone & Olive"
        case .classicAmber: "Classic Amber"
        case .chalkGraphite: "Chalk & Graphite"
        case .ivoryCobalt: "Ivory & Cobalt"
        case .pearlTeal: "Pearl & Teal"
        case .linenMoss: "Linen & Moss"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// Appearance is independent of conversation settings and never touches a run.
/// Perch reads this observable selection when drawing, so changing a theme
/// updates existing views without recreating editors or discarding drafts.
@Observable
final class AppearanceStore {
    static let shared = AppearanceStore()

    var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Self.themeKey) }
    }
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let themeKey = "appTheme"
    private static let appearanceKey = "appAppearance"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Retired palettes, including cream-blue, use the current default.
        theme = defaults.string(forKey: Self.themeKey)
            .flatMap(AppTheme.init(rawValue:)) ?? .chalkTeal
        appearance = defaults.string(forKey: Self.appearanceKey)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
}
