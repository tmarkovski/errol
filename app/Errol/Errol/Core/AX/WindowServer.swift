// The window server's on-screen list, in AX coordinates, parsed in one
// place: the front window's owner that the focus checks fall back on
// (Activation.swift), the arrival a flight waits for and the windows the
// transfer overlay checks a flight against before it draws over them
// (TransferFeedback.swift, TransferOverlay.swift), and the tolerance a
// window-server frame is matched to an AX one with.

import CoreGraphics
import Foundation

/// An on-screen window as the window server lists it, in AX coordinates.
/// Errol's own panels sit above the ordinary layer, so the ordinary-only
/// list leaves them out; the transfer overlay asks for every layer, since
/// its flights set off from Errol's console panel.
struct WindowHitRegion: Equatable {
    let number: UInt32
    let owner: Int32
    let frame: CGRect
}

/// Every ordinary window on the active Space that is neither minimized nor
/// hidden, front to back, in the top-left coordinates AX reports. Kept
/// without arguments so it can stand as a default for a closure parameter
/// (awaitArrival).
func onScreenWindowRegions() -> [WindowHitRegion] {
    onScreenWindowRegions(ordinaryOnly: true)
}

/// The window server's on-screen list, front to back. Ordinary-only keeps
/// layer 0, where the apps' document windows are; false keeps the floating
/// layers too, where Errol's own panels are.
func onScreenWindowRegions(ordinaryOnly: Bool) -> [WindowHitRegion] {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { return [] }
    return info.compactMap { window in
        guard !ordinaryOnly || (window[kCGWindowLayer as String] as? Int) == 0,
              let number = window[kCGWindowNumber as String] as? UInt32,
              let owner = window[kCGWindowOwnerPID as String] as? Int32,
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return WindowHitRegion(number: number, owner: owner, frame: frame)
    }
}

/// The pid owning the frontmost ordinary window, according to the window
/// server. Needs no cooperation from the app, so this is what answers when the
/// AX query (axFocusedPID) does not. Errol's own panels are above layer 0 and so are
/// never mistaken for the front window.
func frontWindowOwnerPID() -> pid_t? {
    onScreenWindowRegions().first?.owner
}

extension CGRect {
    /// Equal to within the rounding between the AX and window-server
    /// coordinate spaces.
    func nearlyEquals(_ other: CGRect) -> Bool {
        abs(minX - other.minX) < 2 && abs(minY - other.minY) < 2
            && abs(width - other.width) < 2 && abs(height - other.height) < 2
    }
}
