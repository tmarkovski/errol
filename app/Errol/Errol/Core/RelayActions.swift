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

/// Letters and digits of `text`, in order: the alphabet a paste is
/// recognized in. Composers rewrite what they are given — ChatGPT turns a
/// pasted markdown fence into a rendered code block and drops the fence
/// line from its AXValue, and swaps quote characters (both observed Sep 8
/// 2026; the fence was behind a run of double pastes) — but the letters and
/// digits come through, in order.
func alphanumerics(of text: String) -> String {
    String(text.filter { $0.isLetter || $0.isNumber })
}

/// Whether a line is a markdown code fence, which a rendering composer
/// consumes whole, language tag and all.
func isFenceLine(_ line: Substring) -> Bool {
    let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
    return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
}

/// The text a paste is recognized by: the first `length` letters and
/// digits of the payload, fence lines left out. A short opening line runs
/// on into the next, so a one-word first line still yields a needle worth
/// matching. Empty for a payload with no letters or digits at all.
func pasteNeedle(for payload: String, length: Int = 24) -> String {
    var needle = ""
    for line in payload.split(whereSeparator: \.isNewline) where !isFenceLine(line) {
        for character in line where character.isLetter || character.isNumber {
            needle.append(character)
            if needle.count >= length { return needle }
        }
    }
    return needle
}

/// What a paste is expected to do to the composer, fixed before the
/// keystroke so the receipt is judged against the composer as it stood.
struct PasteExpectation: Equatable {
    var needle: String
    /// The composer's value just before the paste; nil when no composer
    /// element was found.
    var valueBefore: String?
    var payloadCount: Int

    init(payload: String, valueBefore: String?) {
        needle = pasteNeedle(for: payload)
        self.valueBefore = valueBefore
        payloadCount = payload.count
    }

    /// The needle only counts when the composer did not hold it already —
    /// otherwise a draft that opens with the same words, or a paste already
    /// there, would vouch for one that never arrived.
    var needleIsDistinctive: Bool {
        !needle.isEmpty && !alphanumerics(of: valueBefore ?? "").contains(needle)
    }

    /// The text the paste adds to. A placeholder is not text — it goes
    /// away when anything is typed — so a composer showing one counts as
    /// empty (composerPlaceholders in Config.swift).
    var baselineCount: Int {
        guard let valueBefore else { return 0 }
        let trimmed = valueBefore.trimmingCharacters(in: .whitespacesAndNewlines)
        return composerPlaceholders.contains(trimmed) ? 0 : valueBefore.count
    }

    /// How much the composer must grow for growth alone to count: a third
    /// of the payload, so a rewriting that shortens the text still passes,
    /// and never fewer than four characters.
    var growthRequired: Int { max(4, payloadCount / 3) }

    /// The composer's growth past its baseline, or nil while its value
    /// stands where it was.
    func growth(to value: String?) -> Int? {
        guard let value, value != (valueBefore ?? "") else { return nil }
        return value.count - baselineCount
    }
}

/// A paste is seen to land when the composer holds the payload's opening
/// letters and digits, or a new pasted-text attachment mounted (Claude and
/// ChatGPT move long pastes into a chip and take the text out of AXValue),
/// or — when the composer rewrote the opening text past recognition — the
/// composer's value grew by a payload's worth. Each is a change from the
/// composer as it stood before the paste; none can be met by what was
/// already there.
func observedPasteReceipt(expecting expectation: PasteExpectation, composerValue: String?,
                          attachmentsBefore: Int, attachmentsNow: Int) -> PasteReceipt? {
    if let value = composerValue, expectation.needleIsDistinctive,
       alphanumerics(of: value).contains(expectation.needle) {
        return .text
    }
    if attachmentsNow > attachmentsBefore { return .attachment }
    if let growth = expectation.growth(to: composerValue), growth >= expectation.growthRequired {
        return .growth
    }
    return nil
}

/// Whether pasting again is safe after a paste nobody recognized: only
/// when the composer stands exactly as it did before the keystroke. A
/// composer that moved at all took something — a paste rewritten past
/// recognition, most likely — and a second paste would double it, which
/// is what the retry did for two turns on Sep 8 2026. The case the retry
/// exists for, keystrokes going to another window, leaves the composer
/// untouched.
func pasteRetryIsSafe(valueBefore: String?, valueNow: String?,
                      attachmentsBefore: Int, attachmentsNow: Int) -> Bool {
    (valueBefore ?? "") == (valueNow ?? "") && attachmentsBefore == attachmentsNow
}

