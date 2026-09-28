// The per-window scan: one walk of a window's tree for everything the
// readiness sweep and the setup flow read from it. It is detection, not
// readiness, so it lives beside the element finders.
//
// Detection is grounded in what the apps expose over AX (verified live,
// Aug 2026):
// - ChatGPT's Chat/Work surfaces are named by the composer-level toggle pair
//   (the "Composer mode" group); its AXPopUpButton labeled "Switch mode,
//   current mode: <mode>" says "ChatGPT" for both and only distinguishes
//   Codex mode.
// - Claude Desktop windows carry an AXWebArea whose AXURL is a claude.ai
//   URL, and its first path component names the surface ("epitaxy" is a
//   Claude Code session; the mapping lives in AppSelectors.surfacePathNames).

import ApplicationServices
import Foundation

// MARK: - Per-window scan

/// Everything the status needs from one window, collected in a single tree
/// walk. AX reads are synchronous IPC into the target app and the scan
/// repeats every few seconds, so labels are only read on the few roles that
/// can carry a signal.
struct WindowScan {
    var title = ""
    var hasComposer = false
    /// Carries a window-exclusion marker (a Claude Code session, not a chat).
    var isExcluded = false
    /// Raw mode name from the app's mode switcher popup.
    var modeLabel: String?
    /// Display name of the selected composer surface tab ("Chat"/"Cowork"
    /// on Claude, "Chat"/"Work" on ChatGPT).
    var surfaceTab: String?
    /// Surface named by the composer placeholder, for windows where the
    /// toggle pair is not mounted (ChatGPT conversations).
    var composerSurface: String?
    /// Model announcement, prefix stripped ("Fable 5 · Extra"), or the bare
    /// model popup title on Claude Code ("Fable 5").
    var model: String?
    /// Effort from a separate effort popup (Claude Code's "Effort: Extra");
    /// nil where the model announcement already embeds it.
    var effort: String?
    /// Label of the popup visited just before the current one, for the
    /// model-precedes-effort adjacency on Claude Code.
    var lastPopupLabel: String?
    /// First path component of the window's claude.ai AXWebArea URL.
    var surfacePath: String?
    /// The path of the window's web-area URL when it names one conversation
    /// (AppSelectors.conversationRoutePrefixes): "/chat/<uuid>" on a Claude
    /// chat, "/epitaxy/<id>" on a Claude Code session. nil on a fresh chat,
    /// a Cowork task, a project page, and everywhere ChatGPT.
    var conversationRoute: String?
    /// The value and label of the window's last text area outside a side
    /// panel — the composer, the way `composerElement` picks it — for
    /// judging what it holds (classifyComposer) without a second walk. nil
    /// when the window has no such text area.
    var composerValue: String?
    var composerLabel = ""
    /// A stop control is mounted: the app is producing a reply.
    var isReplying = false
    /// Pasted-text attachment chips anywhere in the window. Coarse — the
    /// composer-scoped count needs the live parent walk — so a chip left in
    /// the history can count; a connection's readiness reads the precise one.
    var attachmentChips = 0
    /// The name of the dialog standing over the conversation, when the
    /// window has no composer because one does (coveringDialog); "" for a
    /// dialog with no name.
    var coveredBy: String?
}

