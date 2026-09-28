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
// each button's label once (messageAffordances, the conversation sighting,
// the readiness scan) can test it against several of them without restating
// any.

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
    return isCopyButton(element, label: element.label, selectors: selectors)
}

/// The same test for a button whose label a walk has already read: the
/// label rule on the string in hand, then, for a button it matches, whether
/// the app named the button so (isAppCommand).
func isCopyButton<Node: ElementNode>(_ button: Node, label: String, selectors: AppSelectors) -> Bool {
    isCopyButtonLabel(label, selectors: selectors)
        && isAppCommand(button, named: { isCopyButtonLabel($0, selectors: selectors) })
}

/// Whether a button is one of the app's own commands, named as `rule`
/// wants, rather than a row that shows data. A label can be data: a
/// conversation title in a sidebar, or a step summary in a Claude Code
/// transcript, is a button whose label is text the human or the model
/// wrote, and one that merely mentions copying met the copy rule ("Idle
/// Claude copy message overlay issue", "Applied the rule to the readiness
/// scan and the copy press", live Sep 28 2026). Both apps name their
/// commands for assistive technology, an aria-label that Chromium reports
/// as AXDescription, and draw them as icons with no text of their own. A
/// row is named by the text it shows, which Chromium reports as AXTitle
/// (Claude's rows and both apps' text buttons), or it shows that text
/// inside it (ChatGPT's conversation rows, which carry an aria-label as
/// well). So the rule must match the AXDescription, and nothing in the
/// button may be text. Only a button whose label the rule already matched
/// gets here, so the walks read this for those alone.
func isAppCommand<Node: ElementNode>(_ button: Node, named rule: (String) -> Bool) -> Bool {
    guard let name = button.axDescription, rule(name) else { return false }
    return !showsText(button)
}

