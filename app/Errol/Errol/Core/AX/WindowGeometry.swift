// The Cocoa/AX coordinate flip and a window's AX frame, which every AX
// caller shares, not only the arrangement that first needed them.

import AppKit
import ApplicationServices

/// AX window coordinates use a top-left origin on the primary display;
/// NSScreen uses bottom-left. The flip about the primary display's height
/// is its own inverse, so this converts a Cocoa rect to AX coordinates and
/// an AX rect back to Cocoa's, the direction the transfer overlay uses.
func axRect(_ rect: CGRect) -> CGRect {
    let primaryHeight = NSScreen.screens[0].frame.height
    return CGRect(x: rect.origin.x, y: primaryHeight - rect.maxY,
                  width: rect.width, height: rect.height)
}

/// A window's frame in AX coordinates, or nil when the element no longer
/// answers — a closed window, or an app whose tree was rebuilt under it.
func windowFrame(_ window: AXUIElement) -> CGRect? {
    var position = CGPoint.zero
    var size = CGSize.zero
    guard let positionValue = axAttribute(window, kAXPositionAttribute),
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
          let sizeValue = axAttribute(window, kAXSizeAttribute),
          CFGetTypeID(sizeValue) == AXValueGetTypeID(),
          AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: position, size: size)
}
