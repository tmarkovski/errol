// Waiting for the reply to a send: the baseline taken before it, the signals
// that say a response arrived, and the wait for it to finish writing.

import Foundation

/// The pre-send snapshot a response is detected against. Two independent
/// signals, because neither is universal: the affordance count works on every
/// surface but stops growing once Claude's virtualized message list starts
/// unmounting older messages (observed live Aug 28 2026: baseline 7, then 3
/// with the response on screen — the stuck-relay bug), and the message
/// ordinal survives virtualization but only exists where messages are
/// numbered (Claude).
struct ResponseBaseline {
    /// Countable message affordances (copy buttons + collapsed-bar toggles).
    var affordances: Int
    /// The newest message's "Message N" ordinal, nil where unnumbered.
    var lastOrdinal: Int?
}

/// Both signals from one walk of the window (conversationSighting). A
/// window gone reads as empty, as the separate finders read it.
func responseBaseline(in target: TargetApp) -> ResponseBaseline {
    let seen = conversationSighting(in: target) ?? ConversationSighting()
    return ResponseBaseline(affordances: seen.affordances, lastOrdinal: seen.lastOrdinal)
}

/// One poll of the responding side, as waitForResponse sees it.
struct ResponseSighting: Equatable {
    var affordances: Int
    var lastOrdinal: Int?
    var streaming: Bool
}

extension ResponseSighting {
    /// The poll's part of a walk of the window that also answered the
    /// cover check.
    init(_ seen: ConversationSighting) {
        self.init(affordances: seen.affordances, lastOrdinal: seen.lastOrdinal,
                  streaming: seen.streaming)
    }
}

/// The completion verdict for one poll — pure, so the tests can drive it
/// through the failure shapes (the fixture suite replays the virtualized
/// tree that hung the relay). A response has arrived when nothing is
/// streaming and any signal says so:
/// - the affordance count rose past the baseline (the fast path, and the
///   only count-based signal that is safe: equality can mean virtualization
///   swallowed a message);
/// - the newest message's ordinal advanced past the baseline by enough to be
///   the response — past the echo too on surfaces where the sent message
///   mounts as its own numbered message (echoCountsAsAffordance);
/// - streaming was observed and has ended: the response the stop button
///   belonged to is complete, whatever the counters claim. Ordered last so
///   the precise signals answer first in the tests.
func responseArrived(_ now: ResponseSighting, since baseline: ResponseBaseline,
                     sawStreaming: Bool, selectors: AppSelectors) -> Bool {
    guard !now.streaming else { return false }
    if now.affordances > baseline.affordances { return true }
    if let base = baseline.lastOrdinal, let ordinal = now.lastOrdinal,
       ordinal >= base + (selectors.echoCountsAsAffordance ? 2 : 1) { return true }
    return sawStreaming
}

/// Whether something was said in the conversation since the reply the
/// wait completed on — the capture gate's question (captureGuard), asked
/// once a second until the reply is copied, through any pause. Pure, so
/// the tests can replay the sightings that fooled it.
///
/// The ordinal is the evidence where the completing sighting read one:
/// a newest message numbered past it is a message since. Where it read
/// none, an ordinal surfacing later says nothing — it is the same reply
/// in a list rendered differently — and only the affordance count can
/// speak, and only a rise past the highest count the wait knew, the
/// pre-send baseline or the completing sighting. Claude's virtualized
/// list mounts and unmounts older messages as it scrolls and re-renders,
/// so a count that fell during the wait and climbs back is the same
/// messages, not new ones. Observed Sep 22 2026: the wait read no
/// ordinal at all and 12 affordances at completion; held at the gate
/// through a pause, the list read 2 affordances and "Message 16", and
/// the guard took 16 against nothing as history moving on, for good.
func conversationMovedOn(_ now: ResponseSighting, since expected: ResponseSighting,
                         baseline: ResponseBaseline) -> Bool {
    if let known = expected.lastOrdinal, let ordinal = now.lastOrdinal { return ordinal > known }
    return now.affordances > max(expected.affordances, baseline.affordances + 1)
}

