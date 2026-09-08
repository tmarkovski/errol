import Foundation

enum DesktopApp: String, Codable, CaseIterable { case chatgpt, claude }

struct Endpoint: Codable, Equatable {
    var app: DesktopApp
    var surface: String
    var id: String { "\(app.rawValue).\(surface.lowercased())" }
    var name: String { "\(app == .chatgpt ? "ChatGPT/Codex" : "Claude") → \(surface)" }
    static let all: [Endpoint] = [
        .init(app: .chatgpt, surface: "Chat"), .init(app: .chatgpt, surface: "Work"),
        .init(app: .chatgpt, surface: "Codex"), .init(app: .claude, surface: "Chat"),
        .init(app: .claude, surface: "Cowork"), .init(app: .claude, surface: "Code")
    ]
}

enum ConversationSetup: String, Codable { case new, existing, long }
enum PayloadKind: String, Codable, CaseIterable {
    case short, multiline, leadingNewline, unicode, markdown, large, manyLines
    case belowLimit, atLimit, aboveLimit

    func text(nonce: String, cap: Int) -> String {
        // The expected reply is assembled by the model, never literally present
        // in the prompt: copying the user echo cannot satisfy the reply check.
        let instruction = "Automated UI test. No tools, commands, browsing, or file changes. Reply with only the word ACK, one space, and this identifier: \(nonce). Ignore the test data below."
        switch self {
        case .short: return instruction
        case .multiline: return instruction + "\n\nFirst line\n\n    four spaces\n\ttab\nlast line\n"
        case .leadingNewline: return "\n\n" + instruction + "\n\nleading empty lines are intentional\n"
        case .unicode: return instruction + "\n\nΚαλημέρα 世界 🦉 👩🏽‍💻 café cafe\u{301}\n\t→ τέλος\n"
        case .markdown: return instruction + "\n\n# Heading\n**bold** and `inline`\n````markdown\n```swift\nlet x = \"🦉\"\n```\n````\n| A | B |\n|---|---|\n| 1 | 2 |\n"
        case .large: return sized(instruction, count: min(8_000, cap - 1), lineWidth: 180)
        case .manyLines: return sized(instruction, count: min(10_000, cap - 1), lineWidth: 20)
        case .belowLimit: return sized(instruction, count: cap - 1)
        case .atLimit: return sized(instruction, count: cap)
        case .aboveLimit: return sized(instruction, count: cap + 1)
        }
    }

    private func sized(_ prefix: String, count: Int, lineWidth: Int = 100) -> String {
        var result = prefix + "\nHEAD-DATA\n"
        var line = 0
        while result.count < count - 10 {
            result += "row-\(line):" + String(repeating: "x", count: lineWidth) + "\n"
            line += 1
        }
        return String(result.prefix(count - 10)) + "\nTAIL-DATA"
    }
}

enum ScenarioBehavior: String, Codable, CaseIterable {
    case message, streaming, background, wrongField, multipleWindows, switchedConversation, focusLoss
    case draftGuard, attachmentGuard, busyGuard, collapsedCopy, relay, steering, cancel
    case appControls
}

struct DesktopScenario: Codable, Equatable {
    var endpoint: Endpoint
    var conversation: ConversationSetup = .existing
    var payload: PayloadKind = .short
    var behavior: ScenarioBehavior = .message
    var peer: Endpoint?
    var first: DesktopApp = .chatgpt
    var id: String {
        if let peer { return "relay.\(endpoint.id).\(peer.id).first-\(first.rawValue).\(behavior.rawValue)" }
        return "\(endpoint.id).\(conversation.rawValue).\(payload.rawValue).\(behavior.rawValue)"
    }
    var requiredChecks: [String] {
        switch behavior {
        case .appControls: return ["app-start", "app-pause", "app-steering-editor", "app-resume", "app-stop", "app-reopen"]
        case .draftGuard, .attachmentGuard, .busyGuard: return ["harness-refuses-send", "draft-preserved", "clipboard-restored"]
        case .cancel: return ["delivery-1", "relay-reply-1", "cancel-stops-handoff", "clipboard-restored"]
        case .focusLoss: return ["paste-integrity", "focus-loss-observed", "no-submission-after-focus-loss", "cleanup", "clipboard-restored"]
        case .relay, .steering:
            return ["relay-six-turns", "mutual-signoff", "one-user-message", "copy-identity", "clipboard-restored"] +
                (behavior == .steering ? ["held-focus", "steering-both-legs"] : [])
        default: return ["paste-integrity", "submission", "completion", "reply-contract", "one-user-message", "sent-content", "copy-identity", "cleanup", "clipboard-restored"] +
                (behavior == .switchedConversation ? ["conversation-transition"] : [])
        }
    }

