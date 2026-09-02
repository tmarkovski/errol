// The perch avatar: the app's own icon, as installed on this Mac, with the
// initial in a feather-colored circle standing in when the app is not here.
//
// Why the installed icon rather than a bundled logo. Both vendors gate their
// marks: OpenAI's Blossom may only appear black or white, under its Marks
// usage terms, and Anthropic's trademark guidelines allow its marks only in
// materials Anthropic approves beforehand — so a Claude starburst shipped
// inside Errol would need written permission. Showing an installed app's
// icon is what the Dock, Finder, and the app switcher do for every app:
// nothing of either brand lives in this bundle, and the avatar follows
// whichever app the bundle ID in Settings names (Codex or classic ChatGPT
// alike), which the initial could not.

import AppKit
import SwiftUI

struct PerchAvatar: View {
    let bundleID: String
    /// The fallback's letter — the app name's first character.
    let initial: String
    /// The fallback circle's fill (Perch.chatgptFeather / claudeFeather).
    let feather: Color
    let presence: Color

    /// The layout slot: the same for the icon and the fallback so the head
    /// does not shift depending on which apps are installed.
    private var slot: CGFloat { Perch.s(46) }

    var body: some View {
        Group {
            if let icon = AppIcons.icon(forBundleID: bundleID) {
                // A macOS app icon keeps a transparent margin around its
                // squircle — the squircle spans about 81% of the canvas
                // (measured on both apps' icons) — so the image is drawn
                // oversize inside the slot to make the squircle itself
                // slot-sized, matching the fallback circle. The overflow is
                // only that margin; nothing paints outside the slot.
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: slot / 0.81, height: slot / 0.81)
                    .frame(width: slot, height: slot)
            } else {
                ZStack {
                    Circle()
                        .fill(feather)
                        .frame(width: slot, height: slot)
                    Text(initial)
                        .font(Perch.text(17, .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(presence)
                .frame(width: Perch.s(11), height: Perch.s(11))
                .overlay(Circle().stroke(Perch.paper, lineWidth: Perch.s(2)))
                .offset(x: Perch.s(1), y: Perch.s(1))
        }
    }
}

/// Icons of the apps the relay targets, looked up by bundle ID through
/// LaunchServices so an app that is installed but not running still has a
/// face. Hits are cached for the process; misses are not, so installing an
/// app while Errol runs shows its icon on the next head refresh.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    @MainActor
    static func icon(forBundleID bundleID: String) -> NSImage? {
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}
