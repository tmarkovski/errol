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
/// republishing (and re-rendering the panel) every poll.
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
    /// The path of the window's web-area URL when it names one conversation
    /// (AppSelectors.conversationRoutePrefixes): "/chat/<uuid>" on a Claude
    /// chat, "/epitaxy/<id>" on a Claude Code session. nil on a fresh chat,
    /// a Cowork task, a project page, and everywhere ChatGPT.
    var conversationRoute: String?
    /// The value and label of the window's last text input — the composer,
    /// the way `composerElement` picks it — for judging what it holds
    /// (classifyComposer) without a second walk. nil when the window has
    /// no text input.
    var composerValue: String?
    var composerLabel = ""
    /// A stop control is mounted: the app is producing a reply.
    var isReplying = false
    /// Pasted-text attachment chips anywhere in the window. Coarse — the
    /// composer-scoped count needs the live parent walk — so a chip left in
    /// the history can count; a connection's readiness reads the precise one.
    var attachmentChips = 0
    /// Messages in the window's tree by their affordances (copy buttons and
    /// collapsed action bars, the count the relay's baselines use).
    var messageAffordances = 0
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

    if role == kAXButtonRole as String {
        // One label read serves every rule a button can match. The
        // exclusion rule is shared with the relay's own window choice
        // rather than restated: the strip must classify a window exactly
        // the way chooseChatWindow will, and two copies of the rule drift.
        let label = element.label
        if !scan.isExcluded, isExclusionMarker(role: role, label: label, selected: false, selectors: selectors) {
            scan.isExcluded = true
        }
        if isCopyButtonLabel(label, selectors: selectors)
            || selectors.messageActionsLabel.map({ label.localizedCaseInsensitiveContains($0) }) == true {
            scan.messageAffordances += 1
        }
        if !scan.isReplying, label.localizedCaseInsensitiveContains(selectors.stopKeyword) {
            scan.isReplying = true
        }
        if let remove = selectors.pastedTextAttachmentRemoveLabel,
           label.localizedCaseInsensitiveContains(remove) {
            scan.attachmentChips += 1
        }
    } else if role == kAXTextAreaRole as String || role == kAXTextFieldRole as String {
        let label = element.label
        if role == kAXTextAreaRole as String {
            scan.hasComposer = true
            if scan.composerSurface == nil, !selectors.composerSurfaceNames.isEmpty {
                scan.composerSurface = selectors.composerSurfaceNames
                    .first { label.contains($0.key) }?.value
            }
        } else if !scan.isExcluded, isExclusionMarker(role: role, label: label, selected: false, selectors: selectors) {
            scan.isExcluded = true
        }
        // The last text input in tree order is the composer, exactly as
        // composerElement picks it; each one seen overwrites the last.
        scan.composerValue = element.stringValue
        scan.composerLabel = label
    } else if role == kAXRadioButtonRole as String, !scan.isExcluded,
              isExclusionMarker(element, role: role, selectors: selectors) {
        scan.isExcluded = true
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
        // Only the app's own web host counts: Claude's window also carries
        // the outer file:// shell, and ChatGPT's an app:// one.
        if let url = element.url, let host = url.host,
           selectors.identityHosts.contains(where: { host.localizedCaseInsensitiveContains($0) }) {
            let components = url.path.split(separator: "/").map { String($0) }
            if scan.surfacePath == nil, !selectors.surfacePathNames.isEmpty {
                scan.surfacePath = components.first?.lowercased()
            }
            if scan.conversationRoute == nil, components.count >= 2,
               selectors.conversationRoutePrefixes.contains(components[0].lowercased()) {
                scan.conversationRoute = url.path
            }
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

/// Everything one sweep of one side learned: the strip's status, and the
/// windows behind it for the setup flow to offer as candidates. The
/// elements stay with the engine; the pure state only ever sees the
/// candidates.
struct SideSweep {
    var status: SideStatus
    var target: TargetApp?
    var windows: [AXUIElement] = []
    var scans: [WindowScan] = []
}

/// One sweep of one side. Mirrors chatWindow's selection rules so the strip
/// reports readiness for exactly the window a run would target.
func sweepSide(bundleID: String, name: String, selectors: AppSelectors) -> SideSweep {
    guard let target = findApp(bundleID: bundleID, name: name, selectors: selectors) else {
        var status = SideStatus(appName: name)
        status.state = .missing
        status.headline = "Not running"
        return SideSweep(status: status)
    }

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
    sweepSide(bundleID: bundleID, name: name, selectors: selectors).status
}

/// A window's identity for the length of the process, from the element's
/// own hash: the same window hashes the same across sweeps, so a candidate
/// chosen from one sweep is found in the registry the next sweep refreshed.
func windowID(of window: AXUIElement) -> WindowID {
    WindowID(raw: UInt(CFHash(window)))
}

/// The candidates one sweep offers for a side, with each window's frame
/// and minimized state read for the picker's highlight.
func windowCandidates(from sweep: SideSweep, selectors: AppSelectors) -> [WindowCandidate] {
    let ids = sweep.windows.map(windowID(of:))
    var candidates = windowCandidates(sweep.scans, ids: ids, selectors: selectors)
    for index in candidates.indices {
        guard let position = ids.firstIndex(of: candidates[index].id) else { continue }
        let window = sweep.windows[position]
        candidates[index].frame = windowFrame(window)
        candidates[index].isMinimized = (axAttribute(window, kAXMinimizedAttribute) as? Bool) ?? false
    }
    return candidates
}

/// What one readiness sweep reports: the strip's status per side, whether
/// each app is installed at all, the windows each app offers, and — for a
/// side the human has connected — how its bound conversation reads now.
struct ReadinessReport: Equatable {
    var chatgpt: SideStatus
    var claude: SideStatus
    var installed: [Speaker: Bool] = [:]
    var candidates: [Speaker: [WindowCandidate]] = [:]
    var bindings: [Speaker: BindingObservation] = [:]

    /// The report while the Accessibility grant is missing: nothing can be
    /// read, and the strip says so.
    static func blocked(installed: [Speaker: Bool]) -> ReadinessReport {
        func status(_ name: String) -> SideStatus {
            SideStatus(appName: name, state: .missing, headline: "No access",
                       detail: "grant Accessibility permission")
        }
        return ReadinessReport(chatgpt: status("ChatGPT"), claude: status("Claude"), installed: installed)
    }
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

// MARK: - Wake hints

/// AXObserver notifications from the target apps, used strictly as
/// invalidation hints: a hint schedules a full sweep and never contributes
/// state of its own. Registration is allowed to fail per process —
/// AXObserverAddNotification can return notification-unsupported or
/// cannot-complete, and Electron's support is spotty — and window-level
/// notifications can't see composer or model changes anyway, so the timed
/// sweep stays the source of truth and hints only make it prompter.
///
/// Main-thread only: AXObserver delivers on the registering thread's run
/// loop, and hosting the sources on main keeps the scanner thread free of
/// a CFRunLoop. The callback does nothing but forward, so the main thread
/// never walks a tree on a hint.
final class AXWakeHints {
    /// Fires on the main thread when any registered notification arrives.
    var onHint: (() -> Void)?
    private var observers: [pid_t: AXObserver] = [:]
    /// Registration already failed for these; retried only after the app
    /// relaunches (termination clears the entry via `forget`).
    private var failed = Set<pid_t>()

    /// Keep one observer per running target process.
    func reconcile(pids: [pid_t]) {
        for (pid, observer) in observers where !pids.contains(pid) {
            removeSource(of: observer)
            observers[pid] = nil
        }
        for pid in pids where observers[pid] == nil && !failed.contains(pid) {
            if let observer = makeObserver(pid) {
                observers[pid] = observer
            } else {
                failed.insert(pid)
            }
        }
    }

    func forget(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            removeSource(of: observer)
        }
        failed.remove(pid)
    }

    private func removeSource(of observer: AXObserver) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(),
                              AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func makeObserver(_ pid: pid_t) -> AXObserver? {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<AXWakeHints>.fromOpaque(refcon).takeUnretainedValue().onHint?()
        }
        guard AXObserverCreate(pid, callback, &observer) == .success,
              let observer else { return nil }
        // Registered on the application element, which receives its
        // descendants' notifications. Any one of the three sufficing is
        // enough to be useful; all failing means this process won't hint.
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var registered = false
        for notification in [kAXWindowCreatedNotification,
                             kAXFocusedWindowChangedNotification,
                             kAXTitleChangedNotification] {
            if AXObserverAddNotification(observer, app, notification as CFString,
                                         refcon) == .success {
                registered = true
            }
        }
        guard registered else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer), .defaultMode)
        return observer
    }
}