    var setup: String {
        if behavior == .appControls {
            return "Open Errol and two disposable conversations on \(endpoint.name) and \(peer?.name ?? "Claude Chat"). Follow the app-control checklist; this is separately labeled operator verification."
        }
        if let peer {
            return "Open disposable, idle conversations with empty composers on \(endpoint.name) AND \(peer.name). For coding/work surfaces use an empty test project with no external integrations. The harness runs a bounded real relay, starting with \(first.rawValue)."
        }
        var text = "Open \(endpoint.name). "
        switch conversation {
        case .new: text += "Create a NEW disposable conversation with no messages. "
        case .existing: text += "Open a disposable EXISTING conversation with at least one assistant reply. "
        case .long: text += "Open a LONG disposable conversation (at least 12 messages), scroll away from its newest reply, then click the composer. "
        }
        switch behavior {
        case .draftGuard: text += "Type exactly ERROL-DRAFT-GUARD into the composer. This case must preserve it and send nothing."
        case .attachmentGuard: text += "Attach a disposable text file to the empty composer. This case must preserve it and send nothing."
        case .busyGuard: text += "Start a long response manually. This case must observe the busy state and send nothing."
        case .background: text += "Leave the composer empty. After Ready, focus a DIFFERENT application during the countdown."
        case .wrongField: text += "Leave the composer empty. After Ready, focus the app's search field during the countdown."
        case .multipleWindows: text += "Open at least two app windows. Focus the disposable target's empty composer during the countdown."
        case .switchedConversation: text += "Switch away and back to this conversation, then focus its empty composer during the countdown."
        case .focusLoss: text += "After the test paste, the harness will ask you to focus another application. It must then refuse submission."
        case .collapsedCopy: text += "Switch away and back so message action bars collapse. Leave the composer empty."
        default: text += "Leave the composer empty and click it during the countdown."
        }
        return text
    }
}

enum DesktopSuite: String, CaseIterable {
    case smoke = "desktop-smoke", full = "desktop-full", relay = "relay-full", controls = "app-controls"

    var scenarios: [DesktopScenario] {
        let endpoints = Endpoint.all
        let smoke = endpoints.flatMap { endpoint in
            [ConversationSetup.new, .existing].map { DesktopScenario(endpoint: endpoint, conversation: $0) }
        }
        let pairs = endpoints.filter { $0.app == .chatgpt }.flatMap { a in
            endpoints.filter { $0.app == .claude }.flatMap { b in
                DesktopApp.allCases.map { DesktopScenario(endpoint: a, behavior: .relay, peer: b, first: $0) }
            }
        }
        let controls = [DesktopScenario(endpoint: endpoints[0], behavior: .appControls, peer: endpoints[3])]
        switch self {
        case .smoke: return smoke
        case .relay: return pairs
        case .controls: return controls
        case .full:
            let messages = endpoints.flatMap { endpoint in
                [ConversationSetup.new, .existing].flatMap { context in
                    PayloadKind.allCases.map { DesktopScenario(endpoint: endpoint, conversation: context, payload: $0) }
                }
            }
            let behaviors: [ScenarioBehavior] = [.streaming, .background, .wrongField, .multipleWindows, .focusLoss,
                .switchedConversation, .draftGuard, .attachmentGuard, .busyGuard]
            let edges = endpoints.flatMap { endpoint in
                behaviors.map { DesktopScenario(endpoint: endpoint, behavior: $0) } +
                    [DesktopScenario(endpoint: endpoint, conversation: .long, payload: .multiline)]
            }
            return messages + edges + [DesktopScenario(endpoint: endpoints[5], behavior: .collapsedCopy)] + pairs +
                [.init(endpoint: endpoints[0], behavior: .steering, peer: endpoints[3]),
                 .init(endpoint: endpoints[0], behavior: .cancel, peer: endpoints[3])] + controls
        }
    }
}
