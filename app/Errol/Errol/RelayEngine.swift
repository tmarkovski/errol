// The seam between the panel's model and the machinery that drives the
// apps. RelayController owns what the panel shows; an engine owns
// everything that reaches outside the process — the Accessibility
// permission, the two apps, the readiness sweeps, the relay worker — and
// reports back over its event stream. The app runs LiveRelayEngine. The
// canvases run PerchPreviewEngine (Perch/PerchPreviewEngine.swift), which
// plays a run without touching any app, so a preview's Start starts
// something and its Stop stops it while nothing is relayed anywhere.
//
// Setup goes through the same seam: the engine opens an app, offers the
// windows it finds, binds the one the human chose, arranges the two, and
// runs the relay into exactly those windows. The live elements never
// leave the engine — the model sees WindowIDs and observations — so a
// saved preference can never masquerade as a live connection.

import AppKit
import ApplicationServices
import Foundation

protocol RelayEngine: AnyObject {
    /// The engine's outward stream. The controller subscribes once; the
    /// engine posts from wherever its work happens, and delivery is on the
    /// main thread in posting order (RelayEventBus).
    var events: RelayEventBus { get }
    /// The inward flags and mailbox: cancel, pause, the steering note. The
    /// controller writes them; the run reads them at its boundaries.
    var control: RelayControl { get }
    /// Readiness sweeps report here, on whatever thread the sweep ran: the
    /// strip's status per side, the windows each app offers, and how each
    /// bound conversation reads now.
    var onReadiness: ((ReadinessReport) -> Void)? { get set }
    /// Whether to sweep at all: only while someone can see the strip, and
    /// never while a run owns the apps.
    func setScanning(_ scanning: Bool)
    /// Ask for a prompt sweep — the picker opening, a return to the editor
    /// — rather than waiting out the interval.
    func requestSweep()
    /// Whether a run can start now: the permission is granted and both
    /// sides are bound. What is missing is reported as a failed start on
    /// the event stream. May prompt (the Accessibility dialog), which is
    /// why it is asked at Send and not at launch.
    func preflight() -> Bool
    /// Start the run, with the settings config holds (seed, turns, first
    /// speaker), into the bound windows, on the engine's own worker. It
    /// ends with `.finished` on the event stream, after every line it
    /// logged. Called after a preflight that passed.
    func startRun()
    /// The debug dump of both apps' windows, buttons, and selector matches
    /// into the log. Does its own preflight.
    func inspect()

    // MARK: Setup

    /// Open the app. false when it is not installed, in which case nothing
    /// is opened.
    func launch(_ side: Speaker) -> Bool
    /// Bring the app forward, so the human can open a conversation in it.
    func bringForward(_ side: Speaker)
    /// Bind `window` as the side's destination. The observation arrives on
    /// the main thread; nil when the window is gone.
    func bind(_ side: Speaker, to window: WindowID, completion: @escaping (BindingObservation?) -> Void)
    /// Resolve the visible window under the pointer, without activating it
    /// or sending a file drop to it. Points use AX screen coordinates.
    func windowAtPoint(_ point: CGPoint, for side: Speaker, ignoring: Set<UInt32>,
                       completion: @escaping (WindowID?) -> Void)
    func unbind(_ side: Speaker)
    /// Apply a layout to the two windows, ChatGPT first. Answered on the
    /// main thread.
    func arrange(_ layout: LayoutChoice, windows: [Speaker: WindowID],
                 completion: @escaping (ArrangeOutcome) -> Void)
    /// Whether an arrangement's original frames are held for a restore.
    var canRestoreArrangement: Bool { get }
    /// Put back the arranged windows that still stand where the layout
    /// left them. Answered on the main thread with how many were.
    func restoreArrangement(completion: @escaping (Int) -> Void)
}

/// The engine the app runs: the relay over Accessibility on a worker
/// thread, reporting on the process-wide bus the Core functions log to,
/// steered through the process-wide control the relay loop polls.
final class LiveRelayEngine: RelayEngine {
    let events = relayEvents
    let control = relayControl
    var onReadiness: ((ReadinessReport) -> Void)? {
        get { scanner.onUpdate }
        set { scanner.onUpdate = newValue }
    }
    private let scanner = ReadinessScanner()
    /// The windows the sweeps found and the sides' bindings, by id.
    private let registry = WindowRegistry()
    private let arranger = WindowArranger()

