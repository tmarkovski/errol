// Adapted from PermissionFlow 2.9.1 (https://github.com/jaywcjlove/PermissionFlow),
// MIT License, Copyright (c) 2026 小弟调调. See THIRD_PARTY_NOTICES.txt.
//
// Follows the System Settings window so the permission guide can stay
// docked under it. The window server lists every app's on-screen windows to
// anyone who asks, so polling that list 30 times a second follows the
// window as it opens, moves, and resizes without any permission, which
// matters because the guide runs exactly when Errol doesn't have one yet.
// Frames are reported in AppKit's screen coordinates, where the origin is
// the bottom left of the main display.

import AppKit

@MainActor
final class GuideWindowTracker {
    /// Called whenever the Settings window's frame changes.
    var onFrameChange: ((CGRect) -> Void)?
    /// Called once System Settings has quit, after tracking has stopped.
    var onTrackingEnded: (() -> Void)?
    /// The Settings window's last known frame, or nil until it is found.
    private var currentFrame: CGRect?

    /// System Settings, which PermissionGuide also opens and brings forward.
    static let settingsBundleID = "com.apple.systempreferences"
    /// Thirty polls a second, so the panel keeps up with the window while
    /// the user drags or resizes it instead of trailing behind.
    private static let pollInterval: TimeInterval = 1.0 / 30.0
    /// System Settings briefly drops out of the running applications while
    /// it opens or swaps panes. Waiting for this many polls in a row without
    /// it (about 0.4 seconds) keeps a short gap from closing the guide.
    private static let missingAppThreshold = 12

    private var pollTimer: Timer?
    /// Whether System Settings was found since tracking started. Until it
    /// is, missing it just means it is still launching.
    private var hasFoundSettings = false
    private var missingPolls = 0

    /// Starts following the Settings window from a clean state.
    func start() {
        stop()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            // The timer runs on the main run loop, where it was scheduled.
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = Self.pollInterval * 0.25
        pollTimer = timer
        refresh()
    }

    /// Stops polling, so the next start begins from nothing.
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        currentFrame = nil
        hasFoundSettings = false
        missingPolls = 0
    }

    /// The one place tracking updates, on every poll: it finds System
    /// Settings and reports the frame the window server has for its window.
    private func refresh() {
        guard let app = Self.runningSettings() else {
            endIfSettingsQuit()
            return
        }
        hasFoundSettings = true
        missingPolls = 0

        if let frame = windowServerFrame(for: app.processIdentifier) {
            report(frame)
        }
    }

    private func report(_ frame: CGRect) {
        guard frame != currentFrame else { return }
        currentFrame = frame
        onFrameChange?(frame)
    }

    /// Ends tracking once System Settings has been missing for several
    /// polls in a row, which means it quit rather than paused.
    private func endIfSettingsQuit() {
        guard hasFoundSettings else { return }
        missingPolls += 1
        guard missingPolls >= Self.missingAppThreshold else { return }
        stop()
        onTrackingEnded?()
    }

    /// The System Settings process to follow. When more than one is
    /// running, one that can show windows wins over a background helper.
    static func runningSettings() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsBundleID)
            .max { ($0.activationPolicy == .prohibited ? 0 : 1) < ($1.activationPolicy == .prohibited ? 0 : 1) }
    }

    // MARK: The window server

    /// The frame of System Settings' largest ordinary window on screen,
    /// which is its main window. Sheets, menus, and other small surfaces
    /// are too small to count.
    private func windowServerFrame(for pid: pid_t) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return windows
            .filter { window in
                guard window[kCGWindowOwnerPID as String] as? pid_t == pid else { return false }
                let layer = window[kCGWindowLayer as String] as? Int ?? 0
                let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
                return layer == 0 && alpha > 0
            }
            .compactMap { window -> CGRect? in
                guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
                let frame = appKitFrame(fromTopLeft: rect)
                return frame.width > 320 && frame.height > 240 ? frame : nil
            }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Converts a rectangle from the window server's coordinates, where y
    /// grows downward from the top of the main display, into AppKit's,
    /// where y grows upward from its bottom. Displays can be arranged
    /// unevenly, so the conversion goes through the display the rectangle
    /// overlaps most.
    private func appKitFrame(fromTopLeft rect: CGRect) -> CGRect {
        let displays = NSScreen.screens.compactMap { screen -> (frame: CGRect, bounds: CGRect)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return (screen.frame, CGDisplayBounds(CGDirectDisplayID(number.uint32Value)))
        }
        func overlap(_ bounds: CGRect) -> CGFloat {
            let shared = bounds.intersection(rect)
            return shared.width * shared.height
        }
        guard let display = displays.filter({ $0.bounds.intersects(rect) })
                .max(by: { overlap($0.bounds) < overlap($1.bounds) })
        else { return rect }
        return CGRect(x: display.frame.minX + (rect.minX - display.bounds.minX),
                      y: display.frame.maxY - (rect.minY - display.bounds.minY) - rect.height,
                      width: rect.width,
                      height: rect.height)
    }
}
