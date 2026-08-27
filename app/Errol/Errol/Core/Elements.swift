// Element finders. Everything is scoped to one chosen chat window per app,
// re-resolved on every call so window churn during a run doesn't leave us
// holding a dead reference.

import ApplicationServices
import Foundation

func axWindows(_ target: TargetApp) -> [AXUIElement] {
    (axAttribute(target.ax, kAXWindowsAttribute) as? [AXUIElement]) ?? []
}

func isExcludedWindow(_ window: AXUIElement, selectors: AppSelectors) -> Bool {
    guard !selectors.windowExcludeLabels.isEmpty else { return false }
    var hits: [AXUIElement] = []
    findAll(in: window, where: { el in
        let role = axAttribute(el, kAXRoleAttribute) as? String
        guard role == kAXButtonRole as String || role == kAXTextFieldRole as String else { return false }
        let label = axLabel(el)
        return selectors.windowExcludeLabels.contains { label.localizedCaseInsensitiveContains($0) }
    }, into: &hits)
    return !hits.isEmpty
}

func hasTextArea(_ window: AXUIElement) -> Bool {
    var areas: [AXUIElement] = []
    findAll(in: window, where: { el in
        axAttribute(el, kAXRoleAttribute) as? String == kAXTextAreaRole as String
    }, into: &areas)
    return !areas.isEmpty
}

/// The window all searches are scoped to: the first chat window, preferring
/// one with a composer. When every window carries an exclusion marker and the
/// selectors allow it, an excluded-surface window with a composer (a Claude
/// Code session in Claude Desktop) is targeted instead — an open chat window
/// always wins.
func chatWindow(in target: TargetApp) -> AXUIElement? {
    let windows = axWindows(target)
    let chat = windows.filter { !isExcludedWindow($0, selectors: target.selectors) }
    if let window = chat.first(where: hasTextArea) ?? chat.first { return window }
    guard target.selectors.excludedSurfaceIsFallback else { return nil }
    return windows.first(where: hasTextArea)
}

func isCopyButtonLabel(_ label: String, selectors: AppSelectors) -> Bool {
    guard label.localizedCaseInsensitiveContains(selectors.copyKeyword) else { return false }
    for exclude in selectors.copyExcludeKeywords
        where label.localizedCaseInsensitiveContains(exclude) { return false }
    return true
}

func isCopyButton(_ element: AXUIElement, selectors: AppSelectors) -> Bool {
    guard axAttribute(element, kAXRoleAttribute) as? String == kAXButtonRole as String else { return false }
    return isCopyButtonLabel(axLabel(element), selectors: selectors)
}

func copyButtons(in target: TargetApp) -> [AXUIElement] {
    guard let root = chatWindow(in: target) else { return [] }
    var results: [AXUIElement] = []
    findAll(in: root, where: { isCopyButton($0, selectors: target.selectors) }, into: &results)
    return results
}

/// The collapsed stand-in for a message's whole action bar (Claude Code's
/// "Show message actions"); pressing it mounts the bar and removes itself.
func isMessageActionsToggle(_ element: AXUIElement, selectors: AppSelectors) -> Bool {
    guard let label = selectors.messageActionsLabel else { return false }
    guard axAttribute(element, kAXRoleAttribute) as? String == kAXButtonRole as String else { return false }
    return axLabel(element).localizedCaseInsensitiveContains(label)
}

/// Exactly one per rendered message: its mounted copy button, or the collapsed
/// toggle standing in for the bar. Counting these is counting messages, which
/// is what the completion baselines actually need; the tree walk is
/// depth-first, so the last element belongs to the newest message.
func messageAffordances(in target: TargetApp) -> [AXUIElement] {
    guard let root = chatWindow(in: target) else { return [] }
    var results: [AXUIElement] = []
    findAll(in: root, where: {
        isCopyButton($0, selectors: target.selectors)
            || isMessageActionsToggle($0, selectors: target.selectors)
    }, into: &results)
    return results
}

func hasStopButton(in target: TargetApp) -> Bool {
    guard let root = chatWindow(in: target) else { return false }
    var results: [AXUIElement] = []
    findAll(in: root, where: { el in
        guard axAttribute(el, kAXRoleAttribute) as? String == kAXButtonRole as String else { return false }
        return axLabel(el).localizedCaseInsensitiveContains(target.selectors.stopKeyword)
    }, into: &results)
    return !results.isEmpty
}

func sendButton(in target: TargetApp) -> AXUIElement? {
    guard let root = chatWindow(in: target) else { return nil }
    var results: [AXUIElement] = []
    findAll(in: root, where: { el in
        guard axAttribute(el, kAXRoleAttribute) as? String == kAXButtonRole as String else { return false }
        let label = axLabel(el)
        guard label.localizedCaseInsensitiveContains(target.selectors.sendKeyword) else { return false }
        for exclude in target.selectors.sendExcludeKeywords
            where label.localizedCaseInsensitiveContains(exclude) { return false }
        return true
    }, into: &results)
    return results.first
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
    // Otherwise take the last text area in the window (composers sit at the bottom).
    var areas: [AXUIElement] = []
    findAll(in: root, where: { el in
        let role = axAttribute(el, kAXRoleAttribute) as? String
        return role == kAXTextAreaRole as String || role == kAXTextFieldRole as String
    }, into: &areas)
    return areas.last
}

func composerValue(in target: TargetApp) -> String? {
    guard let input = inputArea(in: target) else { return nil }
    return axAttribute(input, kAXValueAttribute) as? String
}
