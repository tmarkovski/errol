// App discovery: resolving a running chat app into an AX handle.

import AppKit
import ApplicationServices

struct TargetApp {
    let name: String
    let app: NSRunningApplication
    let ax: AXUIElement
    let selectors: AppSelectors
    /// The one window every finder is scoped to once the human has chosen
    /// it in setup, or a run has bound it: `chatWindow(in:)` answers with
    /// this window and never with another in its place, so a paste cannot
    /// be handed to a window the human did not pick (docs/design-proposals/
    /// setup-interaction/SPEC.md). nil until then, when the finders pick a
    /// window the way the readiness sweep does.
    var boundWindow: AXUIElement? = nil

    /// The same app, with every finder scoped to `window`.
    func bound(to window: AXUIElement) -> TargetApp {
        var copy = self
        copy.boundWindow = window
        return copy
    }
}

func findApp(bundleID: String, name: String, selectors: AppSelectors) -> TargetApp? {
    guard let running = NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == bundleID }) else { return nil }
    let ax = AXUIElementCreateApplication(running.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, 3.0)
    return TargetApp(name: name, app: running, ax: ax, selectors: selectors)
}

/// `side`'s app, found by the bundle ID and selectors of the global `config`
/// as it stands at the call, so a config the harness swapped in is the one
/// searched, and named as the human reads it.
func findApp(_ side: Speaker) -> TargetApp? {
    findApp(bundleID: config.bundleID(for: side), name: side.appName, selectors: config.selectors(for: side))
}

/// Electron apps expose an empty AX tree until nudged. This is the raw
/// setter; the app's repeated contacts go through `electronNudges`, which
/// sends it once per process.
func enableElectronAccessibility(_ target: TargetApp) {
    AXUIElementSetAttributeValue(target.ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(target.ax, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
}

/// Once-per-process bookkeeping for the Electron nudge. Re-sending the
/// attributes every sweep is churn Chromium reacts badly to, and it races
/// the window arranger, which drops AXEnhancedUserInterface around its
/// moves and restores it after. So each process is nudged once, with a
/// single recovery re-nudge banked for a nudged app stuck at zero windows
/// — a failed restore or a dropped flag looks exactly like that. The retry
/// re-banks on app lifecycle events or on windows actually appearing,
/// never on the empty sweeps themselves, so an app legitimately running
/// with no windows open cannot re-create the churn.
/// Thread-safe: the scanner and the relay worker both come through here.
final class ElectronNudges {
    private let lock = NSLock()
    private var nudged = Set<pid_t>()
    private var recoveryBanked = Set<pid_t>()
    private var emptySweeps = [pid_t: Int]()

    /// Nudge on first contact with this process. True when the attributes
    /// were just sent — the tree needs time to populate before reading.
    func beginContact(_ target: TargetApp) -> Bool {
        let pid = target.app.processIdentifier
        lock.lock()
        let first = nudged.insert(pid).inserted
        if first { recoveryBanked.insert(pid) }
        lock.unlock()
        if first { enableElectronAccessibility(target) }
        return first
    }

    /// A nudged process showed an empty window list. The second consecutive
    /// empty sweep spends the banked recovery re-nudge; true means it was
    /// just sent and the caller should settle and rescan.
    func recordEmptySweep(_ target: TargetApp) -> Bool {
        let pid = target.app.processIdentifier
        lock.lock()
        let streak = (emptySweeps[pid] ?? 0) + 1
        emptySweeps[pid] = streak
        let renudge = streak >= 2 && recoveryBanked.remove(pid) != nil
        if renudge { emptySweeps[pid] = 0 }
        lock.unlock()
        if renudge { enableElectronAccessibility(target) }
        return renudge
    }

    /// Nudge every target on first contact, then give the trees one shared
    /// settle wait if any of them was fresh, so two fresh apps populate
    /// side by side rather than one wait after the other.
    func settleFirstContact(_ targets: [TargetApp]) {
        // An eager map, not a short-circuiting contains(where:): every
        // target is nudged.
        let fresh = targets.map(beginContact).contains(true)
        if fresh { usleep(700_000) }
    }

    /// Windows exist: clear the empty streak and re-bank the recovery retry.
    func recordWindowsSeen(_ target: TargetApp) {
        let pid = target.app.processIdentifier
        lock.lock()
        emptySweeps[pid] = 0
        recoveryBanked.insert(pid)
        lock.unlock()
    }

    /// Launch or activation of an already-nudged process re-banks the retry.
    func replenish(_ pid: pid_t) {
        lock.lock()
        if nudged.contains(pid) { recoveryBanked.insert(pid) }
        lock.unlock()
    }

    /// Termination: drop the pid so a relaunch counts as first contact.
    func forget(_ pid: pid_t) {
        lock.lock()
        nudged.remove(pid)
        recoveryBanked.remove(pid)
        emptySweeps[pid] = nil
        lock.unlock()
    }
}

let electronNudges = ElectronNudges()
