// App discovery: resolving a running chat app into an AX handle.

import AppKit
import ApplicationServices

struct TargetApp {
    let name: String
    let app: NSRunningApplication
    let ax: AXUIElement
    let selectors: AppSelectors
}

func findApp(bundleID: String, name: String, selectors: AppSelectors) -> TargetApp? {
    guard let running = NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == bundleID }) else { return nil }
    let ax = AXUIElementCreateApplication(running.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, 3.0)
    return TargetApp(name: name, app: running, ax: ax, selectors: selectors)
}

/// Electron apps expose an empty AX tree until nudged.
func enableElectronAccessibility(_ target: TargetApp) {
    AXUIElementSetAttributeValue(target.ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(target.ax, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
}
