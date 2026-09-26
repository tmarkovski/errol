// Adapted from PermissionFlow 2.9.1 (https://github.com/jaywcjlove/PermissionFlow),
// MIT License, Copyright (c) 2026 小弟调调. See THIRD_PARTY_NOTICES.txt.
//
// The part of the permission guide that the user drags into the list.
// PermissionGuideView draws the tile and passes it in; this view hosts it
// and turns a press-and-move anywhere on it into an AppKit drag of Errol's
// bundle. System Settings only takes the drop from a real dragging session,
// and it takes one most reliably when the payload looks like a file dragged
// out of Finder, so the drag carries the bundle's URL and path under every
// type a Finder drag offers.

import AppKit
import SwiftUI

struct GuideDragArea: NSViewRepresentable {
    let appURL: URL
    let onDragStateChange: (Bool) -> Void
    let content: AnyView

    func makeNSView(context: Context) -> GuideDragSource {
        GuideDragSource(appURL: appURL, content: content, onDragStateChange: onDragStateChange)
    }

    func updateNSView(_ source: GuideDragSource, context: Context) {
        source.update(appURL: appURL, content: content, onDragStateChange: onDragStateChange)
    }

    /// The tile's own size at the width it is offered, so the area is
    /// exactly as tall as what it shows.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView source: GuideDragSource, context: Context) -> CGSize? {
        source.contentSize(forWidth: proposal.width)
    }
}

/// Hosts the tile and starts the drag. The tile is drawn by its own hosting
/// controller, which also measures it at the width SwiftUI offers. A
/// hosting view's fitting size would measure it at its widest, unwrapped
/// width instead, and a tile whose text wraps would come out too short.
final class GuideDragSource: NSView, NSDraggingSource {
    private var appURL: URL
    private var onDragStateChange: (Bool) -> Void
    private let host: NSHostingController<AnyView>
    /// Where the pointer went down, until the press ends or becomes a drag.
    private var pressLocation: NSPoint?
    private var isDragging = false

    /// How far the pointer moves before a press becomes a drag, so a plain
    /// click on the tile doesn't start one.
    private static let dragThreshold: CGFloat = 4
    /// The drag image is Errol's icon, large enough under the pointer to
    /// read as the app being carried rather than as a cursor badge.
    private static let iconSize: CGFloat = 56

    init(appURL: URL, content: AnyView, onDragStateChange: @escaping (Bool) -> Void) {
        self.appURL = appURL
        self.onDragStateChange = onDragStateChange
        host = NSHostingController(rootView: Self.hosted(content))
        // The area's size comes from sizeThatFits above; the hosted view
        // just fills it.
        host.sizingOptions = []
        super.init(frame: .zero)
        host.view.frame = bounds
        host.view.autoresizingMask = [.width, .height]
        addSubview(host.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(appURL: URL, content: AnyView, onDragStateChange: @escaping (Bool) -> Void) {
        self.appURL = appURL
        self.onDragStateChange = onDragStateChange
        host.rootView = Self.hosted(content)
    }

    /// The tile's size at the offered width, at its own height. No width
    /// means SwiftUI is asking for the tile's ideal size, which a tile that
    /// stretches to any width doesn't have; SwiftUI's default answer
    /// stands in then.
    func contentSize(forWidth width: CGFloat?) -> CGSize? {
        let fitted = host.sizeThatFits(in: CGSize(width: width ?? .infinity, height: .infinity))
        guard width != nil || fitted.width.isFinite else { return nil }
        return fitted
    }

    /// The tile only shows, so every press on it belongs to the drag. It
    /// keeps its own height whatever height it is offered.
    private static func hosted(_ content: AnyView) -> AnyView {
        AnyView(content
            .allowsHitTesting(false)
            .fixedSize(horizontal: false, vertical: true))
    }

    // MARK: Pressing and dragging

    /// Claims every point inside the area, so the hosted tile never sees
    /// the press.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    /// The guide's panel belongs to an app in the background, so the first
    /// press on it has to count, or the drag would take two tries.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressLocation = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let pressLocation else { return }
        let location = convert(event.locationInWindow, from: nil)
        guard hypot(location.x - pressLocation.x, location.y - pressLocation.y) > Self.dragThreshold else { return }
        isDragging = true
        beginDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        pressLocation = nil
        isDragging = false
    }

    /// Drags Errol's bundle with its icon under the pointer. A cancelled or
    /// refused drag slides the icon back to the tile.
    private func beginDrag(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: AppBundlePasteboardWriter(url: appURL))
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: Self.iconSize, height: Self.iconSize)
        let location = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: location.x - Self.iconSize / 2, y: location.y - Self.iconSize / 2,
                                     width: Self.iconSize, height: Self.iconSize),
                              contents: icon)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }

    // MARK: NSDraggingSource

    /// Adding an app to the list copies a reference to it; nothing moves.
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    /// Holding Option or Command mustn't turn the drag into something the
    /// list refuses.
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragStateChange(true)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragStateChange(false)
        pressLocation = nil
        isDragging = false
    }
}

/// Writes the bundle to the drag pasteboard the way a Finder drag does: as
/// a file URL, a plain URL, the older list of file names, a promised file
/// URL, and a path string.
private final class AppBundlePasteboardWriter: NSObject, NSPasteboardWriting {
    private let url: URL

    private static let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private static let promisedFileURL = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")

    init(url: URL) {
        self.url = url
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, Self.filenames, Self.promisedFileURL, .string]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL, .URL, Self.promisedFileURL: url.absoluteString
        case Self.filenames: [url.path]
        case .string: url.path
        default: nil
        }
    }
}
