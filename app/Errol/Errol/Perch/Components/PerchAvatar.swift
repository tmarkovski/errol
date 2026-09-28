// The perch avatar: the app's own icon, as installed on this Mac, with the
// initial in a feather-colored circle standing in when the app is not here.
//
// The icon comes from AppIcons (AppIcons.swift), which reads it from the
// installed app and redraws the avatar when the app or its artwork changes.
// The way an app icon is sized to its slot (appIconFilling) lives here too,
// since the permission guide's tile and the onboarding badge draw theirs the
// same way.

import AppKit
import SwiftUI

struct PerchAvatar: View {
    let bundleID: String
    /// The fallback's letter — the app name's first character.
    let initial: String
    /// The fallback circle's fill (Perch.chatgptFeather / claudeFeather).
    let feather: Color

    /// The layout slot: the same for the icon and the fallback so the head
    /// does not shift depending on which apps are installed.
    static var slot: CGFloat { Perch.s(46) }
    private var slot: CGFloat { Self.slot }

    var body: some View {
        Group {
            if let icon = AppIcons.shared.icon(forBundleID: bundleID) {
                // The squircle fills the slot, matching the fallback circle.
                Image(nsImage: icon).appIconFilling(slot)
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
    }
}

extension Image {
    /// A macOS app icon keeps a transparent margin around its squircle — the
    /// squircle spans about 81% of the canvas (measured on both apps' icons)
    /// — so the image is drawn oversize inside the slot to make the squircle
    /// itself slot-sized. The overflow is only that margin; nothing paints
    /// outside the slot.
    func appIconFilling(_ slot: CGFloat) -> some View {
        resizable()
            .interpolation(.high)
            .frame(width: slot / 0.81, height: slot / 0.81)
            .frame(width: slot, height: slot)
    }
}
