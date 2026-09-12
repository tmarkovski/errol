import AppKit
import ApplicationServices
import Foundation

/// Geometry crosses the event stream, never live AX elements. Coordinates
/// use AX's top-left origin; the overlay converts them on the main thread.
struct TransferAnchor: Equatable {
    let frame: CGRect
    /// The receiving composer shell, separate from the text field where
    /// the dot lands. Sources and unrecognized prompt layouts have no shell.
    let promptFrame: CGRect?
    let window: CGRect
    let pid: pid_t
    /// Native Errol panels can resize as their editor closes. Their window
    /// identity remains valid after launch even when that layout changes.
    let windowID: CGWindowID?

    init?(frame: CGRect, window: CGRect, pid: pid_t, windowID: CGWindowID? = nil,
          promptFrame: CGRect? = nil) {
        func usable(_ rect: CGRect) -> Bool {
            [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
                && rect.width > 0 && rect.height > 0
        }
        guard usable(frame), usable(window), window.contains(frame) else { return nil }
        self.frame = frame
        self.promptFrame = promptFrame.flatMap {
            usable($0) && window.contains($0) && $0.contains(frame) ? $0 : nil
        }
        self.window = window
        self.pid = pid
        self.windowID = windowID
    }

    func matchesWindow(id: CGWindowID, pid: pid_t, frame: CGRect) -> Bool {
        guard self.pid == pid else { return false }
        if let windowID { return windowID == id }
        return abs(frame.minX - window.minX) < 2 && abs(frame.minY - window.minY) < 2
            && abs(frame.width - window.width) < 2 && abs(frame.height - window.height) < 2
    }
}

/// A bounded editor landing area and the field the app draws around it.
struct PromptTransferGeometry {
    let editor: CGRect
    let shell: CGRect?
}

/// Find the nearest shell enclosing the editor AND its controls. A fixed
/// parent count does not work across Chat, Work, and Claude Code: some put
/// scrolling/attachment wrappers between the text area and the prompt shell.
/// Geometry limits keep this walk out of the conversation pane. The shell
/// is then widened through wrappers that only pad it (visibleShell), since
/// the border the app draws is often one level out. Missing evidence
/// suppresses the outline; it never changes the paste target.
func promptTransferGeometry<Node: ElementNode>(around input: Node, window: CGRect,
                                              selectors: AppSelectors,
                                              parent: (Node) -> Node?,
                                              frame: (Node) -> CGRect?) -> PromptTransferGeometry? {
    guard var editor = frame(input),
          TransferAnchor(frame: editor, window: editor, pid: 0) != nil else { return nil }
    var node = input
    for _ in 0..<8 {
        guard let ancestor = parent(node),
              let role = ancestor.role,
              ["AXGroup", "AXScrollArea", "AXLayoutArea"].contains(role) else { break }
        node = ancestor
        guard let bounds = frame(ancestor) else { continue }
        guard TransferAnchor(frame: bounds, window: window, pid: 0) != nil else {
            // Full-document wrappers can extend off-window too. They are
            // never shells, but their parent may be the visible viewport.
            if role == "AXScrollArea" { break }
            continue
        }
        if role == "AXGroup", !bounds.contains(editor),
           let clipped = toolbarClippedPromptEditor(editor, in: ancestor, bounds: bounds,
                                                   selectors: selectors, frame: frame) {
            return PromptTransferGeometry(editor: clipped, shell: visibleShell(
                around: ancestor, shell: bounds, window: window, parent: parent, frame: frame))
        }
        if role == "AXScrollArea" {
            // A multiline AX text area can describe its full document, extending
            // beyond both the composer and the window when scrolled. The scroll
            // area's explicit viewport supplies clipping evidence here.
            editor = editor.intersection(bounds)
            guard TransferAnchor(frame: editor, window: window, pid: 0) != nil else { return nil }
        }
        // An unrecognized group is not sufficient clipping evidence. Continue
        // looking for a scroll viewport or a group with its own visible toolbar.
        guard bounds.contains(editor) else { continue }
        guard editor.minX - bounds.minX <= 80,
              bounds.maxX - editor.maxX <= 120,
              editor.minY - bounds.minY <= 200,
              bounds.maxY - editor.maxY <= 120 else { break }
        // An editor wrapper can have exactly the text area's bounds. It
        // cannot be the visible shell enclosing padding and action controls.
        guard bounds != editor else { continue }
        var budget = 80
        if hasPromptControl(under: ancestor, selectors: selectors, depth: 0, budget: &budget) {
            return PromptTransferGeometry(editor: editor, shell: visibleShell(
                around: ancestor, shell: bounds, window: window, parent: parent, frame: frame))
        }
    }
    guard TransferAnchor(frame: editor, window: window, pid: 0) != nil else { return nil }
    return PromptTransferGeometry(editor: editor, shell: nil)
}

/// The border an app draws around its composer is often one level out from
/// the group holding the text area and its controls: a wrapper with the
/// same inset on every side and nothing else framed in it (8 px on Claude's
/// chat and Code composers, live Sep 12 2026). Widen the shell through such
/// wrappers and stop at anything that grows on some sides only or carries
/// other content — the band around ChatGPT's composer, the row under
/// Claude's with the model popup — which is layout, not the field.
private func visibleShell<Node: ElementNode>(around node: Node, shell: CGRect, window: CGRect,
                                             parent: (Node) -> Node?,
                                             frame: (Node) -> CGRect?) -> CGRect {
    var node = node
    var shell = shell
    for _ in 0..<4 {
        guard let wrapper = parent(node), wrapper.role == "AXGroup",
              let bounds = frame(wrapper), bounds.contains(shell),
              TransferAnchor(frame: bounds, window: window, pid: 0) != nil else { break }
        let insets = [shell.minX - bounds.minX, shell.minY - bounds.minY,
                      bounds.maxX - shell.maxX, bounds.maxY - shell.maxY]
        guard let thinnest = insets.min(), let widest = insets.max(),
              widest <= 16, widest - thinnest <= 1 else { break }
        let onlyPads = wrapper.children.allSatisfy { child in
            guard let rect = frame(child) else { return true }
            return rect.width <= 1 || rect.height <= 1 || shell.contains(rect)
        }
        guard onlyPads else { break }
        node = wrapper
        shell = bounds
    }
    return shell
}

/// ChatGPT's scrolling prompt can expose only an AXGroup around the full text
/// document (captured 2026-09-07). Its direct action buttons identify the shell
/// and keep the landing area above the toolbar. Do not borrow nested conversation
/// controls, unframed buttons, or arbitrary popups as evidence for clipping.
private func toolbarClippedPromptEditor<Node: ElementNode>(
    _ editor: CGRect, in node: Node, bounds: CGRect, selectors: AppSelectors,
    frame: (Node) -> CGRect?
) -> CGRect? {
    // The captured composer has 12-point side insets. Allow modest padding,
    // but not the wider conversation wrappers surrounding the composer.
    guard editor.height > bounds.height,
          editor.minX >= bounds.minX, editor.maxX <= bounds.maxX,
          editor.minX - bounds.minX <= 24, bounds.maxX - editor.maxX <= 24 else { return nil }
    let controls = node.children.compactMap { child -> CGRect? in
        guard child.role == "AXButton", isPromptControl(child, selectors: selectors),
              let rect = frame(child),
              TransferAnchor(frame: rect, window: bounds, pid: 0) != nil,
              rect.height <= 48, bounds.maxY - rect.maxY <= 24 else { return nil }
        return rect
    }
    for control in controls {
        let row = controls.filter {
            abs($0.minY - control.minY) <= 4 && abs($0.maxY - control.maxY) <= 4
        }
        guard row.count >= 2, let top = row.map(\.minY).min() else { continue }
        let viewport = CGRect(x: bounds.minX, y: bounds.minY,
                              width: bounds.width, height: top - bounds.minY)
        let visible = editor.intersection(viewport)
        if TransferAnchor(frame: visible, window: bounds, pid: 0) != nil { return visible }
    }
    return nil
}

private func isPromptControl<Node: ElementNode>(_ node: Node, selectors: AppSelectors) -> Bool {
    let role = node.role
    // Model/tool popups remain mounted when Send disappears in an empty
    // ChatGPT prompt. Claude Code keeps its disabled Send control mounted.
    if role == "AXPopUpButton" { return true }
    if role == "AXButton" {
        let label = node.label.lowercased()
        if isSendButtonLabel(label, selectors: selectors)
            || label.localizedCaseInsensitiveContains(selectors.stopKeyword)
            || ["attach", "add files", "tools", "dictat", "voice", "record"]
                .contains(where: { label.contains($0) })
            || label == "add" { return true }
    }
    return false
}

private func hasPromptControl<Node: ElementNode>(under node: Node, selectors: AppSelectors,
                                                 depth: Int, budget: inout Int) -> Bool {
    guard depth <= 6, budget > 0 else { return false }
    budget -= 1
    if isPromptControl(node, selectors: selectors) { return true }
    let role = node.role
    // The text area's contents cannot provide evidence for a toolbar.
    if role == "AXTextArea" || role == "AXTextField" { return false }
    for child in node.children {
        if hasPromptControl(under: child, selectors: selectors, depth: depth + 1, budget: &budget) {
            return true
        }
    }
    return false
}

/// Called on the relay worker, where all other reads of the target occur.
/// Missing or off-window geometry only suppresses decoration.
func transferAnchor(for element: AXUIElement?, in target: TargetApp) -> TransferAnchor? {
    guard let element,
          let windowValue = axAttribute(element, kAXWindowAttribute),
          CFGetTypeID(windowValue) == AXUIElementGetTypeID(),
          let window = windowFrame(windowValue as! AXUIElement) else { return nil }
    guard let geometry = promptTransferGeometry(around: LiveElement(ax: element), window: window,
                                    selectors: target.selectors, parent: { node in
        guard let value = axAttribute(node.ax, kAXParentAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return LiveElement(ax: value as! AXUIElement)
    }, frame: { windowFrame($0.ax) }) else { return nil }
    return TransferAnchor(frame: geometry.editor, window: window, pid: target.app.processIdentifier,
                          promptFrame: geometry.shell)
}

/// A copied reply still gets a flight when its copy control has scrolled out
/// of view or exposes no geometry. Only the source may use this approximation;
/// the destination continues to identify the actual receiving prompt.
func replyTransferAnchor(copyFrame: CGRect?, window: CGRect, pid: pid_t,
                         screens: [CGRect]? = nil) -> TransferAnchor? {
    // Validate before taking intersections or computing a fallback center.
    guard TransferAnchor(frame: window, window: window, pid: pid) != nil else { return nil }
    if let copyFrame,
       let exact = TransferAnchor(frame: copyFrame, window: window, pid: pid),
       screens?.contains(where: { $0.contains(copyFrame) }) ?? true {
        return exact
    }
    // Avoid launching outside a display when the window straddles a screen
    // edge or a gap between monitors. Prefer its largest visible portion.
    let visible = screens.map { frames in
        frames.map { window.intersection($0) }
            .filter { !$0.isNull && !$0.isEmpty }
            .max { $0.width * $0.height < $1.width * $1.height }
    } ?? window
    guard let visible else { return nil }
    let width = min(18, visible.width)
    let height = min(18, visible.height)
    let source = CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2,
                        width: width, height: height)
    return TransferAnchor(frame: source, window: window, pid: pid)
}

/// Capture the window while the source app is active; the copy button itself
/// can be off screen and may unmount when focus moves to the recipient.
func replyTransferAnchor(for element: AXUIElement?, in target: TargetApp) -> TransferAnchor? {
    let elementWindow = element.flatMap { axAttribute($0, kAXWindowAttribute) }
        .flatMap { value -> AXUIElement? in
            CFGetTypeID(value) == AXUIElementGetTypeID() ? (value as! AXUIElement) : nil
        }
    guard let windowElement = elementWindow ?? chatWindow(in: target),
          let window = windowFrame(windowElement) else { return nil }
    return replyTransferAnchor(copyFrame: element.flatMap(windowFrame), window: window,
                               pid: target.app.processIdentifier)
}

enum TransferSource: Equatable {
    case captured(TransferAnchor)
    /// Resolve the prompt on the main thread at launch, after its editor
    /// has closed. No UI references or stale panel coordinates cross threads.
    case userPrompt
}

enum TransferFeedback {
    case began(id: UUID, sources: [TransferSource], destination: TransferAnchor,
               startedAt: TimeInterval)
    /// The paste landed, after the light. Confirms only the paste, not
    /// submission or a reply from the other app; the overlay has nothing
    /// left to draw by then.
    case pasted(id: UUID, destination: TransferAnchor)
    /// The handoff stopped before the paste — Stop, a switched app, a lost
    /// composer — and the flight ends where it is.
    case cancelled(id: UUID)
}

/// Every source follows the same progress clock to the same endpoint,
/// regardless of distance. Separate bends keep the two wakes distinguishable.
struct TransferTrajectory {
    let start: CGPoint
    let end: CGPoint
    var lane: Int = 0

