// Where a run's messages go, and whether that is still what the window is
// showing. A relay run binds one destination per side at Start — the
// window, and whatever identifies the conversation in it — and checks it
// again before every operation that touches the app, so a conversation the
// human switched away from is waited for rather than written into.
//
// The evidence is uneven across surfaces (docs/design-proposals/
// first-run-usability): a Claude chat exposes /chat/<uuid>, a Claude Code
// session /epitaxy/<id>, a fresh chat and a Cowork task only /new, and the
// ChatGPT desktop app no conversation URL at all. So identity comes in
// grades — a route, a title, or nothing — and the comparison says how
// sure it is. The pure parts here run over recorded fixtures in the tests;
// BoundDestination is the live face.

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

    /// Whether anything here tells this conversation from another in the
    /// same window and surface. Without it, a switch to another unnamed
    /// conversation cannot be seen, and the run says so at binding.
    var isDistinct: Bool { route != nil || !titleIsGeneric }

    /// How the conversation is named to the human: its title, or the
    /// surface when the title says nothing.
    var displayName: String {
        if !titleIsGeneric { return "\u{201C}\(title)\u{201D}" }
        if let surface { return "the \(surface) conversation" }
        return "the original conversation"
    }
}

/// What comparing the bound identity with the window's current one found.
enum DestinationVerdict: Equatable {
    /// The window shows the bound conversation.
    case same
    /// The window shows what is the bound conversation now: a fresh chat
    /// that gained its route or its name after the opening message. The
    /// binding takes the new identity.
    case adopted(DestinationIdentity)
    /// The window shows something else, described for the hold message.
    case changed(String)
}

