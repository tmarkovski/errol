// The copy/send/wait primitives one turn of the relay is built from.

import AppKit
import ApplicationServices

/// When the newest message's affordance is the collapsed actions toggle
/// (Claude Code), press it and wait for the bar's copy button to mount —
/// the AXPress equivalent of the hover that normally expands it.
func expandLastMessageActions(in target: TargetApp) {
    guard let last = messageAffordances(in: target).last,
          isMessageActionsToggle(last, selectors: target.selectors) else { return }
    let before = copyButtons(in: target).count
    guard AXUIElementPerformAction(last, kAXPressAction as CFString) == .success else {
        log("\(target.name): AXPress on the message-actions toggle failed")
        return
    }
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if copyButtons(in: target).count > before { return }
        usleep(150_000)
    }
    log("\(target.name): no copy button mounted after expanding message actions")
}

func copyLastResponse(from target: TargetApp) -> String? {
    expandLastMessageActions(in: target)
    let buttons = copyButtons(in: target)
    guard let button = buttons.last else {
        log("\(target.name): no copy button found")
        return nil
    }
    let pasteboard = NSPasteboard.general
    let before = pasteboard.changeCount
    let err = AXUIElementPerformAction(button, kAXPressAction as CFString)
    if err != .success {
        log("\(target.name): AXPress on copy button failed (\(err.rawValue))")
        return nil
    }
    let deadline = Date().addingTimeInterval(3)
    while pasteboard.changeCount == before {
        if Date() > deadline {
            log("\(target.name): clipboard never changed after pressing copy")
            return nil
        }
        usleep(50_000)
    }
    return pasteboard.string(forType: .string)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// The per-message length cap, applied before pasting — the protection
/// (with the turn cap) against two chatty models burning through usage.
func truncatedForRelay(_ text: String) -> String {
    guard text.count > config.maxChars else { return text }
    return String(text.prefix(config.maxChars)) + "\n\n[truncated by relay]"
}

func send(_ text: String, to target: TargetApp) -> Bool {
    let payload = truncatedForRelay(text)
    if payload.count != text.count {
        log("\(target.name): payload truncated to \(config.maxChars) chars")
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(payload, forType: .string)

    // Keystrokes go to the frontmost app no matter what has AX focus, so
    // never type unless the target is verified frontmost.
    guard makeFrontmost(target) else {
        log("\(target.name): could not bring app to front; refusing to type into another app's window")
        log("\(target.name): \(focusReport(target))")
        return false
    }

    // Synthesized keystrokes follow the KEY window, which can lag behind the
    // active app (isFrontmost true while another window keeps key status —
    // e.g. Errol's own non-activating panel). So the paste must be verified
    // in the composer, not assumed: paste, check for the payload text, and on
    // a miss force a LaunchServices activation (the one call that moves key
    // status too) and paste again.
    let needle = String(payload.prefix(while: { $0 != "\n" }).prefix(32))
    for attempt in 0..<2 {
        if let input = inputArea(in: target) {
            AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            usleep(150_000)
        } else {
            log("\(target.name): could not locate input area, pasting into current focus")
        }
        keystroke(keyV, flags: .maskCommand)
        // Give the app time to render the paste; large messages need it before sending.
        let renderDelay = min(2_000_000, 300_000 + payload.count * 20)
        usleep(useconds_t(renderDelay))
        if needle.isEmpty || composerValue(in: target)?.contains(needle) == true { break }
        if attempt == 0 {
            log("\(target.name): paste did not land in the composer; forcing activation and retrying")
            activateViaLaunchServices(target)
            usleep(400_000)
        } else {
            log("\(target.name): WARNING: paste still not visible in the composer after retry")
        }
    }

    let beforeSend = composerValue(in: target)

    // A send button press is more reliable than a Return keystroke (no
    // Return-vs-Cmd+Return ambiguity, no dependence on keyboard focus).
    let hadSendButton: Bool
    if let button = sendButton(in: target),
       AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
        hadSendButton = true
        log("\(target.name): sent via send button")
    } else {
        hadSendButton = false
        keystroke(keyReturn)
        log("\(target.name): sent via Return keystroke")
    }

    // Confirm the send landed; if not, escalate through the known variants,
    // re-checking frontmost before each keystroke so an app that stole focus
    // mid-send doesn't receive stray Returns.
    if !confirmSend(in: target, from: beforeSend, buttonSignal: hadSendButton, within: 3) {
        guard isFrontmost(target) else {
            log("\(target.name): WARNING: lost frontmost during send; not retrying keystrokes")
            return false
        }
        log("\(target.name): send unconfirmed, trying Return keystroke")
        keystroke(keyReturn)
        if !confirmSend(in: target, from: beforeSend, buttonSignal: hadSendButton, within: 3) {
            guard isFrontmost(target) else {
                log("\(target.name): WARNING: lost frontmost during send; not retrying keystrokes")
                return false
            }
            log("\(target.name): send still unconfirmed, trying Cmd+Return")
            keystroke(keyReturn, flags: .maskCommand)
            if !confirmSend(in: target, from: beforeSend, buttonSignal: hadSendButton, within: 3) {
                log("\(target.name): WARNING: could not confirm the message was sent")
            }
        }
    }
    return true
}

/// The message really left the composer. Two independent signals, either
/// confirms: the composer's value moved off the payload, or the send control
/// dropped back to its empty-composer state — disabled on Claude Code, where
/// the button persists (verified live, Aug 27 2026), unmounted entirely on
/// ChatGPT. The composer value alone has been seen reading stale for seconds
/// after a successful send on Claude Code, so it cannot be the only check.
/// The button signal only counts when a send button existed at press time —
/// otherwise its absence is the app's normal idle state, not a confirmation.
func confirmSend(in target: TargetApp, from before: String?, buttonSignal: Bool,
                 within seconds: TimeInterval) -> Bool {
    // With no readable composer and no button to watch, there is nothing to verify.
    guard before != nil || buttonSignal else { return true }
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if before != nil, composerValue(in: target) != before { return true }
        if buttonSignal {
            if let button = sendButton(in: target) {
                if (axAttribute(button, kAXEnabledAttribute) as? Bool) == false { return true }
            } else {
                return true
            }
        }
        usleep(200_000)
    }
    return false
}

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

