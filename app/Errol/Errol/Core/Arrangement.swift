// Window tiling for watching a run: the same result as the native Fill &
// Arrange "Left & Right", which only pairs windows interactively and can't
// be aimed at a specific window across two apps. Frames are set directly
// through AX, with the pre-tiling frames snapshotted for restore.

import AppKit
import ApplicationServices

/// AX window coordinates use a top-left origin on the primary display;
/// NSScreen uses bottom-left. Convert a Cocoa rect to AX coordinates.
func axRect(_ rect: CGRect) -> CGRect {
    let primaryHeight = NSScreen.screens[0].frame.height
    return CGRect(x: rect.origin.x, y: primaryHeight - rect.maxY,
                  width: rect.width, height: rect.height)
}

func windowFrameDescription(_ window: AXUIElement) -> String {
    var position = CGPoint.zero
    var size = CGSize.zero
    if let value = axAttribute(window, kAXPositionAttribute) {
        AXValueGetValue(value as! AXValue, .cgPoint, &position)
    }
    if let value = axAttribute(window, kAXSizeAttribute) {
        AXValueGetValue(value as! AXValue, .cgSize, &size)
    }
    return "(\(Int(position.x)),\(Int(position.y))) \(Int(size.width))x\(Int(size.height))"
}

func setWindowFrame(_ target: TargetApp, _ window: AXUIElement, origin: CGPoint, size: CGSize) {
    // AXEnhancedUserInterface (set at startup as the Electron nudge) makes
    // some apps animate or ignore AX moves; drop it for the move, restore
    // after — but only where it was actually set.
    let hadEnhanced = (axAttribute(target.ax, "AXEnhancedUserInterface") as? Bool) ?? false
    AXUIElementSetAttributeValue(target.ax, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
    var origin = origin
    var size = size
    if let positionValue = AXValueCreate(.cgPoint, &origin),
       let sizeValue = AXValueCreate(.cgSize, &size) {
        // Size, position, size again: position can be clamped by the old
        // size, and the final size settles min-size adjustments.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }
    if hadEnhanced {
        AXUIElementSetAttributeValue(target.ax, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }
}

func currentFrame(_ window: AXUIElement) -> CGRect {
    var position = CGPoint.zero
    var size = CGSize.zero
    if let value = axAttribute(window, kAXPositionAttribute) {
        AXValueGetValue(value as! AXValue, .cgPoint, &position)
    }
    if let value = axAttribute(window, kAXSizeAttribute) {
        AXValueGetValue(value as! AXValue, .cgSize, &size)
    }
    return CGRect(origin: position, size: size)
}

/// Snapshot the pre-tiling frames so Restore Window Positions can put them back.
func saveFrames(_ entries: [(TargetApp, AXUIElement)]) {
    let lines = entries.map { target, window -> String in
        let frame = currentFrame(window)
        return "\(target.name)\t\(frame.origin.x)\t\(frame.origin.y)\t\(frame.width)\t\(frame.height)"
    }
    try? lines.joined(separator: "\n").write(toFile: config.frameStatePath, atomically: true, encoding: .utf8)
}

/// Restore the frames saved by the last tiling. Without a snapshot the
/// best effort is centering both windows, lightly cascaded.
func unarrange(_ targets: [TargetApp]) {
    if let content = try? String(contentsOfFile: config.frameStatePath, encoding: .utf8) {
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count == 5,
                  let x = Double(parts[1]), let y = Double(parts[2]),
                  let width = Double(parts[3]), let height = Double(parts[4]),
                  let target = targets.first(where: { $0.name == parts[0] }),
                  let window = chatWindow(in: target) else { continue }
            setWindowFrame(target, window, origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
            log("restored \(target.name) to \(windowFrameDescription(window))")
        }
        try? FileManager.default.removeItem(atPath: config.frameStatePath)
        return
    }
    log("restore: no saved frames at \(config.frameStatePath); centering both windows instead")
    let area = axRect(NSScreen.screens[0].visibleFrame)
    let size = CGSize(width: (area.width * 0.7).rounded(), height: (area.height * 0.85).rounded())
    var cascade: CGFloat = -30
    for target in targets {
        guard let window = chatWindow(in: target) else { continue }
        let origin = CGPoint(x: (area.midX - size.width / 2 + cascade).rounded(),
                             y: (area.midY - size.height / 2 + cascade / 2).rounded())
        setWindowFrame(target, window, origin: origin, size: size)
        log("centered \(target.name) at \(windowFrameDescription(window))")
        cascade += 60
    }
}

/// Tile the two chat windows into the halves of one screen.
func arrangeSideBySide(left: TargetApp, right: TargetApp) {
    guard let leftWindow = chatWindow(in: left), let rightWindow = chatWindow(in: right) else {
        log("arrange: could not resolve a chat window in both apps")
        return
    }
    // Never overwrite an existing snapshot: arranging twice must not replace
    // the original frames with already-tiled ones.
    if FileManager.default.fileExists(atPath: config.frameStatePath) {
        log("arrange: keeping the existing frame snapshot for restore")
    } else {
        saveFrames([(left, leftWindow), (right, rightWindow)])
    }
    // Tile on whichever screen currently hosts the left app's window.
    var screen = NSScreen.screens[0]
    if let value = axAttribute(leftWindow, kAXPositionAttribute) {
        var position = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &position)
        for candidate in NSScreen.screens where axRect(candidate.frame).contains(position) {
            screen = candidate
        }
    }
    let area = axRect(screen.visibleFrame)
    let half = (area.width / 2).rounded(.down)
    setWindowFrame(left, leftWindow,
                   origin: area.origin,
                   size: CGSize(width: half, height: area.height))
    setWindowFrame(right, rightWindow,
                   origin: CGPoint(x: area.origin.x + half, y: area.origin.y),
                   size: CGSize(width: area.width - half, height: area.height))
    // Raise both so they are the visible pair.
    for target in [left, right] {
        if let window = chatWindow(in: target) {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        _ = makeFrontmost(target)
    }
    log("arranged on \(Int(area.width))x\(Int(area.height)): \(left.name) \(windowFrameDescription(leftWindow)), \(right.name) \(windowFrameDescription(rightWindow))")
}
