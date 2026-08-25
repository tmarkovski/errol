// Readiness scanning for the panel's status strip: whether each app is
// running, whether it exposes the chat surface a run needs, and which
// mode/surface is currently active in it.
//
// Detection is grounded in what the apps expose over AX (verified live,
// Aug 2026):
// - ChatGPT announces its active mode through an AXPopUpButton labeled
//   "Switch mode, current mode: <mode>" — "ChatGPT" is the chat surface,
//   Codex is its own mode.
// - Claude Desktop windows carry an AXWebArea whose AXURL is a claude.ai
//   URL, and its first path component names the surface ("epitaxy" is a
//   Claude Code session; the mapping lives in AppSelectors.surfacePathNames).
//
// The relay's window rules are mirrored here: a window carrying Claude Code
// markers is never the chat window, and "Ready" means the same window and
// composer the run preflight would accept.

import AppKit
import ApplicationServices
import Foundation

/// Coarse per-side state; drives the status dot color in the panel.
enum ReadyState {
    case checking   // no sweep has completed yet
    case missing    // app not running, or no Accessibility permission
    case notReady   // running, but no usable chat surface
    case ready      // chat window with a composer found
}

struct SideStatus {
    var appName: String
    var state = ReadyState.checking
    var headline = "Checking..."
    /// The chosen window's active surface ("Chat mode", "Codex mode", "Chat",
    /// "Claude Code").
    var surface: String?
    /// Secondary context: the window title, or other surfaces open alongside.
    var detail: String?
}

// MARK: - Per-window scan

/// Everything the status needs from one window, collected in a single tree
/// walk. AX reads are synchronous IPC into the target app and the scan
/// repeats every few seconds, so labels are only read on the few roles that
/// can carry a signal.
private struct WindowScan {
    var title = ""
    var hasComposer = false
    /// Carries a window-exclusion marker (a Claude Code session, not a chat).
    var isExcluded = false
    /// Raw mode name from the app's mode switcher popup.
    var modeLabel: String?
    /// First path component of the window's claude.ai AXWebArea URL.
    var surfacePath: String?
}

private func scanWindow(_ window: AXUIElement, selectors: AppSelectors) -> WindowScan {
    var scan = WindowScan()
    scan.title = (axAttribute(window, kAXTitleAttribute) as? String) ?? ""
    visit(window, depth: 0, into: &scan, selectors: selectors)
    return scan
}

private func visit(_ element: AXUIElement, depth: Int, into scan: inout WindowScan,
                   selectors: AppSelectors) {
    guard depth <= 80 else { return }
    let role = (axAttribute(element, kAXRoleAttribute) as? String) ?? ""

    if role == kAXTextAreaRole as String {
        scan.hasComposer = true
    } else if role == kAXButtonRole as String || role == kAXTextFieldRole as String {
        if !scan.isExcluded, !selectors.windowExcludeLabels.isEmpty {
            let label = axLabel(element)
            if selectors.windowExcludeLabels.contains(where: { label.localizedCaseInsensitiveContains($0) }) {
                scan.isExcluded = true
            }
        }
    } else if role == kAXPopUpButtonRole as String {
        if scan.modeLabel == nil, let prefix = selectors.modePopupPrefix {
            let label = axLabel(element)
            if let range = label.range(of: prefix) {
                // axLabel joins several attributes, so the announcement can
                // appear twice; keep only the text between occurrences.
                var rest = String(label[range.upperBound...])
                if let repeated = rest.range(of: prefix) { rest = String(rest[..<repeated.lowerBound]) }
                let mode = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                if !mode.isEmpty { scan.modeLabel = mode }
            }
        }
    } else if role == "AXWebArea" {
        if scan.surfacePath == nil, !selectors.surfacePathNames.isEmpty,
           let url = axAttribute(element, "AXURL") as? NSURL,
           url.host?.localizedCaseInsensitiveContains("claude.ai") == true {
            scan.surfacePath = (url.path ?? "").split(separator: "/").first
                .map { String($0).lowercased() }
        }
    }

    for child in axChildren(element) {
        visit(child, depth: depth + 1, into: &scan, selectors: selectors)
    }
}

/// Human name for a window's active surface, best signal first: the app's
/// own mode switcher, then the claude.ai URL, then the exclusion markers.
private func surfaceName(_ scan: WindowScan, selectors: AppSelectors) -> String? {
    if let mode = scan.modeLabel {
        return (selectors.modeNames[mode.lowercased()] ?? mode) + " mode"
    }
    if let path = scan.surfacePath {
        return selectors.surfacePathNames[path] ?? path
    }
    if scan.isExcluded { return selectors.excludedSurfaceName }
    return nil
}