/// The text after `prefix` in a joined AX label. axLabel concatenates several
/// attributes, so an announcement can appear twice; only the text between
/// occurrences counts.
func value(after prefix: String, in label: String) -> String? {
    guard let range = label.range(of: prefix) else { return nil }
    var rest = String(label[range.upperBound...])
    if let repeated = rest.range(of: prefix) { rest = String(rest[..<repeated.lowerBound]) }
    let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Generic over ElementNode, so fixture windows scan through the identical
/// code the live sweep runs.
func scanWindow<Node: ElementNode>(_ window: Node, selectors: AppSelectors) -> WindowScan {
    var scan = WindowScan()
    scan.title = window.title ?? ""
    var path: [Node] = []
    visit(window, depth: 0, path: &path, into: &scan, selectors: selectors)
    // Only a window without a composer is walked again, and a covered one
    // is a small tree: the dialog hides everything behind it.
    if !scan.hasComposer, let dialog = openDialog(under: window) {
        scan.coveredBy = dialogName(dialog)
    }
    return scan
}

/// `path` holds the nodes above `element`, the window first; they are read
/// only for a text area's side-panel check (isInSidePanel).
private func visit<Node: ElementNode>(_ element: Node, depth: Int, path: inout [Node],
                                      into scan: inout WindowScan, selectors: AppSelectors) {
    guard depth <= axMaxTreeDepth else { return }
    let role = element.role ?? ""

    if role == kAXButtonRole as String {
        // One label read serves every rule a button can match. The
        // exclusion rule is shared with the relay's own window choice
        // rather than restated: the readiness sweep must classify a window exactly
        // the way chooseChatWindow will, and two copies of the rule drift.
        let label = element.label
        if !scan.isExcluded, isExclusionMarker(role: role, label: label, selected: false, selectors: selectors) {
            scan.isExcluded = true
        }
        if !scan.isReplying, isStopButtonLabel(label, selectors: selectors) {
            scan.isReplying = true
        }
        if isPastedTextRemoveLabel(label, selectors: selectors) {
            scan.attachmentChips += 1
        }
    } else if role == kAXTextAreaRole as String || role == kAXTextFieldRole as String {
        let label = element.label
        if role == kAXTextAreaRole as String {
            scan.hasComposer = true
            // The last text area in tree order outside a side panel is the
            // composer, exactly as composerElement picks it; each one seen
            // overwrites the last.
            if !isInSidePanel(path) {
                if scan.composerSurface == nil, !selectors.composerSurfaceNames.isEmpty {
                    scan.composerSurface = selectors.composerSurfaceNames
                        .first { label.contains($0.key) }?.value
                }
                scan.composerValue = element.stringValue
                scan.composerLabel = label
            }
        } else if !scan.isExcluded, isExclusionMarker(role: role, label: label, selected: false, selectors: selectors) {
            scan.isExcluded = true
        }
    } else if role == kAXRadioButtonRole as String, !scan.isExcluded,
              isExclusionMarker(element, role: role, selectors: selectors) {
        scan.isExcluded = true
    } else if role == kAXPopUpButtonRole as String {
        let wantsMode = scan.modeLabel == nil && selectors.modePopupPrefix != nil
        let wantsModel = scan.model == nil
            && (selectors.modelPopupPrefix != nil || !selectors.modelPopupSuffixes.isEmpty
                || selectors.modelPopupDefaultLabel != nil)
        let wantsEffort = scan.effort == nil && selectors.effortPopupPrefix != nil
        if wantsMode || wantsModel || wantsEffort {
            let label = element.label
            if wantsMode, let prefix = selectors.modePopupPrefix {
                scan.modeLabel = value(after: prefix, in: label)
            }
            if wantsModel {
                if let prefix = selectors.modelPopupPrefix, label.contains(prefix) {
                    scan.model = value(after: prefix, in: label)
                } else if selectors.modelPopupPrefix == nil {
                    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lower = trimmed.lowercased()
                    if selectors.modelPopupSuffixes.contains(where: {
                        lower == $0 || lower.hasSuffix(" " + $0)
                    }) {
                        scan.model = trimmed
                    } else if trimmed == selectors.modelPopupDefaultLabel {
                        scan.model = "Default"
                    }
                }
            }
            if wantsEffort, let prefix = selectors.effortPopupPrefix, label.contains(prefix) {
                scan.effort = value(after: prefix, in: label)
                // The bare-titled model popup sits immediately before the
                // effort popup (verified live on Claude Code, Aug 2026).
                if scan.model == nil, let previous = scan.lastPopupLabel, !previous.isEmpty {
                    scan.model = previous
                }
            }
            scan.lastPopupLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    } else if role == kAXRadioButtonRole as String || role == kAXCheckBoxRole as String {
        // Claude's surface tabs are AXRadioButtons, ChatGPT's are AXCheckBox
        // toggle buttons; the title match keeps ordinary checkboxes out.
        if scan.surfaceTab == nil, !selectors.surfaceTabNames.isEmpty,
           let title = element.title,
           let name = selectors.surfaceTabNames.first(where: {
               $0.caseInsensitiveCompare(title) == .orderedSame
           }),
           element.numberValue == 1 {
            scan.surfaceTab = name
        }
    } else if role == "AXWebArea" {
        // Only the app's own web host counts: Claude's window also carries
        // the outer file:// shell, and ChatGPT's an app:// one.
        if let url = element.url, let host = url.host,
           selectors.identityHosts.contains(where: { host.localizedCaseInsensitiveContains($0) }) {
            let components = url.path.split(separator: "/").map { String($0) }
            if scan.surfacePath == nil, !selectors.surfacePathNames.isEmpty {
                scan.surfacePath = components.first?.lowercased()
            }
            if scan.conversationRoute == nil, components.count >= 2,
               selectors.conversationRoutePrefixes.contains(components[0].lowercased()) {
                scan.conversationRoute = url.path
            }
        }
    }

    path.append(element)
    for child in element.children {
        visit(child, depth: depth + 1, path: &path, into: &scan, selectors: selectors)
    }
    path.removeLast()
}

/// Human name for a window's active surface, best signal first: the selected
/// composer tab (ChatGPT's mode popup says "ChatGPT" for both Chat and Work,
/// and Claude's Chat/Cowork share a URL, so the tab outranks everything),
/// then the composer placeholder (ChatGPT unmounts the tab pair inside a
/// conversation), then the app's mode switcher (still tells Codex apart),
/// then the claude.ai URL, then the exclusion markers.
func surfaceName(_ scan: WindowScan, selectors: AppSelectors) -> String? {
    if let tab = scan.surfaceTab { return tab }
    if let surface = scan.composerSurface { return surface }
    if let mode = scan.modeLabel {
        return selectors.modeNames[mode.lowercased()] ?? mode
    }
    if let path = scan.surfacePath {
        // Unmapped paths read fine capitalized ("cowork" -> "Cowork"); the
        // map exists only for paths whose display name differs.
        return selectors.surfacePathNames[path] ?? path.capitalized
    }
    if scan.isExcluded { return selectors.excludedSurfaceName }
    return nil
}

/// A model line's two parts, for showing the effort apart from the model:
/// the text after the line's last " · " — Claude's own announcement
/// ("Fable 5 · Extra"), and the Code pair as composeSideStatus joins it —
/// or, where the line has none, a trailing word from the app's effort
/// suffixes, which ChatGPT folds into the popup's title ("5.6 Sol High").
/// A line with neither, or with nothing before the effort, comes back
/// whole with no effort.
func splitEffort(_ line: String, selectors: AppSelectors) -> (model: String, effort: String?) {
    if let dot = line.range(of: " \u{00B7} ", options: .backwards) {
        let model = line[..<dot.lowerBound].trimmingCharacters(in: .whitespaces)
        let effort = line[dot.upperBound...].trimmingCharacters(in: .whitespaces)
        if !model.isEmpty, !effort.isEmpty { return (model, effort) }
    } else if let space = line.range(of: " ", options: .backwards) {
        let model = line[..<space.lowerBound].trimmingCharacters(in: .whitespaces)
        let effort = String(line[space.upperBound...])
        if !model.isEmpty, selectors.modelPopupSuffixes.contains(effort.lowercased()) {
            return (model, effort)
        }
    }
    return (line, nil)
}
