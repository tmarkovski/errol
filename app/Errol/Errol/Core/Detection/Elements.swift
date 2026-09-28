// Element finders. The detection logic is generic over ElementNode so the
// same code runs against live AXUIElements and recorded fixture trees; the
// TargetApp entry points below are the live face of it. Everything is scoped
// to one chat window per app: the target's bound window when it has one,
// never substituted, since a dead bound window yields nothing; otherwise
// chooseChatWindow's pick, resolved again on every call.

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
        guard selectors.excludedWorldName != nil, element.numberValue == 1 else { return false }
        return isExclusionMarker(role: role, label: element.label, selected: true, selectors: selectors)
    }
    guard role == kAXButtonRole as String || role == kAXTextFieldRole as String,
          !selectors.windowExcludeLabels.isEmpty else { return false }
    return isExclusionMarker(role: role, label: element.label, selected: false, selectors: selectors)
}

/// The same rule over a label already read — the readiness scan reads each
/// button's label once for several purposes and must not read it again.
/// `selected` is the radio button's value; buttons and text fields pass
/// anything.
func isExclusionMarker(role: String, label: String, selected: Bool, selectors: AppSelectors) -> Bool {
    if role == kAXRadioButtonRole as String {
        guard let world = selectors.excludedWorldName, selected else { return false }
        return worldName(label).caseInsensitiveCompare(world) == .orderedSame
    }
    guard role == kAXButtonRole as String || role == kAXTextFieldRole as String else { return false }
    return selectors.windowExcludeLabels.contains { label.localizedCaseInsensitiveContains($0) }
}

func isExcludedWindow<Node: ElementNode>(_ window: Node, selectors: AppSelectors) -> Bool {
    guard selectors.excludedWorldName != nil || !selectors.windowExcludeLabels.isEmpty
    else { return false }
    return firstMatch(in: window, where: { el in
        guard let role = el.role else { return false }
        return isExclusionMarker(el, role: role, selectors: selectors)
    }) != nil
}

