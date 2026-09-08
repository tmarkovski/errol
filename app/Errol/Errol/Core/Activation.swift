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
    if let pid = axFocusedPID() { return pid == target.app.processIdentifier }
    return frontWindowOwnerPID() == target.app.processIdentifier
}

/// The pid the Accessibility API says holds keyboard focus. This is the one
/// that predicts where a synthesized keystroke lands, which is why it is
/// asked first everywhere below; it goes quiet when the focused app's own AX
/// server does.
func axFocusedPID() -> pid_t? {
    guard let focused = axAttribute(systemWideAX, kAXFocusedApplicationAttribute) else { return nil }
    var pid: pid_t = -1
    AXUIElementGetPid(focused as! AXUIElement, &pid)
    return pid
}

/// The pid owning the frontmost ordinary window, according to the window
/// server. Needs no cooperation from the app, so this is what answers when the
/// AX query above does not. Errol's own panels are above layer 0 and so are
/// never mistaken for the front window.
func frontWindowOwnerPID() -> pid_t? {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { return nil }
    for window in info {
        if let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
           let pid = window[kCGWindowOwnerPID as String] as? pid_t {
            return pid
        }
    }
    return nil
}

/// What the focus checks actually saw, for the log line after a failed
/// activation. Without it the failure names the target and nothing else,
/// which is the one thing already known — an app that is hidden, minimized,
/// on another Space, gone since the run resolved it, or simply outranked by a
/// third app holding keyboard focus all fail identically from the outside.
func focusReport(_ target: TargetApp) -> String {
    func describe(_ pid: pid_t?) -> String {
        guard let pid else { return "none" }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "unknown"
        return "\(name) (pid \(pid))"
    }
    var state = [String]()
    if target.app.isTerminated { state.append("terminated") }
    if target.app.isHidden { state.append("hidden") }
    return "wanted pid \(target.app.processIdentifier); "
        + "AX focus \(describe(axFocusedPID())); "
        + "front window \(describe(frontWindowOwnerPID()))"
        + (state.isEmpty ? "" : "; target is \(state.joined(separator: " and "))")
}

/// Whatever app currently holds focus, detected the same dual-path way as
/// isFrontmost (AX focused application, then the window server's front window).
func currentFrontmostApp() -> NSRunningApplication? {
    if let pid = axFocusedPID(), let app = NSRunningApplication(processIdentifier: pid) {
        return app
    }
    if let pid = frontWindowOwnerPID(), let app = NSRunningApplication(processIdentifier: pid) {
        return app
    }
    return NSWorkspace.shared.frontmostApplication
}

/// Hand focus back to the given app — whatever was frontmost before a
/// verification case took it — once the case is done. The app's own runs
/// end the other way round: the console takes the keyboard back
/// (RelayController.finishRun).
func refocus(to app: NSRunningApplication?) {
    guard let app, let bundleID = app.bundleIdentifier else { return }
    // Skip when it never lost focus (e.g. an inspection moves no windows).
    if frontWindowOwnerPID() == app.processIdentifier { return }
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

/// Let go of Errol's own keyboard focus before driving another app.
///
/// The panel is a non-activating floating panel that is nonetheless allowed to
/// become key (KeyablePanel), because its text fields have to be typeable. But
/// a key panel makes Errol the AX-focused application, and everything here
/// reads focus to decide where a synthesized keystroke will land. Two things
/// go wrong while Errol holds it. isFrontmost can never see the target, so
/// activation times out however well it actually worked — Errol pinning the
/// very signal it polls. And if it did type anyway, the paste would go into
/// Errol's own instruction field instead of the chat.
///
/// Async on purpose: the relay drives this from its worker thread, and the
/// caller polls for the result anyway.
func resignOurOwnKeyStatus() {
    DispatchQueue.main.async {
        guard NSApp.isActive || NSApp.keyWindow != nil else { return }
        NSApp.deactivate()
    }
}

/// Bring the target app to the foreground and confirm it got there.
/// NSRunningApplication.activate from a background process is ignored under
/// macOS cooperative activation, so fall back to the AX frontmost attribute
/// (which honors the Accessibility grant) and raising the chat window.
func makeFrontmost(_ target: TargetApp, within seconds: TimeInterval = 6) -> Bool {
    resignOurOwnKeyStatus()
    let deadline = Date().addingTimeInterval(seconds)
    var attempt = 0
    while Date() < deadline {
        if relayControl.isCancelled { return false }
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
