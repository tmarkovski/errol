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

/// A world-switcher option's name, with the live session state the app
/// appends after a comma stripped off ("Code, awaiting your input" -> "Code").
func worldName(_ label: String) -> String {
    (label.split(separator: ",", maxSplits: 1).first.map(String.init) ?? label)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Whether this element marks its window as something other than a chat.
///
/// Two signals, ORed. The app's own world switcher is the direct one — the
/// selected option states which world is mounted — and the furniture labels in
/// windowExcludeLabels are the backstop for builds that predate the switcher
/// or move it. ORing rather than letting the switcher overrule them keeps the
/// asymmetry right: failing to recognize a Claude Code session means typing a
/// relayed conversation into it, while a spurious exclusion only mislabels the
/// surface and, where the fallback is on, still targets the window.
///
/// `role` is passed in because callers have already read it, and every AX
/// attribute read is synchronous IPC into the other app.
func isExclusionMarker<Node: ElementNode>(_ element: Node, role: String,
                                          selectors: AppSelectors) -> Bool {
    if role == kAXRadioButtonRole as String {
        guard let world = selectors.excludedWorldName, element.numberValue == 1 else { return false }
        return worldName(element.label).caseInsensitiveCompare(world) == .orderedSame
    }
    guard role == kAXButtonRole as String || role == kAXTextFieldRole as String,
          !selectors.windowExcludeLabels.isEmpty else { return false }
    let label = element.label
    return selectors.windowExcludeLabels.contains { label.localizedCaseInsensitiveContains($0) }
}

func isExcludedWindow<Node: ElementNode>(_ window: Node, selectors: AppSelectors) -> Bool {
    guard selectors.excludedWorldName != nil || !selectors.windowExcludeLabels.isEmpty
    else { return false }
    var hits: [Node] = []
    findAll(in: window, where: { el in
        guard let role = el.role else { return false }
        return isExclusionMarker(el, role: role, selectors: selectors)
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

/// The absolute ordinal of a conversation message, where the surface numbers
/// them: Claude names each one "Message N" (an AXGroup article, user and
/// assistant messages alike — the name arrives in AXDescription, so it is
/// read through the joined label, with AXTitle kept as a candidate). nil for
/// everything else — including the sidebar hazards ("Message actions
/// button…" session rows are AXButtons, and the whole-string numeric parse
/// rejects any label with more after the number).
func messageOrdinal<Node: ElementNode>(_ element: Node) -> Int? {
    guard element.role == kAXGroupRole as String else { return nil }
    for text in [element.title, element.label] {
        guard let text, text.hasPrefix("Message "),
              let ordinal = Int(text.dropFirst("Message ".count)) else { continue }
        return ordinal
    }
    return nil
}

/// The newest message's ordinal, nil where messages are unnumbered (ChatGPT).
/// This is the completion signal that survives list virtualization: Claude
/// unmounts older messages as a conversation grows — observed live Aug 28
/// 2026 with only "Message 6"–"Message 8" mounted of 8 — so the affordance
/// count can plateau or fall while the ordinal of the always-mounted newest
/// message keeps rising.
func lastMessageOrdinal<Node: ElementNode>(under root: Node) -> Int? {
    var groups: [Node] = []
    findAll(in: root, where: { messageOrdinal($0) != nil }, into: &groups)
    return groups.compactMap(messageOrdinal).max()
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

/// Count the long-paste attachment chips under one composer container. The
/// caller deliberately supplies the app's composer container rather than
/// the whole window: sent messages retain the same pasted-text controls in the
/// conversation history and must not confirm a new paste.
func pastedTextAttachmentCount<Node: ElementNode>(under root: Node,
                                                   selectors: AppSelectors) -> Int {
    guard let removeLabel = selectors.pastedTextAttachmentRemoveLabel else { return 0 }
    var results: [Node] = []
    findAll(in: root, where: { element in
        element.role == kAXButtonRole as String
            && element.label.localizedCaseInsensitiveContains(removeLabel)
    }, into: &results)
    return results.count
}

/// Resolve the app-specific composer scope using the same parent walk for
/// live AX elements and fixtures. Do not search above that container: old
/// messages and unrelated attachment controls cannot verify this paste.
func pastedTextAttachmentCount<Node: ElementNode>(around input: Node,
                                                   selectors: AppSelectors,
                                                   parent: (Node) -> Node?) -> Int {
    guard selectors.pastedTextAttachmentRemoveLabel != nil,
          selectors.pastedTextAttachmentAncestorLevels > 0 else { return 0 }
    var container = input
    for _ in 0..<selectors.pastedTextAttachmentAncestorLevels {
        guard let ancestor = parent(container), ancestor.role == kAXGroupRole as String
        else { return 0 }
        container = ancestor
    }
    return pastedTextAttachmentCount(under: container, selectors: selectors)
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

func lastMessageOrdinal(in target: TargetApp) -> Int? {
    guard let root = chatWindow(in: target) else { return nil }
    return lastMessageOrdinal(under: LiveElement(ax: root))
}

func hasStopButton(in target: TargetApp) -> Bool {
    guard let root = chatWindow(in: target) else { return false }
    return hasStopButton(under: LiveElement(ax: root), selectors: target.selectors)
}

func sendButton(in target: TargetApp) -> AXUIElement? {
    guard let root = chatWindow(in: target) else { return nil }
    return sendButton(under: LiveElement(ax: root), selectors: target.selectors)?.ax
}

/// ChatGPT's remove buttons are siblings of the input; Claude nests its
/// input two groups deeper than its attachment row.
func pastedTextAttachmentCount(around input: AXUIElement,
                               selectors: AppSelectors) -> Int {
    pastedTextAttachmentCount(around: LiveElement(ax: input), selectors: selectors) { node in
        guard let parent = axAttribute(node.ax, kAXParentAttribute) else { return nil }
        return LiveElement(ax: parent as! AXUIElement)
    }
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

/// The composer's text when it holds a real draft; nil when it is empty or
/// showing a known placeholder (composerPlaceholders in Config.swift).
func composerDraft(in target: TargetApp) -> String? {
    let value = (composerValue(in: target) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return composerPlaceholders.contains(value) ? nil : value
}
