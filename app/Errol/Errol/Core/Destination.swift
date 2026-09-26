// Where a run's messages go: the window bound per side at connection, and
// whether it is still there and reachable before every operation that
// touches the app. What the window shows is not compared — the connection
// is the window, not the conversation in it, so a chat the human switches
// to inside that window is written into all the same. (The identity
// comparison that held a run on a switched conversation came out in Sep
// 2026: the drag that connects a window is there to teach where Errol
// writes, and the binding was never meant to police the conversation.)
//
// The identity is still read, to name the destination under the icon and
// in the log. The evidence is uneven across surfaces (docs/design-
// proposals/first-run-usability): a Claude chat exposes /chat/<uuid>, a
// Claude Code session /epitaxy/<id>, a fresh chat and a Cowork task only
// /new, and the ChatGPT desktop app no conversation URL at all. The pure
// parts here run over recorded fixtures in the tests; BoundDestination is
// the live face.

import AppKit
import ApplicationServices
import Foundation

// MARK: - Identity

/// What one window scan says about the conversation it shows.
struct DestinationIdentity: Equatable {
    /// The conversation's own route in the web-area URL, where the surface
    /// exposes one ("/chat/<uuid>"). Binding when present.
    var route: String?
    /// The window title as read.
    var title: String
    /// Whether the title names no conversation (the app's name, "New chat").
    var titleIsGeneric: Bool
    /// The active surface ("Chat", "Cowork", "Code"), where observable.
    var surface: String?
    /// Whether the window carries an exclusion marker (a Claude Code session).
    var excluded: Bool

    init(scan: WindowScan, selectors: AppSelectors) {
        route = scan.conversationRoute
        title = scan.title
        let trimmed = scan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleIsGeneric = trimmed.isEmpty || selectors.genericWindowTitles.contains {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        surface = surfaceName(scan, selectors: selectors)
        excluded = scan.isExcluded
    }

    init(route: String? = nil, title: String, titleIsGeneric: Bool,
         surface: String? = nil, excluded: Bool = false) {
        self.route = route
        self.title = title
        self.titleIsGeneric = titleIsGeneric
        self.surface = surface
        self.excluded = excluded
    }

    /// Whether anything here names this conversation as against another:
    /// what the details call "Continues here" rather than "New chat", and
    /// what a remembered destination is matched by.
    var isDistinct: Bool { route != nil || !titleIsGeneric }

    /// How the conversation is named to the human: its title, or the
    /// surface when the title says nothing.
    var displayName: String {
        if !titleIsGeneric { return "\u{201C}\(title)\u{201D}" }
        if let surface { return "the \(surface) conversation" }
        return "the original conversation"
    }
}

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

/// What `composerState` judged, for the debug log: the element and the way
/// it was found. A hold on a draft the human cannot see in the composer is
/// the fallback having picked some other text input, and only this line
/// says which.
func composerDescription(in target: TargetApp) -> String {
    guard let resolved = resolveInputArea(in: target) else { return "no text input in the window" }
    return "\(resolved.source.rawValue): \(describeElement(resolved.element))"
}

// MARK: - Holds

/// Why a run is standing still while it stays recoverable. Distinct from
/// the steering hold, which the human asks for, and from the outcome the
/// run ends with: a block is a condition observed in the apps, cleared by
/// the apps, and a run can stand in one while the steering editor is open.
enum RunBlock: Equatable {
    /// The side's window is minimized or behind another of the app's
    /// windows: nothing can be read from or typed into it until it shows.
    case windowHidden(side: Speaker, seen: String)
    /// The side's composer holds unsent work.
    case draft(side: Speaker, characters: Int)
    case attachments(side: Speaker, count: Int)
    /// The side is producing a reply the relay did not ask for.
    case replying(side: Speaker)
    /// The side's composer cannot be read, so it cannot be known empty.
    case composerUnreadable(side: Speaker)
    /// The side's conversation has more messages than the reply the relay
    /// waited for: something was said since.
    case historyChanged(side: Speaker)
    /// The side's app would not come to the front for the relay — a
    /// keystroke lands in the frontmost app, and the copy button writes
    /// the clipboard only from a focused window — so the human brings it
    /// forward, and the relay goes on from where it stood.
    case notInFront(side: Speaker)
    /// A dialog stands over the side's conversation — Claude's image viewer
    /// is one — and hides it from the tree: nothing can be read from or
    /// typed into it until the human closes the dialog (coveringDialog).
    /// `by` is the dialog's name, empty when it has none.
    case covered(side: Speaker, by: String)

