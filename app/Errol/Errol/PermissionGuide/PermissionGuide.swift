// Adapted from PermissionFlow 2.9.1 (https://github.com/jaywcjlove/PermissionFlow),
// MIT License, Copyright (c) 2026 小弟调调. See THIRD_PARTY_NOTICES.txt.
//
// The guide behind the permission screen's button, the way Codex Computer
// Use asks for the same grant: System Settings opens on the list, and a
// panel docked under its window holds Errol's icon to drag into the list,
// which adds Errol and turns it on in one move. Nobody has to find Errol
// in a file picker or learn where the list is. The guide needs no
// permission of its own: GuideWindowTracker follows the Settings window
// through the window server, GuidePanel docks under it, PermissionGuideView
// draws the card, and GuideDragArea hands Errol to the list the way a drag
// from Finder would. This file opens the list and ties those pieces
// together. The shell's once-a-second check puts the guide away when the
// grant lands (MenuBarController.refreshAccessibility).

import AppKit

@MainActor
enum PermissionGuide {
    private static let settingsAppURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
    /// The list in Privacy & Security. macOS 27 renamed it Device Control
    /// and Data Access, and the link stayed the same.
    private static let listURL =
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!

    /// What the panel shows, with its actions wired to the guide.
    private static let model: PermissionGuideModel = {
        let model = PermissionGuideModel()
        model.reopenSettings = { reopenList() }
        model.close = { close(returningToPreviousApp: true) }
        model.dragStateChanged = { setDragging($0) }
        return model
    }()

    private static let tracker: GuideWindowTracker = {
        let tracker = GuideWindowTracker()
        tracker.onFrameChange = { place(under: $0) }
        tracker.onTrackingEnded = { close(returningToPreviousApp: false) }
        return tracker
    }()

    private static var panel: GuidePanel?
    /// The app that was in front before the guide opened System Settings,
    /// which the guide's close button returns to.
    private static var previousApp: (pid: pid_t, bundleID: String?)?
    private static var activationObserver: NSObjectProtocol?

    /// Whether the guide was started since it was last put away. Closing
    /// it with its own button leaves this set, so a grant the user then
    /// makes by hand in the list still brings the console back.
    private static var isStarted = false

    /// Opens the list and docks the panel under System Settings. The panel
    /// comes in once the tracker finds the Settings window on screen, so
    /// it never shows anywhere but under it.
    static func show() {
        isStarted = true
        rememberFrontmostApp()
        openList()
        followFrontmostApp()
        if panel == nil {
            panel = GuidePanel(model: model, onPress: { keepSettingsInFront() })
        }
        tracker.start()
    }

    /// Puts the guide away. Returns whether one had been started, so the
    /// caller can bring the console back to where the user left off.
    @discardableResult
    static func dismiss() -> Bool {
        defer { isStarted = false }
        guard isStarted else { return false }
        close(returningToPreviousApp: false)
        return true
    }

    // MARK: The panel

    /// Brings the panel in under the Settings window the first time the
    /// window is found, and moves it straight along with the window after
    /// that.
    private static func place(under settingsFrame: CGRect) {
        guard let panel else { return }
        if panel.isVisible {
            panel.snap(to: settingsFrame)
        } else {
            panel.present(under: settingsFrame)
        }
    }

    /// Takes the panel down and stops following System Settings. The close
    /// button also returns the user to the app they were in before. Every
    /// way out forgets that app, so a later guide opened from System
    /// Settings leaves the user there instead of returning to a stale one.
    private static func close(returningToPreviousApp: Bool) {
        tracker.stop()
        stopFollowingFrontmostApp()
        panel?.close()
        panel = nil
        model.isDragging = false
        if returningToPreviousApp { reactivatePreviousApp() }
        previousApp = nil
    }

    private static func setDragging(_ isDragging: Bool) {
        model.isDragging = isDragging
        panel?.setDraggingPassthrough(isDragging)
    }

    // MARK: System Settings

    /// Opens System Settings on the list and asks it to come forward.
    private static func openList() {
        NSWorkspace.shared.openApplication(at: settingsAppURL, configuration: NSWorkspace.OpenConfiguration())
        NSWorkspace.shared.open(listURL)
        GuideWindowTracker.runningSettings()?.activate(options: [])
    }

    /// Brings the list back after the user has gone to another app, with
    /// the panel over it.
    private static func reopenList() {
        openList()
        panel?.orderFrontRegardless()
    }

    /// A press on the panel keeps System Settings in front, since that is
    /// where the drag ends and where the user works while the guide is up.
    private static func keepSettingsInFront() {
        GuideWindowTracker.runningSettings()?.activate(options: [])
        panel?.orderFrontRegardless()
    }

    /// Tells the panel whether System Settings is in front, so it can offer
    /// a way back when it isn't. The guide has just asked System Settings
    /// forward, so it starts out in front, and each app activation after
    /// that updates it while the guide is up.
    private static func followFrontmostApp() {
        model.isSettingsFrontmost = true
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                model.isSettingsFrontmost =
                    NSWorkspace.shared.frontmostApplication?.bundleIdentifier == GuideWindowTracker.settingsBundleID
            }
        }
    }

    private static func stopFollowingFrontmostApp() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    // MARK: The app the user was in

    /// Remembers the frontmost app, unless it is System Settings itself,
    /// which is where the guide leaves the user anyway.
    private static func rememberFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != GuideWindowTracker.settingsBundleID else { return }
        previousApp = (app.processIdentifier, app.bundleIdentifier)
    }

    /// Returns to the remembered app, by its process when that is still
    /// running and by its bundle when it was relaunched meanwhile.
    private static func reactivatePreviousApp() {
        guard let previous = previousApp else { return }
        let app = NSRunningApplication(processIdentifier: previous.pid)
            ?? previous.bundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        app?.activate(options: [])
    }
}
