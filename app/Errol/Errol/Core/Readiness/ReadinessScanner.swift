// The scanner thread that repeats the readiness sweep, and the AXObserver
// wake hints that make it prompt: app-lifetime machinery with threading
// rules of its own, kept apart from the sweep it runs.

import AppKit
import ApplicationServices
import Foundation

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
    /// Called on the worker thread after each sweep. Set once before the
    /// first setActive(true); Thread.start publishes it to the worker,
    /// which reads it without the lock.
    var onUpdate: ((ReadinessReport) -> Void)?
    /// The sweep itself, run on the worker thread: the engine supplies one
    /// that also refreshes its window registry and checks its bindings.
    let sweep: () -> ReadinessReport

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

    init(sweep: @escaping () -> ReadinessReport) {
        self.sweep = sweep
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