// MARK: - Scanner

/// Polls both apps while the panel is visible and no run is active. One
/// long-lived worker thread (the AX walks need the same oversized stack as
/// the relay's) parks on a condition instead of stopping, so rapid
/// visibility toggles cannot race two loops into existence — and a parked
/// scanner takes zero wakeups. The cadence starts at `baseInterval` and
/// backs off toward `maxInterval` while consecutive sweeps come back
/// identical; an unchanged sweep says nothing about the next moment (a
/// mode or model flip has no workspace-level signal), so the ceiling stays
/// low. Any change, lifecycle event, or fresh activation snaps it back.
final class ReadinessScanner {
    /// Called on the worker thread after each sweep.
    var onUpdate: ((ReadinessReport) -> Void)?
    /// The sweep itself, run on the worker thread: the engine supplies one
    /// that also refreshes its window registry and checks its bindings.
    /// The default is the strip's plain sweep of both apps.
    var sweep: () -> ReadinessReport = {
        let both = scanBothSides()
        return ReadinessReport(chatgpt: both.chatgpt, claude: both.claude)
    }

    private static let baseInterval: TimeInterval = 3
    private static let maxInterval: TimeInterval = 10
    /// Floor between sweeps however fast wake requests arrive, so a burst
    /// of them collapses into one sweep.
    private static let minSpacing: TimeInterval = 1