/// The comparison, pure. `adoptionOpen` is whether the side is still
/// between its first message and its first captured reply — the interval
/// in which a fresh chat acquires a route (Claude) and a name. A route,
/// once bound, is binding; a specific title is a hint that holds until
/// the route says otherwise; a generic title is nothing to compare.
func compareDestination(bound: DestinationIdentity, now: DestinationIdentity,
                        adoptionOpen: Bool, selectors: AppSelectors) -> DestinationVerdict {
    if now.excluded != bound.excluded {
        if now.excluded {
            return .changed("now showing a \(selectors.excludedSurfaceName ?? "non-chat") session")
        }
        return .changed("no longer showing the \(selectors.excludedSurfaceName ?? "non-chat") session")
    }
    // Surface names flap on their own between a chat's tab pair and its
    // URL ("Chat" from the tab, "New chat" from /new once the tabs unmount),
    // so only two named, settled surfaces are compared.
    let newChat = selectors.surfacePathNames["new"]
    if let before = bound.surface, let after = now.surface,
       before != newChat, after != newChat, before != after {
        return .changed("switched to \(after)")
    }
    if let boundRoute = bound.route {
        if now.route == boundRoute { return .same }
        if now.route == nil { return .changed("showing a new chat") }
        return .changed(now.titleIsGeneric ? "showing another conversation"
                                           : "showing \u{201C}\(now.title)\u{201D}")
    }
    if now.route != nil {
        guard adoptionOpen else {
            return .changed(now.titleIsGeneric ? "showing another conversation"
                                               : "showing \u{201C}\(now.title)\u{201D}")
        }
        return .adopted(now)
    }
    // Neither has a route: titles are all there is.
    if bound.titleIsGeneric {
        // An unnamed chat being named is expected progress at any time —
        // naming lags the first exchange by an unpredictable while.
        return now.titleIsGeneric ? .same : .adopted(now)
    }
    if now.title == bound.title { return .same }
    return .changed(now.titleIsGeneric ? "showing a new chat"
                                       : "showing \u{201C}\(now.title)\u{201D}")
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

    var isEmpty: Bool { self == .empty }
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
/// what would be pasted into.
func composerState(in target: TargetApp) -> ComposerState {
    guard let input = inputArea(in: target) else { return .unreadable }
    let value = axAttribute(input, kAXValueAttribute) as? String
    let attachments = pastedTextAttachmentCount(around: input, selectors: target.selectors)
    return classifyComposer(value: value, label: axLabel(input), attachments: attachments,
                            replying: hasStopButton(in: target))
}

// MARK: - Holds

/// Why a run is standing still while it stays recoverable. Distinct from
/// the steering hold, which the human asks for, and from the outcome the
/// run ends with: a block is a condition observed in the apps, cleared by
/// the apps, and a run can stand in one while the steering editor is open.
enum RunBlock: Equatable {
    /// The side's window no longer shows the bound conversation.
    case destinationChanged(side: Speaker, bound: String, seen: String)
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

    var side: Speaker {
        switch self {
        case .destinationChanged(let side, _, _), .draft(let side, _), .attachments(let side, _),
             .replying(let side), .composerUnreadable(let side), .historyChanged(let side):
            return side
        }
    }

    /// The one line that says what is wrong.
    func headline(names: (chatgpt: String, claude: String)) -> String {
        let name = side == .chatgpt ? names.chatgpt : names.claude
        switch self {
        case .destinationChanged: return "Paused: \(name)'s conversation changed"
        case .draft: return "Paused: \(name) has an unsent draft"
        case .attachments: return "Paused: \(name) has an unsent attachment"
        case .replying: return "Paused: \(name) is replying to something else"
        case .composerUnreadable: return "Paused: \(name)'s composer can't be read"
        case .historyChanged: return "Paused: \(name)'s conversation moved on"
        }
    }

    /// What clears it, and that Stop is there.
    func recovery(names: (chatgpt: String, claude: String)) -> String {
        let name = side == .chatgpt ? names.chatgpt : names.claude
        switch self {
        case .destinationChanged(_, let bound, let seen):
            return "It is \(seen). Return to \(bound) to continue, or Stop. Errol resumes when it is showing again."
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
        }
    }

    /// Why a run does not start on this, for the failed-start report: the
    /// condition and what to do before pressing Send again.
    func startRefusal(name: String) -> String {
        switch self {
        case .destinationChanged(_, _, let seen):
            return "\(name) is \(seen). Show the conversation to relay into, then send again."
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
        }
    }

    /// The log line, with the apps' own names.
    func logLine(name: String) -> String {
        switch self {
        case .destinationChanged(_, let bound, let seen):
            return "Paused — \(name)'s conversation changed: \(seen). Return to \(bound) to continue, or Stop."
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
    }
}

// MARK: - The live binding

/// One side's destination for the length of a run: the window chosen at
/// Start and the identity read from it, checked again on demand. A check
/// is one window-list read and one scan of the bound window — the same
/// walk the readiness strip makes — so callers poll it at the pace of the
/// operation they guard, not in a tight loop.
final class BoundDestination {
    /// The app, with every finder scoped to the bound window.
    let target: TargetApp
    let window: AXUIElement
    // The identity is read by the readiness sweep between setup and a
    // run and by the run itself, and adoption rewrites it; one lock
    // covers both fields.
    private let lock = NSLock()
    private var boundIdentity: DestinationIdentity
    private var adoptionIsOpen = true

    var identity: DestinationIdentity {
        lock.lock()
        defer { lock.unlock() }
        return boundIdentity
    }

    /// Open until the side's first reply has been captured: the interval
    /// in which a fresh chat acquires its route and its name.
    var adoptionOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return adoptionIsOpen
    }

    /// What a check found beyond the pure verdict: the window itself gone.
    enum Check: Equatable {
        case same
        case changed(String)
        /// The app quit or the bound window closed: nothing to return to.
        case lost(String)
    }

    /// Bind `window` — the one the human chose, or the one a run found.
    init(target: TargetApp, window: AXUIElement) {
        self.target = target.bound(to: window)
        self.window = window
        boundIdentity = DestinationIdentity(scan: scanWindow(LiveElement(ax: window), selectors: target.selectors),
                                            selectors: target.selectors)
    }

    /// Bind the window the finders would pick: the path for a run started
    /// without setup (the harness), and for a target already bound.
    convenience init?(target: TargetApp) {
        guard let window = chatWindow(in: target) else { return nil }
        self.init(target: target, window: window)
    }

    /// The side has produced a reply in this conversation: from here a new
    /// route or name is navigation, not naming.
    func closeAdoption() {
        lock.lock()
        adoptionIsOpen = false
        lock.unlock()
    }

    /// Whether the bound window is still the one the relay would target,
    /// showing the bound conversation. Adoption updates `identity`.
    func check() -> Check {
        if target.app.isTerminated { return .lost("\(target.name) quit") }
        // A window the app has torn down answers invalidUIElement to every
        // read; one that merely lost its place in the list is still there.
        let role = axAttributeResult(window, kAXRoleAttribute)
        if role.error == .invalidUIElement { return .lost("the \(target.name) window closed") }
        if (axAttribute(window, kAXMinimizedAttribute) as? Bool) == true {
            return .changed("minimized")
        }
        guard let current = chatWindow(in: target) else {
            return .changed("no chat window can be found")
        }
        guard CFEqual(current, window) else {
            return .changed("another \(target.name) window is in front")
        }
        let now = DestinationIdentity(scan: scanWindow(LiveElement(ax: window), selectors: target.selectors),
                                      selectors: target.selectors)
        lock.lock()
        defer { lock.unlock() }
        switch compareDestination(bound: boundIdentity, now: now, adoptionOpen: adoptionIsOpen,
                                  selectors: target.selectors) {
        case .same:
            return .same
        case .adopted(let adopted):
            log("\(target.name): the conversation is now \(adopted.displayName)"
                + (adopted.route.map { " (\($0))" } ?? ""))
            boundIdentity = adopted
            return .same
        case .changed(let seen):
            return .changed(seen)
        }
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

    /// The check as a hold on `side`, nil while the destination holds.
    /// A lost destination is not a hold; the caller ends the run on it.
    /// With `raising`, the window must also be the app's front window,
    /// raised where it can be: the delivery gate's version, since a paste
    /// follows the key window.
    func block(side: Speaker, raising: Bool = false) -> RunBlock? {
        if case .changed(let seen) = check() {
            return .destinationChanged(side: side, bound: identity.displayName, seen: seen)
        }
        if raising, !isFrontWindow(raising: true) {
            return .destinationChanged(side: side, bound: identity.displayName,
                                       seen: "behind another \(target.name) window")
        }
        return nil
    }

    /// The log line at binding: what is being targeted, and whether it can
    /// be told from another conversation at all.
    var bindingReport: String {
        var line = "\(target.name): targeting \(identity.displayName)"
        if let surface = identity.surface { line += " (\(surface))" }
        if let route = identity.route { line += ", \(route)" }
        if !identity.isDistinct {
            line += " — this conversation exposes no name or route yet, so a switch to another unnamed one cannot be seen until it is named"
        }
        return line
    }
}
