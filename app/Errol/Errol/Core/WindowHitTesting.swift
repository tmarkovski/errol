import CoreGraphics

/// Visible windows in front-to-back order, in AX coordinates. Matching
/// only candidate bounds could select a conversation hidden by another app.
struct WindowHitRegion {
    let number: UInt32
    let owner: Int32
    let frame: CGRect
}

func frontmostWindow(at point: CGPoint, among windows: [WindowHitRegion],
                     ignoring: Set<UInt32> = []) -> WindowHitRegion? {
    windows.first { !ignoring.contains($0.number) && $0.frame.contains(point) }
}