    init() {
        scanner.sweep = { [registry] in Self.sweep(registry: registry) }
    }

    func setScanning(_ scanning: Bool) {
        scanner.setActive(scanning)
    }

    func requestSweep() {
        scanner.requestSweep()
    }

    // MARK: The sweep

    /// One readiness sweep, on the scanner's thread: both apps' windows
    /// refreshed into the registry, offered as candidates, and each bound
    /// conversation checked the way the run's preflight will check it.
    private static func sweep(registry: WindowRegistry) -> ReadinessReport {
        let installed: [Speaker: Bool] = [
            .chatgpt: isInstalled(config.chatgptBundleID),
            .claude: isInstalled(config.claudeBundleID),
        ]
        guard AXIsProcessTrusted() else { return .blocked(installed: installed) }
        let chatgpt = sweepSide(bundleID: config.chatgptBundleID, name: "ChatGPT",
                                selectors: config.chatgptSelectors)
        let claude = sweepSide(bundleID: config.claudeBundleID, name: "Claude",
                               selectors: config.claudeSelectors)
        var report = ReadinessReport(chatgpt: chatgpt.status, claude: claude.status, installed: installed)
        for (side, sweep, selectors) in [(Speaker.chatgpt, chatgpt, config.chatgptSelectors),
                                         (Speaker.claude, claude, config.claudeSelectors)] {
            registry.remember(side, windows: sweep.windows, target: sweep.target)
            report.candidates[side] = windowCandidates(from: sweep, selectors: selectors)
            if let binding = registry.binding(side) {
                let check = binding.check()
                report.bindings[side] = BindingObservation(
                    check: check, identity: binding.identity,
                    composer: check == .same ? composerState(in: binding.target) : .unreadable)
            }
        }
        return report
    }

    private static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    // MARK: Runs

    func preflight() -> Bool {
        guard ensureTrusted() else {
            failStart("Accessibility permission missing. Grant Errol in System Settings > Privacy & Security > Accessibility, then send again.")
            return false
        }
        let bindings = registry.bindings
        for side in [Speaker.chatgpt, .claude] where bindings[side] == nil {
            failStart("Connect \(side == .chatgpt ? "ChatGPT" : "Claude")'s conversation first.")
            return false
        }
        return true
    }

    /// A start that never reached the worker still ends with a report, so
    /// the panel shows the reason where the run would have been.
    private func failStart(_ reason: String) {
        events.post(.ended(RunReport(outcome: .failedStart(reason: reason))))
    }

    func startRun() {
        let bindings = registry.bindings
        guard let chatgpt = bindings[.chatgpt], let claude = bindings[.claude] else {
            report("Start skipped: both conversations must be connected.")
            failStart("Connect both conversations first.")
            events.post(.finished)
            return
        }
        // Clear a stale cancel or pause — or a note that never found its
        // handoff — before the worker can read any of them.
        control.reset()
        // The on-disk debug log opens before the first line and closes
        // after the last, so a run's file holds the whole run and nothing
        // else (Inspect reports and idle-time lines stay in the panel).
        RunLog.begin()
        log("Run starting.")
        if let path = RunLog.currentPath { log("Debug log: \(path)") }
        runExclusively { [events, control] in
            // First contact only: the scanner has usually nudged both long
            // ago, and then the trees are already populated and the settle
            // wait would just delay the run.
            let freshChatgpt = electronNudges.beginContact(chatgpt.target)
            let freshClaude = electronNudges.beginContact(claude.target)
            if freshChatgpt || freshClaude { usleep(700_000) }
            _ = runRelay(chatgpt: chatgpt.target, claude: claude.target,
                         bindings: [.chatgpt: chatgpt, .claude: claude],
                         showTransfers: true) { continuing in
                completeFocusOperation(control: control, events: events, continuingRun: continuing)
            }
            // Focus is the controller's to settle on `.finished`: the
            // console takes the keyboard back from whichever chat app
            // replied last (RelayController.finishRun).
            events.post(.finished)
            RunLog.end()
        }
    }

    func inspect() {
        guard ensureTrusted(), let apps = resolveApps() else { return }
        report("Inspecting both apps...")
        runExclusively { [events] in
            let freshChatgpt = electronNudges.beginContact(apps.chatgpt)
            let freshClaude = electronNudges.beginContact(apps.claude)
            if freshChatgpt || freshClaude { usleep(700_000) }
            let report = inspectReport(apps.chatgpt) + "\n\n" + inspectReport(apps.claude)
            events.post(.log(report))
        }
    }

