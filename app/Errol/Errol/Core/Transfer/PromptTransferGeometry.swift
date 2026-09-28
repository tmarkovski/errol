// Where a transfer lands in the receiving prompt: the editor's visible area
// and the field the app draws around it, found by walking up from the text area.

import CoreGraphics
import Foundation

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
          isUsableRect(editor) else { return nil }
    var node = input
    for _ in 0..<8 {
        guard let ancestor = parent(node),
              let role = ancestor.role,
              ["AXGroup", "AXScrollArea", "AXLayoutArea"].contains(role) else { break }
        node = ancestor
        guard let bounds = frame(ancestor) else { continue }
        guard isUsableRect(bounds, within: window) else {
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
            guard isUsableRect(editor, within: window) else { return nil }
        }
        // An unrecognized group is not sufficient clipping evidence. Continue
        // looking for a scroll viewport or a group with its own visible toolbar.
        guard bounds.contains(editor) else { continue }
        let row = editorRow(editor, under: ancestor, selectors: selectors, frame: frame)
        guard row.minX - bounds.minX <= 80,
              bounds.maxX - row.maxX <= 120,
              row.minY - bounds.minY <= 200,
              bounds.maxY - row.maxY <= 120 else { break }
        // An editor wrapper can have exactly the text area's bounds. It
        // cannot be the visible shell enclosing padding and action controls.
        guard bounds != editor else { continue }
        var budget = 80
        if hasPromptControl(under: ancestor, selectors: selectors, depth: 0, budget: &budget) {
            return PromptTransferGeometry(editor: editor, shell: visibleShell(
                around: ancestor, shell: bounds, window: window, parent: parent, frame: frame))
        }
    }
    guard isUsableRect(editor, within: window) else { return nil }
    return PromptTransferGeometry(editor: editor, shell: nil)
}

/// The editor widened through the controls seated beside it. ChatGPT's Chat
/// composer is one row while the prompt is short (live Sep 16 2026): the
/// attach button left of the text area, then the model popup, Dictate, and
/// voice chat, ending 158 px past the editor's right edge, all 8 px inside
/// the pill the app draws. Measured from the editor alone that pill is too
/// wide to be the field; measured from the row it is. Controls on a line of
/// their own, like a Send button under the text, leave the row alone, and
/// so does anything unframed.
private func editorRow<Node: ElementNode>(_ editor: CGRect, under node: Node,
                                          selectors: AppSelectors,
                                          frame: (Node) -> CGRect?) -> CGRect {
    var row = editor
    var budget = 40
    func visit(_ node: Node, depth: Int) {
        guard depth <= 2, budget > 0 else { return }
        budget -= 1
        let role = node.role
        if role == "AXTextArea" || role == "AXTextField" { return }
        if isPromptControl(node, selectors: selectors) {
            if let rect = frame(node), rect.width > 0, rect.height > 0,
               rect.minY < editor.maxY, rect.maxY > editor.minY {
                row = row.union(rect)
            }
            return
        }
        for child in node.children { visit(child, depth: depth + 1) }
    }
    for child in node.children { visit(child, depth: 1) }
    return row
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
              isUsableRect(bounds, within: window) else { break }
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
              isUsableRect(rect, within: bounds),
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
        if isUsableRect(visible, within: bounds) { return visible }
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
