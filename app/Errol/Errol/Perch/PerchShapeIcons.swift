// The shape glyphs: a fixed name→symbol map for the shipped conversation
// shapes, a default for shapes made in Settings, the dashed circle for Free
// chat, and the pencil that marks a prompt written from scratch. Read by
// the settings card's shape rail; the shape tabs and the composer's mid-run
// context line are names alone.

import Foundation

enum PerchShapeIcons {
    static let customIcon = "square.and.pencil"
    static let freeIcon = "circle.dashed"

    private static let known: [String: String] = [
        "Brainstorm": "lightbulb",
        "Debate": "bubble.left.and.bubble.right",
        "Code review": "chevron.left.forwardslash.chevron.right",
        "Adversary": "flag.2.crossed",
    ]

    static func icon(for name: String) -> String {
        if name == RelayController.customConversation { return customIcon }
        if name == RelayController.freeConversation { return freeIcon }
        return known[name] ?? "text.bubble"
    }
}
