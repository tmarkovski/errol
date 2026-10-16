// The artwork ChatGPT (com.openai.codex) puts on its Dock tile in place of
// its Finder icon, worked out from the two preference keys its Settings
// writes. AppIcons reads the keys and loads the file; this half lives in
// Core so the contract tests can pin it without touching another app's
// settings.

import CoreGraphics

enum ChatGPTDockIcon {
    /// An alternate icon's light file and the dark file paired with it, as
    /// ChatGPT names them, without the extension. A build flavor's suffix
    /// ("-nightly") follows the light name and carries over to the dark one.
    private typealias Artwork = (light: String, dark: String)
    private static let codex: Artwork = ("icon-codex-light", "icon-codex-dark-color")
    private static let space: Artwork = ("icon-space-light", "icon-space-dark")

    /// The file in ChatGPT's Resources folder its Dock tile shows, or nil
    /// for "app-default", a missing preference, or a value this version
    /// does not know, all of which leave the ordinary installed icon.
    /// `resourceName` is the light file ChatGPT stored with the preference.
    static func resource(preference: String?, resourceName: String?, dark: Bool) -> String? {
        let artwork: Artwork
        let useDark: Bool
        switch preference {
        case "codex-system": artwork = codex; useDark = dark
        // Earlier versions stored a fixed appearance; ChatGPT rewrites these
        // as "codex-system" once it runs, and its Dock plug-in still reads them.
        case "codex-light": artwork = codex; useDark = false
        case "codex-dark": artwork = codex; useDark = true
        case "space-system": artwork = space; useDark = dark
        default: return nil
        }
        let light = resourceName ?? artwork.light + ".png"
        // Only accept a file in this bundle's Resources folder. Keep optional
        // build-flavor suffixes while following the vendor's paired filenames.
        guard light.hasPrefix(artwork.light), light.hasSuffix(".png"),
              !light.contains("/"), !light.contains("\\"), !light.contains("..") else { return nil }
        return useDark ? artwork.dark + light.dropFirst(artwork.light.count) : light
    }

    /// The part of an alternate icon ChatGPT hands the Dock: it trims a
    /// 128th of the width, rounded, from every edge, so 1024 px artwork
    /// loses 8 px a side. Cropping the same way keeps the avatar's art the
    /// size of the Dock tile's.
    static func dockCrop(width: Int, height: Int) -> CGRect {
        let inset = Int((Double(width) / 128).rounded())
        return CGRect(x: inset, y: inset, width: width - inset * 2, height: height - inset * 2)
    }
}
