// The app entry point. All the real setup happens in MenuBarController
// (the NSApplicationDelegate): the status item and the floating panel.
// The Settings scene is a placeholder — an App must declare at least one
// scene. Its command navigates inside the panel instead of opening a window.

import SwiftUI

@main
struct ErrolApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) private var menuBar

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { menuBar.showSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
