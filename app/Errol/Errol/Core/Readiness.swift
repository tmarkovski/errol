// Readiness scanning for the panel's status strip: whether each app is
// running, whether it exposes the chat surface a run needs, and which
// mode/surface is currently active in it.
//
// Detection is grounded in what the apps expose over AX (verified live,
// Aug 2026):
// - ChatGPT's Chat/Work surfaces are named by the composer-level toggle pair
//   (the "Composer mode" group); its AXPopUpButton labeled "Switch mode,
//   current mode: <mode>" says "ChatGPT" for both and only distinguishes
//   Codex mode.
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

/// Equatable so the controller can drop no-change sweeps instead of
/// republishing (and re-rendering the skins) every poll.
struct SideStatus: Equatable {
    var appName: String
    var state = ReadyState.checking
    var headline = "Checking..."
    /// The chosen window's active surface ("Chat", "Work", "Cowork",
    /// "Code", "Codex"). Shown under the app's own name, so the names
    /// carry no vendor prefix.
    var surface: String?
    /// The chosen window's active model plus effort ("Fable 5 · Extra",
    /// "5.6 Sol High", or "Default"), where the window announces one.
    var model: String?
    /// Secondary context: the window title, or other surfaces open alongside.
    var detail: String?
}

// MARK: - Per-window scan

/// Everything the status needs from one window, collected in a single tree
/// walk. AX reads are synchronous IPC into the target app and the scan
/// repeats every few seconds, so labels are only read on the few roles that
/// can carry a signal.
struct WindowScan {
    var title = ""
    var hasComposer = false
    /// Carries a window-exclusion marker (a Claude Code session, not a chat).
    var isExcluded = false
    /// Raw mode name from the app's mode switcher popup.
    var modeLabel: String?
    /// Display name of the selected composer surface tab ("Chat"/"Cowork"
    /// on Claude, "Chat"/"Work" on ChatGPT).
    var surfaceTab: String?
    /// Surface named by the composer placeholder, for windows where the
    /// toggle pair is not mounted (ChatGPT conversations).
    var composerSurface: String?
    /// Model announcement, prefix stripped ("Fable 5 · Extra"), or the bare
    /// model popup title on Claude Code ("Fable 5").
    var model: String?
    /// Effort from a separate effort popup (Claude Code's "Effort: Extra");
    /// nil where the model announcement already embeds it.
    var effort: String?
    /// Label of the popup visited just before the current one, for the
    /// model-precedes-effort adjacency on Claude Code.
    var lastPopupLabel: String?
    /// First path component of the window's claude.ai AXWebArea URL.
    var surfacePath: String?
}