    private let condition = NSCondition()
    private var active = false
    private var sweepAsked = false
    private var cadenceReset = false
    private var started = false
    /// Main-thread only, like the run-loop sources it manages.
    private let wakeHints = AXWakeHints()

    init() {
        wakeHints.onHint = { [weak self] in self?.requestSweep() }
        // Lifecycle of the two target apps: launch and activation re-bank
        // the nudge ledger's retry and warrant a prompt sweep; termination
        // clears the pid so a relaunch counts as first contact again. The
        // notification center holds the block observers for the scanner's
        // (app-long) life.
        let center = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, terminated: Bool)] = [
            (NSWorkspace.didLaunchApplicationNotification, false),
            (NSWorkspace.didActivateApplicationNotification, false),
            (NSWorkspace.didTerminateApplicationNotification, true),
        ]
        for (name, terminated) in events {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier,
                      [config.chatgptBundleID, config.claudeBundleID].contains(bundleID)
                else { return }
                if terminated {
                    electronNudges.forget(app.processIdentifier)
                    self?.wakeHints.forget(app.processIdentifier)
                } else {
                    electronNudges.replenish(app.processIdentifier)
                }
                self?.requestSweep()
            }
        }
    }

    /// After each sweep: keep an AXObserver on each running target, so the
    /// next relevant change hints instead of waiting out the interval.
    /// Skipped without the Accessibility grant — registration needs it.
    private func reconcileWakeHints() {
        guard AXIsProcessTrusted() else {
            wakeHints.reconcile(pids: [])
            return
        }
        let targets = [config.chatgptBundleID, config.claudeBundleID]
        let pids = NSWorkspace.shared.runningApplications
            .filter { targets.contains($0.bundleIdentifier ?? "") }
            .map(\.processIdentifier)
        wakeHints.reconcile(pids: pids)
    }

    /// Main thread. The first activation lazily starts the thread.
    func setActive(_ scanning: Bool) {
        condition.lock()
        if scanning, !active { cadenceReset = true }
        active = scanning
        condition.signal()
        condition.unlock()
        guard scanning, !started else { return }
        started = true
        let thread = Thread { [weak self] in self?.loop() }
        thread.name = "ReadinessScanner"
        thread.stackSize = 4 << 20
        thread.start()
    }

    /// Ask for a prompt sweep and a cadence reset: app lifecycle events
    /// and AX wake hints land here. Ignored while inactive — the next
    /// activation opens with a fresh sweep anyway.
    func requestSweep() {
        condition.lock()
        if active {
            sweepAsked = true
            cadenceReset = true
            condition.signal()
        }
        condition.unlock()
    }

    private func loop() {
        var interval = Self.baseInterval
        var previous: ReadinessReport?
        var lastSweepEnded = Date.distantPast
        while true {
            condition.lock()
            while !active { condition.wait() }
            sweepAsked = false
            if cadenceReset {
                cadenceReset = false
                interval = Self.baseInterval
            }
            condition.unlock()

            let spacing = Self.minSpacing + lastSweepEnded.timeIntervalSinceNow
            if spacing > 0 { usleep(useconds_t(spacing * 1_000_000)) }

            let report = sweep()
            lastSweepEnded = Date()
            onUpdate?(report)
            DispatchQueue.main.async { [weak self] in self?.reconcileWakeHints() }

            let changed = previous == nil || previous! != report
            previous = report
            interval = changed ? Self.baseInterval
                               : min(interval * 1.6, Self.maxInterval)

            // Sit out the interval; deactivation parks the loop above, and
            // a sweep request cuts the wait short.
            condition.lock()
            let deadline = Date().addingTimeInterval(interval)
            while active, !sweepAsked {
                if !condition.wait(until: deadline) { break }
            }
            condition.unlock()
        }
    }
}
