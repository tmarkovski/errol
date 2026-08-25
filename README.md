# Errol

Relays a conversation between the OpenAI Codex desktop app and Claude Desktop on macOS by automating their UIs: it presses each app's "Copy" button and pastes the response into the other app's composer, exactly like a human relaying messages between two chat windows.

It is a menu bar app: an owl sits in the status bar, and clicking it opens a floating panel where you type the instruction that seeds the conversation and press Start. There is no CLI; the panel's Inspect button covers the selector debugging the old command-line flags used to.

Named for the Weasleys' owl: not the fastest courier, has been known to hit the wrong window, but the message always gets delivered. (The naming candidates that lost are recorded in `docs/brand-exploration.md`.)

## What we're building and why

An experiment in having two AI assistants talk to each other **as products**, not as raw models. Going through the desktop apps means each side keeps its own system prompt, tools, memory, and subscription context. There are no APIs or SDKs involved anywhere; the entire mechanism is the macOS Accessibility API (`AXUIElement`) plus the system clipboard and synthesized keystrokes.

**Design decision: the desktop apps are the point, not a workaround.** A CLI-to-CLI version (`claude -p` piped into `codex exec` in a loop) was considered and rejected. It would be simpler (no permissions, no clipboard, no focus stealing), but it talks to the bare models. This project specifically wants each side operating inside its app: Claude Desktop with its projects, connected tools/MCP servers, memory, and settings; Codex with its threads, skills, and workspace context. The UI relay is the only way to get that, so the added fragility is accepted. Do not "simplify" this into a CLI pipeline.

## How it works

The conversation is framed for both participants before the relay goes hands-off. The first agent receives the ground rules (this is an agent-to-agent conversation, the human is not participating, and it can end the run by replying with an empty message or by including the stop sequence, default `[[END-CONVERSATION]]`) followed by the instruction typed into the panel. When the first response comes back, the second agent receives the same rules plus both the initial message and that response, so both sides start from identical context. Every message after those two framing messages passes through verbatim. A reply that is empty or contains the stop sequence ends the run.

One turn of the loop:

1. Wait until the current speaker finishes its response. Completion is detected when a **new copy button** appears beyond the baseline, **no "Stop" button** is visible (still streaming), and that state holds for two consecutive polls. The just-pasted user message grows a copy button of its own in both apps, so right after sending, the relay waits for that echo and folds it into the baseline; only buttons beyond it can belong to the response.
2. Press the last copy button in the tree (newest message) and confirm the press landed by watching `NSPasteboard.changeCount`.
3. Bring the other app frontmost and verify it actually got there (see safeguards), focus its composer (`AXTextArea`), synthesize Cmd+V, wait for the paste to render, press the send button.
4. Swap speaker and listener. Repeat until the turn cap.

Both apps are Chromium-based, and Chromium exposes an empty accessibility tree until nudged, so `AXManualAccessibility` is set on both at the start of each run. Everything runs against label-based selectors, kept per app in `AppSelectors` structs inside `Config` because they are the part most likely to break. The labels differ between the apps: ChatGPT calls per-message copies "Copy message" (bare "Copy" is code blocks, "Copy table" is tables), while Claude uses "Copy" with excludes.

Three safeguards discovered the hard way:

- **Verified activation.** From a background process under macOS cooperative activation, `NSRunningApplication.activate` returns true without effect and setting the AX `kAXFrontmostAttribute` returns success without effect; LaunchServices (`/usr/bin/open -b`) is what actually brings an app forward. Synthesized keystrokes go to the frontmost app regardless of AX focus, so the relay confirms the target is frontmost before typing — via the system-wide AX focused application, falling back to the window server's front window when the focused app's AX server won't answer (Electron apps go quiet intermittently) — and refuses to send keystrokes otherwise. Without this, the seed gets typed into whatever window the user last touched.

- **Window scoping.** All searches run inside one chosen chat window per app, re-resolved on every poll. Claude Desktop can host Claude Code sessions whose windows contain their own "Copy" and "Stop" buttons — including, if you develop this tool inside one, the session driving the relay. Windows containing Claude Code markers ("Terminal input", "New terminal", "Rewind to here") are never eligible, and the preflight refuses to start if an app has no eligible chat window.
- **Send confirmation.** Sending prefers pressing the app's send button over a Return keystroke, then confirms the composer's value actually changed, escalating through Return and Cmd+Return before warning.