func waitForPasteReceipt(expecting expectation: PasteExpectation, input: AXUIElement?,
                         selectors: AppSelectors, attachmentsBefore: Int,
                         within seconds: TimeInterval = 2) -> PasteReceipt? {
    let startedAt = ProcessInfo.processInfo.systemUptime
    let deadline = Date().addingTimeInterval(seconds)
    var polls = 0
    var lastSeen = ""
    repeat {
        polls += 1
        let read = input.map { axAttributeResult($0, kAXValueAttribute) }
        let value = read?.value as? String
        let attachmentCount = input.map {
            pastedTextAttachmentCount(around: $0, selectors: selectors)
        } ?? attachmentsBefore
        let receipt = observedPasteReceipt(expecting: expectation, composerValue: value,
                                           attachmentsBefore: attachmentsBefore,
                                           attachmentsNow: attachmentCount)
        // What the two reads said, for the debug log — one line per change,
        // not per poll, plus the poll that produced the receipt. The value's
        // read error is kept: an element the app rebuilt under the paste
        // answers invalidUIElement, which a bare nil would hide.
        var seen: String
        if let value {
            seen = "value \(value.count) chars"
            if !value.isEmpty { seen += " \"\(clipped(value, to: 48))\"" }
            if let growth = expectation.growth(to: value) { seen += " (grew \(growth))" }
        } else if let read {
            seen = "value " + (read.error == .success ? "not text" : axErrorName(read.error))
        } else {
            seen = "no input element"
        }
        seen += ", attachments \(attachmentCount) (before: \(attachmentsBefore))"
        if seen != lastSeen || receipt != nil {
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
            trace("paste watch +\(elapsed)ms, poll \(polls): \(seen)"
                + (receipt.map { " -> receipt: \($0)" } ?? ""))
            lastSeen = seen
        }
        if let receipt { return receipt }
        if Date() >= deadline {
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
            trace("paste watch: no receipt after \(polls) polls, \(elapsed)ms; needle was \"\(expectation.needle)\", growth needed \(expectation.growthRequired)")
            return nil
        }
        usleep(100_000)
    } while true
}

/// After a verified text paste: whether the composer holds more than one
/// payload's worth — the mark of a retry that pasted on top of a paste
/// nobody saw land. Two readings, either warns: the payload's first line
/// appearing more often than the payload itself has it, and the composer
/// holding half again the payload's length (a first paste into an empty
/// composer comes out a few characters short of the payload, never long;
/// a second lands near double). The length reading is the one that works
/// when the first line is a code fence the composer renders away.
/// Reported, never acted on: the send goes ahead as it always has, and
/// the log says what it carried.
func noteRepeatedPaste(payload: String, needle: String, input: AXUIElement, in target: TargetApp) {
    guard let value = axAttribute(input, kAXValueAttribute) as? String else { return }
    let inComposer = needle.isEmpty ? 0 : alphanumerics(of: value).components(separatedBy: needle).count - 1
    let inPayload = needle.isEmpty ? 0 : alphanumerics(of: payload).components(separatedBy: needle).count - 1
    trace("composer after the paste: \(value.count) chars against a \(payload.count)-char payload;"
        + " the first line appears \(inComposer)x (the payload has it \(inPayload)x)")
    if inComposer > inPayload {
        log("\(target.name): WARNING: the composer holds the payload's first line \(inComposer) times — a paste appears to have landed twice")
    } else if payload.count >= 8, value.count * 2 >= payload.count * 3 {
        log("\(target.name): WARNING: the composer holds \(value.count) chars against a \(payload.count)-char payload — a paste appears to have landed twice, or a draft was already there")
    }
}