func responseBaseline(in target: TargetApp) -> ResponseBaseline {
    ResponseBaseline(affordances: messageAffordances(in: target).count,
                     lastOrdinal: lastMessageOrdinal(in: target))
}

/// One poll of the responding side, as waitForResponse sees it.
struct ResponseSighting {
    var affordances: Int
    var lastOrdinal: Int?
    var streaming: Bool
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
/// the echo-inclusive delta.
func absorbEchoIntoBaseline(in target: TargetApp, preSend: ResponseBaseline) -> ResponseBaseline {
    guard target.selectors.echoCountsAsAffordance else { return preSend }
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline {
        let echoSeen = messageAffordances(in: target).count > preSend.affordances
            || preSend.lastOrdinal.map { base in
                (lastMessageOrdinal(in: target) ?? base) > base
            } ?? false
        if echoSeen {
            return ResponseBaseline(affordances: preSend.affordances + 1,
                                    lastOrdinal: preSend.lastOrdinal)
        }
        usleep(100_000)
    }
    return preSend
}

func waitForResponse(in target: TargetApp, baseline: ResponseBaseline) -> Bool {
    log("\(target.name): waiting for response (baseline \(baseline.affordances) message affordances"
        + (baseline.lastOrdinal.map { ", message \($0)" } ?? "") + ")...")
    let deadline = Date().addingTimeInterval(config.timeout)
    var stableTicks = 0
    var sawStreaming = false
    while Date() < deadline {
        if relayCancelled.isSet { return false }
        let sighting = ResponseSighting(affordances: messageAffordances(in: target).count,
                                        lastOrdinal: lastMessageOrdinal(in: target),
                                        streaming: hasStopButton(in: target))
        if sighting.streaming { sawStreaming = true }
        if responseArrived(sighting, since: baseline, sawStreaming: sawStreaming,
                           selectors: target.selectors) {
            stableTicks += 1
            if stableTicks >= 2 {
                log("\(target.name): response complete (\(sighting.affordances) message affordances"
                    + (sighting.lastOrdinal.map { ", message \($0)" } ?? "") + ")")
                return true
            }
        } else {
            stableTicks = 0
        }
        usleep(1_200_000)
    }
    log("\(target.name): timed out after \(Int(config.timeout))s"
        + " (affordances \(messageAffordances(in: target).count)/\(baseline.affordances),"
        + " message \(lastMessageOrdinal(in: target).map(String.init) ?? "-")"
        + "/\(baseline.lastOrdinal.map(String.init) ?? "-"),"
        + " streaming seen: \(sawStreaming))")
    return false
}