/// Whether static text sits within three levels under `node`, the depth a
/// row keeps its text at (ChatGPT's, in a group of its own). Level by
/// level, so a row stops being read at the level that shows its text.
private func showsText<Node: ElementNode>(_ node: Node) -> Bool {
    var level = node.children
    for _ in 0..<3 {
        if level.isEmpty { return false }
        if level.contains(where: { $0.role == kAXStaticTextRole as String }) { return true }
        level = level.flatMap(\.children)
    }
    return false
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

/// The copy button the newest reply is taken with: the last in tree order,
/// the walk being depth-first, but never one in a side panel
/// (sidePanelSubrole). ChatGPT's file pane comes after the conversation, so
/// its "Copy Markdown" was the last match, and pressing it took the open
/// file as the reply.
func replyCopyButton<Node: ElementNode>(under root: Node, selectors: AppSelectors) -> Node? {
    lastOutsideSidePanel(under: root, where: { isCopyButton($0, selectors: selectors) })
}

/// Exactly one per rendered message: its mounted copy button, or the collapsed
/// toggle standing in for the bar. Counting these is counting messages, which
/// is what the completion baselines actually need; the tree walk is
/// depth-first, so the last element belongs to the newest message. Role and
/// label are read once per node for both rules, since each read is IPC into
/// the app. The reply wait counts them through conversationSighting, which
/// makes the same test in its one walk.
func messageAffordances<Node: ElementNode>(under root: Node, selectors: AppSelectors) -> [Node] {
    var results: [Node] = []
    findAll(in: root, where: { isMessageAffordance($0, selectors: selectors) }, into: &results)
    return results
}

/// The newest message's affordance: the last one outside a side panel, as
/// replyCopyButton picks the copy button, so a copy button in a pane cannot
/// stand in for the collapsed bar the newest message still needs expanded.
func newestMessageAffordance<Node: ElementNode>(under root: Node, selectors: AppSelectors) -> Node? {
    lastOutsideSidePanel(under: root, where: { isMessageAffordance($0, selectors: selectors) })
}

private func isMessageAffordance<Node: ElementNode>(_ element: Node, selectors: AppSelectors) -> Bool {
    guard element.role == kAXButtonRole as String else { return false }
    let label = element.label
    return isCopyButton(element, label: label, selectors: selectors)
        || isMessageActionsToggleLabel(label, selectors: selectors)
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
    return messageOrdinal(ofGroup: element)
}

/// The same rule for a node already known to be an AXGroup, so a walk that
/// has read the role does not read it again.
private func messageOrdinal<Node: ElementNode>(ofGroup element: Node) -> Int? {
    ordinal(inMessageName: element.title) ?? ordinal(inMessageName: element.label)
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

/// What the relay reads of a conversation while it waits on a reply and
/// before it copies one, from a single walk of the window: the message
/// affordances (messageAffordances' count), the newest message's ordinal
/// (lastMessageOrdinal), whether a reply is streaming (hasStopButton), and
/// whether the window has a composer at all (hasTextArea), which is the
/// first half of the cover check. The response wait polls every 1.2 s for
/// as long as a reply takes, and the capture gate once a second while
/// held; made separately, the four walked the whole window four times,
/// every node's role read in each over IPC into an app busy streaming.
struct ConversationSighting: Equatable {
    var affordances = 0
    var lastOrdinal: Int?
    var streaming = false
    var hasComposer = false
}

/// Generic over ElementNode, so fixture windows answer through the code the
/// live poll runs; ConversationSightingTests pins it to the four finders it
/// stands in for, fixture by fixture. Role is read once per node, a
/// button's label once for all three button rules (and a copy match's
/// description and children once more, isAppCommand), and a group's title
/// (then label) only as messageOrdinal reads them. Dialogs stay out of the
/// walk: the cover check looks for one only when this found no composer
/// (coveringDialog(under:sighting:)), as scanWindow does.
func conversationSighting<Node: ElementNode>(under root: Node,
                                             selectors: AppSelectors) -> ConversationSighting {
    var sighting = ConversationSighting()
    sight(root, depth: 0, into: &sighting, selectors: selectors)
    return sighting
}

private func sight<Node: ElementNode>(_ element: Node, depth: Int,
                                      into sighting: inout ConversationSighting,
                                      selectors: AppSelectors) {
    guard depth <= axMaxTreeDepth else { return }
    let role = element.role ?? ""
    if role == kAXButtonRole as String {
        let label = element.label
        if isCopyButton(element, label: label, selectors: selectors)
            || isMessageActionsToggleLabel(label, selectors: selectors) {
            sighting.affordances += 1
        }
        if !sighting.streaming, isStopButtonLabel(label, selectors: selectors) {
            sighting.streaming = true
        }
    } else if role == kAXGroupRole as String {
        if let ordinal = messageOrdinal(ofGroup: element) {
            sighting.lastOrdinal = max(sighting.lastOrdinal ?? ordinal, ordinal)
        }
    } else if role == kAXTextAreaRole as String {
        sighting.hasComposer = true
    }
    for child in element.children {
        sight(child, depth: depth + 1, into: &sighting, selectors: selectors)
    }
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

/// The subrole Chromium gives role="complementary", an <aside>: content that
/// supports the page's main content rather than being part of it. ChatGPT
/// mounts its file pane in one (live Sep 28 2026), after the conversation in
/// tree order, and the pane holds an editable text area with the open file's
/// text (CodeMirror) and a "Copy Markdown" button that the copy rule
/// matches. A composer, and the copy button on a reply, are the page's main
/// content by definition, so nothing inside a side panel is either.
let sidePanelSubrole = "AXLandmarkComplementary"

/// Whether any of these nodes, a candidate's ancestors, is a side panel. One
/// subrole read per node until one is, so it weighs the ancestors of a few
/// candidates, never every node of a walk.
func isInSidePanel<Nodes: Sequence>(_ ancestors: Nodes) -> Bool where Nodes.Element: ElementNode {
    ancestors.contains { $0.subrole == sidePanelSubrole }
}

/// The last node the predicate accepts that is not inside a side panel. The
/// matches are weighed from the last back, so only those after the answer
/// have their ancestors read, and the answer's own.
func lastOutsideSidePanel<Node: ElementNode>(under root: Node, where predicate: (Node) -> Bool) -> Node? {
    findAllWithAncestors(in: root, where: predicate).last { !isInSidePanel($0.ancestors) }?.node
}

/// The last text area in the window outside a side panel: composers sit at
/// the bottom of the conversation. The live inputArea prefers the focused
/// element; this is its shared fallback. Every composer on every surface of
/// both apps is an AXTextArea; a text field is something else, and it can
/// come after the composer: ChatGPT's terminal panel mounts one ("Terminal
/// input") below it in the tree (live Sep 24 2026), and a paste there, with
/// the Return that sends it, runs the message as a shell command. A text
/// area can come after it too, in a side panel: ChatGPT's file editor, whose
/// text read as the human's unsent draft (sidePanelSubrole).
func composerElement<Node: ElementNode>(under root: Node) -> Node? {
    lastOutsideSidePanel(under: root, where: { $0.role == kAXTextAreaRole as String })
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

/// The same check with the composer already looked for, by a sighting of
/// this window: the dialog is searched for only when it found none.
func coveringDialog<Node: ElementNode>(under window: Node,
                                       sighting: ConversationSighting) -> Node? {
    guard !sighting.hasComposer else { return nil }
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

func replyCopyButton(in target: TargetApp) -> AXUIElement? {
    guard let root = chatWindow(in: target) else { return nil }
    return replyCopyButton(under: LiveElement(ax: root), selectors: target.selectors)?.ax
}

func messageAffordances(in target: TargetApp) -> [AXUIElement] {
    guard let root = chatWindow(in: target) else { return [] }
    return messageAffordances(under: LiveElement(ax: root), selectors: target.selectors).map(\.ax)
}

func newestMessageAffordance(in target: TargetApp) -> AXUIElement? {
    guard let root = chatWindow(in: target) else { return nil }
    return newestMessageAffordance(under: LiveElement(ax: root), selectors: target.selectors)?.ax
}

/// A live element's ancestors, nearest first, each parent read only when the
/// sequence is asked for it.
func axAncestors(of element: AXUIElement) -> some Sequence<LiveElement> {
    sequence(first: element) { node in
        axAttribute(node, kAXParentAttribute).map { $0 as! AXUIElement }
    }
    .dropFirst()
    .prefix(axMaxTreeDepth)
    .lazy
    .map(LiveElement.init)
}

func lastMessageOrdinal(in target: TargetApp) -> Int? {
    guard let root = chatWindow(in: target) else { return nil }
    return lastMessageOrdinal(under: LiveElement(ax: root))
}

func hasStopButton(in target: TargetApp) -> Bool {
    guard let root = chatWindow(in: target) else { return false }
    return hasStopButton(under: LiveElement(ax: root), selectors: target.selectors)
}

/// The target's conversation in one walk of its chat window (see
/// ConversationSighting); nil when it has no chat window.
func conversationSighting(in target: TargetApp) -> ConversationSighting? {
    guard let root = chatWindow(in: target) else { return nil }
    return conversationSighting(under: LiveElement(ax: root), selectors: target.selectors)
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

/// The same answer from a sighting just taken of the target's window, which
/// already says whether it has a composer: nothing more is read while it
/// does, and a window without one is walked for its dialog alone.
func coveringDialogName(in target: TargetApp, sighting: ConversationSighting) -> String? {
    guard !sighting.hasComposer, let root = chatWindow(in: target) else { return nil }
    return coveringDialog(under: LiveElement(ax: root), sighting: sighting).map(dialogName)
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
    case lastTextArea = "the window's last text area outside a side panel"
}

func resolveInputArea(in target: TargetApp) -> (element: AXUIElement, source: InputAreaSource)? {
    guard let root = chatWindow(in: target) else { return nil }
    // Prefer the focused element, but only if it lives in the chat window;
    // focus could be on another window (e.g. a Claude Code session), or on a
    // text area in one of its side panels (ChatGPT's file editor).
    if let focused = axAttribute(target.ax, kAXFocusedUIElementAttribute) {
        let el = focused as! AXUIElement
        if axAttribute(el, kAXRoleAttribute) as? String == kAXTextAreaRole as String,
           let window = axAttribute(el, kAXWindowAttribute),
           CFEqual(window, root),
           !isInSidePanel(axAncestors(of: el)) {
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
