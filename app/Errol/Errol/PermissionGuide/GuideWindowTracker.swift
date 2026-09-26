// Adapted from PermissionFlow 2.9.1 (https://github.com/jaywcjlove/PermissionFlow),
// MIT License, Copyright (c) 2026 小弟调调. See THIRD_PARTY_NOTICES.txt.
//
// Follows the System Settings window so the permission guide can stay
// docked under it. The window server lists every app's on-screen windows to
// anyone who asks, so polling that list 30 times a second follows the
// window as it opens, moves, and resizes without any permission, which
// matters because the guide runs exactly when Errol doesn't have one yet.
// When Errol is already trusted, accessibility notifications for moves and
// resizes are added on top of the polling. Frames are reported in AppKit's
// screen coordinates, where the origin is the bottom left of the main
// display.

import AppKit
import ApplicationServices

@MainActor
final class GuideWindowTracker {
    /// Called whenever the Settings window's frame changes.
    var onFrameChange: ((CGRect) -> Void)?
    /// Called once System Settings has quit, after tracking has stopped.
    var onTrackingEnded: (() -> Void)?
    /// The Settings window's last known frame, or nil until it is found.
    private(set) var currentFrame: CGRect?

    private static let settingsBundleID = "com.apple.systempreferences"
    /// The polling keeps running even with accessibility notifications,
    /// because the window can appear before the observers are attached.
    private static let pollInterval: TimeInterval = 1.0 / 30.0
    /// System Settings briefly drops out of the running applications while
    /// it opens or swaps panes. Waiting for this many polls in a row without
    /// it (about 0.4 seconds) keeps a short gap from closing the guide.
    private static let missingAppThreshold = 12

    private var pollTimer: Timer?
    private var appObserver: AXObserver?
    private var windowObserver: AXObserver?
    private var observedWindow: AXUIElement?
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

    /// Stops polling and removes the observers, so the next start begins
    /// from nothing.
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        for observer in [appObserver, windowObserver].compactMap({ $0 }) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        appObserver = nil
        windowObserver = nil
        observedWindow = nil
        currentFrame = nil
        hasFoundSettings = false
        missingPolls = 0
    }

    /// The one place tracking updates, from the timer and from the
    /// observers alike. It finds System Settings, reports the frame the
    /// window server has for its window, and, when Errol is trusted,
    /// attaches observers to that window for its moves and resizes.
    private func refresh() {
        guard let app = runningSettings() else {
            endIfSettingsQuit()
            return
        }
        hasFoundSettings = true
        missingPolls = 0

        if let frame = windowServerFrame(for: app.processIdentifier) {
            report(frame)
        }
        guard AXIsProcessTrusted() else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        if appObserver == nil, let observer = makeObserver(for: app.processIdentifier) {
            register(kAXMainWindowChangedNotification, on: appElement, with: observer)
            register(kAXFocusedWindowChangedNotification, on: appElement, with: observer)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            appObserver = observer
        }

        guard let window = mainWindow(of: appElement) else { return }
        if let observedWindow, CFEqual(window, observedWindow) {
            reportObservedWindowFrame()
            return
        }
        observedWindow = window
        observeMovesAndResizes(of: window, pid: app.processIdentifier)
        reportObservedWindowFrame()
    }

    private func report(_ frame: CGRect) {
        guard frame != currentFrame else { return }
        currentFrame = frame
        onFrameChange?(frame)
    }

    /// Ends tracking once System Settings has been missing for several
    /// polls in a row, which means it quit rather than paused.
    private func endIfSettingsQuit() {
        guard hasFoundSettings || currentFrame != nil else { return }
        missingPolls += 1
        guard missingPolls >= Self.missingAppThreshold else { return }
        stop()
        onTrackingEnded?()
    }

    /// The System Settings process to follow. When more than one is
    /// running, one that can show windows wins over a background helper.
    private func runningSettings() -> NSRunningApplication? {
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

    /// Converts a rectangle from the window server's and accessibility's
    /// coordinates, where y grows downward from the top of the main display,
    /// into AppKit's, where y grows upward from its bottom. Displays can be
    /// arranged unevenly, so the conversion goes through the display the
    /// rectangle overlaps most.
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

    // MARK: Accessibility, once Errol is trusted

    /// Reports the observed window's frame from its accessibility position
    /// and size.
    private func reportObservedWindowFrame() {
        guard let window = observedWindow,
              let position = pointValue(kAXPositionAttribute, of: window),
              let size = sizeValue(kAXSizeAttribute, of: window) else { return }
        report(appKitFrame(fromTopLeft: CGRect(origin: position, size: size)))
    }

    /// The window to follow: the main window, then the focused one, then
    /// the first in the app's list.
    private func mainWindow(of app: AXUIElement) -> AXUIElement? {
        elementValue(kAXMainWindowAttribute, of: app)
            ?? elementValue(kAXFocusedWindowAttribute, of: app)
            ?? elementsValue(kAXWindowsAttribute, of: app)?.first
    }

    /// Moves the window observer onto a new window.
    private func observeMovesAndResizes(of window: AXUIElement, pid: pid_t) {
        if let windowObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(windowObserver), .commonModes)
        }
        windowObserver = makeObserver(for: pid)
        guard let windowObserver else { return }
        register(kAXMovedNotification, on: window, with: windowObserver)
        register(kAXResizedNotification, on: window, with: windowObserver)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(windowObserver), .commonModes)
    }

    /// An observer whose every notification leads back to refresh(). The
    /// refresh waits for the next turn of the main queue because it can
    /// replace the very observer whose callback is running.
    private func makeObserver(for pid: pid_t) -> AXObserver? {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<GuideWindowTracker>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { tracker.refresh() }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success else { return nil }
        return observer
    }

    /// The tracker lives as long as PermissionGuide, which is the life of
    /// the app, so the observers can hold it unretained.
    private func register(_ notification: String, on element: AXUIElement, with observer: AXObserver) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(observer, element, notification as CFString, refcon)
    }

    // Each reader checks the value's type before casting, so an unexpected
    // reply from System Settings reads as nothing instead of crashing.

    private func elementValue(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func elementsValue(_ attribute: String, of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFArrayGetTypeID() else { return nil }
        let elements = (value as! NSArray).compactMap { item -> AXUIElement? in
            let item = item as CFTypeRef
            return CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
        return elements.isEmpty ? nil : elements
    }

    private func pointValue(_ attribute: String, of element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeValue(_ attribute: String, of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
