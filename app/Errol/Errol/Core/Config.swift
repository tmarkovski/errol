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
    /// Label of the collapsed per-message actions toggle. Claude Code keeps
    /// each message's action bar (Copy, Rewind, Fork, Read aloud) unmounted
    /// behind a "Show message actions" button until a hover or an AXPress
    /// expands it, and every conversation switch collapses all bars again —
    /// so the bare copy count misses fresh responses there. The toggle
    /// itself mounts exactly when a response completes (verified live,
    /// Aug 27 2026), making it the countable stand-in for the bar. nil for
    /// apps that mount copy buttons directly.
    var messageActionsLabel: String?
    /// Whether the echo of a just-sent user message registers in the
    /// message-affordance count. Claude gives user messages the same counted
    /// affordances as responses; ChatGPT's echo mounts "Copy message", which
    /// the copy selector excludes, so its count only ever moves on a
    /// response. When false, echo absorption is skipped entirely — waiting
    /// for an echo that cannot register would swallow any response that
    /// completes inside the wait window into the baseline (observed live in
    /// Codex mode, Aug 27 2026, where replies can land in under 2s), leaving
    /// the relay waiting forever on a baseline it can never exceed.
    var echoCountsAsAffordance = true
    var stopKeyword = "stop"
    var sendKeyword = "send"
    /// Reject send buttons whose label also contains any of these. Claude
    /// Code's "Send feedback" button matches the bare send keyword.
    var sendExcludeKeywords: [String] = []
    /// A window containing a button or text field with any of these labels is
    /// not a chat window (e.g. Claude Code session windows inside Claude Desktop).
    var windowExcludeLabels: [String] = []
    /// Allow targeting an excluded-surface window that has a composer when
    /// the app has no chat window at all (e.g. Claude Desktop showing only a
    /// Claude Code session). An open chat window always wins.
    var excludedSurfaceIsFallback = false
    /// What an excluded window is, for the readiness strip ("Code"). Surface
    /// names are shown right under the app's own name, so they drop a
    /// redundant vendor prefix: Claude's coding surface reads "Code".
    var excludedSurfaceName: String?
    /// Label prefix of the AXPopUpButton that announces the app's active
    /// mode; the text after the prefix names the mode (ChatGPT exposes
    /// "Switch mode, current mode: ChatGPT", or ": Codex" in Codex mode).
    /// ChatGPT's popup does NOT track its Chat/Work composer toggle — it says
    /// "ChatGPT" in both — so the surface tab always outranks this.
    var modePopupPrefix: String?
    /// Display names for raw mode names, keyed lowercased ("chatgpt" -> "Chat").
    var modeNames: [String: String] = [:]
    /// Surface names keyed by the first path component of a window's
    /// claude.ai AXWebArea URL. Empty for apps without claude.ai URLs.
    var surfacePathNames: [String: String] = [:]
    /// Titles of the composer-level surface-tab toggles, matched
    /// case-insensitively; the tab with AXValue 1 is the active surface and
    /// is displayed under the name given here. Claude renders the pair as
    /// AXRadioButtons ("Chat"/"Cowork"), ChatGPT as AXCheckBox toggle
    /// buttons ("Chat"/"Work"); both apps share one window, URL, composer,
    /// and sidebar across the pair, so this toggle is the only direct signal.
    var surfaceTabNames: [String] = []
    /// Surface names keyed by a substring of the composer's placeholder
    /// label, for windows where the surface toggle is not mounted — ChatGPT
    /// removes the Chat/Work pair once a conversation opens, leaving the
    /// per-surface placeholder as the only marker.
    var composerSurfaceNames: [String: String] = [:]
    /// Label prefix of the AXPopUpButton announcing the active model; the
    /// text after it is model plus effort ("Model: Fable 5 · Extra").
    var modelPopupPrefix: String?
    /// For apps whose model pill has no prefix (ChatGPT): an AXPopUpButton
    /// whose label ends with one of these effort words is the pill, and the
    /// whole label is the model string — "5.6 Sol High" with a model chosen,
    /// bare "High" on the default. Unobserved effort names must be added
    /// here. Ignored when modelPopupPrefix is set.
    var modelPopupSuffixes: [String] = []
    /// With the default model active, ChatGPT's pill drops the title and
    /// carries only this description (title and description swap between
    /// states); a pill matching it exactly reports "Default".
    var modelPopupDefaultLabel: String?
    /// Label prefix of a separate effort popup. Claude Code's composer splits
    /// the announcement across two adjacent popups — a bare-titled model
    /// ("Fable 5") immediately followed by "Effort: Extra" — so the effort
    /// match also names the popup right before it as the model.
    var effortPopupPrefix: String?
}

