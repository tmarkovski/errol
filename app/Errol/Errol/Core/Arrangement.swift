// Window arrangement for watching a run: the two chosen windows side by
// side or stacked on one screen, their original frames kept so a restore
// puts back exactly those windows — and only where nobody has moved them
// since. Frames are set directly through AX; the native Fill & Arrange
// only pairs windows interactively and cannot be aimed at a specific
// window across two apps.

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
    let frame = windowFrame(window) ?? .zero
    return "(\(Int(frame.minX)),\(Int(frame.minY))) \(Int(frame.width))x\(Int(frame.height))"
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

func currentFrame(_ window: AXUIElement) -> CGRect {
    windowFrame(window) ?? .zero
}

// MARK: - Layouts

/// The layouts the console offers. Keep positions is a choice too, and the
/// one the console starts on: it moves nothing.
enum LayoutChoice: String, CaseIterable, Equatable {
    case sideBySide
    case stacked
    case keepPositions

    var title: String {
        switch self {
        case .sideBySide: return "Side by side"
        case .stacked: return "Stacked"
        case .keepPositions: return "Keep positions"
        }
    }

    var movesWindows: Bool { self != .keepPositions }

    /// What VoiceOver hears once the layout stands.
    var outcomeMessage: String {
        switch self {
        case .sideBySide: return "Windows are side by side."
        case .stacked: return "Windows are stacked."
        case .keepPositions: return "Window positions kept."
        }
    }
}

/// The frames a layout gives the two windows in `area` (AX coordinates):
/// the first for the window on the left or on top, the second for the
/// other. nil for a layout that moves nothing.
func layoutFrames(_ layout: LayoutChoice, in area: CGRect) -> (first: CGRect, second: CGRect)? {
    switch layout {
    case .keepPositions:
        return nil
    case .sideBySide:
        let half = (area.width / 2).rounded(.down)
        return (CGRect(x: area.minX, y: area.minY, width: half, height: area.height),
                CGRect(x: area.minX + half, y: area.minY, width: area.width - half, height: area.height))
    case .stacked:
        let half = (area.height / 2).rounded(.down)
        return (CGRect(x: area.minX, y: area.minY, width: area.width, height: half),
                CGRect(x: area.minX, y: area.minY + half, width: area.width, height: area.height - half))
    }
}

/// Whether a window took the frame asked of it, to within the few points
/// of rounding a move involves. A window held larger than asked has a
/// minimum size the layout does not respect.
func windowTookFrame(_ landed: CGRect, asked: CGRect, tolerance: CGFloat = 4) -> Bool {
    landed.width <= asked.width + tolerance && landed.height <= asked.height + tolerance
}

/// Whether a window still stands where an arrangement left it, so a
/// restore does not undo a move the human made since.
func windowStandsWhereLeft(_ current: CGRect, applied: CGRect, tolerance: CGFloat = 4) -> Bool {
    abs(current.minX - applied.minX) <= tolerance && abs(current.minY - applied.minY) <= tolerance
        && abs(current.width - applied.width) <= tolerance && abs(current.height - applied.height) <= tolerance
}

enum ArrangeOutcome: Equatable {
    case arranged
    /// Keep positions: nothing moved, by choice.
    case kept
    case windowMissing(Speaker)
    /// A window would not take the frame asked of it — its minimum size is
    /// larger — and both were put back where they were.
    case cannotFit(Speaker, String)
}

/// A window a layout moves, with its app for the frame setter.
struct ArrangedWindow {
    let side: Speaker
    let target: TargetApp
    let window: AXUIElement
}

/// The arranger the engine keeps: applies a layout to the chosen windows
/// on the worker thread and remembers where they were. The first
/// arrangement's snapshot survives re-arrangements until a restore, so
/// putting the windows back means where the human had them, not where an
/// earlier layout left them.
final class WindowArranger {
    private struct Entry {
        let side: Speaker
        let target: TargetApp
        let window: AXUIElement
        let original: CGRect
        var applied: CGRect
    }

