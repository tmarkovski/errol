// Element finders. The detection logic is generic over ElementNode so the
// same code runs against live AXUIElements and recorded fixture trees; the
// TargetApp entry points below are the live face of it. Everything is scoped
// to one chosen chat window per app, re-resolved on every call so window
// churn during a run doesn't leave us holding a dead reference.

import ApplicationServices
import Foundation

func axWindows(_ target: TargetApp) -> [AXUIElement] {
    (axAttribute(target.ax, kAXWindowsAttribute) as? [AXUIElement]) ?? []
}

// MARK: - Generic detection cores

func isExcludedWindow<Node: ElementNode>(_ window: Node, selectors: AppSelectors) -> Bool {
    guard !selectors.windowExcludeLabels.isEmpty else { return false }
    var hits: [Node] = []
    findAll(in: window, where: { el in
        guard let role = el.role,
              role == kAXButtonRole as String || role == kAXTextFieldRole as String
        else { return false }
        let label = el.label
        return selectors.windowExcludeLabels.contains { label.localizedCaseInsensitiveContains($0) }
    }, into: &hits)
    return !hits.isEmpty
}

func hasTextArea<Node: ElementNode>(_ window: Node) -> Bool {
    var areas: [Node] = []
    findAll(in: window, where: { $0.role == kAXTextAreaRole as String }, into: &areas)
    return !areas.isEmpty
}

/// The window all searches are scoped to: the first chat window, preferring
/// one with a composer. When every window carries an exclusion marker and the
/// selectors allow it, an excluded-surface window with a composer (a Claude
/// Code session in Claude Desktop) is targeted instead — an open chat window
/// always wins.
func chooseChatWindow<Node: ElementNode>(from windows: [Node], selectors: AppSelectors) -> Node? {
    let chat = windows.filter { !isExcludedWindow($0, selectors: selectors) }
    if let window = chat.first(where: hasTextArea) ?? chat.first { return window }
    guard selectors.excludedSurfaceIsFallback else { return nil }
    return windows.first(where: hasTextArea)
}

func isCopyButtonLabel(_ label: String, selectors: AppSelectors) -> Bool {
    guard label.localizedCaseInsensitiveContains(selectors.copyKeyword) else { return false }
    for exclude in selectors.copyExcludeKeywords
        where label.localizedCaseInsensitiveContains(exclude) { return false }
    return true
}

func isCopyButton<Node: ElementNode>(_ element: Node, selectors: AppSelectors) -> Bool {
    guard element.role == kAXButtonRole as String else { return false }
    return isCopyButtonLabel(element.label, selectors: selectors)
}

/// The collapsed stand-in for a message's whole action bar (Claude Code's
/// "Show message actions"); pressing it mounts the bar and removes itself.
func isMessageActionsToggle<Node: ElementNode>(_ element: Node, selectors: AppSelectors) -> Bool {
    guard let label = selectors.messageActionsLabel else { return false }
    guard element.role == kAXButtonRole as String else { return false }
    return element.label.localizedCaseInsensitiveContains(label)
}

func copyButtons<Node: ElementNode>(under root: Node, selectors: AppSelectors) -> [Node] {
    var results: [Node] = []
    findAll(in: root, where: { isCopyButton($0, selectors: selectors) }, into: &results)
    return results
}

/// Exactly one per rendered message: its mounted copy button, or the collapsed
/// toggle standing in for the bar. Counting these is counting messages, which
/// is what the completion baselines actually need; the tree walk is
/// depth-first, so the last element belongs to the newest message.
func messageAffordances<Node: ElementNode>(under root: Node, selectors: AppSelectors) -> [Node] {
    var results: [Node] = []
    findAll(in: root, where: {
        isCopyButton($0, selectors: selectors)
            || isMessageActionsToggle($0, selectors: selectors)
    }, into: &results)
    return results
}

func hasStopButton<Node: ElementNode>(under root: Node, selectors: AppSelectors) -> Bool {
    var results: [Node] = []
    findAll(in: root, where: { el in
        guard el.role == kAXButtonRole as String else { return false }
        return el.label.localizedCaseInsensitiveContains(selectors.stopKeyword)
    }, into: &results)
    return !results.isEmpty
}

func isSendButtonLabel(_ label: String, selectors: AppSelectors) -> Bool {
    guard label.localizedCaseInsensitiveContains(selectors.sendKeyword) else { return false }
    for exclude in selectors.sendExcludeKeywords
        where label.localizedCaseInsensitiveContains(exclude) { return false }
    return true
}

func sendButton<Node: ElementNode>(under root: Node, selectors: AppSelectors) -> Node? {
    var results: [Node] = []
    findAll(in: root, where: { el in
        guard el.role == kAXButtonRole as String else { return false }
        return isSendButtonLabel(el.label, selectors: selectors)
    }, into: &results)
    return results.first
}

/// The last text input in the window — composers sit at the bottom. The live
/// inputArea prefers the focused element; this is its shared fallback.
func composerElement<Node: ElementNode>(under root: Node) -> Node? {
    var areas: [Node] = []
    findAll(in: root, where: { el in
        el.role == kAXTextAreaRole as String || el.role == kAXTextFieldRole as String
    }, into: &areas)
    return areas.last
}

// MARK: - Live entry points

func isExcludedWindow(_ window: AXUIElement, selectors: AppSelectors) -> Bool {
    isExcludedWindow(LiveElement(ax: window), selectors: selectors)
}

func hasTextArea(_ window: AXUIElement) -> Bool {
    hasTextArea(LiveElement(ax: window))
}

func chatWindow(in target: TargetApp) -> AXUIElement? {
    chooseChatWindow(from: axWindows(target).map(LiveElement.init),
                     selectors: target.selectors)?.ax
}

func isMessageActionsToggle(_ element: AXUIElement, selectors: AppSelectors) -> Bool {
    isMessageActionsToggle(LiveElement(ax: element), selectors: selectors)
}

func copyButtons(in target: TargetApp) -> [AXUIElement] {
    guard let root = chatWindow(in: target) else { return [] }
    return copyButtons(under: LiveElement(ax: root), selectors: target.selectors).map(\.ax)
}

func messageAffordances(in target: TargetApp) -> [AXUIElement] {
    guard let root = chatWindow(in: target) else { return [] }
    return messageAffordances(under: LiveElement(ax: root), selectors: target.selectors).map(\.ax)
}

func hasStopButton(in target: TargetApp) -> Bool {
    guard let root = chatWindow(in: target) else { return false }
    return hasStopButton(under: LiveElement(ax: root), selectors: target.selectors)
}

func sendButton(in target: TargetApp) -> AXUIElement? {
    guard let root = chatWindow(in: target) else { return nil }
    return sendButton(under: LiveElement(ax: root), selectors: target.selectors)?.ax
}

func inputArea(in target: TargetApp) -> AXUIElement? {
    guard let root = chatWindow(in: target) else { return nil }
    // Prefer the focused element, but only if it lives in the chat window;
    // focus could be on another window (e.g. a Claude Code session).
    if let focused = axAttribute(target.ax, kAXFocusedUIElementAttribute) {
        let el = focused as! AXUIElement
        if axAttribute(el, kAXRoleAttribute) as? String == kAXTextAreaRole as String,
           let window = axAttribute(el, kAXWindowAttribute),
           CFEqual(window, root) {
            return el
        }
    }
    return composerElement(under: LiveElement(ax: root))?.ax
}

func composerValue(in target: TargetApp) -> String? {
    guard let input = inputArea(in: target) else { return nil }
    return axAttribute(input, kAXValueAttribute) as? String
}