// MARK: - Per-side sweep

/// One sweep of one side. Mirrors chatWindow's selection rules so the strip
/// reports readiness for exactly the window a run would target.
func scanSide(bundleID: String, name: String, selectors: AppSelectors) -> SideStatus {
    var status = SideStatus(appName: name)
    guard let target = findApp(bundleID: bundleID, name: name, selectors: selectors) else {
        status.state = .missing
        status.headline = "Not running"
        return status
    }

    enableElectronAccessibility(target)
    var windows = axWindows(target)
    if windows.isEmpty {
        // First contact after the Electron nudge can race an empty tree.
        usleep(700_000)
        windows = axWindows(target)
    }
    guard !windows.isEmpty else {
        status.state = .notReady
        status.headline = "No window"
        return status
    }

    let scans = windows.map { scanWindow($0, selectors: selectors) }
    let eligible = scans.indices.filter { !scans[$0].isExcluded }
    let chosenIndex = eligible.first(where: { scans[$0].hasComposer }) ?? eligible.first
    let chosenSurface = chosenIndex.flatMap { surfaceName(scans[$0], selectors: selectors) }

    // Surfaces open in windows other than the chosen one (e.g. a Claude Code
    // session alongside the chat).
    var others: [String] = []
    for index in scans.indices where index != chosenIndex {
        if let name = surfaceName(scans[index], selectors: selectors),
           name != chosenSurface, !others.contains(name) {
            others.append(name)
        }
    }

    guard let chosenIndex else {
        // Every window is excluded — e.g. Claude Desktop hosting only Claude
        // Code sessions, no chat conversation open.
        status.state = .notReady
        status.headline = "Not found"
        status.surface = others.isEmpty ? nil : others.joined(separator: ", ")
        status.detail = "no chat window"
        return status
    }

    let chosen = scans[chosenIndex]
    status.surface = chosenSurface
    var details: [String] = []
    if !chosen.title.isEmpty, chosen.title.localizedCaseInsensitiveCompare(name) != .orderedSame {
        details.append("\u{201C}\(chosen.title)\u{201D}")
    }
    if !others.isEmpty {
        details.append(others.joined(separator: ", ") + " also open")
    }

    if chosen.hasComposer {
        status.state = .ready
        status.headline = "Ready"
    } else {
        status.state = .notReady
        status.headline = "Not found"
        details.append("no composer")
    }
    status.detail = details.isEmpty ? nil : details.joined(separator: "; ")
    return status
}

/// Both sides in one sweep. Runs on the scanner's worker thread. Checks the
/// permission without prompting — the prompt stays tied to the Start button.
func scanBothSides() -> (chatgpt: SideStatus, claude: SideStatus) {
    guard AXIsProcessTrusted() else {
        func blocked(_ name: String) -> SideStatus {
            SideStatus(appName: name, state: .missing, headline: "No access",
                       detail: "grant Accessibility permission")
        }
        return (blocked("ChatGPT"), blocked("Claude"))
    }
    return (scanSide(bundleID: config.chatgptBundleID, name: "ChatGPT",
                     selectors: config.chatgptSelectors),
            scanSide(bundleID: config.claudeBundleID, name: "Claude",
                     selectors: config.claudeSelectors))
}

// MARK: - Scanner

/// Polls both apps while the panel is visible and no run is active. One
/// long-lived worker thread (the AX walks need the same oversized stack as
/// the relay's) parks on a flag instead of stopping, so rapid visibility
/// toggles cannot race two loops into existence.
final class ReadinessScanner {
    /// Called on the worker thread after each sweep.
    var onUpdate: ((SideStatus, SideStatus) -> Void)?
    private let active = CancelFlag()
    private var started = false

    /// Main thread. The first activation lazily starts the thread.
    func setActive(_ scanning: Bool) {
        active.set(scanning)
        guard scanning, !started else { return }
        started = true
        let thread = Thread { [weak self] in self?.loop() }
        thread.name = "ReadinessScanner"
        thread.stackSize = 4 << 20
        thread.start()
    }

    private func loop() {
        while true {
            guard active.isSet else { usleep(200_000); continue }
            let sweep = scanBothSides()
            onUpdate?(sweep.chatgpt, sweep.claude)
            // Sit out the poll interval, but bail early on deactivation so
            // the next activation starts with a fresh sweep immediately.
            for _ in 0..<30 where active.isSet { usleep(100_000) }
        }
    }
}
