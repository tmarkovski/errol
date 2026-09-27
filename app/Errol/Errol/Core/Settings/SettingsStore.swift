// The conversation shapes behind the panel's picker: their type, the
// shipped defaults, and the store that keeps the edits made in the
// settings card (add, rename, rewrite, delete). The list is persisted
// wholesale in UserDefaults — but only while it differs from the shipped
// defaults, and the stored copy is dropped again the moment the list
// matches them, so an untouched install keeps tracking default-text
// improvements across app updates. Runs never read this store: the panel
// composes the opening message from `conversationTemplates` on the main
// thread at Start, the same moment the rest of the form lands in `config`.

import Combine
import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var templates: [ConversationTemplate]

    private let defaults: UserDefaults
    private static let templatesKey = "conversationTemplates"
    /// The picker's write-from-scratch entry sits beside the shapes under
    /// this name (RelayController.customConversation), so no shape may
    /// take it — selecting it would open the blank editor instead.
    private static let reservedNames = ["Custom"]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.templatesKey),
           let stored = try? JSONDecoder().decode([ConversationTemplate].self,
                                                  from: data),
           !stored.isEmpty {
            templates = stored
        } else {
            templates = defaultConversationTemplates
        }
    }

    func template(named name: String) -> ConversationTemplate? {
        templates.first { $0.name == name }
    }

    /// Append a fresh shape under a free name and hand the name back for
    /// the settings card to select.
    @discardableResult
    func addTemplate() -> String {
        let name = freeName(for: "New shape", allowCurrent: nil)
        templates.append(ConversationTemplate(name: name,
                                              topicPrompt: "What to talk about",
                                              body: ""))
        persist()
        return name
    }

    /// Refuses to empty the list: the panel's picker defaults to the first
    /// shape and always needs one to point at.
    func deleteTemplate(named name: String) {
        guard templates.count > 1,
              let index = templates.firstIndex(where: { $0.name == name })
        else { return }
        templates.remove(at: index)
        persist()
    }

    /// Rename a shape and return the name that actually landed: trimmed,
    /// never blank (an emptied field keeps the old name), and unique — a
    /// collision with another shape or a reserved name gets a numbered
    /// suffix rather than a refusal, so a rename always finishes.
    @discardableResult
    func rename(_ name: String, to proposed: String) -> String {
        guard let index = templates.firstIndex(where: { $0.name == name })
        else { return name }
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else { return name }
        let landed = freeName(for: trimmed, allowCurrent: name)
        templates[index].name = landed
        persist()
        return landed
    }

    func updateTopicPrompt(_ topicPrompt: String, for name: String) {
        guard let index = templates.firstIndex(where: { $0.name == name })
        else { return }
        templates[index].topicPrompt = topicPrompt
        persist()
    }

    func updateBody(_ body: String, for name: String) {
        guard let index = templates.firstIndex(where: { $0.name == name })
        else { return }
        templates[index].body = body
        persist()
    }

    /// Whether the shape shares a name with a shipped default it has
    /// drifted from — the only case Reset has something to restore.
    func canReset(_ name: String) -> Bool {
        guard let shipped = defaultConversationTemplates
            .first(where: { $0.name == name }),
              let current = template(named: name) else { return false }
        return current != shipped
    }

    func resetTemplate(named name: String) {
        guard let shipped = defaultConversationTemplates
            .first(where: { $0.name == name }),
              let index = templates.firstIndex(where: { $0.name == name })
        else { return }
        templates[index] = shipped
        persist()
    }

    private func persist() {
        if templates == defaultConversationTemplates {
            defaults.removeObject(forKey: Self.templatesKey)
        } else if let data = try? JSONEncoder().encode(templates) {
            defaults.set(data, forKey: Self.templatesKey)
        }
    }

    private func freeName(for base: String, allowCurrent: String?) -> String {
        var taken = Set(templates.map(\.name)).union(Self.reservedNames)
        if let allowCurrent { taken.remove(allowCurrent) }
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}

/// A canned conversation shape selectable in the panel's picker. The body
/// carries the purpose and its pacing and refers to the user's topic as
/// "below"; composing appends the topic after a blank line. Templates are
/// starting text, not hidden framing — the panel's full-prompt editor reveals
/// the composed message without changing the selected template, and only that
/// text is ever sent. The relay's standing rules (relayRules) own the sign-off
/// mechanics, so bodies must not mention the stop sequence.
struct ConversationTemplate: Identifiable, Codable, Equatable {
    /// The picker's label and the shape's identity — per-shape drafts and
    /// the panel's selection key on it, so SettingsStore keeps names unique.
    var name: String
    /// Placeholder shown in the panel's topic field.
    var topicPrompt: String
    /// The purpose and pacing framing; refers to the topic as "below".
    var body: String
    var id: String { name }

    func composed(topic: String) -> String {
        body + "\n\n" + topic
    }
}

/// The shipped shapes, in display order. Pacing differs by purpose on top of
/// the standing rules' baseline (never sign off in a first reply): brainstorms
/// need divergence time, a review legitimately ends when the findings run out.
/// These are the defaults Settings edits are measured against; the picker and
/// the relay read `conversationTemplates` below, which applies those edits.
let defaultConversationTemplates = [
    ConversationTemplate(
        name: "Brainstorm",
        topicPrompt: "What to brainstorm about",
        body: """
            Brainstorm together on the topic below. Diverge before you \
            converge: offer a handful of ideas at a time, build on and twist \
            each other's suggestions, and keep new ideas coming for at least \
            three rounds each before any evaluating or narrowing begins. Then \
            converge on the strongest few and end with a shortlist you both \
            like.
            """),
    ConversationTemplate(
        name: "Debate",
        topicPrompt: "The question to debate",
        body: """
            Debate the question below. Take opposing positions — decide who \
            argues which side in your first exchange — and steelman each \
            other's arguments rather than attacking weak versions of them. \
            Concede a point only when genuinely persuaded. End once you have \
            either converged or clearly mapped where and why you still \
            disagree.
            """),
    ConversationTemplate(
        name: "Code review",
        topicPrompt: "Paste the code or describe what to review",
        body: """
            Review the code or design below together. One of you leads with \
            concrete findings — correctness first, then clarity and \
            maintainability — and the other challenges each finding: is it \
            real, does it matter, what is the simplest fix? Work through the \
            material a piece at a time rather than all at once. End with an \
            agreed list of the issues worth fixing.
            """),
    ConversationTemplate(
        name: "Adversary",
        topicPrompt: "The proposal to stress-test",
        body: """
            One of you defends the proposal below and the other attacks it — \
            decide who takes which role in your first exchange, then stay in \
            role. The attacker probes for the weakest assumptions; the \
            defender strengthens or amends the proposal rather than dodging. \
            End once the attacks stop finding new ground, with a verdict on \
            whether the proposal survives and in what amended form.
            """),
]

/// The picker's shapes: the shipped defaults with any Settings edits applied.
/// Computed so every reader — the composer's pills, the controller's
/// compose path — sees an edit the moment it lands.
var conversationTemplates: [ConversationTemplate] {
    SettingsStore.shared.templates
}
