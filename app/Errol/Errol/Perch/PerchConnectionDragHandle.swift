import AppKit
import SwiftUI

/// Mouse tracking continues outside the panel, while a plain click is
/// handed back through `onClick` — the icon's own action, since this view
/// covers the icon and takes the mouse it would have had. The SwiftUI
/// button beneath retains keyboard and VoiceOver activation. No pasteboard
/// item or external drop is created: the drop resolves against the areas
/// Errol draws over the message fields (SetupController), never against
/// the app under the pointer.
struct PerchConnectionDragHandle: NSViewRepresentable {
    let setup: SetupController
    let side: Speaker
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> ConnectionHandleView {
        let view = ConnectionHandleView()
        view.setup = setup
        view.side = side
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: ConnectionHandleView, context: Context) {
        view.setup = setup
        view.side = side
        view.onClick = onClick
    }

    static func dismantleNSView(_ view: ConnectionHandleView, coordinator: ()) {
        view.cancelTracking()
    }
}

final class ConnectionHandleView: NSView {
    weak var setup: SetupController?
    var side = Speaker.chatgpt
    var onClick: (() -> Void)?
    private var origin: CGPoint?
    private var dragging = false
    private var cursorPushed = false

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        origin = NSEvent.mouseLocation
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin else { return }
        let point = NSEvent.mouseLocation
        if !dragging {
            guard hypot(point.x - origin.x, point.y - origin.y) >= 4 else { return }
            dragging = true
            setup?.beginDragging(side, from: iconFrame)
            NSCursor.closedHand.push()
            cursorPushed = true
        }
        setup?.updateDrag(at: axPoint(point), overConsole: isOverConsole(point))
    }

    override func mouseUp(with event: NSEvent) {
        guard origin != nil else { return }
        origin = nil
        if dragging {
            dragging = false
            releaseCursor()
            let point = NSEvent.mouseLocation
            setup?.endDragging(at: axPoint(point), overConsole: isOverConsole(point))
        } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    func cancelTracking() {
        if setup?.draggingSide == side { setup?.cancelDragging() }
        origin = nil
        dragging = false
        releaseCursor()
    }

    /// The pointer in AX coordinates, which the drawn areas use.
    private func axPoint(_ point: CGPoint) -> CGPoint {
        axRect(CGRect(origin: point, size: .zero)).origin
    }

    /// The icon on screen (AX coordinates): this view covers it, and the
    /// lead leaves its edge.
    private var iconFrame: CGRect {
        let inWindow = convert(bounds, to: nil)
        return axRect(window?.convertToScreen(inWindow) ?? inWindow)
    }

    /// Whether the pointer (Cocoa coordinates) is over the console. The
    /// drawn areas sit a level under it, so a release there is the icon
    /// put back, not a drop on whatever the console covers.
    private func isOverConsole(_ point: CGPoint) -> Bool {
        window?.frame.contains(point) ?? false
    }

    private func releaseCursor() {
        if cursorPushed { NSCursor.pop() }
        cursorPushed = false
    }
}
