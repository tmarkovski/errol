// The veil over the side whose turn it is not: a frosted, click-through
// window laid exactly over a chat window during a run, so the window being
// written in is the clear one and the other reads as waiting. Nothing
// public restyles a window another app owns; this is Errol's own window on
// top of it — the mechanism screen annotators and window dimmers use —
// with a behind-window material blurring what it covers. Accessibility
// supplies the covered window's frame, under the grant the run already
// has; the drawing needs no permission at all.
//
// One worker thread follows both chat windows on a short cadence — the AX
// position and size, and the window server's on-screen list — so a veil
// follows a window that is moved, leaves one that is minimized, hidden, or
// on another Space, and comes back with it. Polling, not AXObserver:
// window-level notifications are what Electron supports least, a dragged
// window posts its move only at mouse-up anyway, and the reads are two
// attributes per window. They stay off the main thread — an app that
// stops answering would hold them to the AX timeout — and only a change
// reaches AppKit.

import AppKit
import ApplicationServices

/// The two veils and the thread that places them. Main-thread API; the
/// controller drives it from the run's events.
final class SideVeils {
    private struct Side {
        let speaker: Speaker
        let bundleID: String
        let searchName: String
        let selectors: AppSelectors
        /// What the veil says: whose reply this window is waiting for.
        let caption: String
        var target: TargetApp?
        var window: AXUIElement?
        var lastSearch = Date.distantPast
    }

    private static let cadence: TimeInterval = 0.2
    /// Finding a side's chat window walks its tree; a side without one is
    /// looked for again on this spacing, not every tick.
    private static let searchSpacing: TimeInterval = 2

    private let condition = NSCondition()
    private var active = false
    private var waiting = Set<Speaker>()
    private var names = (chatgpt: "ChatGPT", claude: "Claude")
    /// Bumped by begin; the worker rebuilds its sides when it changes.
    private var generation = 0
    private var poked = false
    private var started = false
    /// Main-thread only.
    private var panels = [Speaker: VeilPanel]()

    /// A run began: follow both chat windows from here. Nothing is veiled
    /// until `update` says who is waiting.
    func begin(chatgptName: String, claudeName: String) {
        condition.lock()
        names = (chatgptName, claudeName)
        waiting = []
        generation += 1
        active = true
        poked = true
        condition.signal()
        condition.unlock()
        guard !started else { return }
        started = true
        let thread = Thread { [weak self] in self?.loop() }
        thread.name = "SideVeils"
        thread.stackSize = 4 << 20
        thread.start()
    }

    /// Who is waiting, from the run's conversation states. A side is veiled
    /// while it waits — its counterpart is writing, or the run is holding
    /// the reply it will receive — and clear while it writes, while its
    /// captured reply stands through a hold, and once it has signed off.
    func update(chatgpt: ConversationStatus, claude: ConversationStatus) {
        var now = Set<Speaker>()
        if chatgpt == .waiting { now.insert(.chatgpt) }
        if claude == .waiting { now.insert(.claude) }
        condition.lock()
        if now != waiting {
            waiting = now
            poked = true
            condition.signal()
        }
        condition.unlock()
    }

    /// The run is over: both veils come off, and the thread parks.
    func end() {
        condition.lock()
        active = false
        waiting = []
        condition.signal()
        condition.unlock()
        for panel in panels.values { panel.hide() }
    }

    // MARK: Worker

    private func loop() {
        var sides = [Side]()
        var seen = 0
        /// The last frame handed to the main thread per side; absent
        /// while the side is unveiled.
        var sent = [Speaker: CGRect]()
        while true {
            condition.lock()
            while !active { condition.wait() }
            if seen != generation {
                seen = generation
                sides = Self.makeSides(names)
                sent = [:]
            }
            poked = false
            let wanted = waiting
            condition.unlock()

            let onScreen = wanted.isEmpty ? [] : Self.onScreenWindows()
            for index in sides.indices {
                let speaker = sides[index].speaker
                let frame = wanted.contains(speaker)
                    ? locate(&sides[index], onScreen: onScreen) : nil
                guard sent[speaker] != frame else { continue }
                sent[speaker] = frame
                let caption = sides[index].caption
                DispatchQueue.main.async { [weak self] in
                    self?.apply(speaker, frame: frame, caption: caption)
                }
            }

            // Sit out the cadence; a change in who is waiting, or the end
            // of the run, cuts the wait short.
            condition.lock()
            let deadline = Date().addingTimeInterval(Self.cadence)
            while active, !poked {
                if !condition.wait(until: deadline) { break }
            }
            condition.unlock()
        }
    }

