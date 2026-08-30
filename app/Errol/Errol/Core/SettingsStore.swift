// The conversation shapes behind the panel's picker, editable in the
// settings card: add, rename, rewrite, delete. The list is persisted
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
