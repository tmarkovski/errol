// Per-app label keywords and the run configuration. The selectors are the
// part most likely to break when either app renames or icon-ifies its
// buttons after an update, so they live here rather than near the finders.

import Foundation

/// Per-app label keywords. Kept separate per app because the two UIs label
/// their affordances differently (verified against live trees, Aug 2026).
struct AppSelectors {
    /// Per-message copy button label substring.
    var copyKeyword: String
    /// Reject copy buttons whose label also contains any of these.
    var copyExcludeKeywords: [String]
    var stopKeyword = "stop"
    var sendKeyword = "send"
    /// A window containing a button or text field with any of these labels is
    /// not a chat window (e.g. Claude Code session windows inside Claude Desktop).
    var windowExcludeLabels: [String] = []
    /// What an excluded window is, for the readiness strip ("Claude Code").
    var excludedSurfaceName: String?
    /// Label prefix of the AXPopUpButton that announces the app's active
    /// mode; the text after the prefix names the mode (ChatGPT exposes
    /// "Switch mode, current mode: ChatGPT", or ": Codex" in Codex mode).
    var modePopupPrefix: String?
    /// Display names for raw mode names, keyed lowercased ("chatgpt" -> "Chat").
    var modeNames: [String: String] = [:]
    /// Surface names keyed by the first path component of a window's
    /// claude.ai AXWebArea URL. Empty for apps without claude.ai URLs.
    var surfacePathNames: [String: String] = [:]
}

struct Config {
    var chatgptBundleID = "com.openai.codex"   // standalone Codex / unified app; classic ChatGPT is com.openai.chat
    var claudeBundleID = "com.anthropic.claudefordesktop"
    var turns = 10
    var first = "chatgpt"
    var newChats = false
    /// The human's initial message. The relay wraps it in a framing preamble
    /// (see openingMessage/introMessage), so this should read like an ordinary
    /// user request, not an explanation of the relay.
    var seed = ""
    /// A reply containing this marker (or an empty reply) ends the run early.
    var stopSequence = "[[END-CONVERSATION]]"
    var timeout: TimeInterval = 300
    var maxChars = 12000
    /// Run artifacts live in Documents: the app is launched from Finder with
    /// "/" as its working directory, so relative paths would be unwritable.
    var transcriptPath = Config.documentsPath("errol-transcript.md")
    var frameStatePath = Config.documentsPath(".errol-frames")

    // ChatGPT's response action bar uses bare "Copy"; "Copy message" (paired
    // with "Edit message") belongs to user messages, and tables/links get
    // their own qualified labels. Match bare copy, exclude the qualified ones.
    var chatgptSelectors = AppSelectors(
        copyKeyword: "copy",
        copyExcludeKeywords: ["message", "table", "link", "code"],
        modePopupPrefix: "Switch mode, current mode:",
        modeNames: ["chatgpt": "Chat"])
    var claudeSelectors = AppSelectors(
        copyKeyword: "copy",
        copyExcludeKeywords: ["code", "link", "table"],
        windowExcludeLabels: ["Terminal input", "New terminal", "Rewind to here"],
        excludedSurfaceName: "Claude Code",
        // Only "epitaxy" is verified against a live tree; the rest are the
        // expected paths for surfaces not yet observed over AX.
        surfacePathNames: [
            "epitaxy": "Claude Code",
            "chat": "Chat",
            "new": "New chat",
            "project": "Project chat",
            "projects": "Projects",
        ])

    static func documentsPath(_ name: String) -> String {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent(name).path
    }
}

var config = Config()