    var side: Speaker {
        switch self {
        case .windowHidden(let side, _), .draft(let side, _), .attachments(let side, _),
             .replying(let side), .composerUnreadable(let side), .historyChanged(let side),
             .notInFront(let side), .covered(let side, _):
            return side
        }
    }

    /// A covering dialog as the lines name it: by its own name where it
    /// has one, else as a dialog — at the start of a sentence, and after
    /// "Close".
    private static func cover(_ by: String) -> (subject: String, object: String) {
        by.isEmpty ? ("A dialog", "the dialog") : ("\u{201C}\(by)\u{201D}", "\u{201C}\(by)\u{201D}")
    }

    /// The one line that says what is wrong.
    func headline(names: (chatgpt: String, claude: String)) -> String {
        let name = side == .chatgpt ? names.chatgpt : names.claude
        switch self {
        case .windowHidden: return "Paused: \(name)'s window isn't showing"
        case .draft: return "Paused: \(name) has an unsent draft"
        case .attachments: return "Paused: \(name) has an unsent attachment"
        case .replying: return "Paused: \(name) is replying to something else"
        case .composerUnreadable: return "Paused: \(name)'s composer can't be read"
        case .historyChanged: return "Paused: \(name)'s conversation moved on"
        case .notInFront: return "Paused: \(name) couldn't be brought to the front"
        case .covered: return "Paused: \(name)'s conversation is covered"
        }
    }

    /// What clears it, and that Stop is there.
    func recovery(names: (chatgpt: String, claude: String)) -> String {
        let name = side == .chatgpt ? names.chatgpt : names.claude
        switch self {
        case .windowHidden(_, let seen):
            return "It is \(seen). Bring it back to continue, or Stop. Errol resumes when it is showing again."
        case .draft(_, let characters):
            return "Finish or clear the \(characters)-character draft in \(name) to continue, or Stop."
        case .attachments(_, let count):
            return "Send or remove the \(count == 1 ? "attachment" : "\(count) attachments") in \(name) to continue, or Stop."
        case .replying:
            return "Errol waits for \(name) to finish, then continues if the conversation is unchanged. Stop is available."
        case .composerUnreadable:
            return "Click into \(name)'s message field so it can be read, or Stop."
        case .historyChanged:
            return "Messages were added in \(name) since the reply Errol was waiting for. Errol cannot tell what to relay now; Stop, or undo the change to continue."
        case .notInFront:
            return "Click \(name)'s window to bring it to the front. Errol continues once it is in front, or Stop."
        case .covered(_, let by):
            return "Close \(Self.cover(by).object) in \(name) to continue, or Stop. Errol resumes once the conversation is showing."
        }
    }

    /// Why a run does not start on this, for the failed-start report: the
    /// condition and what to do before pressing Send again.
    func startRefusal(name: String) -> String {
        switch self {
        case .windowHidden(_, let seen):
            return "\(name)'s window is \(seen). Bring it back, then send again."
        case .draft(_, let characters):
            return "\(name) has an unsent draft (\(characters) characters). Finish or clear it, then send again."
        case .attachments(_, let count):
            return "\(name) has \(count) unsent attachment\(count == 1 ? "" : "s"). Send or remove \(count == 1 ? "it" : "them"), then send again."
        case .replying:
            return "\(name) is still replying. Wait for it to finish, then send again."
        case .composerUnreadable:
            return "\(name)'s message field can't be read. Click into it, then send again."
        case .historyChanged:
            return "\(name)'s conversation changed. Send again."
        case .notInFront:
            return "\(name) couldn't be brought to the front. Click its window, then send again."
        case .covered(_, let by):
            return "\(Self.cover(by).subject) is open over \(name)'s conversation. Close it, then send again."
        }
    }