/// Response polling state, with monotonic timestamps supplied by the
/// caller. The timeout bounds inactivity, not total generation time.
struct ResponseWaitState {
    enum Result: Equatable { case waiting, complete, timedOut }

    private let timeout: TimeInterval
    private var lastActivity: TimeInterval
    private var stableTicks = 0
    private(set) var sawStreaming = false
    private var suspendedAt: TimeInterval?

    init(timeout: TimeInterval, startedAt: TimeInterval) {
        self.timeout = timeout
        lastActivity = startedAt
    }

    /// Whether observation is suspended (`suspend`), the conversation
    /// being out of view.
    var isSuspended: Bool { suspendedAt != nil }

    /// Stop the inactivity clock: the window is showing something other
    /// than the conversation being waited on, so nothing seen means
    /// nothing — the poll just before the hold included, which may have
    /// been taken as a dialog was opening over the conversation and seen
    /// it gone, Stop button and all. So the confirming pair starts over:
    /// completion needs two polls of the conversation after the hold.
    /// Idempotent.
    mutating func suspend(at now: TimeInterval) {
        if suspendedAt == nil { suspendedAt = now }
        stableTicks = 0
    }

    /// The conversation is back: the time it was out of view is taken off
    /// the inactivity clock, so a hold never becomes a timeout. Idempotent.
    mutating func resume(at now: TimeInterval) {
        guard let since = suspendedAt else { return }
        lastActivity += max(0, now - since)
        suspendedAt = nil
    }

    mutating func observe(_ sighting: ResponseSighting, since baseline: ResponseBaseline,
                          selectors: AppSelectors, at now: TimeInterval) -> Result {
        if sighting.streaming {
            sawStreaming = true
            lastActivity = now
        }
        if responseArrived(sighting, since: baseline, sawStreaming: sawStreaming,
                           selectors: selectors) {
            stableTicks += 1
            // Give a reply first seen at the deadline its confirming poll.
            return stableTicks >= 2 ? .complete : .waiting
        }
        stableTicks = 0
        return now - lastActivity >= timeout ? .timedOut : .waiting
    }
}

/// Where the just-pasted user message's own affordance registers in the
/// count (Claude), a raw "count went up" check would fire on that echo, so
/// wait for it to render and fold it into the baseline; only affordances
/// beyond it can belong to the response. The echo also confirms by ordinal —
/// the pasted message mounts as its own numbered message — which is the only
/// signal left when the virtualized list unmounts an older message in the
/// same breath and the count never moves. Where the echo cannot register
/// (ChatGPT — see echoCountsAsAffordance), skip the wait: any rise it saw
/// would be the response itself, and folding that in leaves the relay
/// waiting forever (the Codex-mode fast-reply race, observed Aug 27 2026).
/// The baseline ordinal deliberately stays pre-send: responseArrived expects
/// the echo-inclusive delta. Each look is one walk of the window for both
/// signals (conversationSighting).
func absorbEchoIntoBaseline(in target: TargetApp, preSend: ResponseBaseline) -> ResponseBaseline {
    guard target.selectors.echoCountsAsAffordance else { return preSend }
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline {
        let seen = conversationSighting(in: target) ?? ConversationSighting()
        let echoSeen = seen.affordances > preSend.affordances
            || preSend.lastOrdinal.map { base in
                (seen.lastOrdinal ?? base) > base
            } ?? false
        if echoSeen {
            return ResponseBaseline(affordances: preSend.affordances + 1,
                                    lastOrdinal: preSend.lastOrdinal)
        }
        usleep(100_000)
    }
    return preSend
}

