import AppKit
import ApplicationServices
@testable import ErrolKit

/// A bounded, fixture-compatible AX capture. Limits are explicit evidence gaps,
/// never silently treated as a complete tree. No value truncation within budget.
struct EvidenceNode: Codable {
    var role: String?
    var subrole: String?
    var title: String?
    var description: String?
    var help: String?
    var label: String?
    var value: String?
    var number: Int?
    var url: String?
    var children: [EvidenceNode] = []

    var caption: String { [description, title, label].compactMap { $0 }.joined(separator: " ") }
    var text: String {
        if role == "AXTextArea" || role == "AXTextField" || role == "AXButton" || role == "AXToolbar" ||
            subrole == "AXTimeGroup" || subrole == "AXApplicationStatus" { return "" }
        if role == "AXStaticText" { return value ?? title ?? description ?? "" }
        return children.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }
    var buttons: [String] { (role == "AXButton" ? [caption] : []) + children.flatMap(\.buttons) }
    var messages: [EvidenceNode] {
        let label = caption.lowercased()
        let numbered = label.range(of: "^message [0-9]+$", options: .regularExpression) != nil
        if subrole == "AXDocumentArticle" || numbered || label == "user message" || label == "assistant message" { return [self] }
        return children.flatMap(\.messages)
    }
    var userMessage: Bool {
        caption.lowercased() == "user message" || headings.contains { $0.hasPrefix("you said:") } || buttons.contains {
            $0.lowercased().contains("edit message") || $0.lowercased() == "rewind to here"
        }
    }
    var assistantMessage: Bool {
        caption.lowercased() == "assistant message" || headings.contains {
            $0.hasPrefix("claude responded:") || $0.hasPrefix("chatgpt said:")
        } || buttons.contains {
            let label = $0.lowercased()
            return label.contains("good response") || label.contains("bad response") || label == "retry"
        }
    }
    var headings: [String] { (role == "AXHeading" ? [caption.lowercased()] : []) + children.flatMap(\.headings) }
    var ordinal: Int? {
        for label in [description, title].compactMap({ $0 }) where label.hasPrefix("Message ") {
            if let n = Int(label.dropFirst(8)) { return n }
        }
        return nil
    }

    /// Use the existing fixture schema (numeric AXValue goes in value).
    var fixture: [String: Any] {
        var item: [String: Any] = [:]
        for (key, value) in [("role", role), ("subrole", subrole), ("title", title),
                             ("description", description), ("help", help), ("label", label), ("url", url)] {
            if let value { item[key] = value }
        }
        if let value { item["value"] = value }
        else if let number { item["value"] = number }
        if !children.isEmpty { item["children"] = children.map(\.fixture) }
        return item
    }
}

extension EvidenceNode {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        subrole = try c.decodeIfPresent(String.self, forKey: .subrole)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        help = try c.decodeIfPresent(String.self, forKey: .help)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        value = try? c.decode(String.self, forKey: .value)
        number = (try? c.decode(Int.self, forKey: .value)) ?? (try? c.decode(Int.self, forKey: .number))
        if let boolean = try? c.decode(Bool.self, forKey: .value) { number = boolean ? 1 : 0 }
        url = try c.decodeIfPresent(String.self, forKey: .url)
        children = try c.decodeIfPresent([EvidenceNode].self, forKey: .children) ?? []
    }
}

struct EvidenceSnapshot {
    var root: EvidenceNode
    var complete: Bool
    var nodes: Int

    /// Every attribute a node records, read in one call per node.
    private static let nodeAttributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute,
        kAXDescriptionAttribute, kAXHelpAttribute, "AXLabel", kAXValueAttribute, "AXURL"]

    /// One IPC round trip for all of a node's attributes, as ax-dump.swift
    /// does: per-attribute reads spend the walk's time budget on IPC, and a
    /// capture that runs out of time is incomplete, which leaves the checks
    /// built on it inconclusive on long conversations. Unreadable or absent
    /// attributes come back as AXValue error placeholders and are skipped, as
    /// a failed single read was; a failed call (an element torn down mid-walk)
    /// reads as no attributes, so the missing role still marks the capture
    /// incomplete.
    private static func axMultiple(_ element: AXUIElement, _ names: [String]) -> [String: CFTypeRef] {
        var values: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(
            element, names as CFArray, AXCopyMultipleAttributeOptions(), &values)
        guard err == .success, let list = values as? [AnyObject] else { return [:] }
        var out: [String: CFTypeRef] = [:]
        for (index, name) in names.enumerated() where index < list.count {
            let value = list[index] as CFTypeRef
            if CFGetTypeID(value) == AXValueGetTypeID(),
               AXValueGetType(value as! AXValue) == .axError { continue }
            out[name] = value
        }
        return out
    }

    static func capture(_ element: AXUIElement, budget: Int = 12_000, seconds: Double = 8) -> Self {
        var count = 0
        var complete = true
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        func walk(_ element: AXUIElement, depth: Int) -> EvidenceNode {
            guard count < budget, depth <= 90, ProcessInfo.processInfo.systemUptime < deadline else {
                complete = false
                return EvidenceNode(description: "CAPTURE LIMIT REACHED")
            }
            count += 1
            let attrs = axMultiple(element, nodeAttributes)
            func string(_ key: String) -> String? { attrs[key] as? String }
            let value = attrs[kAXValueAttribute]
            var node = EvidenceNode(role: string(kAXRoleAttribute), subrole: string(kAXSubroleAttribute),
                title: string(kAXTitleAttribute), description: string(kAXDescriptionAttribute),
                help: string(kAXHelpAttribute), label: string("AXLabel"), value: value as? String,
                number: (value as? NSNumber)?.intValue, url: (attrs["AXURL"] as? URL)?.absoluteString)
            if node.role == nil { complete = false }
            for child in axChildren(element) {
                guard count < budget, ProcessInfo.processInfo.systemUptime < deadline else { complete = false; break }
                node.children.append(walk(child, depth: depth + 1))
            }
            return node
        }
        let root = walk(element, depth: 0)
        return Self(root: root, complete: complete, nodes: count)
    }
}

