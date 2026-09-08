#!/usr/bin/env swift
//
// ax-dump: standalone accessibility-tree inspector for Errol development.
//
// Captures the live AX tree of a running app (typically the two relay targets,
// Claude Desktop and the ChatGPT/Codex app) so detection heuristics can be built
// from real dumps instead of hovering in Xcode's Accessibility Inspector. The
// core workflow is capture-and-diff: dump a tree in one state, flip the state
// (open a panel, start a response streaming, empty the chat), dump again, and
// the diff shows exactly which elements or attributes to key on.
//
//   swift tools/ax-dump.swift --list                    # running apps and bundle IDs
//   swift tools/ax-dump.swift claude                    # summary fingerprint per window
//   swift tools/ax-dump.swift chatgpt --buttons         # distinct button labels + inputs
//   swift tools/ax-dump.swift chatgpt --prompt-geometry # input bounds, parents, nearby controls
//   swift tools/ax-dump.swift claude --tree > a.txt     # full tree; flip state, dump b.txt, diff
//   swift tools/ax-dump.swift claude --find stop        # every attribute of matching elements
//   swift tools/ax-dump.swift claude --menus            # menu bar (hover-free AX targets)
//
// "claude" and "chatgpt"/"codex" resolve to the bundle IDs from Core/Config.swift;
// anything else matches a bundle ID or app name of a running app.
//
// Permission: the *invoking* process needs Accessibility — macOS attributes it to
// the responsible app: your terminal when run by hand, Claude.app when run from a
// Claude Code shell (agent note: run with the Bash sandbox disabled, it blocks the
// AX server). Grant it in System Settings > Privacy & Security > Accessibility —
// renamed "Device Control and Data Access" in the macOS 27 beta; this deep link
// still lands there:
//   open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
//
// Output is diff-friendly: stable ordering, no timestamps, frames off unless
// --frames (window positions would pollute every diff), values truncated. Both
// target apps are Chromium and publish an empty tree until nudged, so the same
// AXManualAccessibility/AXEnhancedUserInterface nudge Errol applies at run start
// (Core/TargetApp.swift) is applied here before reading.

import AppKit
import ApplicationServices

// MARK: - AX helpers (same idioms as app/Errol/Errol/Core/Accessibility.swift)

func axAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return err == .success ? value : nil
}

