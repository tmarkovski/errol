# BotBridge

Relays a conversation between the OpenAI Codex desktop app and Claude Desktop on macOS by automating their UIs: it presses each app's "Copy" button and pastes the response into the other app's composer, exactly like a human relaying messages between two chat windows.

## What we're building and why

An experiment in having two AI assistants talk to each other **as products**, not as raw models. Going through the desktop apps means each side keeps its own system prompt, tools, memory, and subscription context. There are no APIs or SDKs involved anywhere; the entire mechanism is the macOS Accessibility API (`AXUIElement`) plus the system clipboard and synthesized keystrokes.

**Design decision: the desktop apps are the point, not a workaround.** A CLI-to-CLI version (`claude -p` piped into `codex exec` in a loop) was considered and rejected. It would be simpler (no permissions, no clipboard, no focus stealing), but it talks to the bare models. This project specifically wants each side operating inside its app: Claude Desktop with its projects, connected tools/MCP servers, memory, and settings; Codex with its threads, skills, and workspace context. The UI relay is the only way to get that, so the added fragility is accepted. Do not "simplify" this into a CLI pipeline.

## How it works

One turn of the loop:

1. Wait until the current speaker finishes its response. Completion is detected when a **new copy button** appears (count compared to a baseline taken before sending), **no "Stop" button** is visible (still streaming), and that state holds for two consecutive polls.
2. Press the last copy button in the tree (newest message) and confirm the press landed by watching `NSPasteboard.changeCount`.
3. Activate the other app, focus its composer (`AXTextArea`), synthesize Cmd+V, wait for the paste to render, synthesize Return.
4. Swap speaker and listener. Repeat until the turn cap.

Both apps are Chromium-based, and Chromium exposes an empty accessibility tree until nudged, so the script sets `AXManualAccessibility` on both at startup. Everything runs against label-based selectors, kept per app in `AppSelectors` structs inside `Config` because they are the part most likely to break. The labels differ between the apps: ChatGPT calls per-message copies "Copy message" (bare "Copy" is code blocks, "Copy table" is tables), while Claude uses "Copy" with excludes.

Two safeguards discovered the hard way:

- **Window scoping.** All searches run inside one chosen chat window per app, re-resolved on every poll. Claude Desktop can host Claude Code sessions whose windows contain their own "Copy" and "Stop" buttons — including, if you develop this tool inside one, the session driving the relay. Windows containing Claude Code markers ("Terminal input", "New terminal", "Rewind to here") are never eligible, and the preflight refuses to start if an app has no eligible chat window.
- **Send confirmation.** Sending prefers pressing the app's send button over a Return keystroke, then confirms the composer's value actually changed, escalating through Return and Cmd+Return before warning.

## Layout

- `Sources/BotBridge/main.swift`: the whole tool. `Config` at the top holds bundle IDs, label keywords, caps, and timings. Below it: AX helpers, element finders, keyboard synthesis, the copy/send/wait primitives, and the orchestration loop.
- `Package.swift`: plain executable SwiftPM package, macOS 13+.

A markdown transcript of each run is written incrementally (default `botbridge-transcript.md`, gitignored).

## Setup

1. Grant Accessibility permission to your **terminal app** in System Settings > Privacy & Security > Accessibility. Processes launched from the terminal inherit its grant. (If running via Claude Code inside a desktop app, the grant attributes to that app instead; running from Terminal is the clean path.)
2. Launch both apps with a conversation open in each.
3. Build and run:

```sh
swift run BotBridge --turns 2 --seed "Hi! You're talking to another AI through a relay. Say hello briefly."
```

The machine is effectively unusable while it runs (shared clipboard and focus). Ctrl+C stops it and keeps the transcript so far.

## Flags

| Flag | Default | Purpose |
|---|---|---|
| `--list` | | Print running apps and bundle IDs, then exit |
| `--inspect` | | Dump each app's windows, buttons, text inputs, and what the selectors match, then exit |
| `--press chatgpt\|claude "label"` | | Press the first button whose label contains the substring, then exit (debug) |
| `--turns N` | 10 | Responses to relay before stopping |
| `--first chatgpt\|claude` | chatgpt | Who gets the seed prompt (anything not "claude" means the Codex side) |
| `--seed "text"` / `--seed-file path` | generic intro | Seed prompt |
| `--timeout N` | 300 | Seconds to wait for each response |
| `--max-chars N` | 12000 | Truncate relayed messages |
| `--transcript path` | ./botbridge-transcript.md | Markdown transcript output |
| `--chatgpt-bundle-id` | com.openai.codex | Codex/unified app; classic ChatGPT is com.openai.chat |
| `--claude-bundle-id` | com.anthropic.claudefordesktop | Override if needed |

## Status and known brittleness

Verified against live trees (Aug 2026), via `--inspect`:

- **ChatGPT side (com.openai.codex, the unified app)**: a populated conversation exposes "Copy message" buttons per message (one for the user message, one for the response — the relay takes the last), a "Send" button, and a "Message ChatGPT" `AXTextArea` composer. An **empty** chat exposes no copy buttons at all, which looks like selector breakage but isn't. Neither app has a "copy last response" menu command; the message buttons are the only path.
- **Claude side**: a Claude Code session window exposes "Prompt"/"Terminal input" inputs and its own Copy/Stop buttons; the exclusion markers correctly disqualify it. A regular chat window has NOT yet been inspected live — the per-response copy label ("Copy"), the composer label, and the send button label still need verification with a real conversation open.
- The "Stop" label during streaming has not been observed live on either side yet.
- Selectors are label-based and will break when either app renames or icon-ifies its buttons after an update. Non-English UI needs the keywords in `AppSelectors` changed.
- OpenAI's app naming is mid-migration: the unified app can be named ChatGPT.app while identifying as `com.openai.codex`, with a "ChatGPT Classic.app" as `com.openai.chat`. Use `--list` to see what this machine actually runs.
- Turn and length caps are the protection against two chatty models burning through usage limits.

## Troubleshooting

- **App "not running" but it is**: bundle ID mismatch. `--list`, or `osascript -e 'id of app "ChatGPT"'`.
- **Empty tree / no buttons found**: restart the script so the `AXManualAccessibility` nudge reapplies; confirm with Accessibility Inspector.
- **Wrong button pressed (e.g. "Copy code")**: adjust `copyExcludeKeywords` in `Config`.
- **Paste lands but Return doesn't send**: some layouts use Cmd+Return; change `keystroke(keyReturn)` to `keystroke(keyReturn, flags: .maskCommand)` in `send(_:to:)`.
- **Permission prompt loops**: TCC grants stick to the responsible process; grant whichever app actually launched the binary.