// The clipboard capture and restore live in ErrolKit (ClipboardLease):
// the relay leases the clipboard per operation, and the harness takes one
// lease per case and puts everything back with `restore()` at the end.

final class CaseEvidence {
    let directory: URL
    var result: CaseResult
    private var events: [[String: Any]] = []
    private var sequence = 0
    private(set) var writeError: String?
    private static let timestampFormatter = ISO8601DateFormatter()

    init(scenario: DesktopScenario, directory: URL) throws {
        self.directory = directory
        self.result = CaseResult(scenario: scenario, startedAt: Date())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func check(_ name: String, _ status: CheckStatus, _ detail: String, required: Bool = true) {
        result.checks.append(.init(name: name, status: status, detail: detail, required: required))
        print("\(status.rawValue.uppercased()) \(name): \(detail)")
        event("check", ["name": name, "status": status.rawValue, "detail": detail])
    }
    func event(_ name: String, _ fields: [String: Any] = [:]) {
        events.append(fields.merging(["event": name, "at": Self.timestampFormatter.string(from: Date()),
                                      "uptime": ProcessInfo.processInfo.systemUptime]) { _, new in new })
        do {
            try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("events.json"), options: .atomic)
        } catch { writeError = String(describing: error) }
    }
    func text(_ text: String, name: String) {
        do {
            try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
            artifact(name)
        } catch { writeError = String(describing: error) }
    }
    func artifact(_ name: String) {
        let relative = "\(result.scenario.id)/\(name)"
        if !result.artifacts.contains(relative) { result.artifacts.append(relative) }
    }
    @discardableResult func capture(_ target: TargetApp, stage: String, screenshots: Bool = false) -> EvidenceSnapshot? {
        guard let window = chatWindow(in: target) else {
            check("snapshot-\(stage)", .inconclusive, "No selected window; cannot capture evidence")
            return nil
        }
        sequence += 1
        let stem = String(format: "%03d", sequence) + "-" + stage
        let snapshot = EvidenceSnapshot.capture(window)
        do {
            try JSONSerialization.data(withJSONObject: [snapshot.root.fixture], options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent(stem + ".json"), options: .atomic)
            artifact(stem + ".json")
        } catch { writeError = String(describing: error) }
        event("snapshot", ["stage": stage, "nodes": snapshot.nodes, "complete": snapshot.complete])
        if !snapshot.complete { check("snapshot-\(stage)", .inconclusive, "AX capture was unreadable or exceeded its node/time budget") }
        if screenshots { screenshot(window, stem: stem) }
        return snapshot
    }
    private func screenshot(_ window: AXUIElement, stem: String) {
        guard CGPreflightScreenCaptureAccess() else {
            check("screenshot", .inconclusive, "Screen Recording permission unavailable; AX evidence retained", required: false)
            return
        }
        var point = CGPoint.zero, size = CGSize.zero
        guard let position = axAttribute(window, kAXPositionAttribute), let dimensions = axAttribute(window, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(dimensions) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(dimensions as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R\(Int(point.x)),\(Int(point.y)),\(Int(size.width)),\(Int(size.height))", directory.appendingPathComponent(stem + ".png").path]
        do {
            try process.run(); process.waitUntilExit()
            if process.terminationStatus == 0 { artifact(stem + ".png") }
            else { check("screenshot", .inconclusive, "screencapture exited \(process.terminationStatus)", required: false) }
        } catch { check("screenshot", .inconclusive, String(describing: error), required: false) }
    }
    func finish() -> CaseResult {
        if let writeError { check("artifact-write", .failed, writeError) }
        for name in result.scenario.requiredChecks where !result.checks.contains(where: { $0.name == name }) {
            check(name, .notRun, "Case ended before this required assertion")
        }
        artifact("events.json")
        result.finishedAt = Date()
        return result
    }
}
