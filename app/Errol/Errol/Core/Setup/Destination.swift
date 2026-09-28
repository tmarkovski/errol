// Where a run's messages go: the window bound per side at connection, and
// whether it is still there and reachable before every operation that
// touches the app. What the window shows is not compared — the connection
// is the window, not the conversation in it, so a chat the human switches
// to inside that window is written into all the same. (The identity
// comparison that held a run on a switched conversation came out in Sep
// 2026: the planned drag that connects a window is meant to teach where
// Errol writes, and the binding was never meant to police the conversation.)
//
// The identity is still read, to name the window in the chooser an app
// with several windows offers, and in the log. The evidence is uneven
// across surfaces (docs/design-proposals/first-run-usability): a Claude
// chat exposes /chat/<uuid>, a Claude Code session /epitaxy/<id>, a fresh
// chat and a Cowork task only /new, and the ChatGPT desktop app no
// conversation URL at all. The pure
// parts here run over recorded fixtures in the tests; BoundDestination is
// the live face.

import AppKit
import ApplicationServices
import Foundation

// MARK: - Identity

/// What one window scan says about the conversation it shows.
struct DestinationIdentity: Equatable {
    /// The conversation's own route in the web-area URL, where the surface
    /// exposes one ("/chat/<uuid>"). Named in the log's targeting line and
    /// not compared, since the identity comparison came out in Sep 2026.
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
    /// a route, or a title that is not the app's own name or a placeholder.
    /// Evidence only; it says nothing of whether the chat is new.
    var isDistinct: Bool { route != nil || !titleIsGeneric }

    /// How the conversation is named to the human: its title, or the
    /// surface when the title says nothing.
    var displayName: String {
        if !titleIsGeneric { return "\u{201C}\(title)\u{201D}" }
        if let surface { return "the \(surface) conversation" }
        return "the original conversation"
    }
}

// MARK: - The live binding

/// One side's destination for the length of a run: the window chosen at
/// connection, checked again on demand for being there and reachable, and
/// the identity read from it then, which names it in the console and in
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
        // A window that merely lost its place in the list is still there.
        if !windowIsAlive(window) { return .lost("the \(target.name) window closed") }
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
