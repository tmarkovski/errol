// The copy/send primitives one turn of the relay is built from. Recognizing
// the paste and waiting for the response live beside them, in their own files.

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
func copyLastResponse(from target: TargetApp,
                      mayContinue: () -> Bool = { true }) -> String? {
    for attempt in 0..<2 {
        // The destination is the caller's to judge; a press into a
        // conversation the human switched to would copy their message.
        guard mayContinue() else { return nil }
        if !makeFrontmost(target) {
            // Unlike a keystroke, an AXPress lands on the element whatever is
            // frontmost, so the press is still worth making — but say what
            // focus looked like, since it is the first suspect for a press
            // that reports success and copies nothing.
            log("\(target.name): could not bring app to front before copying; pressing anyway")
            log("\(target.name): \(focusReport(target))")
        }
        if let text = pressCopyButton(in: target) {
            trace("copied \(text.count) chars from \(target.name) on attempt \(attempt + 1)")
            return text
        }
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
    // Whatever the human had on the clipboard goes back the moment the
    // reply is in memory: the clipboard is not held across the wait for
    // the delivery gate (ClipboardLease).
    let lease = ClipboardLease(pasteboard)
    defer { noteRelease(lease.release(), of: "the copied reply", in: target) }
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
    lease.claim()
    return pasteboard.string(forType: .string)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// What became of the clipboard at the end of an operation, to the debug
/// log — and to the run log when the human's contents were left as they
/// were, which is worth knowing when a later paste surprises.
func noteRelease(_ release: ClipboardLease.Release, of what: String, in target: TargetApp) {
    switch release {
    case .restored:
        trace("clipboard: the earlier contents are back after \(what)")
    case .nothingOwned:
        trace("clipboard: nothing written for \(what), nothing to put back")
    case .preservedNewer:
        log("\(target.name): the clipboard changed after \(what) was written; leaving the newer contents in place")
    case .leftInPlace(let reason):
        log("\(target.name): leaving \(what) on the clipboard — \(reason)")
    }
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
    /// The attempt started but cannot continue safely (lost focus,
    /// cancellation, or an inspection veto). Submission may have happened.
    case abandoned
    /// The send was called off before anything was typed: cancelled, or
    /// vetoed by an inspection.
    case refused
    /// The app could not be brought to the front, so nothing was typed:
    /// a keystroke lands in whatever app is frontmost. The composer stands
    /// as it was; the caller holds for the human to bring the app forward
    /// (RunBlock.notInFront) and tries again.
    case notInFront
    /// Nothing was typed because a check made just before the keystroke
    /// found the destination changed or the clipboard taken. The composer
    /// stands as it was, so the delivery can be tried again once the
    /// condition clears; the caller holds rather than ends.
    case withheld

    /// Whether the relay can go on to the next turn: a message that may
    /// well have landed does not end the run, the two that lost the
    /// machine do. A withheld send is neither; the caller retries it.
    var continuesRun: Bool { self == .confirmed || self == .unconfirmed }
}

/// How a paste was seen to land. `text` and `attachment` are the direct
/// signals; `growth` is the fallback for a composer that rewrote the
/// opening text on the way in.
enum PasteReceipt: Equatable {
    /// The payload's opening letters and digits are in the composer.
    case text
    /// The composer grew by a payload's worth, though its opening text
    /// could not be recognized.
    case growth
    /// A pasted-text attachment chip mounted.
    case attachment
}

/// Optional synchronous diagnostics for the live compatibility harness. The
/// normal app supplies none. A probe may veto submission after inspecting the
/// actual paste, but it never substitutes a different paste/send implementation.
struct SendInspection {
    var event: (String) -> Void = { _ in }
    var mayContinue: () -> Bool = { true }
    var inspectPaste: (AXUIElement?, String, Int, Int, PasteReceipt?) -> Bool = { _, _, _, _, _ in true }
}

private func describeAnchor(_ anchor: TransferAnchor) -> String {
    func rect(_ r: CGRect) -> String { "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))" }
    return "editor \(rect(anchor.frame)), shell \(anchor.promptFrame.map(rect) ?? "none"), window \(rect(anchor.window))"
}

/// Paste `text` into the target's composer and submit it. The outcome says
/// how much of that was seen to happen; only `.confirmed` means both the
/// paste and the submission were observed, which is what a steering note's
/// receipt is allowed to rest on.
func send(_ text: String, to target: TargetApp,
          sources: [TransferSource] = [],
          showTransfer: Bool = false,
          destination: BoundDestination? = nil,
          inspection: SendInspection? = nil) -> SendOutcome {
    guard !relayControl.isCancelled, inspection?.mayContinue() != false else { return .refused }
    let payload = truncatedForRelay(text)
    if payload.count != text.count {
        log("\(target.name): payload truncated to \(config.maxChars) chars")
    }

    // The clipboard is the human's until the paste needs it and again as
    // soon as the send is over: what was there is captured now and goes
    // back at return, unless they copied something newer meanwhile.
    let lease = ClipboardLease()
    lease.write(payload)
    defer { noteRelease(lease.release(), of: "the message", in: target) }

    // Keystrokes go to the frontmost app no matter what has AX focus, so
    // never type unless the target is verified frontmost.
    guard makeFrontmost(target) else {
        log("\(target.name): could not bring app to front; not typing into another app's window")
        log("\(target.name): \(focusReport(target))")
        return .notInFront
    }

    // The two checks made right before every keystroke, after any
    // activation or wait: the bound window is still there and reachable,
    // and the clipboard still holds the payload. Either failing before
    // the first paste withholds the send with the composer untouched;
    // after typing began, it abandons it.
    func destinationHolds() -> Bool {
        guard let destination else { return true }
        switch destination.check() {
        case .same: break
        case .hidden(let seen):
            log("\(target.name): the window is \(seen) before the keystroke; not typing")
            return false
        case .lost(let detail):
            log("\(target.name): the destination is gone (\(detail)); not typing")
            return false
        }
        // The keystroke lands in the app's key window, so the bound window
        // must be that window — raised there now, since the app is frontmost.
        guard destination.isFrontWindow(raising: true) else {
            log("\(target.name): another \(target.name) window is in front of the conversation; not typing")
            return false
        }
        return true
    }
    func clipboardHolds() -> Bool {
        guard lease.isOwned else {
            log("\(target.name): the clipboard changed since the message was written; not pasting what is on it now")
            return false
        }
        return true
    }

    // Synthesized keystrokes follow the KEY window, which can lag behind the
    // active app (isFrontmost true while another window keeps key status —
    // e.g. Errol's own non-activating panel). So the paste must be verified
    // in the composer, not assumed: paste, then look for the payload's
    // opening text, a new pasted-text attachment chip, or the composer
    // growing by a payload's worth (observedPasteReceipt). On a miss, force
    // a LaunchServices activation (the one call that moves key status too)
    // and paste again — but only if the composer stands exactly as it did
    // before the keystroke. A composer that moved took the paste in some
    // form the receipt did not recognize, and a second paste would double
    // it (pasteRetryIsSafe). A paste that never verified caps the outcome
    // at unconfirmed whatever the composer does afterwards: a send signal
    // cannot vouch for a payload nobody saw land.
    var pasteVerified = false
    // Whether this send has already brought the app back once (holdsFront).
    var frontRetried = false
    // The opening letters and digits, fence lines skipped: what the composer
    // is expected to hold once the paste lands (pasteNeedle).
    let needle = pasteNeedle(for: payload)
    trace("send to \(target.name): \(payload.count) chars, recognized by \"\(needle)\"")
    pasteAttempts: for attempt in 0..<2 {
        guard !relayControl.isCancelled, inspection?.mayContinue() != false else {
            return attempt == 0 ? .refused : .abandoned
        }
        let resolved = resolveInputArea(in: target)
        let input = resolved?.element
        let transferID = UUID()
        let attachmentsBefore = input.map {
            pastedTextAttachmentCount(around: $0, selectors: target.selectors)
        } ?? 0
        var valueBefore: String?
        if let resolved {
            trace("paste attempt \(attempt + 1): the composer is \(resolved.source.rawValue): "
                + "\(describeElement(resolved.element)); attachments before: \(attachmentsBefore)")
            AXUIElementSetAttributeValue(resolved.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            usleep(150_000)
            valueBefore = axAttribute(resolved.element, kAXValueAttribute) as? String
            let focused = axAttribute(target.ax, kAXFocusedUIElementAttribute)
            let onComposer = focused.map { CFEqual($0, resolved.element) } ?? false
            let elsewhere = focused.map {
                CFGetTypeID($0) == AXUIElementGetTypeID() ? describeElement($0 as! AXUIElement) : "a non-element value"
            } ?? "nothing"
            trace("after the focus request: "
                + (onComposer ? "the app reports the composer focused" : "the app reports focus on \(elsewhere)")
                + "; \(focusReport(target))")
        } else {
            log("\(target.name): could not locate input area, pasting into current focus")
            trace("focus before pasting: \(focusReport(target))")
        }
        // The human can take the front while the dot is in flight: a click
        // on the console, or on another app. The app is brought back once
        // per send before the send gives up on it (makeFrontmost lets go of
        // the console's key status first); the flight has played, so the
        // paste goes on from where it stood, into the composer asked for
        // focus again. A second loss is the human's to settle
        // (RunBlock.notInFront).
        func holdsFront(_ when: String) -> Bool {
            if isFrontmost(target) { return true }
            guard !frontRetried, !relayControl.isCancelled else {
                log("\(target.name): lost the front \(when); not typing")
                log("\(target.name): \(focusReport(target))")
                return false
            }
            frontRetried = true
            log("\(target.name): lost the front \(when); bringing it back")
            log("\(target.name): \(focusReport(target))")
            guard makeFrontmost(target) else {
                if !relayControl.isCancelled {
                    log("\(target.name): would not come back to the front; not typing")
                    log("\(target.name): \(focusReport(target))")
                }
                return false
            }
            if let resolved {
                AXUIElementSetAttributeValue(resolved.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                usleep(150_000)
            }
            trace("back in front: \(focusReport(target))")
            return true
        }
        // What a send that could not keep the front comes to: nothing typed
        // yet, a hold for the human, or a Stop that won meanwhile.
        func lostFront() -> SendOutcome {
            if attempt > 0 { return .abandoned }
            return relayControl.isCancelled ? .refused : .notInFront
        }
        let expectation = PasteExpectation(payload: payload, valueBefore: valueBefore)
        trace("expecting: needle \"\(expectation.needle)\""
            + (expectation.needleIsDistinctive ? "" : " (already in the composer, so not counted)")
            + ", or a new attachment, or growth of \(expectation.growthRequired)+ chars over a baseline of "
            + "\(expectation.baselineCount)" + (valueBefore.map { " (composer holds \($0.count))" } ?? ""))
        var destination = showTransfer ? transferAnchor(for: input, in: target) : nil
        if showTransfer {
            trace(destination.map { "transfer destination: \(describeAnchor($0))" }
                ?? "transfer destination: none (no usable geometry for the composer, so no dot and no outline)")
        }
        // The app is frontmost, but under Stage Manager its window may
        // still be on the way to its place (awaitArrival). One that does
        // not get there has nothing drawn over it, and no light to wait for.
        if let anchor = destination {
            let asked = ProcessInfo.processInfo.systemUptime
            let arrived = awaitArrival(of: anchor)
            let waited = ProcessInfo.processInfo.systemUptime - asked
            if !arrived {
                trace("transfer destination: the window is not showing at that frame after "
                    + String(format: "%.2f", waited) + " s, so no dot and no outline")
                destination = nil
            } else if waited > 0.05 {
                trace("transfer destination: waited " + String(format: "%.2f", waited)
                    + " s for the window to reach its place")
            }
        }
        if let destination {
            let startedAt = ProcessInfo.processInfo.systemUptime
            relayEvents.post(.transfer(.began(id: transferID, sources: sources,
                                              destination: destination, startedAt: startedAt)))
            // The dot's flight and the prompt's light run on this clock in
            // the overlay, and the paste waits for the light to fade: the
            // text going in can grow the composer and move the border the
            // light traces, so the light plays first, over the border the
            // dot landed on. No renderer callback gates delivery. CLI runs
            // and missing composer geometry have no destination and skip
            // the wait; Reduce Motion skips the flight and keeps the light.
            let timing = TransferTiming(startedAt: startedAt, travels: !sources.isEmpty,
                                        reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            while ProcessInfo.processInfo.systemUptime < timing.pasteTime, !relayControl.isCancelled {
                Thread.sleep(forTimeInterval: 0.01)
            }
            // The human may have switched apps or stopped during the flight.
            guard !relayControl.isCancelled else {
                relayEvents.post(.transfer(.cancelled(id: transferID)))
                return attempt == 0 ? .refused : .abandoned
            }
            guard holdsFront("during the transfer") else {
                relayEvents.post(.transfer(.cancelled(id: transferID)))
                return lostFront()
            }
        }
        guard !relayControl.isCancelled, inspection?.mayContinue() != false else {
            return attempt == 0 ? .refused : .abandoned
        }
        guard holdsFront("before the keystroke") else { return lostFront() }
        // A retry only happens over a composer that stands as it did, so
        // a withheld retry has typed nothing that landed either.
        guard destinationHolds(), clipboardHolds() else { return .withheld }
        inspection?.event("paste-attempt-\(attempt + 1)")
        trace("pasting (Cmd+V): pasteboard change count \(NSPasteboard.general.changeCount); \(focusReport(target))")
        keystroke(keyV, flags: .maskCommand)
        let receipt = waitForPasteReceipt(expecting: expectation, input: input,
                                          selectors: target.selectors,
                                          attachmentsBefore: attachmentsBefore)
        if let inspection {
            let attachmentsNow = input.map { pastedTextAttachmentCount(around: $0, selectors: target.selectors) } ?? 0
            if !inspection.inspectPaste(input, payload, attachmentsBefore, attachmentsNow, receipt) {
                log("\(target.name): verification stopped the handoff before submission")
                return .abandoned
            }
        }
        if let receipt {
            if receipt == .attachment {
                log("\(target.name): paste landed as a text attachment")
            } else if receipt == .growth {
                log("\(target.name): paste recognized by the composer growing; its opening text was rewritten on the way in")
            }
            pasteVerified = true
            if receipt != .attachment, let input {
                noteRepeatedPaste(payload: payload, needle: needle, input: input, in: target)
            }
            // Where the paste landed, for the event stream and the trace; the
            // light has faded by now, so nothing is drawn from it.
            if destination != nil {
                if let input, let landed = transferAnchor(for: input, in: target) {
                    trace("transfer landed: \(describeAnchor(landed))")
                    relayEvents.post(.transfer(.pasted(id: transferID, destination: landed)))
                } else {
                    trace("transfer cancelled: the composer has no usable geometry after the paste")
                    relayEvents.post(.transfer(.cancelled(id: transferID)))
                }
            }
            break pasteAttempts
        }
        if destination != nil { relayEvents.post(.transfer(.cancelled(id: transferID))) }
        // Did the composer move at all? If so the paste is in there in some
        // form, and another would double it: go on to the send unverified.
        let valueNow = input.flatMap { axAttribute($0, kAXValueAttribute) as? String }
        let attachmentsNow = input.map {
            pastedTextAttachmentCount(around: $0, selectors: target.selectors)
        } ?? attachmentsBefore
        let retryIsSafe = pasteRetryIsSafe(valueBefore: valueBefore, valueNow: valueNow,
                                           attachmentsBefore: attachmentsBefore, attachmentsNow: attachmentsNow)
        if !retryIsSafe {
            log("\(target.name): WARNING: the paste was not recognized, but the composer changed"
                + " (\(valueBefore?.count ?? 0) -> \(valueNow?.count ?? 0) chars, attachments \(attachmentsBefore) -> \(attachmentsNow));"
                + " not pasting again")
        } else if attempt == 0 {
            log("\(target.name): paste did not land in the composer; forcing activation and retrying")
        } else {
            log("\(target.name): WARNING: paste still not visible in the composer after retry")
        }
        pasteMissSnapshot(in: target, input: input, needle: needle, payload: payload, attempt: attempt + 1)
        if !retryIsSafe { break pasteAttempts }
        if attempt == 0 {
            activateViaLaunchServices(target)
            usleep(400_000)
        }
    }

    let beforeSend = composerValue(in: target)
    trace("composer before the send: " + (beforeSend.map { "\($0.count) chars (payload \(payload.count))" } ?? "unreadable"))
    guard !relayControl.isCancelled, isFrontmost(target), inspection?.mayContinue() != false else { return .abandoned }
    // The paste is in a composer; whether that composer still belongs to
    // the bound conversation is checked once more before it is submitted.
    guard destinationHolds() else {
        log("\(target.name): WARNING: the conversation changed after the paste; not submitting. The pasted text may still be in a composer.")
        return .abandoned
    }
    inspection?.event("submit-attempt-1")

    // A send button press is more reliable than a Return keystroke (no
    // Return-vs-Cmd+Return ambiguity, no dependence on keyboard focus).
    let hadSendButton: Bool
    if let button = sendButton(in: target),
       AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
        hadSendButton = true
        log("\(target.name): sent via send button")
        // The first "send" button in the window, which a press that does
        // nothing may show to be some other control than the composer's.
        trace("the send button pressed: \(describeElement(button))")
    } else {
        hadSendButton = false
        guard !relayControl.isCancelled, isFrontmost(target), inspection?.mayContinue() != false else { return .abandoned }
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
        guard !relayControl.isCancelled, isFrontmost(target), inspection?.mayContinue() != false else {
            log("\(target.name): WARNING: lost frontmost during send; not retrying keystrokes")
            return .abandoned
        }
        guard destinationHolds() else { return .abandoned }
        log("\(target.name): send unconfirmed, trying Return keystroke")
        inspection?.event("submit-attempt-2")
        keystroke(keyReturn)
        confirmation = confirmSend(in: target, from: beforeSend,
                                   buttonSignal: hadSendButton, within: 3)
        if confirmation == .pending {
            guard !relayControl.isCancelled, isFrontmost(target), inspection?.mayContinue() != false else {
                log("\(target.name): WARNING: lost frontmost during send; not retrying keystrokes")
                return .abandoned
            }
            guard destinationHolds() else { return .abandoned }
            log("\(target.name): send still unconfirmed, trying Cmd+Return")
            inspection?.event("submit-attempt-3")
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
    let startedAt = ProcessInfo.processInfo.systemUptime
    func confirmed(_ how: String) -> SendConfirmation {
        trace("send confirmed after \(Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000))ms: \(how)")
        return .confirmed
    }
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if before != nil, composerValue(in: target) != before { return confirmed("the composer value moved") }
        if buttonSignal {
            if let button = sendButton(in: target) {
                if (axAttribute(button, kAXEnabledAttribute) as? Bool) == false { return confirmed("the send button disabled") }
            } else {
                return confirmed("the send button unmounted")
            }
        }
        usleep(200_000)
    }
    trace("send not confirmed within \(Int(seconds))s: the composer " + (before.map { "still holds \($0.count) chars" } ?? "is unreadable")
        + (buttonSignal ? ", the send button is still enabled" : ""))
    return .pending
}
