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

func axLabel(_ element: AXUIElement) -> String {
    [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute, "AXLabel"]
        .compactMap { axAttribute(element, $0) as? String }
        .joined(separator: " ")
}

func findAll(in element: AXUIElement,
             depth: Int = 0,
             maxDepth: Int = 80,
             where predicate: (AXUIElement) -> Bool,
             into results: inout [AXUIElement]) {
    guard depth <= maxDepth else { return }
    if predicate(element) { results.append(element) }
    for child in axChildren(element) {
        findAll(in: child, depth: depth + 1, maxDepth: maxDepth, where: predicate, into: &results)
    }
}
