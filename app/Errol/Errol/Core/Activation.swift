// Bringing an app frontmost and verifying it actually got there. From a
// background process under macOS cooperative activation, most activation
// APIs return success without effect; synthesized keystrokes go to the
// frontmost app regardless of AX focus, so nothing here is optional.

import AppKit
import ApplicationServices

/// NSWorkspace.frontmostApplication is refreshed by run-loop notifications,
/// which the relay's worker thread never services, so it goes stale mid-run.
/// The system-wide AX focused application is queried live, but it proxies
/// through the focused app, whose
/// AX server (Electron) is intermittently unresponsive; fall back to the
/// window server's front window, which needs no cooperation from the app.
func isFrontmost(_ target: TargetApp) -> Bool {
    if let focused = axAttribute(systemWideAX, kAXFocusedApplicationAttribute) {
        var pid: pid_t = -1
        AXUIElementGetPid(focused as! AXUIElement, &pid)
        return pid == target.app.processIdentifier
    }
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { return false }
    for window in info {
        if let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
           let pid = window[kCGWindowOwnerPID as String] as? pid_t {
            return pid == target.app.processIdentifier
        }
    }
    return false
}

/// Whatever app currently holds focus, detected the same dual-path way as
/// isFrontmost (AX focused application, then the window server's front window).
func currentFrontmostApp() -> NSRunningApplication? {
    if let focused = axAttribute(systemWideAX, kAXFocusedApplicationAttribute) {
        var pid: pid_t = -1
        AXUIElementGetPid(focused as! AXUIElement, &pid)
        if let app = NSRunningApplication(processIdentifier: pid) { return app }
    }
    if let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] {
        for window in info {
            if let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
               let pid = window[kCGWindowOwnerPID as String] as? pid_t,
               let app = NSRunningApplication(processIdentifier: pid) {
                return app
            }
        }
    }
    return NSWorkspace.shared.frontmostApplication
}

/// Hand focus back to the given app — whatever was frontmost when Start was
/// pressed — at the end of each run.
func refocus(to app: NSRunningApplication?) {
    guard let app, let bundleID = app.bundleIdentifier else { return }
    // Skip when it never lost focus (e.g. an inspection moves no windows).
    if let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] {
        for window in info {
            if let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
               let pid = window[kCGWindowOwnerPID as String] as? pid_t {
                if pid == app.processIdentifier { return }
                break
            }
        }
    }
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-b", bundleID]
    try? open.run()
    open.waitUntilExit()
    log("Focus returned to \(app.localizedName ?? bundleID).")
}

/// LaunchServices activation — the one path that reliably moves both the
/// active-app state and the key window to the target from a background
/// process. isFrontmost can be true while another window still holds key
/// status (synthesized keystrokes follow key, not the active app), so this
/// exists for callers that need typing to land, not just frontmost to read
/// true.
func activateViaLaunchServices(_ target: TargetApp) {
    guard let bundleID = target.app.bundleIdentifier else { return }
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-b", bundleID]
    try? open.run()
    open.waitUntilExit()
}

/// Bring the target app to the foreground and confirm it got there.
/// NSRunningApplication.activate from a background process is ignored under
/// macOS cooperative activation, so fall back to the AX frontmost attribute
/// (which honors the Accessibility grant) and raising the chat window.
func makeFrontmost(_ target: TargetApp, within seconds: TimeInterval = 6) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    var attempt = 0
    while Date() < deadline {
        if relayCancelled.isSet { return false }
        if isFrontmost(target) { return true }
        switch attempt % 3 {
        case 0:
            // Ignored under cooperative activation, but free when it does work.
            target.app.activate(options: [])
        case 1:
            // Observed returning success without effect (macOS 26); kept as a
            // cheap second try on systems where it still lands.
            AXUIElementSetAttributeValue(target.ax, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if let window = chatWindow(in: target) {
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }
        default:
            // LaunchServices activation is the one that reliably lands from a
            // background process (verified: the two above are no-ops here).
            if let bundleID = target.app.bundleIdentifier {
                let open = Process()
                open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                open.arguments = ["-b", bundleID]
                try? open.run()
                open.waitUntilExit()
            }
        }
        attempt += 1
        usleep(300_000)
    }
    return isFrontmost(target)
}
