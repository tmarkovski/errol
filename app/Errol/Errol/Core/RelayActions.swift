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

/// The newest response's text, taken with the app's own per-message copy
/// button.
///
/// The press is a plain AXPress, but the handler behind it writes the
/// clipboard from the app's renderer, and Chromium refuses that write while
/// the document is unfocused: the press still reports success and the
/// clipboard never moves (observed live Aug 31 2026 — a run died mid-turn on
/// "clipboard never changed after pressing copy" with Claude no longer
/// focused). So the target is brought frontmost first, the way `send` does
/// before typing, and a miss is retried once behind a LaunchServices
/// activation — the one call that moves key status too, which is what the
/// renderer actually reads.
func copyLastResponse(from target: TargetApp) -> String? {
    for attempt in 0..<2 {
        if !makeFrontmost(target) {
            // Unlike a keystroke, an AXPress lands on the element whatever is
            // frontmost, so the press is still worth making — but say what
            // focus looked like, since it is the first suspect for a press
            // that reports success and copies nothing.
            log("\(target.name): could not bring app to front before copying; pressing anyway")
            log("\(target.name): \(focusReport(target))")
        }
        if let text = pressCopyButton(in: target) { return text }
        if attempt == 0 {
            log("\(target.name): retrying the copy after forcing activation")
            activateViaLaunchServices(target)
            usleep(400_000)
        }
    }
    return nil
}

