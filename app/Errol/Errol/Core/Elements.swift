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

/// The window all searches are scoped to. Windows with exclusion markers
/// (e.g. Claude Code sessions inside Claude Desktop) are never eligible.
func chatWindow(in target: TargetApp) -> AXUIElement? {
    let eligible = axWindows(target).filter { !isExcludedWindow($0, selectors: target.selectors) }
    return eligible.first(where: hasTextArea) ?? eligible.first
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
        return axLabel(el).localizedCaseInsensitiveContains(target.selectors.sendKeyword)
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
