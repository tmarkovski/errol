// The run configuration and the per-app label keywords. The selector values
// are the part most likely to break when either app renames or icon-ifies
// its buttons after an update, so they live here rather than near the
// finders; their type, AppSelectors, is in Core/Detection/AppSelectors.swift.

import Foundation

/// How a run ends on its own, chosen on the console before Start. Stop ends
/// any run, and so do a failure, a response timeout, an empty reply, or a
/// lost window, whichever ending was chosen.
enum RunEnding: Equatable, CaseIterable {
    /// The mutual sign-off: both sides send the stop sequence in
    /// consecutive replies.
    case bothAgree
    /// At most `Config.turns` replies are relayed. The mutual sign-off can
    /// end the run sooner.
    case turnLimit
    /// Only Stop ends the run. The agents are told the human will end it and
    /// get no sign-off, and a stop sequence that turns up in a reply is
    /// relayed like any other text.
    case whenStopped

    /// Whether the agents are given the sign-off, and the loop acts on it.
    var endsOnSignOff: Bool { self != .whenStopped }
}

struct Config {
    let chatgptBundleID = "com.openai.codex"   // standalone Codex / unified app; classic ChatGPT is com.openai.chat
    let claudeBundleID = "com.anthropic.claudefordesktop"
    /// End condition: by default a run continues until the conversation
    /// closes itself — the mutual stop-sequence sign-off, an empty reply, a
    /// response timeout, or the Stop button. A turn limit additionally caps
    /// how many responses get relayed; ending when stopped leaves the
    /// sign-off out altogether.
    var ending = RunEnding.bothAgree
    /// The turn cap, applied only with the turn-limit ending — extra
    /// protection, along with the message length cap, against two chatty
    /// models burning through usage limits.
    var turns = 10
    /// The cap in force: `turns` with the turn-limit ending, else none.
    var turnCap: Int? { ending == .turnLimit ? turns : nil }
    /// Which side sends the opening message; the other one answers it.
    var first = Speaker.chatgpt
    /// The human's initial message. The relay wraps it in a framing preamble
    /// (see openingMessage/introMessage), so this should read like an ordinary
    /// user request, not an explanation of the relay.
    var seed = ""
    /// A reply containing this marker (or an empty reply) ends the run early.
    var stopSequence = "[[END-CONVERSATION]]"
    /// Maximum wait without detected response activity. A visible Stop
    /// control means the app is still working and renews this interval;
    /// thinking and tool use can take longer than five minutes overall.
    var timeout: TimeInterval = 300
    var maxChars = 12000

    // ChatGPT's response action bar uses bare "Copy"; "Copy message" (paired
    // with "Edit message") belongs to user messages, and tables/links get
    // their own qualified labels. Match bare copy, exclude the qualified ones.
    let chatgptSelectors = AppSelectors(
        copyKeyword: "copy",
        copyExcludeKeywords: ["message", "table", "link", "code"],
        // The echo's "Copy message" is excluded above, so it never counts.
        echoCountsAsAffordance: false,
        // Long pastes become a pasted-text.txt chip. Its contents disappear
        // from the text area's AXValue, but this composer-local remove button
        // mounts once per chip (verified live Aug 30 2026).
        pastedTextAttachmentRemoveLabel: "Remove pasted text attachment",
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
        modelPopupDefaultLabel: "Select ChatGPT model",
        // The desktop app exposes an app:// shell URL, never a conversation
        // URL (captured Aug 2026); the hosts and route are for a build that
        // does, and cost nothing until then. Identity rests on the title.
        identityHosts: ["chatgpt.com", "chat.openai.com"],
        conversationRoutePrefixes: ["c"],
        genericWindowTitles: ["ChatGPT", "Codex", "New chat", "New task"])
    let claudeSelectors = AppSelectors(
        copyKeyword: "copy",
        copyExcludeKeywords: ["code", "link", "table"],
        // Claude Code's collapsed action-bar toggle; not seen on the chat
        // surfaces, where the harmless extra match arm never fires.
        messageActionsLabel: "Show message actions",
        // Claude Code's "Send feedback" button matches the bare send keyword
        // (observed live, Aug 2026); the chat surface has no such trap but
        // the exclude is harmless there.
        sendExcludeKeywords: ["feedback"],
        // Chat long pastes leave AXValue empty and mount a preview plus
        // "Remove Pasted text, pasted, N lines" three parents above the input
        // (verified live Sep 7 2026). Match the stable prefix, not the count.
        pastedTextAttachmentRemoveLabel: "Remove Pasted text,",
        pastedTextAttachmentAncestorLevels: 3,
        // The backstop under the world switcher below, for builds that have
        // no switcher (the older multi-window layout) or that move it. Of
        // these, only "Rewind to here" is present in current Claude Code
        // trees (Aug 2026); the terminal labels appear only with a terminal
        // pane open. Markers are ORed, so stale extras cost nothing.
        windowExcludeLabels: ["Terminal input", "New terminal", "Rewind to here"],
        // The switcher's own name for the Claude Code world.
        excludedWorldName: "Code",
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
        effortPopupPrefix: "Effort:",
        identityHosts: ["claude.ai"],
        // /chat/<uuid> and /epitaxy/<id> name one conversation; /new is
        // every fresh chat and every Cowork task, and /project/<uuid> is a
        // project, not a conversation in it (fixtures, Sep 2026).
        conversationRoutePrefixes: ["chat", "epitaxy"],
        genericWindowTitles: ["Claude", "New chat", "New task"])
}

/// In the app the per-run fields are written on main only, in
/// RelayController.start, while no run is in flight; the scanner thread
/// reads only the per-app fields, which are constants. The harness and the
/// tests set the per-run fields before a run and restore them after.
var config = Config()

/// Known empty-composer placeholder values across both apps' surfaces. The
/// harness tiers and the live tests refuse to act on a composer holding
/// anything else: it could be a human draft, and a cleanup or a send would
/// take it along (a select-all revert once ate a real draft).
let composerPlaceholders = ["Type / for commands",
                            "Describe a task or ask a question",
                            "Message ChatGPT", "Work with ChatGPT",
                            "Do anything",
                            "Write your prompt to Claude", ""]