func hasTextArea<Node: ElementNode>(_ window: Node) -> Bool {
    firstMatch(in: window, where: { $0.role == kAXTextAreaRole as String }) != nil
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

// The button rules below take a label already read, so a walk that reads
// each button's label once (messageAffordances, the readiness scan) can test
// it against several of them without restating any.

/// The collapsed stand-in for a message's whole action bar; never on an app
/// without one.
func isMessageActionsToggleLabel(_ label: String, selectors: AppSelectors) -> Bool {
    guard let actions = selectors.messageActionsLabel else { return false }
    return label.localizedCaseInsensitiveContains(actions)
}

/// The control that stops a reply in progress.
func isStopButtonLabel(_ label: String, selectors: AppSelectors) -> Bool {
    label.localizedCaseInsensitiveContains(selectors.stopKeyword)
}

/// The remove button on a long paste's attachment chip; never on an app
/// that does not turn long pastes into chips.
func isPastedTextRemoveLabel(_ label: String, selectors: AppSelectors) -> Bool {
    guard let remove = selectors.pastedTextAttachmentRemoveLabel else { return false }
    return label.localizedCaseInsensitiveContains(remove)
}

func isCopyButton<Node: ElementNode>(_ element: Node, selectors: AppSelectors) -> Bool {
    guard element.role == kAXButtonRole as String else { return false }
    return isCopyButtonLabel(element.label, selectors: selectors)
}

/// The collapsed stand-in for a message's whole action bar (Claude Code's
/// "Show message actions"); pressing it mounts the bar and removes itself.
func isMessageActionsToggle<Node: ElementNode>(_ element: Node, selectors: AppSelectors) -> Bool {
    guard selectors.messageActionsLabel != nil else { return false }
    guard element.role == kAXButtonRole as String else { return false }
    return isMessageActionsToggleLabel(element.label, selectors: selectors)
}

func copyButtons<Node: ElementNode>(under root: Node, selectors: AppSelectors) -> [Node] {
    var results: [Node] = []
    findAll(in: root, where: { isCopyButton($0, selectors: selectors) }, into: &results)
    return results
}

/// Exactly one per rendered message: its mounted copy button, or the collapsed
/// toggle standing in for the bar. Counting these is counting messages, which
/// is what the completion baselines actually need; the tree walk is
/// depth-first, so the last element belongs to the newest message. Role and
/// label are read once per node for both rules: this walk runs on every
/// tick of a reply wait, and each read is IPC into the app.
func messageAffordances<Node: ElementNode>(under root: Node, selectors: AppSelectors) -> [Node] {
    var results: [Node] = []
    findAll(in: root, where: { el in
        guard el.role == kAXButtonRole as String else { return false }
        let label = el.label
        return isCopyButtonLabel(label, selectors: selectors)
            || isMessageActionsToggleLabel(label, selectors: selectors)
    }, into: &results)
    return results
}

/// The absolute ordinal of a conversation message, where the surface numbers
/// them: Claude names each one "Message N" (an AXGroup article, user and
/// assistant messages alike — the name arrives in AXDescription, so it is
/// read through the joined label, with AXTitle kept as a candidate). nil for
/// everything else — including the sidebar hazards ("Message actions
/// button…" session rows are AXButtons, and the whole-string numeric parse
/// rejects any label with more after the number). The label is read only
/// when the title does not parse, which saves a read on every group whose
/// title answers without changing which text wins.
func messageOrdinal<Node: ElementNode>(_ element: Node) -> Int? {
    guard element.role == kAXGroupRole as String else { return nil }
    return ordinal(inMessageName: element.title) ?? ordinal(inMessageName: element.label)
}

private func ordinal(inMessageName text: String?) -> Int? {
    guard let text, text.hasPrefix("Message ") else { return nil }
    return Int(text.dropFirst("Message ".count))
}

/// The newest message's ordinal, nil where messages are unnumbered (ChatGPT).
/// This is the completion signal that survives list virtualization: Claude
/// unmounts older messages as a conversation grows — observed live Aug 28
/// 2026 with only "Message 6"–"Message 8" mounted of 8 — so the affordance
/// count can plateau or fall while the ordinal of the always-mounted newest
/// message keeps rising.
///
/// One walk that keeps the highest ordinal as it goes, so each group's
/// ordinal is read once and nothing is collected.
func lastMessageOrdinal<Node: ElementNode>(under root: Node) -> Int? {
    var newest: Int?
    var none: [Node] = []
    findAll(in: root, where: { el in
        if let ordinal = messageOrdinal(el) { newest = max(newest ?? ordinal, ordinal) }
        return false
    }, into: &none)
    return newest
}

func hasStopButton<Node: ElementNode>(under root: Node, selectors: AppSelectors) -> Bool {
    firstMatch(in: root, where: { el in
        guard el.role == kAXButtonRole as String else { return false }
        return isStopButtonLabel(el.label, selectors: selectors)
    }) != nil
}

func isSendButtonLabel(_ label: String, selectors: AppSelectors) -> Bool {
    guard label.localizedCaseInsensitiveContains(selectors.sendKeyword) else { return false }
    for exclude in selectors.sendExcludeKeywords
        where label.localizedCaseInsensitiveContains(exclude) { return false }
    return true
}

func sendButton<Node: ElementNode>(under root: Node, selectors: AppSelectors) -> Node? {
    firstMatch(in: root, where: { el in
        guard el.role == kAXButtonRole as String else { return false }
        return isSendButtonLabel(el.label, selectors: selectors)
    })
}

/// Count the long-paste attachment chips under one composer container. The
/// caller deliberately supplies the app's composer container rather than
/// the whole window: sent messages retain the same pasted-text controls in the
/// conversation history and must not confirm a new paste.
func pastedTextAttachmentCount<Node: ElementNode>(under root: Node,
                                                   selectors: AppSelectors) -> Int {
    guard selectors.pastedTextAttachmentRemoveLabel != nil else { return 0 }
    var results: [Node] = []
    findAll(in: root, where: { element in
        element.role == kAXButtonRole as String
            && isPastedTextRemoveLabel(element.label, selectors: selectors)
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

/// The last text area in the window — composers sit at the bottom. The live
/// inputArea prefers the focused element; this is its shared fallback.
/// Every composer on every surface of both apps is an AXTextArea; a text
/// field is something else, and it can come after the composer: ChatGPT's
/// terminal panel mounts one ("Terminal input") below it in the tree (live
/// Sep 24 2026), and a paste there, with the Return that sends it, runs the
/// message as a shell command.
func composerElement<Node: ElementNode>(under root: Node) -> Node? {
    var areas: [Node] = []
    findAll(in: root, where: { $0.role == kAXTextAreaRole as String }, into: &areas)
    return areas.last
}

/// The subroles Chromium gives role="dialog" and role="alertdialog". Neither
/// app's windows carry one at rest.
let dialogSubroles: Set<String> = ["AXApplicationDialog", "AXApplicationAlertDialog"]

/// The dialog open in the window, if any: the last in tree order, since a
/// dialog mounts at the end of the document, over what came before it.
func openDialog<Node: ElementNode>(under root: Node) -> Node? {
    var dialogs: [Node] = []
    findAll(in: root, where: { element in
        element.role == kAXGroupRole as String
            && element.subrole.map(dialogSubroles.contains) == true
    }, into: &dialogs)
    return dialogs.last
}

/// The dialog standing over the conversation, when one does. Claude's image
/// viewer is a modal dialog ("Image preview"), and while it is open Chromium
/// exposes nothing behind it: no composer, no copy buttons, no "Message N",
/// no Stop (live Sep 25 2026, the claude-code-image-viewer fixture — about
/// 870 elements down to 66). Read as it stands, that tree says the reply
/// is over and has nothing to copy, which is how a run on Sep 24 2026
/// ended on "Couldn't copy Claude's reply" with the reply still streaming
/// behind the viewer. Both signals are required: a dialog alone can be a
/// popover that leaves the conversation readable (and pressable — AXPress
/// does not hit-test), and a missing composer alone says nothing the human
/// could close.
func coveringDialog<Node: ElementNode>(under window: Node) -> Node? {
    guard !hasTextArea(window) else { return nil }
    return openDialog(under: window)
}

/// What a dialog is called, for the human: its title, which is where
/// Claude's viewer keeps "Image preview", else its joined label; empty
/// when it has neither.
func dialogName<Node: ElementNode>(_ dialog: Node) -> String {
    let title = (dialog.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? dialog.label.trimmingCharacters(in: .whitespacesAndNewlines) : title
}

// MARK: - Live entry points

func isExcludedWindow(_ window: AXUIElement, selectors: AppSelectors) -> Bool {
    isExcludedWindow(LiveElement(ax: window), selectors: selectors)
}

/// Whether a window element still answers: one the app has torn down
/// replies invalidUIElement to every read. An app that is merely slow
/// (cannotComplete) still has the window.
func windowIsAlive(_ window: AXUIElement) -> Bool {
    axAttributeResult(window, kAXRoleAttribute).error != .invalidUIElement
}

func chatWindow(in target: TargetApp) -> AXUIElement? {
    if let bound = target.boundWindow {
        // The chosen window or nothing. A general search here could hand a
        // copy or a paste to another window of the same app, which is the
        // one substitution setup exists to rule out.
        return windowIsAlive(bound) ? bound : nil
    }
    return chooseChatWindow(from: axWindows(target).map(LiveElement.init),
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

/// The name of the dialog covering the target's conversation (see
/// coveringDialog) — "" when it has none — or nil when nothing covers it.
/// One walk while the composer is there; the dialog is looked for only in
/// a window without one, which is a small tree when it is covered.
func coveringDialogName(in target: TargetApp) -> String? {
    guard let root = chatWindow(in: target) else { return nil }
    return coveringDialog(under: LiveElement(ax: root)).map(dialogName)
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

/// Which way `inputArea` found the composer. The two answer differently
/// once the app rebuilds its composer or moves focus, and a paste is
/// verified against whichever element was handed back — so the debug log
/// names the way alongside the element.
enum InputAreaSource: String {
    case focused = "the focused element"
    case lastTextArea = "the window's last text area"
}

func resolveInputArea(in target: TargetApp) -> (element: AXUIElement, source: InputAreaSource)? {
    guard let root = chatWindow(in: target) else { return nil }
    // Prefer the focused element, but only if it lives in the chat window;
    // focus could be on another window (e.g. a Claude Code session).
    if let focused = axAttribute(target.ax, kAXFocusedUIElementAttribute) {
        let el = focused as! AXUIElement
        if axAttribute(el, kAXRoleAttribute) as? String == kAXTextAreaRole as String,
           let window = axAttribute(el, kAXWindowAttribute),
           CFEqual(window, root) {
            return (el, .focused)
        }
    }
    return composerElement(under: LiveElement(ax: root)).map { ($0.ax, .lastTextArea) }
}

func inputArea(in target: TargetApp) -> AXUIElement? {
    resolveInputArea(in: target)?.element
}

func composerValue(in target: TargetApp) -> String? {
    guard let input = inputArea(in: target) else { return nil }
    return axAttribute(input, kAXValueAttribute) as? String
}
