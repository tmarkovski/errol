// The two sides of a relay, named apart from the loop because settings, the
// panel and the run all speak in it, and the per-side vocabulary built on
// it: the other side, each side's app name, and a pair of names keyed by
// side, so each of those lookups is written once here rather than as a
// ternary at every site that needs it.

/// Which side of the relay a message belongs to. Only the opening message
/// needs naming — every turn after it goes to whoever did not just speak —
/// so this is what `config.first` holds and what the panel nominates before
/// a run starts. The case order is the order both sides are listed in,
/// ChatGPT then Claude, so `allCases` walks them that way.
enum Speaker: String, CaseIterable {
    case chatgpt
    case claude
}

extension Speaker {
    /// Whoever did not just speak: the side every turn after this one's
    /// goes to.
    var other: Speaker { self == .chatgpt ? .claude : .chatgpt }

    /// The side's app by the name the human reads, ChatGPT or Claude.
    var appName: String { self == .chatgpt ? "ChatGPT" : "Claude" }
}

/// One name per side, read by subscripting with a `Speaker` rather than by a
/// ternary. The names are the apps' own (`apps`) wherever the app runs, but
/// the types that print them take a value, so a test or a preview can hand
/// in its own.
struct SideNames: Equatable {
    var chatgpt: String
    var claude: String

    subscript(_ side: Speaker) -> String {
        side == .chatgpt ? chatgpt : claude
    }

    static let apps = SideNames(chatgpt: Speaker.chatgpt.appName, claude: Speaker.claude.appName)
}
