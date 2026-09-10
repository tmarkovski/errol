// The seam between the panel's model and the machinery that drives the
// apps. RelayController owns what the panel shows; an engine owns
// everything that reaches outside the process — the Accessibility
// permission, the two apps, the readiness sweeps, the relay worker — and
// reports back over its event stream. The app runs LiveRelayEngine. The
// canvases run PerchPreviewEngine (Perch/PerchPreviewEngine.swift), which
// plays a run without touching any app, so a preview's Start starts
// something and its Stop stops it while nothing is relayed anywhere.

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
    /// Readiness sweeps report here, on whatever thread the sweep ran.
    var onReadiness: ((SideStatus, SideStatus) -> Void)? { get set }
    /// Whether to sweep at all: only while someone can see the strip, and
    /// never while a run owns the apps.
    func setScanning(_ scanning: Bool)
    /// Whether a run can start now: the permission is granted and both
    /// apps are up. What is missing is said on the event stream as log
    /// lines. May prompt (the Accessibility dialog), which is why it is
    /// asked at Start and not at launch.
    func preflight() -> Bool
    /// Tile the chat windows now — ChatGPT left, Claude right — or put
    /// them back where they were: the Tile chip's press, done at once
    /// rather than at Start, so the layout is settled before the run and
    /// the console can be set beside it. Answered with `.arranged` on the
    /// event stream once the windows have moved.
    func setTiling(_ tiled: Bool)
    /// Start the run, with the settings config holds (seed, turns, first
    /// speaker), on the engine's own worker. It ends with `.finished` on
    /// the event stream, after every line it logged. Called after a
    /// preflight that passed.
    func startRun()
    /// The debug dump of both apps' windows, buttons, and selector matches
    /// into the log. Does its own preflight.
    func inspect()
}

/// The engine the app runs: the relay over Accessibility on a worker
/// thread, reporting on the process-wide bus the Core functions log to,
/// steered through the process-wide control the relay loop polls.
final class LiveRelayEngine: RelayEngine {
    let events = relayEvents
    let control = relayControl
    var onReadiness: ((SideStatus, SideStatus) -> Void)? {
        get { scanner.onUpdate }
        set { scanner.onUpdate = newValue }
    }
    private let scanner = ReadinessScanner()
    /// What preflight found, for the run that follows it.
    private var apps: (chatgpt: TargetApp, claude: TargetApp)?

    func setScanning(_ scanning: Bool) {
        scanner.setActive(scanning)
    }

    func preflight() -> Bool {
        guard ensureTrusted() else {
            failStart("Accessibility permission missing. Grant Errol in System Settings > Privacy & Security > Accessibility, then Run again.")
            return false
        }
        apps = resolveApps(reportingStart: true)
        return apps != nil
    }

    /// A start that never reached the worker still ends with a report, so
    /// the panel shows the reason where the run would have been.
    private func failStart(_ reason: String) {
        events.post(.ended(RunReport(outcome: .failedStart(reason: reason))))
    }

    func setTiling(_ tiled: Bool) {
        guard ensureTrusted(), let apps = resolveApps() else {
            events.post(.arranged(tiled: false))
            return
        }
        runExclusively { [events, control] in
            // A cancel left by the last run's End session would make the
            // activation inside the tiling give up at once. No run is on
            // the worker while this is — they share it — so clearing the
            // flags here touches nothing in flight.
            control.reset()
            let freshChatgpt = electronNudges.beginContact(apps.chatgpt)
            let freshClaude = electronNudges.beginContact(apps.claude)
            if freshChatgpt || freshClaude { usleep(700_000) }
            if tiled {
                events.post(.arranged(tiled: arrangeSideBySide(left: apps.chatgpt, right: apps.claude)))
            } else {
                unarrange([apps.chatgpt, apps.claude])
                events.post(.arranged(tiled: false))
            }
        }
    }

    func startRun() {
        guard let apps else {
            report("Start skipped: the apps were not resolved.")
            failStart("The apps were not resolved. Press Run again.")
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
            let freshChatgpt = electronNudges.beginContact(apps.chatgpt)
            let freshClaude = electronNudges.beginContact(apps.claude)
            if freshChatgpt || freshClaude { usleep(700_000) }
            _ = runRelay(chatgpt: apps.chatgpt, claude: apps.claude, showTransfers: true) { continuing in
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

    /// Both apps as running processes. `reportingStart` is the preflight
    /// before a run, whose failure is the run's report; tiling and Inspect
    /// resolve the apps too and only log what is missing.
    private func resolveApps(reportingStart: Bool = false) -> (chatgpt: TargetApp, claude: TargetApp)? {
        guard let chatgpt = findApp(bundleID: config.chatgptBundleID, name: "Codex",
                                    selectors: config.chatgptSelectors) else {
            report("ERROR: Codex/ChatGPT (\(config.chatgptBundleID)) is not running. Launch it with a conversation open.")
            if reportingStart { failStart("ChatGPT is not running. Launch it with a conversation open, then Run again.") }
            return nil
        }
        guard let claude = findApp(bundleID: config.claudeBundleID, name: "Claude",
                                   selectors: config.claudeSelectors) else {
            report("ERROR: Claude Desktop (\(config.claudeBundleID)) is not running. Launch it with a conversation open.")
            if reportingStart { failStart("Claude is not running. Launch it with a conversation open, then Run again.") }
            return nil
        }
        return (chatgpt, claude)
    }

    /// Everything that drives the apps goes through one worker, in the
    /// order asked: a tiling pressed just before Start is finished before
    /// the run touches a window, and a quick on–off on the chip cannot
    /// tile and restore at once.
    private let worker = EngineWorker()

    private func runExclusively(_ work: @escaping () -> Void) {
        worker.run(work)
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