struct Config {
    var chatgptBundleID = "com.openai.codex"   // standalone Codex / unified app; classic ChatGPT is com.openai.chat
    var claudeBundleID = "com.anthropic.claudefordesktop"
    /// End condition: by default a run continues until the conversation
    /// closes itself — the mutual stop-sequence sign-off, an empty reply, a
    /// response timeout, or the Stop button. When true, `turns` additionally
    /// caps how many responses get relayed.
    var limitTurns = false
    /// The optional turn cap, applied only when limitTurns is set — extra
    /// protection, along with the message length cap, against two chatty
    /// models burning through usage limits.
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
        // The echo's "Copy message" is excluded above, so it never counts.
        echoCountsAsAffordance: false,
        modePopupPrefix: "Switch mode, current mode:",
        modeNames: ["chatgpt": "Chat"],
        // The Chat/Work toggle pair in the "Composer mode" group (AXCheckBox
        // toggle buttons) exists only on the home screen; open conversations
        // fall back to the placeholder. "Message ChatGPT" and the Work home
        // screen's "Work with ChatGPT" are verified live (Aug 2026); a Work
        // conversation keeping that placeholder is expected, not yet observed.
        surfaceTabNames: ["Chat", "Work"],
        composerSurfaceNames: ["Message ChatGPT": "Chat", "Work with ChatGPT": "Work"],
        // "high" and "medium" observed live (Aug 2026); "low" is expected.
        modelPopupSuffixes: ["high", "medium", "low"],
        modelPopupDefaultLabel: "Select ChatGPT model")
    var claudeSelectors = AppSelectors(
        copyKeyword: "copy",
        copyExcludeKeywords: ["code", "link", "table"],
        // Claude Code's collapsed action-bar toggle; not seen on the chat
        // surfaces, where the harmless extra match arm never fires.
        messageActionsLabel: "Show message actions",
        // Claude Code's "Send feedback" button matches the bare send keyword
        // (observed live, Aug 2026); the chat surface has no such trap but
        // the exclude is harmless there.
        sendExcludeKeywords: ["feedback"],
        // Of these, only "Rewind to here" is present in current Claude Code
        // trees (Aug 2026); the terminal labels appear only with a terminal
        // pane open. Markers are ORed, so stale extras cost nothing.
        windowExcludeLabels: ["Terminal input", "New terminal", "Rewind to here"],
        excludedSurfaceIsFallback: true,
        excludedSurfaceName: "Code",
        // Only paths whose display name differs from the capitalized path
        // (unmapped ones fall back to that: "cowork" -> "Cowork"). "epitaxy"
        // and "cowork" are verified against live trees; the rest are the
        // expected paths for surfaces not yet observed over AX.
        surfacePathNames: [
            "epitaxy": "Code",
            "new": "New chat",
            "project": "Project chat",
        ],
        surfaceTabNames: ["Chat", "Cowork"],
        // Chat and Cowork announce model plus effort in one "Model:" popup;
        // Claude Code splits them into the bare-model + "Effort:" pair.
        modelPopupPrefix: "Model:",
        effortPopupPrefix: "Effort:")

    static func documentsPath(_ name: String) -> String {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent(name).path
    }
}

var config = Config()

/// A canned conversation shape selectable in the panel's picker. The body
/// carries the purpose and its pacing and refers to the user's topic as
/// "below"; composing appends the topic after a blank line. Templates are
/// starting text, not hidden framing — the panel's "Edit instructions" link
/// reveals the composed message for free editing, and only that text is ever
/// sent. The relay's standing rules (relayRules) own the sign-off mechanics,
/// so bodies must not mention the stop sequence.
struct ConversationTemplate: Identifiable {
    let name: String
    /// Placeholder shown in the panel's topic field.
    let topicPrompt: String
    /// The purpose and pacing framing; refers to the topic as "below".
    let body: String
    var id: String { name }

    func composed(topic: String) -> String {
        body + "\n\n" + topic
    }
}

/// The picker's shapes, in display order. Pacing differs by purpose on top of
/// the standing rules' baseline (never sign off in a first reply): brainstorms
/// need divergence time, a review legitimately ends when the findings run out.
let conversationTemplates = [
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

/// Known empty-composer placeholder values across both apps' surfaces. The
/// harness tiers and the live tests refuse to act on a composer holding
/// anything else: it could be a human draft, and a cleanup or a send would
/// take it along (a select-all revert once ate a real draft).
let composerPlaceholders = ["Type / for commands",
                            "Describe a task or ask a question",
                            "Message ChatGPT", "Work with ChatGPT",
                            "Do anything",
                            "Write your prompt to Claude", ""]
