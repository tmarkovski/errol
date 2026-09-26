// The element protocol the finders run over, with two conformances: live
// AXUIElements and recorded trees. This is what lets the contract tests cover
// the finders themselves — an ax-dump capture of a real app state replays
// through the exact detection code the relay runs, no apps open.
//
// The protocol carries only the primitives detection actually reads: role,
// subrole (a dialog is a group told apart by it), the joined label every
// selector match goes through, the title (surface tabs match on AXTitle
// alone), the value in its two used shapes (composer text, toggle state),
// the web-area URL, and children. Live-only concerns — focus, AXPress,
// window identity — stay on AXUIElement in the live wrappers.

import ApplicationServices
import Foundation

protocol ElementNode {
    var role: String? { get }
    var subrole: String? { get }
    var title: String? { get }
    /// Joined description/title/help/AXLabel — see axLabel in Accessibility.swift.
    var label: String { get }
    var stringValue: String? { get }
    var numberValue: Int? { get }
    var url: URL? { get }
    var children: [Self] { get }
}

func findAll<Node: ElementNode>(in node: Node,
                                depth: Int = 0,
                                maxDepth: Int = 80,
                                where predicate: (Node) -> Bool,
                                into results: inout [Node]) {
    guard depth <= maxDepth else { return }
    if predicate(node) { results.append(node) }
    for child in node.children {
        findAll(in: child, depth: depth + 1, maxDepth: maxDepth, where: predicate, into: &results)
    }
}

// MARK: - Live trees

/// An AXUIElement viewed through the protocol. Each accessor is one AX read,
/// same as the direct calls the finders made before.
struct LiveElement: ElementNode {
    let ax: AXUIElement

    var role: String? { axAttribute(ax, kAXRoleAttribute) as? String }
    var subrole: String? { axAttribute(ax, kAXSubroleAttribute) as? String }
    var title: String? { axAttribute(ax, kAXTitleAttribute) as? String }
    var label: String { axLabel(ax) }
    var stringValue: String? { axAttribute(ax, kAXValueAttribute) as? String }
    var numberValue: Int? { (axAttribute(ax, kAXValueAttribute) as? NSNumber)?.intValue }
    var url: URL? { (axAttribute(ax, "AXURL") as? NSURL) as URL? }
    var children: [LiveElement] { axChildren(ax).map(LiveElement.init) }
}

// MARK: - Recorded trees

/// One node of a recorded AX tree — the JSON `tools/ax-dump.swift --capture`
/// emits, and what the fixtures under tests/ErrolKitTests/Fixtures hold. Keys
/// (all optional): role, subrole, description, title, help, label (the
/// AXLabel attribute), value (string, number, or bool), url, children.
/// The label heuristic mirrors axLabel: the label attributes joined in the
/// same order, so fixtures exercise the joining behavior too.
struct FixtureElement: ElementNode, Equatable {
    var role: String?
    var subrole: String?
    var axDescription: String?
    var title: String?
    var help: String?
    var axLabelText: String?
    var value: FixtureValue?
    var urlString: String?
    var children: [FixtureElement] = []

    var label: String {
        [axDescription, title, help, axLabelText].compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    var stringValue: String? {
        if case .string(let string)? = value { return string }
        return nil
    }
    var numberValue: Int? {
        switch value {
        case .number(let number): return number
        case .bool(let flag): return flag ? 1 : 0
        default: return nil
        }
    }
    var url: URL? { urlString.flatMap { URL(string: $0) } }
}

enum FixtureValue: Equatable {
    case string(String)
    case number(Int)
    case bool(Bool)
}

extension FixtureElement: Decodable {
    enum CodingKeys: String, CodingKey {
        case role, subrole, title, help, value, children
        case axDescription = "description"
        case axLabelText = "label"
        case urlString = "url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        subrole = try container.decodeIfPresent(String.self, forKey: .subrole)
        axDescription = try container.decodeIfPresent(String.self, forKey: .axDescription)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        help = try container.decodeIfPresent(String.self, forKey: .help)
        axLabelText = try container.decodeIfPresent(String.self, forKey: .axLabelText)
        value = try container.decodeIfPresent(FixtureValue.self, forKey: .value)
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        children = try container.decodeIfPresent([FixtureElement].self, forKey: .children) ?? []
    }
}

extension FixtureValue: Decodable {
    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let string = try? single.decode(String.self) { self = .string(string); return }
        if let bool = try? single.decode(Bool.self) { self = .bool(bool); return }
        if let number = try? single.decode(Int.self) { self = .number(number); return }
        throw DecodingError.typeMismatch(FixtureValue.self, .init(
            codingPath: decoder.codingPath,
            debugDescription: "value must be a string, number, or bool"))
    }
}
