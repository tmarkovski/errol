# Errol

Relays a conversation between the OpenAI Codex desktop app and Claude Desktop on macOS by automating their UIs: it presses each app's "Copy" button and pastes the response into the other app's composer, exactly like a human relaying messages between two chat windows.

Named for the Weasleys' owl: not the fastest courier, has been known to hit the wrong window, but the message always gets delivered. (The naming candidates that lost are recorded in `docs/brand-exploration.md`.)

## What we're building and why

An experiment in having two AI assistants talk to each other **as products**, not as raw models. Going through the desktop apps means each side keeps its own system prompt, tools, memory, and subscription context. There are no APIs or SDKs involved anywhere; the entire mechanism is the macOS Accessibility API (`AXUIElement`) plus the system clipboard and synthesized keystrokes.

**Design decision: the desktop apps are the point, not a workaround.** A CLI-to-CLI version (`claude -p` piped into `codex exec` in a loop) was considered and rejected. It would be simpler (no permissions, no clipboard, no focus stealing), but it talks to the bare models. This project specifically wants each side operating inside its app: Claude Desktop with its projects, connected tools/MCP servers, memory, and settings; Codex with its threads, skills, and workspace context. The UI relay is the only way to get that, so the added fragility is accepted. Do not "simplify" this into a CLI pipeline.

## How it works

The conversation is framed for both participants before the relay goes hands-off. The first agent receives the ground rules (this is an agent-to-agent conversation, the human is not participating, and it can end the run by replying with an empty message or by including the stop sequence, default `[[END-CONVERSATION]]`) followed by the human's initial message from `--seed`. When the first response comes back, the second agent receives the same rules plus both the initial message and that response, so both sides start from identical context. Every message after those two framing messages passes through verbatim. A reply that is empty or contains the stop sequence ends the run.

One turn of the loop:

1. Wait until the current speaker finishes its response. Completion is detected when a **new copy button** appears beyond the baseline, **no "Stop" button** is visible (still streaming), and that state holds for two consecutive polls. The just-pasted user message grows a copy button of its own in both apps, so right after sending, the relay waits for that echo and folds it into the baseline; only buttons beyond it can belong to the response.
2. Press the last copy button in the tree (newest message) and confirm the press landed by watching `NSPasteboard.changeCount`.
3. Bring the other app frontmost and verify it actually got there (see safeguards), focus its composer (`AXTextArea`), synthesize Cmd+V, wait for the paste to render, press the send button.
4. Swap speaker and listener. Repeat until the turn cap.

Both apps are Chromium-based, and Chromium exposes an empty accessibility tree until nudged, so the script sets `AXManualAccessibility` on both at startup. Everything runs against label-based selectors, kept per app in `AppSelectors` structs inside `Config` because they are the part most likely to break. The labels differ between the apps: ChatGPT calls per-message copies "Copy message" (bare "Copy" is code blocks, "Copy table" is tables), while Claude uses "Copy" with excludes.

Three safeguards discovered the hard way:

- **Verified activation.** From a background CLI under macOS cooperative activation, `NSRunningApplication.activate` returns true without effect and setting the AX `kAXFrontmostAttribute` returns success without effect; LaunchServices (`/usr/bin/open -b`) is what actually brings an app forward. Synthesized keystrokes go to the frontmost app regardless of AX focus, so the relay confirms the target is frontmost before typing — via the system-wide AX focused application, falling back to the window server's front window when the focused app's AX server won't answer (Electron apps go quiet intermittently) — and refuses to send keystrokes otherwise. Without this, the seed gets typed into whatever window the user last touched.

- **Window scoping.** All searches run inside one chosen chat window per app, re-resolved on every poll. Claude Desktop can host Claude Code sessions whose windows contain their own "Copy" and "Stop" buttons — including, if you develop this tool inside one, the session driving the relay. Windows containing Claude Code markers ("Terminal input", "New terminal", "Rewind to here") are never eligible, and the preflight refuses to start if an app has no eligible chat window.
- **Send confirmation.** Sending prefers pressing the app's send button over a Return keystroke, then confirms the composer's value actually changed, escalating through Return and Cmd+Return before warning.

## Layout

- `Sources/Errol/main.swift`: the whole tool. `Config` at the top holds bundle IDs, label keywords, caps, and timings. Below it: AX helpers, element finders, keyboard synthesis, the copy/send/wait primitives, and the orchestration loop.
- `Package.swift`: plain executable SwiftPM package, macOS 13+.

A markdown transcript of each run is written incrementally (default `errol-transcript.md`, gitignored).

## Setup

1. Grant Accessibility permission to your **terminal app** in System Settings > Privacy & Security > Accessibility. Processes launched from the terminal inherit its grant. (If running via Claude Code inside a desktop app, the grant attributes to that app instead; running from Terminal is the clean path.)
2. Launch both apps with a conversation open in each.
3. Build and run:

```sh
swift run Errol --turns 2 --seed "Introduce yourselves briefly and compare notes on what you're each good at."
```

