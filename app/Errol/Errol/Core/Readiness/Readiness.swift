// Readiness sweeps: whether each app is running, whether it exposes the
// chat surface a run needs, and which windows it offers. Each sweep feeds
// the setup state and the participant badges; the per-window walk it runs
// is in Detection/WindowScan.swift, and the thread that repeats it in
// ReadinessScanner.swift.
//
// The relay's window rules are mirrored here: a window carrying Claude Code
// markers is never the chat window, and "Ready" means the same window and
// composer the run preflight would accept.

import ApplicationServices
import Foundation

/// Coarse per-side state. The setup state reads `.missing` as an app to
/// open; the other states are diagnostics for the tools and the tests.
enum ReadyState {
    case checking   // no sweep has completed yet
    case missing    // app not running, or no Accessibility permission
    case notReady   // running, but no usable chat surface
    case ready      // chat window with a composer found
}

/// One side's status as a sweep read it. The app reads only its name and
/// whether it is missing; the headline, surface, model and detail stay as
/// the diagnostics the verification tools and the tests read. Equatable so
/// the controller can drop no-change sweeps instead of republishing (and
/// re-rendering the console) every poll.
struct SideStatus: Equatable {
    var appName: String
    var state = ReadyState.checking
    var headline = "Checking..."
    /// The chosen window's active surface ("Chat", "Work", "Cowork",
    /// "Code", "Codex"), with no vendor prefix: the console shows a
    /// surface under the app's own name.
    var surface: String?
    /// The chosen window's active model plus effort ("Fable 5 · Extra",
    /// "5.6 Sol High", or "Default"), where the window announces one.
    var model: String?
    /// Secondary context: the window title, or other surfaces open alongside.
    var detail: String?
}

// MARK: - Per-side sweep

/// Everything one sweep of one side learned: the side's status, and the
/// windows behind it for the setup state to offer as candidates. The
/// elements stay with the engine; the pure state only ever sees the
/// candidates.
struct SideSweep {
    var status: SideStatus
    var target: TargetApp?
    var windows: [AXUIElement] = []
    var scans: [WindowScan] = []
}

/// One sweep of `side`, its app found by `findApp(_:)` from the global
/// config and named as the human reads it.
func sweepSide(_ side: Speaker) -> SideSweep {
    sweepSide(findApp(side), name: side.appName)
}

/// One sweep of one side. Mirrors chatWindow's selection rules so the
/// status reports readiness for exactly the window a run would target.
/// The app comes in already looked up, nil when it is not running; `name`
/// labels the status either way, and the scan reads the found app's own
/// selectors.
private func sweepSide(_ found: TargetApp?, name: String) -> SideSweep {
    guard let target = found else {
        var status = SideStatus(appName: name)
        status.state = .missing
        status.headline = "Not running"
        return SideSweep(status: status)
    }
    let selectors = target.selectors

    let firstContact = electronNudges.beginContact(target)
    var windows = axWindows(target)
    if windows.isEmpty, firstContact {
        // First contact after the Electron nudge can race an empty tree.
        usleep(700_000)
        windows = axWindows(target)
    }
    if windows.isEmpty, electronNudges.recordEmptySweep(target) {
        // The ledger judged the app stuck and spent its recovery re-nudge;
        // give the tree the same settle time first contact gets.
        usleep(700_000)
        windows = axWindows(target)
    }
    if !windows.isEmpty { electronNudges.recordWindowsSeen(target) }
    let scans = windows.map { scanWindow(LiveElement(ax: $0), selectors: selectors) }
    return SideSweep(status: composeSideStatus(appName: name, scans: scans, selectors: selectors),
                     target: target, windows: windows, scans: scans)
}

func scanSide(bundleID: String, name: String, selectors: AppSelectors) -> SideStatus {
    sweepSide(findApp(bundleID: bundleID, name: name, selectors: selectors), name: name).status
}

/// A window's identity for the length of the process, from the element's
/// own hash: the same window hashes the same across sweeps, so a candidate
/// chosen from one sweep is found in the registry the next sweep refreshed.
func windowID(of window: AXUIElement) -> WindowID {
    WindowID(raw: UInt(CFHash(window)))
}

/// The candidates one sweep offers for a side, with each window's
/// minimized state read for its state line.
func windowCandidates(from sweep: SideSweep, selectors: AppSelectors) -> [WindowCandidate] {
    let ids = sweep.windows.map(windowID(of:))
    var candidates = windowCandidates(sweep.scans, ids: ids, selectors: selectors)
    for index in candidates.indices {
        guard let position = ids.firstIndex(of: candidates[index].id) else { continue }
        let window = sweep.windows[position]
        candidates[index].isMinimized = (axAttribute(window, kAXMinimizedAttribute) as? Bool) ?? false
    }
    return candidates
}

/// What one readiness sweep reports, for the setup state and the
/// participant badges: each side's status, whether each app is installed,
/// the windows each app offers, and — for a side the human has connected —
/// how its bound conversation reads now.
struct ReadinessReport: Equatable {
    var chatgpt: SideStatus
    var claude: SideStatus
    var installed: [Speaker: Bool] = [:]
    var candidates: [Speaker: [WindowCandidate]] = [:]
    var bindings: [Speaker: BindingObservation] = [:]

    /// The report while the Accessibility grant is missing: nothing can be
    /// read, and each side's status says so.
    static func blocked(installed: [Speaker: Bool]) -> ReadinessReport {
        func status(_ name: String) -> SideStatus {
            SideStatus(appName: name, state: .missing, headline: "No access",
                       detail: "turn on Errol in \(AccessPermission.listName)")
        }
        return ReadinessReport(chatgpt: status(Speaker.chatgpt.appName), claude: status(Speaker.claude.appName),
                               installed: installed)
    }
}

/// The pure half of a sweep: window scans in, the side's status out. Split
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

/// Both sides in one sweep, without the engine's registry or bindings: the
/// live tests' read of the two apps (the app's scanner runs the engine's
/// own sweep). Checks the permission without prompting — the prompt stays
/// tied to the Start button.
func scanBothSides() -> (chatgpt: SideStatus, claude: SideStatus) {
    guard AXIsProcessTrusted() else {
        let blocked = ReadinessReport.blocked(installed: [:])
        return (blocked.chatgpt, blocked.claude)
    }
    return (sweepSide(.chatgpt).status, sweepSide(.claude).status)
}
