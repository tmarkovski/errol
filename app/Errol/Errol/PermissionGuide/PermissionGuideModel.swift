// What the permission guide's panel shows, shared by the window that hosts
// it (GuidePanel, driven by PermissionGuide) and the SwiftUI that draws it
// (PermissionGuideView). PermissionGuide owns the one instance and sets the
// actions; the view only reads the state and calls them.

import AppKit
import Observation

@MainActor
@Observable
final class PermissionGuideModel {
    /// Errol's own bundle. The tile shows its icon and name, and the drag
    /// carries its file URL into the list.
    let appURL: URL
    /// The name Finder shows for that bundle.
    let appName: String
    /// Whether the tile is being dragged. The panel dims and lets the
    /// pointer through meanwhile, so System Settings under it takes the drop.
    var isDragging = false
    /// Whether System Settings is the frontmost app. When it isn't, the view
    /// offers a way back to it.
    var isSettingsFrontmost = true

    /// Brings System Settings back on the list, when it has gone behind
    /// other windows.
    @ObservationIgnored var reopenSettings: () -> Void = {}
    /// Puts the guide away and returns to the app that was in front before.
    @ObservationIgnored var close: () -> Void = {}
    /// The drag source reports a drag starting (true) and ending (false).
    @ObservationIgnored var dragStateChanged: (Bool) -> Void = { _ in }

    init(appURL: URL = Bundle.main.bundleURL) {
        self.appURL = appURL.standardizedFileURL
        appName = FileManager.default.displayName(atPath: appURL.path)
    }
}