    // MARK: Setup

    func launch(_ side: Speaker) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID(side)) else {
            return false
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { log("\(self.name(side)): could not be opened: \(error.localizedDescription)") }
        }
        // The scanner also hears the launch itself (didLaunchApplication),
        // and sweeps again when the windows appear.
        return true
    }

    func bringForward(_ side: Speaker) {
        runExclusively { [self] in
            guard let target = findApp(bundleID: bundleID(side), name: name(side), selectors: selectors(side)) else { return }
            activateViaLaunchServices(target)
        }
    }

    func bind(_ side: Speaker, to window: WindowID, completion: @escaping (BindingObservation?) -> Void) {
        runExclusively { [self, registry] in
            guard let (target, element) = registry.window(side, window), windowIsAlive(element) else {
                log("\(name(side)): the chosen window is gone before it could be connected")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let binding = BoundDestination(target: target, window: element)
            registry.bind(side, binding)
            log(binding.bindingReport)
            let observation = BindingObservation(check: .same, identity: binding.identity,
                                                 composer: composerState(in: binding.target))
            DispatchQueue.main.async { completion(observation) }
        }
    }

    func unbind(_ side: Speaker) {
        registry.unbind(side)
    }

    func windowAtPoint(_ point: CGPoint, for side: Speaker, ignoring: Set<UInt32>,
                       completion: @escaping (WindowID?) -> Void) {
        runExclusively { [registry] in
            let window = registry.windowAtPoint(point, for: side, ignoring: ignoring)
            DispatchQueue.main.async { completion(window) }
        }
    }

    func arrange(_ layout: LayoutChoice, windows: [Speaker: WindowID],
                 completion: @escaping (ArrangeOutcome) -> Void) {
        runExclusively { [registry, arranger, control] in
            var arranged: [ArrangedWindow] = []
            for side in [Speaker.chatgpt, .claude] {
                guard let id = windows[side], let (target, element) = registry.window(side, id),
                      windowIsAlive(element) else {
                    DispatchQueue.main.async { completion(.windowMissing(side)) }
                    return
                }
                arranged.append(ArrangedWindow(side: side, target: target, window: element))
            }
            // A cancel left by the last run's Stop would make the activation
            // inside the arrangement give up at once. No run is on the
            // worker while this is — they share it — so clearing the flags
            // here touches nothing in flight.
            control.reset()
            for window in arranged where electronNudges.beginContact(window.target) { usleep(700_000) }
            let outcome = arranger.apply(layout, to: arranged)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    var canRestoreArrangement: Bool { arranger.canRestore }

    func restoreArrangement(completion: @escaping (Int) -> Void) {
        runExclusively { [arranger, control] in
            control.reset()
            let restored = arranger.restore()
            DispatchQueue.main.async { completion(restored) }
        }
    }

    private func bundleID(_ side: Speaker) -> String {
        side == .chatgpt ? config.chatgptBundleID : config.claudeBundleID
    }

    private func name(_ side: Speaker) -> String {
        side == .chatgpt ? "ChatGPT" : "Claude"
    }

    private func selectors(_ side: Speaker) -> AppSelectors {
        side == .chatgpt ? config.chatgptSelectors : config.claudeSelectors
    }

    // MARK: Plumbing

    /// An app-side line for the log, as the controller would append it:
    /// no timestamp, unlike the engine's own `log`.
    private func report(_ line: String) {
        events.post(.log(line))
    }

    /// Prompting on demand (not at app launch) means the permission dialog
    /// appears while the user is looking at the panel, not out of nowhere.
    private func ensureTrusted() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) { return true }
        report("Accessibility permission missing. Grant Errol in System Settings > Privacy & Security > Accessibility, then try again.")
        return false
    }

    /// Both apps as running processes, for Inspect.
    private func resolveApps() -> (chatgpt: TargetApp, claude: TargetApp)? {
        guard let chatgpt = findApp(bundleID: config.chatgptBundleID, name: "ChatGPT",
                                    selectors: config.chatgptSelectors) else {
            report("ERROR: ChatGPT (\(config.chatgptBundleID)) is not running.")
            return nil
        }
        guard let claude = findApp(bundleID: config.claudeBundleID, name: "Claude",
                                   selectors: config.claudeSelectors) else {
            report("ERROR: Claude Desktop (\(config.claudeBundleID)) is not running.")
            return nil
        }
        return (chatgpt, claude)
    }

    /// Everything that drives the apps goes through one worker, in the
    /// order asked: an arrangement pressed just before Send is finished
    /// before the run touches a window, and a binding is made before the
    /// run that needs it.
    private let worker = EngineWorker()

    private func runExclusively(_ work: @escaping () -> Void) {
        worker.run(work)
    }
}

