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
    /// Start the run, with the settings config holds (seed, turns, first
    /// speaker), on the engine's own worker. It ends with `.finished` on
    /// the event stream, after every line it logged. Called after a
    /// preflight that passed.
    func startRun(tileWindows: Bool)
    /// The debug dump of both apps' windows, buttons, and selector matches
    /// into the log. Does its own preflight.
    func inspect()
    /// Open the last run's transcript, or say there is none.
    func openTranscript()
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
        guard ensureTrusted() else { return false }
        apps = resolveApps()
        return apps != nil
    }

    func startRun(tileWindows: Bool) {
        guard let apps else {
            report("Start skipped: the apps were not resolved.")
            events.post(.finished)
            return
        }
        // Clear a stale cancel or pause — or a note that never found its
        // handoff — before the worker can read any of them.
        control.reset()
        let origin = currentFrontmostApp()
        log("Run starting. Transcript: \(config.transcriptPath)")
        runOnWorkerThread { [events] in
            // First contact only: the scanner has usually nudged both long
            // ago, and then the trees are already populated and the settle
            // wait would just delay the run.
            let freshChatgpt = electronNudges.beginContact(apps.chatgpt)
            let freshClaude = electronNudges.beginContact(apps.claude)
            if freshChatgpt || freshClaude { usleep(700_000) }
            if tileWindows { arrangeSideBySide(left: apps.chatgpt, right: apps.claude) }
            _ = runRelay(chatgpt: apps.chatgpt, claude: apps.claude)
            refocus(to: origin)
            events.post(.finished)
        }
    }

    func inspect() {
        guard ensureTrusted(), let apps = resolveApps() else { return }
        report("Inspecting both apps...")
        runOnWorkerThread { [events] in
            let freshChatgpt = electronNudges.beginContact(apps.chatgpt)
            let freshClaude = electronNudges.beginContact(apps.claude)
            if freshChatgpt || freshClaude { usleep(700_000) }
            let report = inspectReport(apps.chatgpt) + "\n\n" + inspectReport(apps.claude)
            events.post(.log(report))
        }
    }

    func openTranscript() {
        let url = URL(fileURLWithPath: config.transcriptPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            report("No transcript yet at \(config.transcriptPath).")
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

    private func resolveApps() -> (chatgpt: TargetApp, claude: TargetApp)? {
        guard let chatgpt = findApp(bundleID: config.chatgptBundleID, name: "Codex",
                                    selectors: config.chatgptSelectors) else {
            report("ERROR: Codex/ChatGPT (\(config.chatgptBundleID)) is not running. Launch it with a conversation open.")
            return nil
        }
        guard let claude = findApp(bundleID: config.claudeBundleID, name: "Claude",
                                   selectors: config.claudeSelectors) else {
            report("ERROR: Claude Desktop (\(config.claudeBundleID)) is not running. Launch it with a conversation open.")
            return nil
        }
        return (chatgpt, claude)
    }

    /// The deep AX tree walks need more stack than the default worker thread
    /// provides.
    private func runOnWorkerThread(_ work: @escaping () -> Void) {
        let worker = Thread(block: work)
        worker.stackSize = 4 << 20
        worker.start()
    }
}
