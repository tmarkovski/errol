// The engine the app runs, behind the seam in RelayEngine.swift:
// LiveRelayEngine, the registry of the windows its sweeps found and the
// sides' bindings, and the worker thread its runs and setup jobs go to.

import AppKit
import ApplicationServices
import Foundation

/// The engine the app runs: the relay over Accessibility on a worker
/// thread, reporting on the process-wide bus the Core functions log to,
/// steered through the process-wide control the relay loop polls.
final class LiveRelayEngine: RelayEngine {
    let events = relayEvents
    let control = relayControl
    let transcriber: VoiceTranscriber = SpeechAnalyzerTranscriber()
    var onReadiness: ((ReadinessReport) -> Void)? {
        get { scanner.onUpdate }
        set { scanner.onUpdate = newValue }
    }
    private let scanner: ReadinessScanner
    /// The windows the sweeps found and the sides' bindings, by id.
    private let registry: WindowRegistry
    private let arranger = WindowArranger()

    init() {
        // The registry is a local first, so the sweep closure captures it
        // without reading self before every property is set.
        let registry = WindowRegistry()
        self.registry = registry
        scanner = ReadinessScanner(sweep: { Self.sweep(registry: registry) })
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
    /// conversation checked the way the run's preflight will check it —
    /// reusing this sweep's scan of the bound window for its Stop button
    /// and covering dialog, and walking it afresh only when the app no
    /// longer lists it among its windows.
    private static func sweep(registry: WindowRegistry) -> ReadinessReport {
        let installed = Dictionary(uniqueKeysWithValues: Speaker.allCases.map {
            ($0, isInstalled(config.bundleID(for: $0)))
        })
        guard AXIsProcessTrusted() else { return .blocked(installed: installed) }
        let chatgpt = sweepSide(.chatgpt)
        let claude = sweepSide(.claude)
        var report = ReadinessReport(chatgpt: chatgpt.status, claude: claude.status, installed: installed)
        for (side, sweep) in [(Speaker.chatgpt, chatgpt), (.claude, claude)] {
            registry.remember(side, windows: sweep.windows, target: sweep.target)
            report.candidates[side] = windowCandidates(from: sweep, selectors: config.selectors(for: side))
            if let binding = registry.binding(side) {
                let check = binding.check()
                var composer = ComposerState.unreadable
                if check == .same {
                    if let i = sweep.windows.firstIndex(where: { CFEqual($0, binding.window) }) {
                        composer = composerState(in: binding.target, scan: sweep.scans[i])
                    } else {
                        composer = composerState(in: binding.target)
                    }
                }
                report.bindings[side] = BindingObservation(
                    window: windowID(of: binding.window), check: check, identity: binding.identity,
                    composer: composer)
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
            failStart("Errol isn\u{2019}t turned on in \(AccessPermission.settingsPath). Turn it on, then send again.")
            return false
        }
        let bindings = registry.bindings
        for side in Speaker.allCases where bindings[side] == nil {
            failStart("Connect \(side.appName)'s conversation first.")
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
            electronNudges.settleFirstContact([chatgpt.target, claude.target])
            _ = runRelay(chatgpt: chatgpt.target, claude: claude.target,
                         bindings: [.chatgpt: chatgpt, .claude: claude],
                         showTransfers: true) { continuing in
                completeFocusOperation(control: control, events: events, continuingRun: continuing)
            }
            // The file closes before `.finished` is posted, because
            // `.finished` is what lets the controller allow the next Start,
            // whose RunLog.begin() this end() must not be able to close.
            RunLog.end()
            // Focus is the controller's to settle on `.finished`: the
            // console takes the keyboard back from whichever chat app
            // replied last (RelayController.finishRun).
            events.post(.finished)
        }
    }

    #if DEBUG
    func inspect() {
        guard ensureTrusted(), let apps = resolveApps() else { return }
        report("Inspecting both apps...")
        runExclusively { [events] in
            electronNudges.settleFirstContact(apps)
            let report = apps.map(inspectReport).joined(separator: "\n\n")
            events.post(.log(report))
        }
    }
    #endif

    // MARK: Setup

    func launch(_ side: Speaker) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.bundleID(for: side)) else {
            return false
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { log("\(side.appName): could not be opened: \(error.localizedDescription)") }
        }
        // The scanner also hears the launch itself (didLaunchApplication),
        // and sweeps again when the windows appear.
        return true
    }