    private static func makeSides(_ names: (chatgpt: String, claude: String)) -> [Side] {
        [Side(speaker: .chatgpt, bundleID: config.chatgptBundleID, searchName: "Codex",
              selectors: config.chatgptSelectors, caption: "Waiting for \(names.claude)"),
         Side(speaker: .claude, bundleID: config.claudeBundleID, searchName: "Claude",
              selectors: config.claudeSelectors, caption: "Waiting for \(names.chatgpt)")]
    }

    /// Where the side's chat window stands, if it is showing: looked for
    /// again when the app relaunches or the element stops answering, and
    /// nil while the window is minimized, hidden, or on another Space.
    private func locate(_ side: inout Side,
                        onScreen: [(pid: pid_t, bounds: CGRect)]) -> CGRect? {
        if side.target?.app.isTerminated ?? true {
            side.target = findApp(bundleID: side.bundleID, name: side.searchName,
                                  selectors: side.selectors)
            side.window = nil
        }
        guard let target = side.target else { return nil }
        if side.window == nil {
            guard Date().timeIntervalSince(side.lastSearch) >= Self.searchSpacing else { return nil }
            side.lastSearch = Date()
            side.window = chatWindow(in: target)
        }
        guard let window = side.window else { return nil }
        guard let frame = windowFrame(window) else {
            side.window = nil
            return nil
        }
        let pid = target.app.processIdentifier
        let showing = onScreen.contains { $0.pid == pid && $0.bounds.nearlyEquals(frame) }
        return showing ? frame : nil
    }

    /// Every ordinary window on the active Space that is neither minimized
    /// nor hidden, by owner and bounds — the same top-left coordinates AX
    /// reports, so a chat window is matched by its frame.
    private static func onScreenWindows() -> [(pid: pid_t, bounds: CGRect)] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
            else { return nil }
            return (pid, bounds)
        }
    }

    // MARK: Panels (main thread)

    private func apply(_ speaker: Speaker, frame: CGRect?, caption: String) {
        condition.lock()
        let live = active
        condition.unlock()
        guard live, let frame else {
            panels[speaker]?.hide()
            return
        }
        let panel = panels[speaker] ?? VeilPanel.make()
        panels[speaker] = panel
        panel.caption = caption
        panel.show(at: axRect(frame))
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

/// One veil: a borderless, non-activating, click-through panel a level
/// under the console — so the console can be dragged across a veiled
/// window and stay on top — with clicks falling through to the app
/// beneath. It is never key or main, stays off Mission Control, and can
/// stand on a full-screen Space when the window it covers is there.
private final class VeilPanel: NSPanel {
    /// The window corners it should match. Tune by eye against the chat
    /// apps' windows on the current macOS.
    static let cornerRadius: CGFloat = 12
    static let fadeIn: TimeInterval = 0.25
    static let fadeOut: TimeInterval = 0.2

    var caption: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }
    private let label = NSTextField(labelWithString: "")
    /// Whether it is meant to be up. A hide still fading can be reversed
    /// by a show, which is why this is not `isVisible`.
    private var shown = false

    static func make() -> VeilPanel {
        let panel = VeilPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        panel.collectionBehavior = [.transient, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let frost = NSVisualEffectView()
        frost.blendingMode = .behindWindow
        frost.material = .fullScreenUI
        // Follows the panel's own key status otherwise, and a veil is never
        // key: without this the frost goes flat the moment it shows.
        frost.state = .active
        frost.maskImage = cornerMask()
        panel.contentView = frost

        panel.label.font = .systemFont(ofSize: 13, weight: .medium)
        panel.label.textColor = .secondaryLabelColor
        panel.label.alignment = .center
        panel.label.translatesAutoresizingMaskIntoConstraints = false
        frost.addSubview(panel.label)
        NSLayoutConstraint.activate([
            panel.label.centerXAnchor.constraint(equalTo: frost.centerXAnchor),
            panel.label.centerYAnchor.constraint(equalTo: frost.centerYAnchor),
        ])
        return panel
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Put the veil over `frame` (Cocoa coordinates): fading in if it is
    /// not up, moving it if it is.
    func show(at frame: NSRect) {
        if shown {
            if frame != self.frame { setFrame(frame, display: true) }
            return
        }
        shown = true
        if !isVisible {
            alphaValue = 0
            setFrame(frame, display: false)
            orderFrontRegardless()
        } else if frame != self.frame {
            setFrame(frame, display: true)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeIn
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard shown else { return }
        shown = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeOut
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !shown else { return }
            orderOut(nil)
        })
    }

    /// A stretchable rounded rectangle: the corners stay put, the middle
    /// fills whatever size the window takes. The material is clipped to
    /// it, so the frost ends where the window's corners do.
    private static func cornerMask() -> NSImage {
        let radius = cornerRadius
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
