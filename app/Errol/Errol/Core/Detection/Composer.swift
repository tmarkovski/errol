// What a side's composer holds before a paste: read from the chosen window
// the way the paste resolves it, and classified pure for ComposerStateTests.

import ApplicationServices
import Foundation

// MARK: - The composer

/// What the composer holds, as far as it can be read. Only `.empty` admits
/// a paste: a draft or an attachment is the human's unsent work, a reply
/// underway means the conversation is busy with something else, and a
/// value that cannot be read establishes nothing.
enum ComposerState: Equatable {
    case empty
    case draft(characters: Int)
    case attachments(Int)
    case replying
    case unreadable
    /// Out of the tree because a dialog stands over the conversation
    /// (coveringDialog), named as the dialog names itself: unreadable, with
    /// the one thing that makes it readable again.
    case covered(by: String)

    var isEmpty: Bool { self == .empty }
    var isCovered: Bool {
        if case .covered = self { return true }
        return false
    }
}

/// The classification, pure. A composer's empty value is not always empty
/// text: Claude's reads as a bare newline, ChatGPT's as its placeholder
/// (both from live captures), so whitespace and the known placeholders —
/// the shared list, or the element's own label, which is where the apps
/// keep the placeholder — count as empty. A whitespace-only draft is
/// therefore read as empty too; it is indistinguishable from Claude's
/// idle composer.
func classifyComposer(value: String?, label: String, attachments: Int, replying: Bool) -> ComposerState {
    if replying { return .replying }
    guard let value else { return .unreadable }
    if attachments > 0 { return .attachments(attachments) }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || composerPlaceholders.contains(trimmed) { return .empty }
    if !label.isEmpty, label.localizedCaseInsensitiveContains(trimmed) { return .empty }
    return .draft(characters: trimmed.count)
}

/// The composer's state in the target's chosen window, read now. The
/// element is resolved the way the paste resolves it, so what is judged is
/// what would be pasted into. A composer that is not there is looked for
/// under a dialog before it is called unreadable.
func composerState(in target: TargetApp) -> ComposerState {
    guard let input = inputArea(in: target) else {
        return coveringDialogName(in: target).map { .covered(by: $0) } ?? .unreadable
    }
    let value = axAttribute(input, kAXValueAttribute) as? String
    let attachments = pastedTextAttachmentCount(around: input, selectors: target.selectors)
    return classifyComposer(value: value, label: axLabel(input), attachments: attachments,
                            replying: hasStopButton(in: target))
}

/// The same judgment for a window the readiness sweep has just scanned:
/// the composer, its value and the precise attachment count are still read
/// live, the way `composerState(in:)` reads them, but whether a reply is
/// underway and which dialog covers the window come from `scan`, whose walk
/// already found them (scanWindow checks the same Stop button and the same
/// dialog), so the window is not walked twice in one sweep. The order is
/// the live one's: covered or unreadable only when no composer resolves.
func composerState(in target: TargetApp, scan: WindowScan) -> ComposerState {
    guard let input = inputArea(in: target) else {
        return scan.coveredBy.map { .covered(by: $0) } ?? .unreadable
    }
    let value = axAttribute(input, kAXValueAttribute) as? String
    let attachments = pastedTextAttachmentCount(around: input, selectors: target.selectors)
    return classifyComposer(value: value, label: axLabel(input), attachments: attachments,
                            replying: scan.isReplying)
}

/// What `composerState` judged, for the debug log: the element and the way
/// it was found. A hold on a draft the human cannot see in the composer is
/// the fallback having picked some other text input, and only this line
/// says which.
func composerDescription(in target: TargetApp) -> String {
    guard let resolved = resolveInputArea(in: target) else { return "no text input in the window" }
    return "\(resolved.source.rawValue): \(describeElement(resolved.element))"
}
