// The window server's on-screen list, in AX coordinates: what the
// transfer overlay checks a receiving window against before it draws over
// it (TransferFeedback.swift).

import CoreGraphics
import Foundation

/// An on-screen window as the window server lists it, in AX coordinates.
/// Errol's own panels sit above the ordinary layer and are never listed.
struct WindowHitRegion: Equatable {
    let number: UInt32
    let owner: Int32
    let frame: CGRect
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