    func point(at progress: Double) -> CGPoint {
        let p = min(1, max(0, progress))
        let eased = p * p * (3 - 2 * p)
        let q = 1 - eased
        let distance = hypot(end.x - start.x, end.y - start.y)
        let bend = min(100, distance * 0.18) * (lane == 0 ? 1 : 0.55)
        let control = CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + bend)
        return CGPoint(x: q * q * start.x + 2 * q * eased * control.x + eased * eased * end.x,
                       y: q * q * start.y + 2 * q * eased * control.y + eased * eased * end.y)
    }
}

/// One clock for the dot, the prompt's light, and the paste. The light
/// plays when the dot lands, and the worker pastes only once it has faded
/// (pasteTime), so the border the light traces is the one the dot landed
/// on: the text going in can grow the composer and move that border.
/// Without a flight — Reduce Motion, or no visible source — the light
/// plays at once, and the paste still waits for it.
struct TransferTiming {
    static let flightDuration: TimeInterval = 0.55
    /// The light's quick rise, short hold, and long fall (TransferDrawing).
    static let lightDuration: TimeInterval = 0.95
    let startedAt: TimeInterval
    let travels: Bool
    let reducedMotion: Bool

    var flightDuration: TimeInterval {
        travels && !reducedMotion ? Self.flightDuration : 0
    }

    var arrivalTime: TimeInterval { startedAt + flightDuration }

    /// When the paste may go in: the light has faded.
    var pasteTime: TimeInterval { arrivalTime + Self.lightDuration }

    func progress(at time: TimeInterval) -> Double {
        guard flightDuration > 0 else { return 1 }
        return min(1, max(0, (time - startedAt) / flightDuration))
    }

    func arrivalAge(at time: TimeInterval) -> TimeInterval? {
        time >= arrivalTime ? time - arrivalTime : nil
    }

    func isFinished(at time: TimeInterval) -> Bool {
        time >= pasteTime
    }
}