    /// The log line, with the apps' own names.
    func logLine(name: String) -> String {
        switch self {
        case .windowHidden(_, let seen):
            return "Paused — \(name)'s window is \(seen). Bring it back to continue, or Stop."
        case .draft(_, let characters):
            return "Paused — \(name) has an unsent draft (\(characters) characters). Finish or clear it to continue, or Stop."
        case .attachments(_, let count):
            return "Paused — \(name) has \(count) unsent attachment\(count == 1 ? "" : "s"). Send or remove \(count == 1 ? "it" : "them") to continue, or Stop."
        case .replying:
            return "Paused — \(name) is replying to something the relay did not send; waiting for it to finish."
        case .composerUnreadable:
            return "Paused — \(name)'s composer cannot be read, so it cannot be known to be empty."
        case .historyChanged:
            return "Paused — \(name)'s conversation has messages the relay did not expect since its reply completed."
        case .notInFront:
            return "Paused — \(name) would not come to the front. Click its window to bring it forward; the relay continues from there, or Stop."
        case .covered(_, let by):
            return "Paused — \(Self.cover(by).subject) is open over \(name)'s conversation, which hides it from Errol. Close it to continue, or Stop."
        }
    }
}

/// The composer's state as a block on delivering to `side`, nil when it
/// admits a paste.
func deliveryBlock(for state: ComposerState, side: Speaker) -> RunBlock? {
    switch state {
    case .empty: return nil
    case .draft(let characters): return .draft(side: side, characters: characters)
    case .attachments(let count): return .attachments(side: side, count: count)
    case .replying: return .replying(side: side)
    case .unreadable: return .composerUnreadable(side: side)
    case .covered(let by): return .covered(side: side, by: by)
    }
}

// MARK: - The live binding

/// One side's destination for the length of a run: the window chosen at
/// connection, checked again on demand for being there and reachable, and
/// the identity read from it then, which names it under the icon and in
/// the log. A check is a few attribute reads on the bound window, so
/// callers poll it at the pace of the operation they guard, not in a
/// tight loop.
final class BoundDestination {
    /// The app, with every finder scoped to the bound window.
    let target: TargetApp
    let window: AXUIElement
    /// What the window showed when it was connected. Never compared
    /// against the window since: the connection is the window.
    let identity: DestinationIdentity

    /// What a check found. Minimized is waited for; gone ends the run.
    enum Check: Equatable {
        case same
        /// The window is there but not where a copy or a paste can reach
        /// it, described for the hold line ("minimized").
        case hidden(String)
        /// The app quit or the bound window closed: nothing to return to.
        case lost(String)
    }

    /// Bind `window` — the one the human chose, or the one a run found.
    init(target: TargetApp, window: AXUIElement) {
        self.target = target.bound(to: window)
        self.window = window
        identity = DestinationIdentity(scan: scanWindow(LiveElement(ax: window), selectors: target.selectors),
                                       selectors: target.selectors)
    }

    /// Bind the window the finders would pick: the path for a run started
    /// without setup (the harness), and for a target already bound.
    convenience init?(target: TargetApp) {
        guard let window = chatWindow(in: target) else { return nil }
        self.init(target: target, window: window)
    }

    /// Whether the bound window is still there and reachable. What it
    /// shows is not looked at.
    func check() -> Check {
        if target.app.isTerminated { return .lost("\(target.name) quit") }
        // A window the app has torn down answers invalidUIElement to every
        // read; one that merely lost its place in the list is still there.
        let role = axAttributeResult(window, kAXRoleAttribute)
        if role.error == .invalidUIElement { return .lost("the \(target.name) window closed") }
        if (axAttribute(window, kAXMinimizedAttribute) as? Bool) == true {
            return .hidden("minimized")
        }
        return .same
    }

    /// Whether the app's focused window is this one — the window a
    /// keystroke lands in once the app is frontmost. With `raising`, the
    /// window is brought to the front of the app's windows first and given
    /// a moment to get there; a reorder inside the app moves nobody's
    /// focus, so this is safe outside a focus operation. An app that does
    /// not answer for its focused window is taken at its word.
    func isFrontWindow(raising: Bool) -> Bool {
        func focusedIsBound() -> Bool {
            guard let focused = axAttribute(target.ax, kAXFocusedWindowAttribute),
                  CFGetTypeID(focused) == AXUIElementGetTypeID() else { return true }
            return CFEqual(focused, window)
        }
        if focusedIsBound() { return true }
        guard raising else { return false }
        raiseWindow(window)
        for _ in 0..<5 {
            usleep(100_000)
            if focusedIsBound() { return true }
        }
        return false
    }

    /// The check as a hold on `side`, nil while the window is reachable.
    /// A lost window is not a hold; the caller ends the run on it. With
    /// `raising`, the window must also be the app's front window, raised
    /// where it can be: the delivery gate's version, since a paste follows
    /// the key window.
    func block(side: Speaker, raising: Bool = false) -> RunBlock? {
        if case .hidden(let seen) = check() {
            return .windowHidden(side: side, seen: seen)
        }
        if raising, !isFrontWindow(raising: true) {
            return .windowHidden(side: side, seen: "behind another \(target.name) window")
        }
        return nil
    }

    /// The log line at binding: which window is being written into, named
    /// by what it showed when it was connected.
    var bindingReport: String {
        var line = "\(target.name): targeting \(identity.displayName)"
        if let surface = identity.surface { line += " (\(surface))" }
        if let route = identity.route { line += ", \(route)" }
        return line
    }
}
