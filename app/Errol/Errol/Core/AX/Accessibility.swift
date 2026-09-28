// Thin wrappers over the AXUIElement API: attribute reads, tree walks, and
// the label heuristic every selector match goes through.

import ApplicationServices
import Foundation

let systemWideAX = AXUIElementCreateSystemWide()

func axAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return err == .success ? value : nil
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    (axAttribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

/// The attributes a label joins, in the order it joins them. captureSubtree
/// writes the same four under the fixture keys, and FixtureElement.label
/// joins its fields in this order.
let axLabelAttributes = [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute, "AXLabel"]

/// Empty attributes are dropped before joining: Chromium reports AXTitle as
/// "" (not absent) next to a real AXDescription, and keeping it would leave a
/// stray trailing separator — harmless to the contains-based selectors, fatal
/// to exact parses like messageOrdinal ("Message 6 " is not a number), and a
/// silent divergence from FixtureElement.label, whose captures never carry
/// empty strings.
///
/// One batched read rather than four: every label read is synchronous IPC
/// into the other app, and the finders read labels on every button of a
/// whole-window walk. An attribute the element lacks comes back as an error
/// placeholder, which the String cast drops, just as a failed single read
/// did; a failed call (an element the app has torn down) reads as no label.
func axLabel(_ element: AXUIElement) -> String {
    var values: CFArray?
    guard AXUIElementCopyMultipleAttributeValues(element, axLabelAttributes as CFArray,
                                                 AXCopyMultipleAttributeOptions(), &values) == .success
    else { return "" }
    return ((values as? [AnyObject]) ?? [])
        .compactMap { $0 as? String }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

/// The live face of the generic walk in ElementNode.swift, for callers that
/// hold raw AXUIElements; the depth limit and the order are the same.
func findAll(in element: AXUIElement,
             where predicate: (AXUIElement) -> Bool,
             into results: inout [AXUIElement]) {
    var found: [LiveElement] = []
    findAll(in: LiveElement(ax: element), where: { predicate($0.ax) }, into: &found)
    results += found.map(\.ax)
}

// MARK: - Diagnostics

/// An attribute read that keeps the error code, for the debug log. A nil
/// from `axAttribute` cannot tell a composer that is empty from one whose
/// element went stale when the app rebuilt it (invalidUIElement) or whose
/// AX server stopped answering (cannotComplete), and the paste receipt
/// hangs on exactly that difference.
func axAttributeResult(_ element: AXUIElement, _ name: String) -> (value: CFTypeRef?, error: AXError) {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return (err == .success ? value : nil, err)
}

func axErrorName(_ error: AXError) -> String {
    let name: String
    switch error {
    case .success: name = "success"
    case .failure: name = "failure"
    case .illegalArgument: name = "illegalArgument"
    case .invalidUIElement: name = "invalidUIElement"
    case .invalidUIElementObserver: name = "invalidUIElementObserver"
    case .cannotComplete: name = "cannotComplete"
    case .attributeUnsupported: name = "attributeUnsupported"
    case .actionUnsupported: name = "actionUnsupported"
    case .notificationUnsupported: name = "notificationUnsupported"
    case .notImplemented: name = "notImplemented"
    case .notificationAlreadyRegistered: name = "notificationAlreadyRegistered"
    case .notificationNotRegistered: name = "notificationNotRegistered"
    case .apiDisabled: name = "apiDisabled"
    case .noValue: name = "noValue"
    case .parameterizedAttributeUnsupported: name = "parameterizedAttributeUnsupported"
    case .notEnoughPrecision: name = "notEnoughPrecision"
    @unknown default: name = "unknown"
    }
    return "\(name)(\(error.rawValue))"
}

/// Text made safe for one log line: line breaks and tabs shown as symbols,
/// the rest cut at `limit` with the count of what was cut.
func clipped(_ text: String, to limit: Int) -> String {
    let flat = text.replacingOccurrences(of: "\r\n", with: "⏎")
        .replacingOccurrences(of: "\n", with: "⏎")
        .replacingOccurrences(of: "\r", with: "⏎")
        .replacingOccurrences(of: "\t", with: "⇥")
    guard flat.count > limit else { return flat }
    return String(flat.prefix(limit)) + "…(+\(flat.count - limit))"
}

/// One line on an element for the debug log: role and subrole, label,
/// frame in AX coordinates, and the size of its text value — or the error
/// the reads came back with, which for a paste verified against an
/// element the app has since rebuilt is the finding itself.
func describeElement(_ element: AXUIElement) -> String {
    let role = axAttributeResult(element, kAXRoleAttribute)
    guard role.error == .success else { return "<unreadable element: \(axErrorName(role.error))>" }
    var parts = [(role.value as? String) ?? "?"]
    if let subrole = axAttribute(element, kAXSubroleAttribute) as? String, !subrole.isEmpty {
        parts[0] += "/" + subrole
    }
    let label = axLabel(element).trimmingCharacters(in: .whitespacesAndNewlines)
    if !label.isEmpty { parts.append("\"\(clipped(label, to: 60))\"") }
    if let frame = windowFrame(element) {
        parts.append("at \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
    } else {
        parts.append("no frame")
    }
    let value = axAttributeResult(element, kAXValueAttribute)
    if let text = value.value as? String {
        parts.append("value \(text.count) chars" + (text.isEmpty ? "" : " \"\(clipped(text, to: 40))\""))
    } else if ![.success, .noValue, .attributeUnsupported].contains(value.error) {
        parts.append("value \(axErrorName(value.error))")
    }
    return parts.joined(separator: " ")
}

/// A bounded capture of a subtree as JSON in the fixture schema — the one
/// `tools/ax-dump.swift --capture` writes and tests/ErrolKitTests/Fixtures
/// hold — plus a "frame" key and the truncation markers, which the fixture
/// decoder ignores. So the composer a paste was lost in can be replayed
/// through the very finders that lost it, in a test, with no app open.
/// Long values are cut at 4000 characters and marked; the node budget stops
/// the walk before a whole conversation comes along.
struct SubtreeCapture {
    var json: Data
    var nodes: Int
    var truncated: Bool
}

func captureSubtree(_ root: AXUIElement, maxNodes: Int = 500, maxDepth: Int = 16) -> SubtreeCapture? {
    let valueLimit = 4000
    let keys = [("role", kAXRoleAttribute), ("subrole", kAXSubroleAttribute)]
        + Array(zip(["description", "title", "help", "label"], axLabelAttributes))
    var budget = maxNodes
    var truncated = false
    func node(_ element: AXUIElement, depth: Int) -> [String: Any] {
        budget -= 1
        var item: [String: Any] = [:]
        for (key, attribute) in keys {
            if let text = axAttribute(element, attribute) as? String, !text.isEmpty { item[key] = text }
        }
        if let value = axAttribute(element, kAXValueAttribute) {
            if let text = value as? String {
                if text.count > valueLimit {
                    item["value"] = String(text.prefix(valueLimit))
                    item["valueTruncated"] = text.count
                } else {
                    item["value"] = text
                }
            } else if CFGetTypeID(value) == CFBooleanGetTypeID() {
                item["value"] = CFBooleanGetValue((value as! CFBoolean))
            } else if let number = value as? NSNumber {
                item["value"] = number.intValue
            }
        }
        if let url = axAttribute(element, "AXURL") as? NSURL, let text = url.absoluteString {
            item["url"] = text
        }
        if let frame = windowFrame(element) {
            item["frame"] = [frame.minX, frame.minY, frame.width, frame.height].map { Int($0) }
        }
        let children = axChildren(element)
        guard !children.isEmpty else { return item }
        if depth >= maxDepth || budget <= 0 {
            truncated = true
            item["childrenOmitted"] = children.count
            return item
        }
        var captured: [[String: Any]] = []
        for child in children {
            if budget <= 0 {
                truncated = true
                item["childrenOmitted"] = children.count - captured.count
                break
            }
            captured.append(node(child, depth: depth + 1))
        }
        item["children"] = captured
        return item
    }
    let tree = node(root, depth: 0)
    guard let json = try? JSONSerialization.data(withJSONObject: tree,
                                                 options: [.prettyPrinted, .sortedKeys]) else { return nil }
    return SubtreeCapture(json: json, nodes: maxNodes - budget, truncated: truncated)
}
