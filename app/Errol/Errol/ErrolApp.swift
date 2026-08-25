// The app entry point. All the real setup happens in MenuBarController
// (the NSApplicationDelegate): the status item and the floating panel.
// The Settings scene is a placeholder — an App must declare at least one
// scene, and Errol has no regular windows.

import SwiftUI

@main
struct ErrolApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) private var menuBar

    var body: some Scene {
        Settings { EmptyView() }
    }
}