/// One press of the newest message's copy button, confirmed by the pasteboard
/// moving. nil when no button could be found, the press failed, or it
/// produced no clipboard write.
func pressCopyButton(in target: TargetApp) -> String? {
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

/// What a cut message ends with, so the peer sees it was cut rather than a
/// silent ellipsis.
let relayTruncationMark = "\n\n[truncated by relay]"

/// The per-message length cap, applied before pasting — the protection
/// (with the turn cap) against two chatty models burning through usage.
/// The plain cap keeps the beginning; a handoff carrying steering notes is
/// assembled to fit under it first (HandoffPayload), so the notes travel
/// whole and this never cuts one.
func truncatedForRelay(_ text: String) -> String {
    guard text.count > config.maxChars else { return text }
    return String(text.prefix(config.maxChars)) + relayTruncationMark
}

/// How a send ended, as far as the relay could observe.
enum SendOutcome: Equatable {
    /// The paste was verified in the composer and a submission signal was
    /// observed afterwards: the message is in the conversation.
    case confirmed
    /// A submission was attempted without a signal that confirms it — or
    /// the paste itself never verified, in which case no later signal can
    /// vouch for what was submitted.
    case unconfirmed
    /// The foreground was lost during confirmation, after a submission may
    /// already have gone out. The relay stops rather than type into
    /// whatever took focus.
    case abandoned
    /// The foreground could not be taken before typing; nothing was typed.
    case refused

    /// Whether the relay can go on to the next turn: a message that may
    /// well have landed does not end the run, the two that lost the
    /// machine do.
    var continuesRun: Bool { self == .confirmed || self == .unconfirmed }
}

enum PasteReceipt: Equatable {
    case text
    case attachment
}

/// A paste is visible either as ordinary composer text or as a newly mounted
/// pasted-text attachment. ChatGPT removes long paste contents from AXValue
/// when it builds the attachment chip, so checking text alone causes the
/// recovery path to paste the same payload a second time.
func observedPasteReceipt(needle: String, composerValue: String?,
                          attachmentsBefore: Int, attachmentsNow: Int) -> PasteReceipt? {
    if needle.isEmpty || composerValue?.contains(needle) == true { return .text }
    if attachmentsNow > attachmentsBefore { return .attachment }
    return nil
}

func waitForPasteReceipt(needle: String, input: AXUIElement?, selectors: AppSelectors,
                         attachmentsBefore: Int,
                         within seconds: TimeInterval = 2) -> PasteReceipt? {
    let deadline = Date().addingTimeInterval(seconds)
    repeat {
        let value = input.flatMap { axAttribute($0, kAXValueAttribute) as? String }
        let attachmentCount = input.map {
            pastedTextAttachmentCount(around: $0, selectors: selectors)
        } ?? attachmentsBefore
        if let receipt = observedPasteReceipt(needle: needle, composerValue: value,
                                              attachmentsBefore: attachmentsBefore,
                                              attachmentsNow: attachmentCount) {
            return receipt
        }
        if Date() >= deadline { return nil }
        usleep(100_000)
    } while true
}

/// Paste `text` into the target's composer and submit it. The outcome says
/// how much of that was seen to happen; only `.confirmed` means both the
/// paste and the submission were observed, which is what a steering note's
/// receipt is allowed to rest on.
func send(_ text: String, to target: TargetApp) -> SendOutcome {
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
        return .refused
    }

    // Synthesized keystrokes follow the KEY window, which can lag behind the
    // active app (isFrontmost true while another window keeps key status —
    // e.g. Errol's own non-activating panel). So the paste must be verified
    // in the composer, not assumed: paste, check for the payload text or a new
    // pasted-text attachment chip, and on a miss force a LaunchServices
    // activation (the one call that moves key status too) and paste again.
    // A paste that never verified caps the outcome at unconfirmed whatever
    // the composer does afterwards: a send signal cannot vouch for a
    // payload nobody saw land.
    var pasteVerified = false
    let needle = String(payload.prefix(while: { $0 != "\n" }).prefix(32))
    pasteAttempts: for attempt in 0..<2 {
        let input = inputArea(in: target)
        let attachmentsBefore = input.map {
            pastedTextAttachmentCount(around: $0, selectors: target.selectors)
        } ?? 0
        if let input {
            AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            usleep(150_000)
        } else {
            log("\(target.name): could not locate input area, pasting into current focus")
        }
        keystroke(keyV, flags: .maskCommand)
        if let receipt = waitForPasteReceipt(needle: needle, input: input,
                                             selectors: target.selectors,
                                             attachmentsBefore: attachmentsBefore) {
            if receipt == .attachment {
                log("\(target.name): paste landed as a text attachment")
            }
            pasteVerified = true
            break pasteAttempts
        }
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
    // mid-send doesn't receive stray Returns. A surface that offers no
    // signal to watch is not escalated — another Return could only double a
    // send nobody can see — and reports unconfirmed, not success.
    var confirmation = confirmSend(in: target, from: beforeSend,
                                   buttonSignal: hadSendButton, within: 3)
    if confirmation == .pending {
        guard isFrontmost(target) else {
            log("\(target.name): WARNING: lost frontmost during send; not retrying keystrokes")
            return .abandoned
        }
        log("\(target.name): send unconfirmed, trying Return keystroke")
        keystroke(keyReturn)
        confirmation = confirmSend(in: target, from: beforeSend,
                                   buttonSignal: hadSendButton, within: 3)
        if confirmation == .pending {
            guard isFrontmost(target) else {
                log("\(target.name): WARNING: lost frontmost during send; not retrying keystrokes")
                return .abandoned
            }
            log("\(target.name): send still unconfirmed, trying Cmd+Return")
            keystroke(keyReturn, flags: .maskCommand)
            confirmation = confirmSend(in: target, from: beforeSend,
                                       buttonSignal: hadSendButton, within: 3)
            if confirmation == .pending {
                log("\(target.name): WARNING: could not confirm the message was sent")
            }
        }
    } else if confirmation == .unobservable {
        log("\(target.name): WARNING: nothing to confirm the send against on this surface — no readable composer and no send button")
    }
    guard confirmation == .confirmed else { return .unconfirmed }
    guard pasteVerified else {
        log("\(target.name): WARNING: the send was confirmed but the paste never was; treating it as unconfirmed")
        return .unconfirmed
    }
    return .confirmed
}

/// What one confirmation window learned about the send.
enum SendConfirmation: Equatable {
    /// A signal said the message left the composer.
    case confirmed
    /// A signal exists to watch and has not fired yet — worth escalating.
    case pending
    /// Neither signal exists on this surface: no readable composer and no
    /// send button. Nothing can be learned by waiting, or by pressing again.
    case unobservable
}

/// The message really left the composer. Two independent signals, either
/// confirms: the composer's value moved off the payload, or the send control
/// dropped back to its empty-composer state — disabled on Claude Code, where
/// the button persists (verified live, Aug 27 2026), unmounted entirely on
/// ChatGPT. The composer value alone has been seen reading stale for seconds
/// after a successful send on Claude Code, so it cannot be the only check.
/// The button signal only counts when a send button existed at press time —
/// otherwise its absence is the app's normal idle state, not a confirmation.
/// With neither signal there is nothing to verify, and that is reported as
/// such rather than as a success.
func confirmSend(in target: TargetApp, from before: String?, buttonSignal: Bool,
                 within seconds: TimeInterval) -> SendConfirmation {
    guard before != nil || buttonSignal else { return .unobservable }
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if before != nil, composerValue(in: target) != before { return .confirmed }
        if buttonSignal {
            if let button = sendButton(in: target) {
                if (axAttribute(button, kAXEnabledAttribute) as? Bool) == false { return .confirmed }
            } else {
                return .confirmed
            }
        }
        usleep(200_000)
    }
    return .pending
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
        if relayControl.isCancelled { return false }
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
