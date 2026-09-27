// The shape of the per-app label keywords the finders match against. The
// two values stay in Config.swift, where a broken selector sends readers.

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
    /// Label of the remove control mounted for each long paste that the app
    /// turns into a text attachment instead of leaving in the text area. nil
    /// where the app does not expose this behavior over AX.
    var pastedTextAttachmentRemoveLabel: String?
    /// Number of parents from the text area to the attachment container.
    /// Keep this scoped to the composer, excluding conversation history.
    var pastedTextAttachmentAncestorLevels = 1
    /// A window containing a button or text field with any of these labels is
    /// not a chat window (e.g. Claude Code session windows inside Claude Desktop).
    var windowExcludeLabels: [String] = []
    /// Name of the option in the app's own world switcher that means "this
    /// window is not a chat". Claude Desktop's top-level AXRadioGroup carries
    /// "Chat and Cowork" and "Code" with AXValue 1 on the mounted world, and
    /// appends live session state after a comma ("Code, awaiting your input"),
    /// so the name is the part before that comma.
    ///
    /// This asks the app which world it is showing. windowExcludeLabels only
    /// infer it from furniture that happens to sit around in one world and not
    /// the other, which is fragile in both directions: a rename breaks the
    /// match silently, and "Rewind to here" lives inside a message's
    /// hover-gated action bar, so it is unmounted whenever no bar is expanded
    /// and the very same Code session classifies as a chat. Both signals are
    /// ORed rather than one replacing the other — see isExclusionMarker.
    var excludedWorldName: String?
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
    /// Hosts whose URLs in a window's AXWebArea identify what the window is
    /// showing (the surface path, and a conversation route where one is
    /// exposed). Matched as substrings of the URL's host.
    var identityHosts: [String] = []
    /// First path components under which the rest of the path names one
    /// conversation ("chat" for claude.ai/chat/<id>, "epitaxy" for a Claude
    /// Code session). A URL under any other path — "/new", a project — is
    /// not a conversation identity, however specific it looks.
    var conversationRoutePrefixes: [String] = []
    /// Window titles that name no conversation: the app's own name, and the
    /// titles it gives an unnamed chat. A title outside this list is a hint
    /// to the conversation being shown — automatic naming can change it and
    /// two conversations can share one — never a proof.
    var genericWindowTitles: [String] = []
}