/// The text after `prefix` in a joined AX label. axLabel concatenates several
/// attributes, so an announcement can appear twice; only the text between
/// occurrences counts.
func value(after prefix: String, in label: String) -> String? {
    guard let range = label.range(of: prefix) else { return nil }
    var rest = String(label[range.upperBound...])
    if let repeated = rest.range(of: prefix) { rest = String(rest[..<repeated.lowerBound]) }
    let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Generic over ElementNode, so fixture windows scan through the identical
/// code the live sweep runs.
func scanWindow<Node: ElementNode>(_ window: Node, selectors: AppSelectors) -> WindowScan {
    var scan = WindowScan()
    scan.title = window.title ?? ""
    visit(window, depth: 0, into: &scan, selectors: selectors)
    return scan
}

private func visit<Node: ElementNode>(_ element: Node, depth: Int, into scan: inout WindowScan,
                                      selectors: AppSelectors) {
    guard depth <= 80 else { return }
    let role = element.role ?? ""

    // Shared with the relay's own window choice, rather than restated here:
    // the strip must classify a window exactly the way chooseChatWindow will,
    // and two copies of the rule drift.
    if !scan.isExcluded, isExclusionMarker(element, role: role, selectors: selectors) {
        scan.isExcluded = true
    }

    if role == kAXTextAreaRole as String {
        scan.hasComposer = true
        if scan.composerSurface == nil, !selectors.composerSurfaceNames.isEmpty {
            let label = element.label
            scan.composerSurface = selectors.composerSurfaceNames
                .first { label.contains($0.key) }?.value
        }
    } else if role == kAXPopUpButtonRole as String {
        let wantsMode = scan.modeLabel == nil && selectors.modePopupPrefix != nil
        let wantsModel = scan.model == nil
            && (selectors.modelPopupPrefix != nil || !selectors.modelPopupSuffixes.isEmpty
                || selectors.modelPopupDefaultLabel != nil)
        let wantsEffort = scan.effort == nil && selectors.effortPopupPrefix != nil
        if wantsMode || wantsModel || wantsEffort {
            let label = element.label
            if wantsMode, let prefix = selectors.modePopupPrefix {
                scan.modeLabel = value(after: prefix, in: label)
            }
            if wantsModel {
                if let prefix = selectors.modelPopupPrefix, label.contains(prefix) {
                    scan.model = value(after: prefix, in: label)
                } else if selectors.modelPopupPrefix == nil {
                    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lower = trimmed.lowercased()
                    if selectors.modelPopupSuffixes.contains(where: {
                        lower == $0 || lower.hasSuffix(" " + $0)
                    }) {
                        scan.model = trimmed
                    } else if trimmed == selectors.modelPopupDefaultLabel {
                        scan.model = "Default"
                    }
                }
            }
            if wantsEffort, let prefix = selectors.effortPopupPrefix, label.contains(prefix) {
                scan.effort = value(after: prefix, in: label)
                // The bare-titled model popup sits immediately before the
                // effort popup (verified live on Claude Code, Aug 2026).
                if scan.model == nil, let previous = scan.lastPopupLabel, !previous.isEmpty {
                    scan.model = previous
                }
            }
            scan.lastPopupLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    } else if role == kAXRadioButtonRole as String || role == kAXCheckBoxRole as String {
        // Claude's surface tabs are AXRadioButtons, ChatGPT's are AXCheckBox
        // toggle buttons; the title match keeps ordinary checkboxes out.
        if scan.surfaceTab == nil, !selectors.surfaceTabNames.isEmpty,
           let title = element.title,
           let name = selectors.surfaceTabNames.first(where: {
               $0.caseInsensitiveCompare(title) == .orderedSame
           }),
           element.numberValue == 1 {
            scan.surfaceTab = name
        }
    } else if role == "AXWebArea" {
        if scan.surfacePath == nil, !selectors.surfacePathNames.isEmpty,
           let url = element.url,
           url.host?.localizedCaseInsensitiveContains("claude.ai") == true {
            scan.surfacePath = url.path.split(separator: "/").first
                .map { String($0).lowercased() }
        }
    }

    for child in element.children {
        visit(child, depth: depth + 1, into: &scan, selectors: selectors)
    }
}

/// Human name for a window's active surface, best signal first: the selected
/// composer tab (ChatGPT's mode popup says "ChatGPT" for both Chat and Work,
/// and Claude's Chat/Cowork share a URL, so the tab outranks everything),
/// then the composer placeholder (ChatGPT unmounts the tab pair inside a
/// conversation), then the app's mode switcher (still tells Codex apart),
/// then the claude.ai URL, then the exclusion markers.
func surfaceName(_ scan: WindowScan, selectors: AppSelectors) -> String? {
    if let tab = scan.surfaceTab { return tab }
    if let surface = scan.composerSurface { return surface }
    if let mode = scan.modeLabel {
        return selectors.modeNames[mode.lowercased()] ?? mode
    }
    if let path = scan.surfacePath {
        // Unmapped paths read fine capitalized ("cowork" -> "Cowork"); the
        // map exists only for paths whose display name differs.
        return selectors.surfacePathNames[path] ?? path.capitalized
    }
    if scan.isExcluded { return selectors.excludedSurfaceName }
    return nil
}

// MARK: - Per-side sweep

/// One sweep of one side. Mirrors chatWindow's selection rules so the strip
/// reports readiness for exactly the window a run would target.
func scanSide(bundleID: String, name: String, selectors: AppSelectors) -> SideStatus {
    guard let target = findApp(bundleID: bundleID, name: name, selectors: selectors) else {
        var status = SideStatus(appName: name)
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
    let scans = windows.map { scanWindow(LiveElement(ax: $0), selectors: selectors) }
    return composeSideStatus(appName: name, scans: scans, selectors: selectors)
}

/// The pure half of a sweep: window scans in, the strip's status out. Split
/// from the AX walking so fixture trees can drive the whole readiness
/// decision in tests.
func composeSideStatus(appName: String, scans: [WindowScan], selectors: AppSelectors) -> SideStatus {
    var status = SideStatus(appName: appName)
    guard !scans.isEmpty else {
        status.state = .notReady
        status.headline = "No window"
        return status
    }

    let eligible = scans.indices.filter { !scans[$0].isExcluded }
    // Mirrors chatWindow: prefer a chat window; when every window is excluded
    // and the selectors allow it, fall back to an excluded-surface window
    // with a composer (a Claude Code session).
    var chosenIndex = eligible.first(where: { scans[$0].hasComposer }) ?? eligible.first
    if chosenIndex == nil, selectors.excludedSurfaceIsFallback {
        chosenIndex = scans.indices.first(where: { scans[$0].hasComposer })
    }
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
    status.model = chosen.model
    if let effort = chosen.effort {
        // Claude Code announces effort separately; render it the way the
        // chat surfaces embed it ("Fable 5 · Extra").
        status.model = status.model.map { "\($0) \u{00B7} \(effort)" } ?? effort
    }
    var details: [String] = []
    if !chosen.title.isEmpty, chosen.title.localizedCaseInsensitiveCompare(appName) != .orderedSame {
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