    func bringForward(_ side: Speaker, completion: @escaping () -> Void) {
        // A held relay occupies the ordinary worker. The controller keeps
        // its hold until this action returns (Resume and Start are gated).
        // Recheck on the worker: a stopped/finished hold must do nothing.
        let duringHold = control.canOpenSteering
        let work = { [self, registry] in
            defer { DispatchQueue.main.async(execute: completion) }
            if duringHold && !control.canOpenSteering { return }
            guard let target = findApp(side) else { return }
            // The bound window comes to the front of its app's own windows
            // first: activation alone leaves whichever window was last up.
            if let bound = registry.binding(side), windowIsAlive(bound.window) { raiseWindow(bound.window) }
            let pid = target.app.processIdentifier
            if frontWindowOwnerPID() != pid {
                // LaunchServices activation is the one that lands from a
                // background process (Activation.swift). The wait is for
                // the window server to show the app in front — a Space
                // switch, an unhide — and is bounded.
                activateViaLaunchServices(target)
                let deadline = Date().addingTimeInterval(2)
                while frontWindowOwnerPID() != pid, Date() < deadline { usleep(100_000) }
            }
        }
        if duringHold { heldWindowWorker.run(work) } else { runExclusively(work) }
    }

    func bind(_ side: Speaker, to window: WindowID, completion: @escaping (BindingObservation?) -> Void) {
        runExclusively { [registry] in
            guard let (target, element) = registry.window(side, window), windowIsAlive(element) else {
                log("\(side.appName): the chosen window is gone before it could be connected")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let binding = BoundDestination(target: target, window: element)
            registry.bind(side, binding)
            log(binding.bindingReport)
            let observation = BindingObservation(window: window, check: .same, identity: binding.identity,
                                                 composer: composerState(in: binding.target))
            DispatchQueue.main.async { completion(observation) }
        }
    }

    func unbind(_ side: Speaker) {
        registry.unbind(side)
    }

    func arrange(_ layout: LayoutChoice, windows: [Speaker: WindowID],
                 completion: @escaping (ArrangeOutcome) -> Void) {
        runExclusively { [registry, arranger, control] in
            var arranged: [ArrangedWindow] = []
            for side in Speaker.allCases {
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
            electronNudges.settleFirstContact(arranged.map(\.target))
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
        report("Errol isn\u{2019}t turned on in \(AccessPermission.settingsPath). Turn it on, then try again.")
        return false
    }

    #if DEBUG
    /// Both apps as running processes, for Inspect, in `Speaker.allCases`
    /// order, ChatGPT first.
    private func resolveApps() -> [TargetApp]? {
        var apps: [TargetApp] = []
        for side in Speaker.allCases {
            guard let target = findApp(side) else {
                report("ERROR: \(side.appName) (\(config.bundleID(for: side))) is not running.")
                return nil
            }
            apps.append(target)
        }
        return apps
    }
    #endif

    /// Relay and setup jobs go through one worker, in the
    /// order asked: an arrangement pressed just before Send is finished
    /// before the run touches a window, and a binding is made before the
    /// run that needs it.
    private let worker = EngineWorker()
    /// Only Show window during a granted steering hold uses this worker.
    /// The relay worker is parked, the hold remains set, and the controller
    /// blocks Resume/Start until activation's completion reaches the main thread.
    private let heldWindowWorker = EngineWorker()

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
