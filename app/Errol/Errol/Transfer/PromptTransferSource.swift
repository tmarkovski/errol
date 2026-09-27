import AppKit
import SwiftUI

/// The same prompt region survives topic, custom-prompt, and steering states.
/// Read its current screen position at launch, without replacing the editor.
/// A side's icon is read the same way, for the replies that set off from
/// it (RelayController.iconTransferSources).
final class PromptTransferSource {
    weak var view: NSView?

    func anchor() -> TransferAnchor? {
        guard let view, let window = view.window,
              window.isVisible, window.isOnActiveSpace,
              !view.isHiddenOrHasHiddenAncestor, window.windowNumber > 0 else { return nil }
        // Non-clipping AppKit views can report their parent's visible region.
        // Keep the launch point inside the actual prompt, not the whole panel.
        let visible = view.visibleRect.intersection(view.bounds)
        guard !visible.isEmpty else { return nil }
        let frame = window.convertToScreen(view.convert(visible, to: nil))
        return TransferAnchor(frame: axRect(frame), window: axRect(window.frame),
                              pid: ProcessInfo.processInfo.processIdentifier,
                              windowID: CGWindowID(window.windowNumber))
    }
}

/// A passive background view gives AppKit the prompt's real bounds, including
/// panel dragging and layout changes; it never accepts a click or focus.
struct PromptTransferProbe: NSViewRepresentable {
    let source: PromptTransferSource

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        source.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        source.view = view
    }
}