    private let lock = NSLock()
    private var snapshot: [Entry] = []

    /// Whether a restore has anything to put back.
    var canRestore: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !snapshot.isEmpty
    }

    /// Worker thread. Apply `layout` to the two windows — the first on the
    /// left or on top — on the screen hosting the first, raise both, and
    /// say how it went.
    func apply(_ layout: LayoutChoice, to windows: [ArrangedWindow]) -> ArrangeOutcome {
        guard layout.movesWindows else { return .kept }
        guard windows.count == 2 else { return .windowMissing(windows.first?.side ?? .chatgpt) }
        var originals: [CGRect] = []
        for arranged in windows {
            guard let frame = windowFrame(arranged.window) else { return .windowMissing(arranged.side) }
            originals.append(frame)
        }
        let area = axRect(screenHosting(originals[0]).visibleFrame)
        guard let frames = layoutFrames(layout, in: area) else { return .kept }
        let asked = [frames.first, frames.second]

        // The snapshot is taken once, for these windows; a re-arrangement
        // of the same windows keeps the original frames.
        lock.lock()
        let sameWindows = snapshot.count == windows.count
            && zip(snapshot, windows).allSatisfy { CFEqual($0.window, $1.window) }
        if !sameWindows {
            snapshot = zip(windows, originals).map { arranged, original in
                Entry(side: arranged.side, target: arranged.target, window: arranged.window,
                      original: original, applied: original)
            }
        }
        lock.unlock()

        for (arranged, frame) in zip(windows, asked) {
            setWindowFrame(arranged.target, arranged.window, origin: frame.origin, size: frame.size)
        }
        usleep(150_000)
        for (arranged, frame) in zip(windows, asked) {
            guard let landed = windowFrame(arranged.window) else { return .windowMissing(arranged.side) }
            guard windowTookFrame(landed, asked: frame) else {
                // Neither window is left squeezed or half-moved.
                _ = putBack(all: true)
                let reason = "\(arranged.target.name)'s window can't be made "
                    + "\(Int(frame.width))\u{00D7}\(Int(frame.height)) on this display."
                log("arrange: \(reason) (it stayed \(Int(landed.width))x\(Int(landed.height)))")
                return .cannotFit(arranged.side, reason)
            }
        }
        lock.lock()
        for index in snapshot.indices where index < asked.count { snapshot[index].applied = asked[index] }
        lock.unlock()
        for arranged in windows {
            raiseWindow(arranged.window)
            _ = makeFrontmost(arranged.target)
        }
        log("arranged \(layout.title.lowercased()) on \(Int(area.width))x\(Int(area.height)): "
            + windows.map { "\($0.target.name) \(windowFrameDescription($0.window))" }.joined(separator: ", "))
        return .arranged
    }

    /// Worker thread. Put back every window of the snapshot that still
    /// exists and still stands where the arrangement left it; a window the
    /// human moved since is theirs. Returns how many were put back.
    @discardableResult
    func restore() -> Int {
        putBack(all: false)
    }

    private func putBack(all: Bool) -> Int {
        lock.lock()
        let entries = snapshot
        snapshot = []
        lock.unlock()
        var restored = 0
        for entry in entries {
            guard let current = windowFrame(entry.window) else {
                log("restore: \(entry.target.name)'s window is gone; nothing to put back")
                continue
            }
            guard all || windowStandsWhereLeft(current, applied: entry.applied) else {
                log("restore: \(entry.target.name)'s window was moved since; leaving it")
                continue
            }
            setWindowFrame(entry.target, entry.window, origin: entry.original.origin, size: entry.original.size)
            log("restored \(entry.target.name) to \(windowFrameDescription(entry.window))")
            restored += 1
        }
        return restored
    }

    /// The screen a frame's origin lies on, the primary one otherwise.
    private func screenHosting(_ frame: CGRect) -> NSScreen {
        var screen = NSScreen.screens[0]
        for candidate in NSScreen.screens where axRect(candidate.frame).contains(frame.origin) {
            screen = candidate
        }
        return screen
    }
}
