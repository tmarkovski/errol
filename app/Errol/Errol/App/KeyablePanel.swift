// The console's window kinds, apart from the shell that places them: the
// panel that takes the keyboard without activating Errol, and the hosting
// view that acts on the first click.

import AppKit
import SwiftUI

/// NSPanel refuses key status in some non-activating configurations, which
/// would make the instruction field untypeable; force it. Esc hides the
/// panel instead of beeping.
final class KeyablePanel: NSPanel {
    /// Fires on every path the panel appears or disappears through — toggle,
    /// Esc, the close button — so the readiness scanner tracks visibility.
    var onVisibilityChange: ((Bool) -> Void)?
    /// A window that handles Escape itself, like the transcript sending it
    /// back to the console, returns true; otherwise Escape hides the panel.
    var onCancel: (() -> Bool)?

    var permitsKey: (() -> Bool)?
    override var canBecomeKey: Bool { permitsKey?() ?? true }
    override func cancelOperation(_ sender: Any?) {
        if onCancel?() != true { orderOut(nil) }
    }
    /// Every close path — the title bar's close button, Cmd+W, a menu Close
    /// — puts the console away rather than tearing it down. Errol is a
    /// menu-bar app: the window going away is the app going quiet in the
    /// status item, and the process only ends through Quit in that item's
    /// menu.
    override func performClose(_ sender: Any?) { orderOut(nil) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Borderless windows have no standard Close item of their own.
        if !styleMask.contains(.titled),
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        invalidateShadow()
        onVisibilityChange?(true)
    }
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        onVisibilityChange?(false)
    }
    override func close() {
        super.close()
        onVisibilityChange?(false)
    }
}

/// The panel floats over the chat apps without taking their focus, so most
/// clicks land on a window that is not key — and AppKit spends the first
/// click on a window like that activating it, never delivering it to the
/// content. That is why the console had to be clicked once before it could
/// be dragged or pressed. Claiming the click makes it behave like the
/// floating palette it is: the first one acts, wherever it lands.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
