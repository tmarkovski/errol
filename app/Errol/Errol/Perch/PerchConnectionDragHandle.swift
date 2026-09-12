import AppKit
import SwiftUI

/// Mouse tracking continues outside the panel, while a normal click still
/// opens the picker. The SwiftUI button beneath retains keyboard and
/// VoiceOver activation. No pasteboard item or external drop is created.
struct PerchConnectionDragHandle: NSViewRepresentable {
    let setup: SetupController
    let side: Speaker

    func makeNSView(context: Context) -> ConnectionHandleView {
        let view = ConnectionHandleView()
        view.setup = setup
        view.side = side
        return view
    }

    func updateNSView(_ view: ConnectionHandleView, context: Context) {
        view.setup = setup
        view.side = side
    }

    static func dismantleNSView(_ view: ConnectionHandleView, coordinator: ()) {
        view.cancelTracking()
    }
}

final class ConnectionHandleView: NSView {
    weak var setup: SetupController?
    var side = Speaker.chatgpt
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
            setup?.beginDragging(side)
            NSCursor.closedHand.push()
            cursorPushed = true
        }
        setup?.updateDrag(at: axRect(CGRect(origin: point, size: .zero)).origin)
    }

    override func mouseUp(with event: NSEvent) {
        guard origin != nil else { return }
        origin = nil
        if dragging {
            dragging = false
            releaseCursor()
            setup?.endDragging(at: axRect(CGRect(origin: NSEvent.mouseLocation, size: .zero)).origin)
        } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
            setup?.beginPicking(side)
        }
    }

    func cancelTracking() {
        if setup?.draggingSide == side { setup?.cancelDragging() }
        origin = nil
        dragging = false
        releaseCursor()
    }

    private func releaseCursor() {
        if cursorPushed { NSCursor.pop() }
        cursorPushed = false
    }
}