/// One IPC round trip for all attributes of an element; per-attribute reads make
/// full-tree dumps of long conversations take minutes.
func axMultiple(_ element: AXUIElement, _ names: [String]) -> [String: CFTypeRef] {
    var values: CFArray?
    let err = AXUIElementCopyMultipleAttributeValues(
        element, names as CFArray, AXCopyMultipleAttributeOptions(), &values)
    guard err == .success, let list = values as? [AnyObject] else { return [:] }
    var out: [String: CFTypeRef] = [:]
    for (index, name) in names.enumerated() where index < list.count {
        let value = list[index] as CFTypeRef
        // Unreadable attributes come back as AXValue error placeholders.
        if CFGetTypeID(value) == AXValueGetTypeID(),
           AXValueGetType(value as! AXValue) == .axError { continue }
        out[name] = value
    }
    return out
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    (axAttribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

let labelAttributes = [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute, "AXLabel"]

func label(from attrs: [String: CFTypeRef]) -> String {
    labelAttributes.compactMap { attrs[$0] as? String }
        .filter { !$0.isEmpty }.joined(separator: " ")
}

func axLabel(_ element: AXUIElement) -> String {
    label(from: axMultiple(element, labelAttributes))
}

func truncate(_ string: String, _ limit: Int) -> String {
    let flat = string.replacingOccurrences(of: "\n", with: "\\n")
    return flat.count <= limit ? flat : String(flat.prefix(limit)) + "…"
}

/// Human-readable rendering of any AX attribute value.
func describeValue(_ value: CFTypeRef) -> String {
    if let string = value as? String { return "\"\(truncate(string, 120))\"" }
    if CFGetTypeID(value) == CFBooleanGetTypeID() {
        return (value as! Bool) ? "true" : "false"
    }
    if let number = value as? NSNumber { return number.stringValue }
    if CFGetTypeID(value) == AXUIElementGetTypeID() {
        let element = value as! AXUIElement
        let attrs = axMultiple(element, [kAXRoleAttribute] + labelAttributes)
        let role = attrs[kAXRoleAttribute] as? String ?? "?"
        let name = truncate(label(from: attrs), 40)
        return name.isEmpty ? "<\(role)>" : "<\(role) \"\(name)\">"
    }
    if CFGetTypeID(value) == AXValueGetTypeID() {
        let axValue = value as! AXValue
        switch AXValueGetType(axValue) {
        case .cgPoint:
            var point = CGPoint.zero
            AXValueGetValue(axValue, .cgPoint, &point)
            return "(x:\(Int(point.x)), y:\(Int(point.y)))"
        case .cgSize:
            var size = CGSize.zero
            AXValueGetValue(axValue, .cgSize, &size)
            return "(w:\(Int(size.width)), h:\(Int(size.height)))"
        case .cgRect:
            var rect = CGRect.zero
            AXValueGetValue(axValue, .cgRect, &rect)
            return "(x:\(Int(rect.minX)), y:\(Int(rect.minY)), w:\(Int(rect.width)), h:\(Int(rect.height)))"
        case .cfRange:
            var range = CFRange()
            AXValueGetValue(axValue, .cfRange, &range)
            return "(loc:\(range.location), len:\(range.length))"
        default:
            break
        }
    }
    if let array = value as? [AnyObject] {
        if array.isEmpty { return "[]" }
        let sample = array.prefix(3).map { describeValue($0 as CFTypeRef) }.joined(separator: ", ")
        return "[\(array.count): \(sample)\(array.count > 3 ? ", …" : "")]"
    }
    return truncate(String(describing: value), 80)
}

// MARK: - Element rendering

struct Options {
    enum Mode { case list, summary, tree, buttons, find(String), menus, capture, promptGeometry }
    var mode = Mode.summary
    var appSpec: String?
    var windowIndex: Int?
    var maxDepth = 80
    var frames = false
    var values = true
}

let lineAttributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXValueAttribute,
                      kAXEnabledAttribute, kAXFocusedAttribute, kAXPositionAttribute,
                      kAXSizeAttribute, "AXMenuItemCmdChar"] + labelAttributes

func elementLine(_ element: AXUIElement, options: Options) -> String {
    let attrs = axMultiple(element, lineAttributes)
    let role = attrs[kAXRoleAttribute] as? String ?? "?"
    var parts = ["[\(role)]"]
    if let subrole = attrs[kAXSubroleAttribute] as? String { parts.append("(\(subrole))") }
    let name = label(from: attrs).trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty { parts.append("\"\(truncate(name, 80))\"") }
    if options.values, let value = attrs[kAXValueAttribute] {
        parts.append("value=\(describeValue(value))")
    }
    if let cmdChar = attrs["AXMenuItemCmdChar"] as? String, !cmdChar.isEmpty {
        parts.append("[Cmd+\(cmdChar)]")
    }
    if let enabled = attrs[kAXEnabledAttribute] as? Bool, !enabled { parts.append("(disabled)") }
    if let focused = attrs[kAXFocusedAttribute] as? Bool, focused { parts.append("(focused)") }
    if options.frames,
       let posValue = attrs[kAXPositionAttribute], CFGetTypeID(posValue) == AXValueGetTypeID(),
       let sizeValue = attrs[kAXSizeAttribute], CFGetTypeID(sizeValue) == AXValueGetTypeID() {
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        parts.append("frame=(\(Int(position.x)),\(Int(position.y)) \(Int(size.width))x\(Int(size.height)))")
    }
    return parts.joined(separator: " ")
}

func walk(_ element: AXUIElement, depth: Int = 0, path: String = "",
          options: Options, visit: (AXUIElement, Int, String) -> Void) {
    visit(element, depth, path)
    guard depth < options.maxDepth else { return }
    for (index, child) in axChildren(element).enumerated() {
        walk(child, depth: depth + 1, path: path.isEmpty ? "\(index)" : "\(path).\(index)",
             options: options, visit: visit)
    }
}

// MARK: - Modes

func selectedWindows(_ appElement: AXUIElement, options: Options) -> [(Int, AXUIElement)] {
    let windows = (axAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    let indexed = Array(windows.enumerated())
    guard let only = options.windowIndex else { return indexed }
    guard only >= 0 && only < windows.count else {
        fail("window index \(only) out of range; app has \(windows.count) window(s)")
    }
    return [indexed[only]]
}

func windowHeading(_ index: Int, _ window: AXUIElement, appElement: AXUIElement) -> String {
    let title = (axAttribute(window, kAXTitleAttribute) as? String) ?? ""
    var markers = ""
    if let main = axAttribute(appElement, kAXMainWindowAttribute), CFEqual(main, window) {
        markers += " [main]"
    }
    if let focused = axAttribute(appElement, kAXFocusedWindowAttribute), CFEqual(focused, window) {
        markers += " [focused]"
    }
    return "-- Window \(index): \"\(title)\"\(markers)"
}

func runSummary(_ appElement: AXUIElement, options: Options) {
    for (index, window) in selectedWindows(appElement, options: options) {
        print(windowHeading(index, window, appElement: appElement))
        var roleCounts: [String: Int] = [:]
        var buttonLabels: [String: Int] = [:]
        var inputs: [String] = []
        walk(window, options: options) { element, _, _ in
            let attrs = axMultiple(element, [kAXRoleAttribute] + labelAttributes)
            let role = attrs[kAXRoleAttribute] as? String ?? "?"
            roleCounts[role, default: 0] += 1
            if role == kAXButtonRole as String {
                let name = label(from: attrs).trimmingCharacters(in: .whitespacesAndNewlines)
                buttonLabels[name.isEmpty ? "<unlabeled>" : name, default: 0] += 1
            }
            if role == kAXTextAreaRole as String || role == kAXTextFieldRole as String {
                inputs.append("[\(role)] \"\(truncate(label(from: attrs), 60))\"")
            }
        }
        let counts = roleCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("   roles: \(counts)")
        print("   buttons: \(buttonLabels.values.reduce(0, +)) total, \(buttonLabels.count) distinct")
        print("   text inputs: \(inputs.count)\(inputs.isEmpty ? "" : "  " + inputs.joined(separator: "  "))")
    }
}

func runTree(_ appElement: AXUIElement, options: Options) {
    for (index, window) in selectedWindows(appElement, options: options) {
        print(windowHeading(index, window, appElement: appElement))
        walk(window, options: options) { element, depth, _ in
            print(String(repeating: "  ", count: depth + 1) + elementLine(element, options: options))
        }
    }
}

// MARK: - Prompt geometry

/// Keep fractional screen coordinates and identifiers; omit text values. A long
/// editor's AX frame may be its full document, not its visible scroll viewport.
func promptGeometryLine(_ element: AXUIElement) -> String {
    let attrs = axMultiple(element, [kAXRoleAttribute, kAXSubroleAttribute,
        kAXPositionAttribute, kAXSizeAttribute, kAXEnabledAttribute, kAXFocusedAttribute,
        "AXIdentifier", "AXNumberOfCharacters", "AXVisibleCharacterRange"] + labelAttributes)
    var parts = ["[\(attrs[kAXRoleAttribute] as? String ?? "?")]"]
    for name in [kAXSubroleAttribute, "AXIdentifier"] {
        if let value = attrs[name] as? String, !value.isEmpty {
            parts.append("\(name)=\(String(reflecting: value))")
        }
    }
    let name = label(from: attrs)
    if !name.isEmpty { parts.append("label=\(String(reflecting: truncate(name, 100)))") }
    if let position = attrs[kAXPositionAttribute], CFGetTypeID(position) == AXValueGetTypeID(),
       let size = attrs[kAXSizeAttribute], CFGetTypeID(size) == AXValueGetTypeID(),
       AXValueGetType(position as! AXValue) == .cgPoint,
       AXValueGetType(size as! AXValue) == .cgSize {
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        if AXValueGetValue(position as! AXValue, .cgPoint, &point),
           AXValueGetValue(size as! AXValue, .cgSize, &dimensions) {
            parts.append("frame=(x:\(point.x), y:\(point.y), w:\(dimensions.width), h:\(dimensions.height))")
        } else {
            parts.append("frame=<unreadable>")
        }
    } else {
        parts.append("frame=<unavailable>")
    }
    for name in [kAXEnabledAttribute, kAXFocusedAttribute,
                 "AXNumberOfCharacters", "AXVisibleCharacterRange"] {
        if let value = attrs[name] { parts.append("\(name)=\(describeValue(value))") }
    }
    // A scrollbar's numeric value is useful evidence of the scroll position.
    if attrs[kAXRoleAttribute] as? String == "AXScrollBar",
       let value = axAttribute(element, kAXValueAttribute) as? NSNumber {
        parts.append("scrollValue=\(value)")
    }
    return parts.joined(separator: " ")
}

func runPromptGeometry(_ appElement: AXUIElement, options: Options) {
    print("Prompt geometry v1. Frames use AX screen coordinates (origin at top left).")
    print("Text values omitted. Parent 1 is the immediate parent; no shell is inferred.")
    var totalInputs = 0
    for (index, window) in selectedWindows(appElement, options: options) {
        print("\n-- Window \(index): \(promptGeometryLine(window))")
        var inputs: [(AXUIElement, String)] = []
        var searchBudget = 4000
        var searchTruncated = false
        func findInputs(_ element: AXUIElement, depth: Int, path: String) {
            guard searchBudget > 0 else { searchTruncated = true; return }
            searchBudget -= 1
            let role = axAttribute(element, kAXRoleAttribute) as? String
            if role == "AXTextArea" || role == "AXTextField" {
                inputs.append((element, path))
                return // Text contents cannot contain another composer.
            }
            if role == "AXStaticText" { return }
            let children = axChildren(element)
            guard depth < options.maxDepth else {
                if !children.isEmpty { searchTruncated = true }
                return
            }
            for (childIndex, child) in children.enumerated() {
                findInputs(child, depth: depth + 1, path: "\(path).\(childIndex)")
                if searchBudget == 0 { break }
            }
        }
        findInputs(window, depth: 0, path: "w\(index)")
        if searchTruncated || searchBudget == 0 { print("  <input search reached its depth/node limit>") }
        for (inputIndex, entry) in inputs.enumerated() {
            let (input, path) = entry
            totalInputs += 1
            print("\nInput \(inputIndex) at \(path): \(promptGeometryLine(input))")
            var chain = [input]
            var node = input
            for level in 1...16 {
                guard let value = axAttribute(node, kAXParentAttribute),
                      CFGetTypeID(value) == AXUIElementGetTypeID() else {
                    print("  <no readable parent>")
                    break
                }
                let ancestor = value as! AXUIElement
                guard !chain.contains(where: { CFEqual($0, ancestor) }) else {
                    print("  <parent cycle>")
                    break
                }
                print("  Parent \(level): \(promptGeometryLine(ancestor))")
                let role = axAttribute(ancestor, kAXRoleAttribute) as? String
                // Show each off-path branch once. These are the wrappers and
                // controls the shell detector can encounter in its eight hops.
                if level <= 8, ["AXGroup", "AXScrollArea", "AXLayoutArea"].contains(role ?? "") {
                    var budget = 80
                    func nearby(_ child: AXUIElement, depth: Int, path: String) {
                        guard budget > 0 else { return }
                        budget -= 1
                        print(String(repeating: "  ", count: depth + 2)
                              + "\(path): \(promptGeometryLine(child))")
                        let childRole = axAttribute(child, kAXRoleAttribute) as? String
                        if childRole == "AXTextArea" || childRole == "AXTextField"
                            || childRole == "AXStaticText" { return }
                        let children = axChildren(child)
                        guard depth < 6 else {
                            if !children.isEmpty { print("      <branch depth limit>") }
                            return
                        }
                        for (childIndex, descendant) in children.enumerated() {
                            nearby(descendant, depth: depth + 1, path: "\(path).\(childIndex)")
                            if budget == 0 { break }
                        }
                    }
                    for (childIndex, child) in axChildren(ancestor).enumerated() {
                        if CFEqual(child, node) {
                            print("    child[\(childIndex)]: <toward this input>")
                        } else {
                            nearby(child, depth: 1, path: "child[\(childIndex)]")
                        }
                    }
                    if budget == 0 { print("    <nearby branch node limit>") }
                }
                chain.append(ancestor)
                node = ancestor
                if role == "AXWindow" || role == "AXApplication" { break }
                if level == 16 { print("  <parent limit>") }
            }
        }
        if inputs.isEmpty { print("  No text inputs found in this window.") }
    }
    print("\nFound \(totalInputs) text input(s).")
}

func runButtons(_ appElement: AXUIElement, options: Options) {
    for (index, window) in selectedWindows(appElement, options: options) {
        print(windowHeading(index, window, appElement: appElement))
        var counts: [String: Int] = [:]
        var order: [String] = []
        var inputs: [String] = []
        walk(window, options: options) { element, _, _ in
            let attrs = axMultiple(element, [kAXRoleAttribute, kAXValueAttribute] + labelAttributes)
            let role = attrs[kAXRoleAttribute] as? String
            if role == kAXButtonRole as String {
                let name = label(from: attrs).trimmingCharacters(in: .whitespacesAndNewlines)
                let key = name.isEmpty ? "<unlabeled>" : name
                if counts[key] == nil { order.append(key) }
                counts[key, default: 0] += 1
            }
            if role == kAXTextAreaRole as String || role == kAXTextFieldRole as String {
                let value = (attrs[kAXValueAttribute] as? String) ?? ""
                inputs.append("[\(role!)] \"\(truncate(label(from: attrs), 60))\" value=\"\(truncate(value, 60))\"")
            }
        }
        print("   Buttons (\(counts.values.reduce(0, +)) total, \(order.count) distinct):")
        for key in order { print("     \(counts[key]!)x \(truncate(key, 100))") }
        print("   Text inputs (\(inputs.count)):")
        for input in inputs { print("     \(input)") }
    }
}

/// Every attribute of every element whose role, subrole, label, or value matches.
/// This is the "hover in Accessibility Inspector" replacement.
func runFind(_ appElement: AXUIElement, query: String, options: Options) {
    var matches = 0
    for (index, window) in selectedWindows(appElement, options: options) {
        walk(window, options: options) { element, _, path in
            let attrs = axMultiple(element, [kAXRoleAttribute, kAXSubroleAttribute,
                                             kAXValueAttribute] + labelAttributes)
            let haystack = [attrs[kAXRoleAttribute] as? String,
                            attrs[kAXSubroleAttribute] as? String,
                            label(from: attrs),
                            attrs[kAXValueAttribute] as? String]
                .compactMap { $0 }.joined(separator: " ")
            guard haystack.localizedCaseInsensitiveContains(query) else { return }
            matches += 1
            print("window \(index) path \(path.isEmpty ? "(root)" : path)")
            var names: CFArray?
            guard AXUIElementCopyAttributeNames(element, &names) == .success,
                  let attributeNames = names as? [String] else {
                print("   <could not list attributes>")
                return
            }
            for name in attributeNames.sorted() {
                if name == kAXChildrenAttribute as String {
                    print("   \(name) = <\(axChildren(element).count) children>")
                } else if let value = axAttribute(element, name) {
                    print("   \(name) = \(describeValue(value))")
                }
            }
            print("")
        }
    }
    print("\(matches) element(s) matching \"\(query)\"")
}

// MARK: - Capture (fixture JSON)

/// One node in the schema ErrolKit's FixtureElement decodes (see
/// app/Errol/Errol/Core/ElementNode.swift): role, subrole, the label
/// attributes under their own keys, value, url, children. Empty strings are
/// dropped, long values truncated — detection reads labels and short values,
/// never message bodies.
func captureNode(_ element: AXUIElement, depth: Int, options: Options) -> [String: Any] {
    let attrs = axMultiple(element, [kAXRoleAttribute, kAXSubroleAttribute,
                                     kAXValueAttribute, "AXURL"] + labelAttributes)
    var node: [String: Any] = [:]
    if let role = attrs[kAXRoleAttribute] as? String { node["role"] = role }
    if let subrole = attrs[kAXSubroleAttribute] as? String { node["subrole"] = subrole }
    if let text = attrs[kAXDescriptionAttribute] as? String, !text.isEmpty { node["description"] = text }
    if let text = attrs[kAXTitleAttribute] as? String, !text.isEmpty { node["title"] = text }
    if let text = attrs[kAXHelpAttribute] as? String, !text.isEmpty { node["help"] = text }
    if let text = attrs["AXLabel"] as? String, !text.isEmpty { node["label"] = text }
    if let value = attrs[kAXValueAttribute] {
        if let string = value as? String {
            node["value"] = string.count > 300 ? String(string.prefix(300)) : string
        } else if CFGetTypeID(value) == CFBooleanGetTypeID() {
            node["value"] = (value as! Bool)
        } else if let number = value as? NSNumber {
            node["value"] = number
        }
    }
    if let url = attrs["AXURL"] as? NSURL, let absolute = url.absoluteString { node["url"] = absolute }
    if depth < options.maxDepth {
        let children = axChildren(element).map { captureNode($0, depth: depth + 1, options: options) }
        if !children.isEmpty { node["children"] = children }
    }
    return node
}

/// stdout is a JSON array of the selected windows' trees, ready to drop into
/// tests/ErrolKitTests/Fixtures/<scenario>.json.
func runCapture(_ appElement: AXUIElement, options: Options) {
    let windows = selectedWindows(appElement, options: options)
        .map { captureNode($0.1, depth: 0, options: options) }
    let data = try! JSONSerialization.data(withJSONObject: windows,
                                           options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

func runMenus(_ appElement: AXUIElement, options: Options) {
    guard let menuBar = axAttribute(appElement, kAXMenuBarAttribute) else {
        print("no menu bar exposed")
        return
    }
    walk(menuBar as! AXUIElement, options: options) { element, depth, _ in
        print(String(repeating: "  ", count: depth) + elementLine(element, options: options))
    }
}

// MARK: - App resolution

/// Shortcuts mirror the bundle IDs in Core/Config.swift.
let shortcuts = [
    "claude": "com.anthropic.claudefordesktop",
    "chatgpt": "com.openai.codex",
    "codex": "com.openai.codex",
]

func runningApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
}

func resolveApp(_ spec: String) -> NSRunningApplication {
    let apps = NSWorkspace.shared.runningApplications
    if let bundleID = shortcuts[spec.lowercased()] {
        if let app = apps.first(where: { $0.bundleIdentifier == bundleID }) { return app }
        fail("\(spec) (\(bundleID)) is not running")
    }
    if let app = apps.first(where: { $0.bundleIdentifier == spec }) { return app }
    let byName = runningApps().filter {
        $0.localizedName?.localizedCaseInsensitiveContains(spec) ?? false
    }
    switch byName.count {
    case 1: return byName[0]
    case 0: fail("no running app matches \"\(spec)\" — try --list")
    default:
        let names = byName.map { "\($0.localizedName ?? "?") (\($0.bundleIdentifier ?? "?"))" }
        fail("\"\(spec)\" is ambiguous: \(names.joined(separator: ", "))")
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("ax-dump: \(message)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Arguments

let usage = """
usage: swift tools/ax-dump.swift <app> [mode] [options]
       swift tools/ax-dump.swift --list

  <app>            claude | chatgpt | codex | a bundle ID | a running app's name

modes (default: summary)
  --summary        per-window role counts, button totals, text inputs
  --tree           full indented tree (redirect to a file; diff two captures)
  --buttons        distinct button labels with counts, plus text inputs
  --prompt-geometry input frames, parent chain, and nearby controls (no text values)
  --find <text>    all attributes of elements matching role/subrole/label/value
  --menus          menu bar tree (menu items are hover-free AX targets)
  --capture        fixture JSON of the windows' trees, for the contract tests
                   (redirect into tests/ErrolKitTests/Fixtures/<scenario>.json)

options
  --window <n>     restrict to window n (index from --summary)
  --depth <n>      max tree depth (default 80)
  --frames         include element frames (off by default: breaks diffs)
  --no-values      omit element values (structure-only diffs)
"""

func parseOptions() -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    func next(_ flag: String) -> String {
        guard !args.isEmpty else { fail("\(flag) needs a value\n\(usage)") }
        return args.removeFirst()
    }
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--list": options.mode = .list
        case "--summary": options.mode = .summary
        case "--tree": options.mode = .tree
        case "--buttons": options.mode = .buttons
        case "--prompt-geometry": options.mode = .promptGeometry
        case "--find": options.mode = .find(next(arg))
        case "--menus": options.mode = .menus
        case "--capture": options.mode = .capture
        case "--window": options.windowIndex = Int(next(arg)) ?? -1
        case "--depth": options.maxDepth = Int(next(arg)) ?? 80
        case "--frames": options.frames = true
        case "--no-values": options.values = false
        case "--help", "-h":
            print(usage)
            exit(0)
        default:
            if arg.hasPrefix("-") { fail("unknown option \(arg)\n\(usage)") }
            guard options.appSpec == nil else { fail("only one app at a time\n\(usage)") }
            options.appSpec = arg
        }
    }
    return options
}

// MARK: - Main

let options = parseOptions()

if case .list = options.mode {
    for app in runningApps().sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
        print("\(app.localizedName ?? "?")  \(app.bundleIdentifier ?? "?")  pid \(app.processIdentifier)")
    }
    exit(0)
}

guard let spec = options.appSpec else { fail("no app given\n\(usage)") }

guard AXIsProcessTrusted() else {
    fail("""
    this process is not trusted for Accessibility.
    Grant the responsible app (your terminal, or Claude.app when run from a Claude \
    Code shell) in System Settings > Privacy & Security > Accessibility — called \
    "Device Control and Data Access" in the macOS 27 beta. Deep link:
      open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    Agent note: the Claude Code Bash sandbox also blocks the AX server; run unsandboxed.
    """)
}

let app = resolveApp(spec)
let appElement = AXUIElementCreateApplication(app.processIdentifier)

// Chromium exposes an empty tree until nudged (see Core/TargetApp.swift); the
// nudge is harmless for native apps. The tree populates asynchronously.
AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
Thread.sleep(forTimeInterval: 0.4)

let heading = "=== \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "?")) pid \(app.processIdentifier) ==="
if case .capture = options.mode {
    // stdout must stay pure JSON; the heading goes to stderr.
    FileHandle.standardError.write((heading + "\n").data(using: .utf8)!)
} else {
    print(heading)
}

switch options.mode {
case .list: break
case .summary: runSummary(appElement, options: options)
case .tree: runTree(appElement, options: options)
case .buttons: runButtons(appElement, options: options)
case .promptGeometry: runPromptGeometry(appElement, options: options)
case .find(let query): runFind(appElement, query: query, options: options)
case .menus: runMenus(appElement, options: options)
case .capture: runCapture(appElement, options: options)
}
