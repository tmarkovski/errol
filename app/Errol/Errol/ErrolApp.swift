// The app entry point. All the real setup happens in MenuBarController
// (the NSApplicationDelegate): the status item and the floating panel.
// The Settings scene is a placeholder — an App must declare at least one
// scene. Errol has no settings screen, so its command is taken out, and
// About opens Errol's own window rather than the standard panel.

import SwiftUI

@main
struct ErrolApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) private var menuBar

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About Errol") { menuBar.showAbout() }
                }
                CommandGroup(replacing: .appSettings) {}
            }
    }
}