## Layout

Everything lives in the Xcode project at `app/Errol` (`Errol.xcodeproj`). Inside the app target:

- `ErrolApp.swift`: the `@main` entry point; a placeholder Settings scene plus the delegate adaptor that installs the shell.
- `MenuBarController.swift`: the AppKit shell — the status item and the floating panel hosting the SwiftUI view. It stays AppKit because the panel must be a non-activating floating panel (the Spotlight pattern): SwiftUI's `MenuBarExtra` window dismisses itself whenever another app activates, which the relay does on every turn, so the controls and log would vanish exactly when a run needs them visible.
- `ControlPanelView.swift` / `RelayController.swift`: the SwiftUI interface and its observable model — form state, the log, and the start/stop/inspect wiring around the engine.
- `Core/`: the relay engine, split by concern. `Config.swift` holds bundle IDs, label keywords, caps, and timings; `Accessibility.swift` and `Elements.swift` the AX wrappers and window-scoped element finders; `Activation.swift` the verified-activation and refocus logic; `Arrangement.swift` the window tiling; `Keyboard.swift` the synthesized keystrokes; `RelayActions.swift` the copy/send/wait primitives; `Relay.swift` the message framing and the orchestration loop; `Inspect.swift` the selector-debugging dump; `Readiness.swift` the continuous scan behind the panel's readiness strip; `Logging.swift` the log, transcript, and the cancellation flag behind the Stop button.

Three build settings depart from the app template's defaults and matter: **App Sandbox is off** (a sandboxed app can neither get the Accessibility permission nor post keystrokes — with it on, Errol can do nothing), **`SWIFT_DEFAULT_ACTOR_ISOLATION` is `nonisolated`** (the engine runs on a worker thread while the main thread serves the panel; the template's main-actor default would fight that design), and **`LSUIElement` is set** (menu bar only, no Dock icon).

A markdown transcript of each run is written incrementally to `~/Documents/errol-transcript.md` (the app is launched from Finder with `/` as its working directory, so the path is absolute; macOS may ask once for access to the Documents folder).

## Setup

1. Open `app/Errol/Errol.xcodeproj` in Xcode and run, or build and copy `Errol.app` wherever you keep apps.
2. Launch both chat apps with a conversation open in each.
3. Click the owl in the menu bar, type the instruction that should seed the conversation, and press Start. The first Start triggers the Accessibility permission prompt; grant **Errol** in System Settings > Privacy & Security > Accessibility and press Start again. (When running from Xcode, the grant may attribute to Xcode instead — grant whichever the prompt names. Re-signed rebuilds can look like a new app to the privacy system; re-toggle the grant if pressing Start silently does nothing.)

The machine is effectively unusable while a run is active (shared clipboard and focus). Stop ends the run at the next safe point and keeps the transcript so far; when a run ends, focus is handed back to whatever was frontmost when Start was pressed.

## Controls

- **Readiness strip**: the top of the panel shows each side's live status — ChatGPT on the left, Claude on the right, the same sides the tiling uses. While the panel is open it re-scans every few seconds (paused during runs). The dot turns green with "Ready" when the app has a chat window with a composer — the same test the run preflight applies — "Not found" when it's running without a usable chat UI, and "Not running" when it isn't up. Each side also names the surface it detected: ChatGPT's active mode is read from its mode-switcher popup (Chat vs Codex), and Claude's surface comes from the window's claude.ai URL (chat, project chat, or a Claude Code session), with a note when other surfaces are open alongside. The scan never triggers the permission prompt (that stays tied to Start); without the Accessibility grant both sides show "No access".
- **Instruction**: the human's initial message. The relay wraps it in the framing preamble, so it should read like an ordinary request, not an explanation of the relay.
- **Turns** (default 10): responses to relay before stopping — the protection, along with the message length cap, against two chatty models burning through usage limits.
- **Start new chats**: Cmd+N in both apps before seeding; without it, the relay continues in whatever chats are open.
- **Tile the chat windows side by side**: arrange ChatGPT left, Claude right before the run, so both conversations are visible. This sets window frames directly through AX (the same thing tiling utilities do) rather than driving the native Fill & Arrange menus, because the native cross-app "Left & Right" arrangement only pairs windows interactively and, in Claude Desktop, a menu-driven tile would act on whatever window is front — which can be a Claude Code session rather than the chat. `AXEnhancedUserInterface` (set as the Electron accessibility nudge) makes apps ignore or animate AX window moves, so it is temporarily dropped during each move. Tiling twice keeps the first snapshot, so restore always returns to the true original layout.
- **Inspect**: dump each app's windows, buttons, text inputs, and what the selectors match into the log — the first stop when a run misbehaves after an app update.
- Right-clicking the owl offers **Open Transcript**, **Restore Window Positions** (undo the tiling from the saved snapshot), and **Quit**.