/// Everything worth knowing about the composer at the moment a paste
/// receipt failed to appear, to the debug log: the element the paste was
/// verified against and whether the app still answers for it, the element
/// the finders would pick now, every text input in the window and which of
/// them holds the needle, the composer's ancestors with the attachment
/// controls the selector counts under each, every button in the window
/// mentioning remove or paste, and — as sidecar files — the composer's
/// container and its neighbourhood as fixture JSON. A miss is where a
/// double paste comes from (the retry lands on a paste that did arrive),
/// so this is the state to have when one happens. The panel gets only the
/// verdict line the caller logs.
func pasteMissSnapshot(in target: TargetApp, input: AXUIElement?, needle: String,
                       payload: String, attempt: Int) {
    let pasteboard = NSPasteboard.general
    trace("=== paste miss snapshot: \(target.name), attempt \(attempt) ===")
    trace("needle \"\(clipped(needle, to: 48))\"; payload \(payload.count) chars; \(focusReport(target))")
    trace("pasteboard: change count \(pasteboard.changeCount), \((pasteboard.string(forType: .string) ?? "").count) chars of text")
    guard let window = chatWindow(in: target) else {
        trace("no chat window resolves now")
        trace("=== end of snapshot ===")
        return
    }
    if let input {
        let read = axAttributeResult(input, kAXValueAttribute)
        trace("verified against: \(describeElement(input)); value read now: \(axErrorName(read.error))")
    } else {
        trace("verified against: no element (the paste went to the current focus)")
    }
    if let now = resolveInputArea(in: target) {
        let same = input.map { CFEqual($0, now.element) } ?? false
        trace("the composer resolves now to \(now.source.rawValue): \(describeElement(now.element))"
            + (same ? " (the same element)" : " (A DIFFERENT ELEMENT)"))
    } else {
        trace("the composer resolves now to: nothing")
    }
    var inputs: [AXUIElement] = []
    findAll(in: window, where: { el in
        let role = axAttribute(el, kAXRoleAttribute) as? String
        return role == kAXTextAreaRole as String || role == kAXTextFieldRole as String
    }, into: &inputs)
    trace("text inputs in the window: \(inputs.count)")
    for element in inputs.prefix(12) {
        let value = axAttribute(element, kAXValueAttribute) as? String
        let holds = value.map { !needle.isEmpty && $0.contains(needle) } ?? false
        trace("  \(describeElement(element))" + (holds ? "  <- holds the needle" : ""))
    }
    if let input {
        var node = input
        var chain: [AXUIElement] = []
        let countedLevel = target.selectors.pastedTextAttachmentAncestorLevels
        for level in 1...5 {
            guard let parent = axAttribute(node, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            node = parent as! AXUIElement
            chain.append(node)
            let count = pastedTextAttachmentCount(under: LiveElement(ax: node), selectors: target.selectors)
            trace("ancestor \(level): \(describeElement(node)); attachment remove buttons under it: \(count)"
                + (level == countedLevel ? "  <- the level the selector counts" : ""))
        }
        // The container the selector inspects, whole; and two levels above
        // it, shallow, for the siblings a chip could have mounted among.
        let tag = "paste-miss-\(attempt)-\(target.name.lowercased())"
        let container = countedLevel >= 1 && chain.count >= countedLevel ? chain[countedLevel - 1] : input
        let neighbourhood = chain.count >= countedLevel + 2 ? chain[max(countedLevel + 1, 0)] : (chain.last ?? input)
        let captures: [(String, AXUIElement, Int, Int)] = [
            ("container", container, 500, 16),
            ("neighbourhood", neighbourhood, 300, 3),
        ]
        for (name, root, nodes, depth) in captures {
            guard let capture = captureSubtree(root, maxNodes: nodes, maxDepth: depth),
                  let url = RunLog.sidecar("\(tag)-\(name)", extension: "json") else { continue }
            do {
                try capture.json.write(to: url)
                trace("\(name) subtree captured to \(url.path) (\(capture.nodes) nodes\(capture.truncated ? ", truncated" : ""))")
            } catch {
                trace("could not write the \(name) capture: \(error)")
            }
        }
    }
    var mentions: [AXUIElement] = []
    findAll(in: window, where: { el in
        guard axAttribute(el, kAXRoleAttribute) as? String == kAXButtonRole as String else { return false }
        let label = axLabel(el)
        return label.localizedCaseInsensitiveContains("remove") || label.localizedCaseInsensitiveContains("paste")
    }, into: &mentions)
    trace("buttons in the window mentioning remove or paste: \(mentions.count)")
    for button in mentions.prefix(12) { trace("  \(describeElement(button))") }
    trace("=== end of snapshot ===")
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
            guard !relayControl.isCancelled, isFrontmost(target) else {
                relayEvents.post(.transfer(.cancelled(id: transferID)))
                return attempt == 0 ? .refused : .abandoned
            }
        }
        guard !relayControl.isCancelled, isFrontmost(target), inspection?.mayContinue() != false else {
            return attempt == 0 ? .refused : .abandoned
        }
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
struct ResponseSighting: Equatable {
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
    /// nothing. Idempotent.
    mutating func suspend(at now: TimeInterval) {
        if suspendedAt == nil { suspendedAt = now }
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

/// The wait's verdict. A completed reply's sighting travels with it, so
/// the capture that follows can tell that reply from anything said since.
enum ResponseWait: Equatable {
    case complete(ResponseSighting)
    case timedOut
    /// Cancelled, vetoed by `mayContinue`, or the destination is gone.
    case ended
}

func waitForResponse(in target: TargetApp, baseline: ResponseBaseline,
                     mayContinue: () -> Bool = { true },
                     blocked: (() -> RunBlock?)? = nil,
                     onBlock: ((RunBlock?) -> Void)? = nil,
                     onPoll: ((ResponseSighting) -> Void)? = nil) -> ResponseWait {
    log("\(target.name): waiting for response (baseline \(baseline.affordances) message affordances"
        + (baseline.lastOrdinal.map { ", message \($0)" } ?? "") + ")...")
    let timeout = config.timeout
    let startedAt = ProcessInfo.processInfo.systemUptime
    var wait = ResponseWaitState(timeout: timeout, startedAt: startedAt)
    var lastSeen = ""
    var block: RunBlock?
    defer { if block != nil { onBlock?(nil) } }
    while true {
        if relayControl.isCancelled || !mayContinue() { return .ended }
        // While the window shows another conversation, what it shows is
        // not evidence about this one: no sighting is taken, and the time
        // does not count against the reply. The baseline is kept, so a
        // reply that completed out of view is seen on return.
        if let blocked {
            let now = blocked()
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
        }
        let sighting = ResponseSighting(affordances: messageAffordances(in: target).count,
                                        lastOrdinal: lastMessageOrdinal(in: target),
                                        streaming: hasStopButton(in: target))
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
