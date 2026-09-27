// Recognizing a paste in a composer that rewrites it: the needle, the receipt,
// when a retry is safe, and the snapshot logged when nothing matched.

import AppKit
import ApplicationServices

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
