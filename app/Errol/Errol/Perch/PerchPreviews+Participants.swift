// The side columns: a side's tip, which the pointer on its icon brings up,
// and the avatar with its fallback. The scene and the states are in
// PerchPreviews.swift.

#if DEBUG
import SwiftUI

#Preview("Tip · ChatGPT") { PerchPreviewState.details.scene }
#Preview("Tip · no window chosen") { PerchPreviewState.detailsChoosing.scene }
#Preview("Tip · ChatGPT closed") { PerchPreviewState.detailsClosed.scene }
#Preview("Tip · Claude minimized mid-run") { PerchPreviewState.detailsHeld.scene }

#Preview("Avatars (icon and fallback)") {
    // The first wears whatever Claude Desktop's icon is on this Mac; the
    // second names no installed app, so it is the initial-in-a-circle
    // fallback the column uses when an app is missing.
    HStack(spacing: Perch.s(24)) {
        PerchAvatar(bundleID: config.claudeBundleID, initial: "C", feather: Perch.claudeFeather)
        PerchAvatar(bundleID: "com.example.not-installed", initial: "C", feather: Perch.claudeFeather)
    }
    .padding(Perch.s(24))
    .background(Perch.paper)
}
#endif