Settings without UI — bundle IDs, timeouts, the stop sequence, the per-message length cap, selector keywords — live at the top of `Core/Config.swift`.

## Status and known brittleness

Verified against live trees and a completed 4-turn relay run (Aug 2026):

- **ChatGPT side (com.openai.codex, the unified app)**: the response's action bar uses a bare "Copy" button; "Copy message" (paired with "Edit message") belongs to the **user** message, and tables get "Copy table". The selector matches "copy" and excludes the qualified labels. An earlier reading that responses use "Copy message" was wrong and cost a debugging round: the relay kept copying its own pasted message back. A "Send" button and a "Message ChatGPT" `AXTextArea` composer are exposed; an **empty** chat exposes no copy buttons at all, which looks like selector breakage but isn't. Neither app has a "copy last response" menu command.
- **Claude side**: verified live — the composer is a "Write your prompt to Claude" `AXTextArea`, the send button matches "send", and per-message copy buttons match bare "copy" with the code/link/table excludes. User messages expose copy buttons too (the echo absorption in step 1 exists for both apps). A Claude Code session window exposes "Prompt"/"Terminal input" inputs and its own Copy/Stop buttons; the exclusion markers correctly disqualify it.
- The "Stop" label during streaming has not been observed live on either side yet; in practice the echo-absorbed copy-button count alone detected completion correctly, since the action bar only renders when a response finishes.
- "Continue in new chat" in ChatGPT carries prior context into the new conversation and leaves stale copy buttons in the tree; start genuinely fresh chats (the "Start new chats" toggle) between runs.
- Surface detection for the readiness strip: ChatGPT's `Switch mode, current mode: <mode>` popup and Claude's `/epitaxy/` web-area URL (a Claude Code session) are verified against live trees (Aug 2026). The claude.ai path names for regular chats, new chats, and project chats in `surfacePathNames` are expected values that have not been observed yet — an unknown path shows up raw in the strip, which is the cue to add it to the map in `Core/Config.swift`.
- Selectors are label-based and will break when either app renames or icon-ifies its buttons after an update. Non-English UI needs the keywords in `AppSelectors` changed.
- OpenAI's app naming is mid-migration: the unified app can be named ChatGPT.app while identifying as `com.openai.codex`, with a "ChatGPT Classic.app" as `com.openai.chat`. `osascript -e 'id of app "ChatGPT"'` shows what this machine actually runs.

## Troubleshooting

- **App "not running" but it is**: bundle ID mismatch. Check with `osascript -e 'id of app "ChatGPT"'` and adjust the IDs in `Core/Config.swift`.
- **Empty tree / no buttons found in Inspect**: quit and relaunch Errol so the `AXManualAccessibility` nudge reapplies; confirm with Accessibility Inspector.
- **Wrong button pressed (e.g. "Copy code")**: adjust `copyExcludeKeywords` in `Core/Config.swift`.
- **Paste lands but Return doesn't send**: some layouts use Cmd+Return; change `keystroke(keyReturn)` to `keystroke(keyReturn, flags: .maskCommand)` in `send(_:to:)`.
- **Start silently does nothing after a rebuild**: the privacy system treats a re-signed build as a new app; re-toggle Errol (or Xcode, for Xcode-launched runs) in System Settings > Privacy & Security > Accessibility.
