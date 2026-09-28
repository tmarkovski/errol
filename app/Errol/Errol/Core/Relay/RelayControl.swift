// The app's inward channel to a run in flight: cancel and pause flags,
// focus-operation ownership and the steering mailbox, under one lock.

import Foundation

/// The worker's verdict at a handoff boundary, reached under RelayControl's
/// lock in the same step as the mailbox: hold, end, or go — and if go, with
/// whatever note the mailbox held at that instant.
enum HandoffDecision: Equatable {
    case hold
    case cancel
    /// The handoff goes ahead. `note` rides it whole. `unfit` is a note
    /// taken off the mailbox because it could not travel whole; it is
    /// reported not sent rather than trimmed.
    case commit(note: String?, unfit: String?)
}

enum HoldGrant: Equatable { case now, afterOperation, cancelled }
enum OperationDecision: Equatable { case proceed, hold, cancel }
enum FocusOperation: Equatable { case capture, delivery }

/// The app's inward channel to a run in flight: the cancel and pause flags
/// the relay's wait loops poll — so a run can end or hold without killing
/// the process — and the steering-note mailbox. Set from the main thread,
/// read on the relay worker; one lock covers the lot.
// Every stored value is protected by lock, including operation ownership.
final class RelayControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var paused = false
    /// The steering mailbox: one slot. The console's path in is
    /// finishSteering(note:), which sets the slot and lifts the hold in one
    /// step; the worker takes the note at the next handoff boundary — it
    /// rides to the side about to reply and is echoed to the other side a
    /// turn later. Setting it is a set, never an append.
    private var note: String?
    private var operation: FocusOperation?
    private var pendingEditor = false
    private var finished = false

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() {
        lock.lock()
        cancelled = true
        pendingEditor = false
        lock.unlock()
    }

    /// Both capture and delivery wait while the steering editor owns focus.
    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }

    var hasFocusOperation: Bool { lock.lock(); defer { lock.unlock() }; return operation != nil }
    var canOpenSteering: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused && operation == nil && !cancelled && !finished
    }

    func requestHold() -> HoldGrant {
        lock.lock()
        defer { lock.unlock() }
        return requestHoldLocked()
    }

    private func requestHoldLocked() -> HoldGrant {
        guard !cancelled, !finished else { return .cancelled }
        paused = true
        pendingEditor = operation != nil
        return pendingEditor ? .afterOperation : .now
    }

    /// Used for capture and the opener. Neither consumes the note mailbox.
    func beginOperation(_ kind: FocusOperation) -> OperationDecision {
        lock.lock()
        defer { lock.unlock() }
        if cancelled || finished { return .cancel }
        if paused || operation != nil { return .hold }
        operation = kind
        return .proceed
    }

    /// The app calls this inside its synchronous main-queue completion fence.
    /// Keep the hold set when granting, so the next operation cannot race the
    /// controller's receipt of steeringGranted.
    func endOperation(continuingRun: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        precondition(operation != nil, "No focus operation to end")
        operation = nil
        if !continuingRun { finished = true }
        let grant = pendingEditor && !cancelled && !finished
        pendingEditor = false
        return grant
    }

    /// Seal terminal paths before the finished event reaches the controller.
    /// Preserve the hold for the end-of-run focus restoration decision.
    func finishRun() {
        lock.lock()
        defer { lock.unlock() }
        precondition(operation == nil, "Finish the focus operation first")
        finished = true
        pendingEditor = false
    }

    /// The editor must stop accepting input before the controller calls this.
    func finishSteering(note text: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, !finished else { return }
        note = text
        paused = false
        pendingEditor = false
    }

    /// Test seam: queue a note without the hold/finish handshake; a second
    /// post replaces the first.
    func postSteering(_ text: String) { lock.lock(); note = text; lock.unlock() }

    /// Withdraw the queued note. nil when the slot is empty — including
    /// when the worker has already committed the note to a handoff, in
    /// which case the withdrawal lost the race and the note is on its way.
    func takeSteering() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let taken = note
        note = nil
        return taken
    }

    /// Test seam: whether a note is waiting for its handoff.
    var hasSteering: Bool { lock.lock(); defer { lock.unlock() }; return note != nil }

    /// Claim the note and ask for editor ownership together. A lost claim
    /// still holds the next operation, opening a new, empty note after send.
    func claimSteering() -> (note: String?, grant: HoldGrant) {
        lock.lock()
        defer { lock.unlock() }
        let grant = requestHoldLocked()
        guard grant != .cancelled else { return (nil, grant) }
        let claimed = note
        note = nil
        return (claimed, grant)
    }

    /// The worker's one decision at a handoff boundary. It reads the cancel
    /// and pause flags and, when the handoff goes ahead, takes the note in
    /// the same locked step: checking the pause and then taking the note
    /// separately left a gap in which a claim from the panel could win the
    /// mailbox and still lose the handoff. `carries` says whether a note
    /// can travel whole with this handoff; one that cannot is taken off the
    /// mailbox and returned as `unfit`, because a note that long has no
    /// handoff that carries it, and leaving it would only report the same
    /// failure at the next one.
    func decideHandoff(carries: (String) -> Bool) -> HandoffDecision {
        lock.lock()
        defer { lock.unlock() }
        if cancelled || finished { return .cancel }
        if paused || operation != nil { return .hold }
        operation = .delivery
        guard let pending = note else { return .commit(note: nil, unfit: nil) }
        note = nil
        return carries(pending)
            ? .commit(note: pending, unfit: nil)
            : .commit(note: nil, unfit: pending)
    }

    /// Run start: clear everything, so a stale cancel or pause — or a note
    /// that never found its handoff — cannot leak into the new run.
    func reset() {
        lock.lock()
        cancelled = false
        paused = false
        note = nil
        operation = nil
        pendingEditor = false
        finished = false
        lock.unlock()
    }
}

let relayControl = RelayControl()

/// Drain the operation's queued main-thread focus work before releasing its
/// ownership. The live worker waits here; the main thread must never join it.
/// Main-thread preview/test callers can complete directly.
func completeFocusOperation(control: RelayControl, events: RelayEventBus,
                            continuingRun: Bool) {
    let complete = {
        if control.endOperation(continuingRun: continuingRun) {
            events.post(.steeringGranted)
        }
    }
    if Thread.isMainThread { complete() }
    else { DispatchQueue.main.sync(execute: complete) }
}
