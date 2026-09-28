import AppKit
import SwiftUI

/// Turns any NSView in the console into a TransferAnchor: its current screen
/// position, read at launch. RelayController keeps one for the prompt, whose
/// region survives topic, custom-prompt, and steering states and is read
/// without replacing the editor, and one for each side's icon, where that
/// side's replies set off from (RelayController.iconTransferSources).
final class TransferAnchorSource {
    weak var view: NSView?

    func anchor() -> TransferAnchor? {
        guard let view, let window = view.window,
              window.isVisible, window.isOnActiveSpace,
              !view.isHiddenOrHasHiddenAncestor, window.windowNumber > 0 else { return nil }
        // Non-clipping AppKit views can report their parent's visible region.
        // Keep the launch point inside the actual view (the prompt, an icon),
        // not the whole panel.
        let visible = view.visibleRect.intersection(view.bounds)
        guard !visible.isEmpty else { return nil }
        let frame = window.convertToScreen(view.convert(visible, to: nil))
        return TransferAnchor(frame: axRect(frame), window: axRect(window.frame),
                              pid: ProcessInfo.processInfo.processIdentifier,
                              windowID: CGWindowID(window.windowNumber))
    }
}

/// A passive background view gives AppKit the real bounds of what it sits
/// behind (the prompt, a side's icon), including panel dragging and layout
/// changes; it never accepts a click or focus.
struct TransferAnchorProbe: NSViewRepresentable {
    let source: TransferAnchorSource

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        source.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        source.view = view
    }
}
