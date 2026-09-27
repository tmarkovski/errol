// A bounded claim on the pasteboard for one operation. The relay copies
// with the app's own copy button and delivers with Cmd+V, so it owns the
// clipboard twice a turn — and the human, who may be working in another
// app during a long run, owns it the rest of the time. The lease keeps
// the two apart: what was there before the operation is captured, the
// operation's own write is remembered by change count, and at release the
// capture goes back only if the clipboard still holds that write. A copy
// the human made in between is theirs and stays.
//
// The capture keeps every item and every representation, so a rich copy
// (an image with a file promise, styled text with its plain fallback)
// comes back whole; a representation that cannot be read, or a capture
// past the byte limit, marks the capture incomplete, and an incomplete
// capture is never put back in part.

import AppKit

final class ClipboardLease {
    /// What releasing the lease did.
    enum Release: Equatable {
        /// The capture is back on the clipboard.
        case restored
        /// Something else was written since the lease's own write; it stays.
        case preservedNewer
        /// The lease never wrote, so there is nothing to undo.
        case nothingOwned
        /// The capture was incomplete, so the lease's write is left in place
        /// rather than half of what was there before.
        case leftInPlace(reason: String)
    }

    private let pasteboard: NSPasteboard
    private let capture: [[NSPasteboard.PasteboardType: Data]]
    private let captureComplete: Bool
    private let captureReason: String?
    private var owned: Int?
    private var released = false

    /// Capture the clipboard as it stands. `byteLimit` bounds what is kept
    /// in memory: a capture past it is incomplete, not truncated.
    init(_ pasteboard: NSPasteboard = .general, byteLimit: Int = 32 << 20) {
        self.pasteboard = pasteboard
        var complete = true
        var reason: String?
        var bytes = 0
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    complete = false
                    reason = "a \(type.rawValue) representation could not be read"
                    continue
                }
                bytes += data.count
                if bytes > byteLimit {
                    complete = false
                    reason = "the earlier contents exceed \(byteLimit >> 20) MB"
                    break
                }
                representations[type] = data
            }
            items.append(representations)
        }
        capture = items
        captureComplete = complete
        captureReason = reason
    }

    /// Write `text` as the clipboard's only content and take ownership.
    func write(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        owned = pasteboard.changeCount
    }

    /// Take ownership of a write someone else made on the lease's behalf —
    /// an app's copy button, pressed by the relay — as the clipboard stands
    /// now.
    func claim() {
        owned = pasteboard.changeCount
    }

    /// Whether the clipboard still holds the lease's write: nothing has
    /// been written since.
    var isOwned: Bool {
        guard let owned else { return false }
        return pasteboard.changeCount == owned
    }

    /// The lease's write as text, while it still owns the clipboard.
    var text: String? {
        isOwned ? pasteboard.string(forType: .string) : nil
    }

    /// Put the capture back if the clipboard still holds the lease's own
    /// write; leave a newer write alone. Idempotent: a second release does
    /// nothing.
    @discardableResult
    func release() -> Release {
        guard !released else { return .nothingOwned }
        released = true
        guard owned != nil else { return .nothingOwned }
        guard isOwned else { return .preservedNewer }
        guard captureComplete else {
            return .leftInPlace(reason: captureReason ?? "the earlier contents could not be captured whole")
        }
        put(capture)
        return .restored
    }

    /// Put the capture back whatever has happened since — the verification
    /// harness's whole-case restore, made with hands off the keyboard.
    /// Returns whether the clipboard now matches the capture.
    @discardableResult
    func restore() -> Bool {
        released = true
        put(capture)
        let actual = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        return captureComplete && actual == capture
    }

    private func put(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        pasteboard.clearContents()
        let restored = items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { _ = pasteboard.writeObjects(restored) }
    }
}