/// The live elements behind the ids the model holds: each side's windows
/// as the last sweep found them, and the binding the human made. Read on
/// the scanner thread, the engine worker, and the main thread; one lock.
final class WindowRegistry {
    private let lock = NSLock()
    private var windows: [Speaker: [WindowID: AXUIElement]] = [:]
    private var targets: [Speaker: TargetApp] = [:]
    private var bound: [Speaker: BoundDestination] = [:]

    /// A sweep's windows replace the side's earlier ones: an id the app no
    /// longer lists is gone, and a binding keeps its own element.
    func remember(_ side: Speaker, windows found: [AXUIElement], target: TargetApp?) {
        lock.lock()
        windows[side] = Dictionary(found.map { (windowID(of: $0), $0) }, uniquingKeysWith: { first, _ in first })
        targets[side] = target
        lock.unlock()
    }

    func window(_ side: Speaker, _ id: WindowID) -> (TargetApp, AXUIElement)? {
        lock.lock()
        defer { lock.unlock() }
        guard let target = targets[side], let element = windows[side]?[id] else { return nil }
        return (target, element)
    }

    /// Runs on the engine worker. The window server guards against a
    /// different app covering the candidate; AX identifies the exact
    /// registered window, including overlapping windows of the same app.
    func windowAtPoint(_ point: CGPoint, for side: Speaker, ignoring: Set<UInt32>) -> WindowID? {
        lock.lock()
        let target = targets[side]
        lock.unlock()
        guard AXIsProcessTrusted(), let target,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        let regions = info.compactMap { item -> WindowHitRegion? in
            guard let number = item[kCGWindowNumber as String] as? UInt32,
                  let owner = item[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return WindowHitRegion(number: number, owner: owner, frame: frame)
        }
        guard frontmostWindow(at: point, among: regions, ignoring: ignoring)?.owner
                == target.app.processIdentifier else { return nil }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(target.ax, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        let element: AXUIElement
        if axAttribute(hit, kAXRoleAttribute) as? String == kAXWindowRole {
            element = hit
        } else if let value = axAttribute(hit, kAXWindowAttribute),
                  CFGetTypeID(value) == AXUIElementGetTypeID() {
            element = value as! AXUIElement
        } else {
            return nil
        }
        let id = windowID(of: element)
        guard let (_, registered) = window(side, id), CFEqual(registered, element) else { return nil }
        return id
    }

    func bind(_ side: Speaker, _ binding: BoundDestination) {
        lock.lock()
        bound[side] = binding
        lock.unlock()
    }

    func unbind(_ side: Speaker) {
        lock.lock()
        bound[side] = nil
        lock.unlock()
    }

    func binding(_ side: Speaker) -> BoundDestination? {
        lock.lock()
        defer { lock.unlock() }
        return bound[side]
    }

    var bindings: [Speaker: BoundDestination] {
        lock.lock()
        defer { lock.unlock() }
        return bound
    }
}

/// One long-lived thread taking jobs in order. Not a dispatch queue: those
/// give their workers a stack too small for the deep AX tree walks, and
/// parking a dispatch worker on a semaphore while a bigger-stacked thread
/// does the job is the priority inversion the thread checker flags. The
/// thread parks on a condition between jobs, so an idle engine costs
/// nothing.
private final class EngineWorker {
    private let condition = NSCondition()
    private var jobs: [() -> Void] = []
    private var started = false

    func run(_ job: @escaping () -> Void) {
        condition.lock()
        jobs.append(job)
        let first = !started
        started = true
        condition.signal()
        condition.unlock()
        guard first else { return }
        let thread = Thread { [self] in loop() }
        thread.name = "RelayEngine"
        thread.stackSize = 4 << 20
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    private func loop() {
        while true {
            condition.lock()
            while jobs.isEmpty { condition.wait() }
            let job = jobs.removeFirst()
            condition.unlock()
            job()
        }
    }
}