The machine is effectively unusable while it runs (shared clipboard and focus). Ctrl+C stops it and keeps the transcript so far. On any exit — run finished, an agent sent the stop sequence, an error, or Ctrl+C — focus is handed back to the app Errol was launched from.

To watch a run with both conversations visible, tile the chat windows first with `swift run Errol --arrange` and restore them afterwards with `--unarrange`. This sets the window frames directly through AX (the same thing tiling utilities do) rather than driving the native Fill & Arrange menus, because the native cross-app "Left & Right" arrangement only pairs windows interactively and, in Claude Desktop, a menu-driven tile would act on whatever window is front — which can be a Claude Code session rather than the chat. Note that `AXEnhancedUserInterface` (set as the Electron accessibility nudge) makes apps ignore or animate AX window moves, so it is temporarily dropped during the move. Arranging twice keeps the first snapshot, so `--unarrange` always restores the true original layout.

## Flags

| Flag | Default | Purpose |
|---|---|---|
| `--list` | | Print running apps and bundle IDs, then exit |
| `--arrange` | | Tile the two chat windows side by side (ChatGPT left, Claude right) on the screen hosting the ChatGPT window, saving their frames first, then exit |
| `--unarrange` | | Restore the frames saved by the last `--arrange` (falls back to centering both), then exit |
| `--inspect` | | Dump each app's windows, buttons, text inputs, and what the selectors match, then exit |
| `--press chatgpt\|claude "label"` | | Press the first button whose label contains the substring, then exit (debug) |
| `--no-hud` | | Don't show the floating log panel during the run |
| `--turns N` | 10 | Responses to relay before stopping |
| `--new-chats` | off | Start a fresh chat in both apps (Cmd+N) before seeding; without it, the relay continues in whatever chats are open |
| `--first chatgpt\|claude` | chatgpt | Who gets the seed prompt (anything not "claude" means the Codex side) |
| `--seed "text"` / `--seed-file path` | generic intro | The human's initial message; the relay wraps it in the framing preamble |
| `--stop-sequence "token"` | `[[END-CONVERSATION]]` | A reply containing this (or an empty reply) ends the run |
| `--timeout N` | 300 | Seconds to wait for each response |
| `--max-chars N` | 12000 | Truncate relayed messages |
| `--transcript path` | ./errol-transcript.md | Markdown transcript output |
| `--chatgpt-bundle-id` | com.openai.codex | Codex/unified app; classic ChatGPT is com.openai.chat |
| `--claude-bundle-id` | com.anthropic.claudefordesktop | Override if needed |

## Status and known brittleness

Verified against live trees and a completed 4-turn relay run (Aug 2026):

- **ChatGPT side (com.openai.codex, the unified app)**: the response's action bar uses a bare "Copy" button; "Copy message" (paired with "Edit message") belongs to the **user** message, and tables get "Copy table". The selector matches "copy" and excludes the qualified labels. An earlier reading that responses use "Copy message" was wrong and cost a debugging round: the relay kept copying its own pasted message back. A "Send" button and a "Message ChatGPT" `AXTextArea` composer are exposed; an **empty** chat exposes no copy buttons at all, which looks like selector breakage but isn't. Neither app has a "copy last response" menu command.
- **Claude side**: verified live — the composer is a "Write your prompt to Claude" `AXTextArea`, the send button matches "send", and per-message copy buttons match bare "copy" with the code/link/table excludes. User messages expose copy buttons too (the echo absorption in step 1 exists for both apps). A Claude Code session window exposes "Prompt"/"Terminal input" inputs and its own Copy/Stop buttons; the exclusion markers correctly disqualify it.
- The "Stop" label during streaming has not been observed live on either side yet; in practice the echo-absorbed copy-button count alone detected completion correctly, since the action bar only renders when a response finishes.
- "Continue in new chat" in ChatGPT carries prior context into the new conversation and leaves stale copy buttons in the tree; start genuinely fresh chats (Cmd+N) between runs.
- Selectors are label-based and will break when either app renames or icon-ifies its buttons after an update. Non-English UI needs the keywords in `AppSelectors` changed.
- OpenAI's app naming is mid-migration: the unified app can be named ChatGPT.app while identifying as `com.openai.codex`, with a "ChatGPT Classic.app" as `com.openai.chat`. Use `--list` to see what this machine actually runs.
- Turn and length caps are the protection against two chatty models burning through usage limits.

## Troubleshooting

- **App "not running" but it is**: bundle ID mismatch. `--list`, or `osascript -e 'id of app "ChatGPT"'`.
- **Empty tree / no buttons found**: restart the script so the `AXManualAccessibility` nudge reapplies; confirm with Accessibility Inspector.
- **Wrong button pressed (e.g. "Copy code")**: adjust `copyExcludeKeywords` in `Config`.
- **Paste lands but Return doesn't send**: some layouts use Cmd+Return; change `keystroke(keyReturn)` to `keystroke(keyReturn, flags: .maskCommand)` in `send(_:to:)`.
- **Permission prompt loops**: TCC grants stick to the responsible process; grant whichever app actually launched the binary.
