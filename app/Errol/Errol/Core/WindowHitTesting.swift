// Where a dragged icon can be dropped to connect a window: the area drawn
// over the window's message field once its app has been brought forward
// under the console. The geometry is pure — the window server's on-screen
// list in, the areas out — so the overlap rules run in the tests; only
// the last function reads the list.

import CoreGraphics
import Foundation

/// An on-screen window as the window server lists it, in AX coordinates.
/// Errol's own panels sit above the ordinary layer and are never listed.
struct WindowHitRegion: Equatable {
    let number: UInt32
    let owner: Int32
    let frame: CGRect
}

/// One window a dragged icon could connect: its frame, and where its
/// message field was found, as the transfer outline finds it — the prompt
/// shell where the layout is recognized, else the editor, else nothing.
struct ConnectionDropCandidate: Equatable {
    let window: WindowID
    let frame: CGRect
    let prompt: CGRect?
}

/// The area drawn for one window: over its message field, or over the
/// whole window when the field's geometry could not be read.
struct ConnectionDropZone: Equatable {
    let window: WindowID
    let frame: CGRect
    let marksPrompt: Bool
}

/// The areas the candidates offer, front to back in the window server's
/// order. A window the server does not list — minimized, hidden, on
/// another Space — has none. Nor has one whose area another window in
/// front overlaps: the area is drawn above every ordinary window, so it
/// would float over whatever covers it, and a drop there would connect a
/// window the human cannot see. Windows that merely touch, side by side,
/// cover nothing.
func dropZones(for candidates: [ConnectionDropCandidate], owner: Int32,
               onScreen: [WindowHitRegion]) -> [ConnectionDropZone] {
    var zones: [(order: Int, zone: ConnectionDropZone)] = []
    for candidate in candidates {
        guard let position = onScreen.firstIndex(where: {
            $0.owner == owner && $0.frame.nearlyEquals(candidate.frame)
        }) else { continue }
        let area = candidate.prompt ?? candidate.frame
        let inner = area.insetBy(dx: 2, dy: 2)
        guard !onScreen[..<position].contains(where: { $0.frame.intersects(inner) }) else { continue }
        zones.append((position, ConnectionDropZone(window: candidate.window, frame: area,
                                                   marksPrompt: candidate.prompt != nil)))
    }
    return zones.sorted { $0.order < $1.order }.map(\.zone)
}

/// The area under the pointer: the front one, where areas overlap.
func dropZone(at point: CGPoint, among zones: [ConnectionDropZone]) -> ConnectionDropZone? {
    zones.first { $0.frame.contains(point) }
}

/// Every ordinary window on the active Space that is neither minimized nor
/// hidden, front to back, in the top-left coordinates AX reports.
func onScreenWindowRegions() -> [WindowHitRegion] {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { return [] }
    return info.compactMap { window in
        guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
              let number = window[kCGWindowNumber as String] as? UInt32,
              let owner = window[kCGWindowOwnerPID as String] as? Int32,
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return WindowHitRegion(number: number, owner: owner, frame: frame)
    }
}

private extension CGRect {
    /// Equal to within the rounding between the AX and window-server
    /// coordinate spaces.
    func nearlyEquals(_ other: CGRect) -> Bool {
        abs(minX - other.minX) < 2 && abs(minY - other.minY) < 2
            && abs(width - other.width) < 2 && abs(height - other.height) < 2
    }
}