/// The wait's verdict. A completed reply's sighting travels with it, so
/// the capture that follows can tell that reply from anything said since.
enum ResponseWait: Equatable {
    case complete(ResponseSighting)
    case timedOut
    /// Cancelled, vetoed by `mayContinue`, or the destination is gone.
    case ended
}

/// `blocked` is the run's guard, asked before every poll: the block the
/// run stands on, or none with the sighting the guard took of the window
/// on the way — its cover check reads the whole conversation in the walk
/// that looks for a composer (conversationSighting), so the poll uses that
/// reading rather than walking the window again. With no guard, or one
/// that hands back no sighting, the wait reads the window itself.
func waitForResponse(in target: TargetApp, baseline: ResponseBaseline,
                     mayContinue: () -> Bool = { true },
                     blocked: (() -> (block: RunBlock?, sighting: ConversationSighting?))? = nil,
                     onBlock: ((RunBlock?) -> Void)? = nil,
                     onPoll: ((ResponseSighting) -> Void)? = nil) -> ResponseWait {
    log("\(target.name): waiting for response (baseline \(baseline.affordances) message affordances"
        + (baseline.lastOrdinal.map { ", message \($0)" } ?? "") + ")...")
    let timeout = config.timeout
    let startedAt = ProcessInfo.processInfo.systemUptime
    var wait = ResponseWaitState(timeout: timeout, startedAt: startedAt)
    var lastSeen = ""
    var block: RunBlock?
    while true {
        if relayControl.isCancelled || !mayContinue() { return .ended }
        // While the window shows another conversation, what it shows is
        // not evidence about this one: no sighting is taken, and the time
        // does not count against the reply. The baseline is kept, so a
        // reply that completed out of view is seen on return.
        var guardSighting: ConversationSighting?
        if let blocked {
            let (now, sighted) = blocked()
            // A Stop, or a destination found gone by this very check, ends
            // the wait where it stands: the block is left for the run's
            // report to name, as the gate leaves it, nothing is said to have
            // resumed, and no sighting is taken of a window that is gone.
            if relayControl.isCancelled || !mayContinue() { return .ended }
            if now != block {
                onBlock?(now)
                block = now
            }
            if now != nil {
                wait.suspend(at: ProcessInfo.processInfo.systemUptime)
                usleep(1_200_000)
                continue
            }
            wait.resume(at: ProcessInfo.processInfo.systemUptime)
            guardSighting = sighted
        }
        // A window gone since the guard reads as empty, as the separate
        // finders read it; the next guard finds it gone.
        let sighting = ResponseSighting(guardSighting ?? conversationSighting(in: target)
                                        ?? ConversationSighting())
        onPoll?(sighting)
        let seen = "affordances \(sighting.affordances), message \(sighting.lastOrdinal.map(String.init) ?? "-"), streaming \(sighting.streaming)"
        if seen != lastSeen {
            trace("response watch +\(Int(ProcessInfo.processInfo.systemUptime - startedAt))s: \(seen)")
            lastSeen = seen
        }
        let now = ProcessInfo.processInfo.systemUptime
        switch wait.observe(sighting, since: baseline, selectors: target.selectors, at: now) {
        case .complete:
            log("\(target.name): response complete (\(sighting.affordances) message affordances"
                + (sighting.lastOrdinal.map { ", message \($0)" } ?? "") + ")")
            return .complete(sighting)
        case .timedOut:
            log("\(target.name): timed out after \(Int(timeout))s without detected response activity"
                + " (\(Int(now - startedAt))s total wait,"
                + " affordances \(sighting.affordances)/\(baseline.affordances),"
                + " message \(sighting.lastOrdinal.map(String.init) ?? "-")"
                + "/\(baseline.lastOrdinal.map(String.init) ?? "-"),"
                + " streaming seen: \(wait.sawStreaming), streaming now: \(sighting.streaming))")
            return .timedOut
        case .waiting:
            break
        }
        usleep(1_200_000)
    }
}
