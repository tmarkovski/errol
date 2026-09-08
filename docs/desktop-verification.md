# Live desktop compatibility tests

Run the guided harness from the repository in Terminal:

```sh
tools/verify --guided --suite desktop-smoke
```

It asks you to prepare each surface, waits while you focus it, then uses Errol's
production activation, paste, send, response-wait, and copy code. It sends real
prompts into the displayed conversations. New conversations are created by the
operator; the test verifies the empty-composer-to-first-response transition.

The default OpenAI target is the unified ChatGPT/Codex application
(`com.openai.codex`), with Chat, Work, and Codex surfaces. The classic separate
ChatGPT application (`com.openai.chat`) is not covered by this catalog. Claude's
target is `com.anthropic.claudefordesktop`, with Chat, Cowork, and Code surfaces.

## Setup

Use an unlocked, logged-in Mac with both applications installed. Grant
Accessibility permission to the invoking terminal/runner in System Settings →
Privacy & Security → Accessibility. The harness reports blocked coverage if it
cannot access Accessibility; it does not automatically request new permissions.
If macOS attributes access to the built executable, grant that executable. A
rebuild may require refreshing the grant. See `tools/ax-dump.swift` for the
existing terminal permission troubleshooting instructions.

Use disposable conversations. For Work, Cowork, Codex, and Code, use an empty
test project with no external integrations. The prompts explicitly request no
tools, commands, browsing, or file changes. Run one harness at a time and leave
the keyboard alone during each active case, except for a requested focus-loss
step. The native Errol controls checklist explicitly asks you to operate Errol.
Automatic mutations are protected by a per-user process lock so two harnesses
cannot paste or send at the same time. After a completed guided case, focus
returns to the terminal for the next setup prompt. The focus-loss case sounds
a beep when it is time to switch applications.

At a setup prompt:

- Enter: ready; focus the requested app during the countdown.
- `s reason`: record the case as blocked and proceed.
- `q` or end of input: stop; remaining cases stay not run.
- Ctrl+C during an active automatic case: cancel the worker, retain evidence,
  clean up recognized test content, restore the clipboard, and stop the suite.

The case deadline is independent of the production inactivity timeout. A
permanently visible Stop control cannot keep a case alive indefinitely. The
worker gets 20 seconds after the deadline to return and clean up. If it remains
stuck in an app/AX call, the process exits 124 and leaves `deadline.txt` beside
the active case. Inspect leftover test content and the clipboard after a hard
exit; cleanup cannot be guaranteed after forced process termination.

## Suites and selection

```sh
# Inspect the full catalog without touching either app.
tools/verify --suite desktop-full --list

# Save a coverage plan; every case is NOT RUN and exit status is 2.
tools/verify --suite desktop-full --dry-run --output /tmp/errol-desktop-plan

# Twelve core cases: new/existing short prompts on all six surfaces.
tools/verify --guided --suite desktop-smoke

# Payloads, limits, focus, guards, streaming, long history, pairs, and controls.
tools/verify --guided --suite desktop-full --timeout 300

# Nine mode pairings, each with either side starting: 18 six-reply relays.
tools/verify --guided --suite relay-full --timeout 600

# Narrow a run using a case ID or substring. Case IDs come from --list.
tools/verify --guided --suite desktop-full --filter claude.code.new
tools/verify --guided --suite desktop-full --filter leadingNewline
tools/verify --guided --suite desktop-full --filter focusLoss

# Test a higher configured limit, including its boundary and truncation cases.
tools/verify --guided --suite desktop-full --filter aboveLimit --max-chars 64000

# Retain target-window screenshots when Screen Recording is already permitted.
tools/verify --guided --suite desktop-smoke --screenshots
```

The catalog is deterministic. Filtering defines a **selected scope**, not a pass
for the entire suite. Reports retain the selected case IDs and total suite size.
To retry a case, select its ID with `--filter` and use a new output directory.
Runs are not silently combined across application versions or repository changes.

| Cases | Assertions |
| --- | --- |
| New/existing × ten payloads × six surfaces | Empty/draft preflight, paste receipt, exact readable UTF-8 content, confirmed submission, fresh reply contract, independently observed user-message uniqueness and copy identity, cleanup |
| Payloads | Single line, multiline/blank lines/tabs, leading blank lines, Unicode including decomposed accents, Markdown/code, large text, many short lines, cap−1/cap/cap+1 |
| Streaming | Production completion logic plus an actually observed busy-to-idle transition |
| Long history | At least 12 messages by an exposed ordinal; captured mounted messages reveal virtualization |
| Background/search/multiple windows | Verify the prepared focus/window condition before production activation and delivery |
| Conversation switch | Capture original → different → original identities before delivery; guided mode is needed to perform the setup checkpoints |
| Focus loss | Paste, ask the operator to focus another app, then verify production refuses submission and response counters remain unchanged |
| Draft/attachment/busy guards | Harness preflight refuses to call send and preserves the prepared content; these are harness safety tests, not a claim that arbitrary direct callers of `send` protect drafts |
| Claude Code collapsed actions | Observe the newest collapsed action toggle, then exercise production copy expansion |
| Relay pairings | Six numbered replies, current run identifier, confirmed deliveries, readable pasted content, independent message/copy checks, and both final sign-offs |
| Steering/cancel | Live worker waits at the delivery gate, resumes with the note and its echo, or stops before the next handoff |
| Native Errol controls | Operator checklist for Start, Pause, editing/IME, steering, Stop, and reopen; manual evidence is explicitly separate |

For the full matrix, some cases are inapplicable to a particular app build. For
example, a single-window build cannot exercise a multiwindow case. Record this
as blocked coverage instead of presenting it as a pass. If a response finishes
before a busy state is sampled, the streaming case is inconclusive even when
the basic response succeeds.

## Evidence and interpretation

Each run creates `.artifacts/verify/<timestamp>-<id>/` (git-ignored), containing:

- `report.json`: environment, source fingerprint, selected cases, explicit
  computed case statuses, required assertions, and overall completion.
- `report.md`: readable coverage and links to evidence.
- `junit.xml`: test-runner import; incomplete cases appear as skipped, and the
  harness still exits nonzero so a skipped suite cannot make a release green.
- Per-case `events.json`, input and expected paste files, observed composer
  text, copied response and raw clipboard response, AX snapshots, and optional
  screenshots. Pair cases also save the production relay transcript.

Reports are checkpointed before side effects and after each case. An unfinished
case stays not run even if the runner crashes. Evidence write failures stop
further automatic sending and fail the case. Reports must not be overwritten;
use a fresh output directory for each run.

Snapshots retain the fixture schema used by `tests/ErrolKitTests/Fixtures`.
Capture limits and unavailable AX attributes are explicit evidence gaps.
Snapshots and screenshots may include other displayed conversation content;
keep the original run local and anonymize a minimal reproducing fixture before
committing it. Do not automatically replace expected fixtures with a new app's
tree: inspect the changed behavior first and add a regression assertion for it.

The response contract uses a fresh identifier and asks the model to assemble a
reply that does not occur verbatim in the prompt. Copying the user echo therefore
cannot satisfy the reply contract. Unexpected model output is inconclusive,
with delivery and copy evidence retained, rather than automatically blamed on
the UI. Server errors, login requirements, account limits, and unavailable
surfaces appear through setup/completion failures and their saved evidence;
the harness does not guess a vendor-specific error classification from prose.

Byte fidelity is checked against the **actual production-capped payload**.
`maxChars` counts Swift Characters; the explicit truncation marker is appended
after the cap, as production does. UTF-8 byte counts and SHA-256 are also recorded.
Canonical Unicode equivalence does not count as an exact byte match.

When a paste becomes a text attachment, one new chip verifies receipt, not its
contents. Unless readable content is available, `paste-integrity` remains
inconclusive. Sent-message AX text can also normalize formatting. The report
keeps that separate from paste fidelity and does not assert byte transparency
from a model's answer. The copy evidence excludes composer fields, buttons,
toolbars, and timestamps and requires an independently recognized newest
assistant message; unknown message structures remain unverified.

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | Every required assertion in the selected scope passed automatically |
| 1 | At least one required check failed |
| 2 | Blocked, inconclusive, manual, missing, or not-run coverage; or invalid options |
| 124 | Hard overall deadline; current case remains incomplete |

The `desktop-full` catalog includes native app-control checks. A manually
confirmed check is not an automated pass, so those observations do not turn the
full report green. Review the per-stage evidence and unresolved coverage for a
release decision. There is deliberately no “ignore incompletes” switch.

## Offline tests and preconfigured desktop runners

```sh
swift test

# For a desktop runner whose disposable conversation is already prepared:
ERROL_LIVE=1 ERROL_LIVE_CASE=chatgpt.chat.new.short.message \
  swift test --filter LiveRelay
```

The live XCTest entry point uses the same scenario runner and fails if the
selected case is incomplete. It requires one exact catalog ID and does not
create chats or guide conversation switching. Ordinary `swift test` skips the
live tests. A named-pasteboard integration test also skips if the OS pasteboard
service is unavailable to the test process; it never touches the general board.

Keep offline tests in regular CI. Run the small live suite on an unlocked
desktop regularly and after app updates, and run the broader cases before a
release. A dedicated logged-in Mac avoids interfering with ongoing work. Remote
CI without these applications, account sessions, and a window server cannot
establish live desktop compatibility. Regular runs also detect UI changes that
arrive without a desktop application version change.

No scheduled job is installed by building this harness. The existing release
workflow still runs offline tests; live reports are a separate release input.

## Implementation boundaries

`ErrolVerification` is a SwiftPM-only library shared by the command-line runner
and its tests. It uses `@testable import ErrolKit` in debug builds. The Xcode app
continues compiling Core directly and has no dependency on the harness.

Optional synchronous `SendInspection`, `RelayInspection`, and response-poll
callbacks expose production operations to the test runner. The runner can stop
before submitting a mismatched paste; it does not repair selectors or replace
the production transport with a second implementation. Tests must reveal an
adapter regression rather than work around it with another automation agent.

Core now rejects an empty paste needle, uses the first nonempty line for its paste
receipt needle, and rechecks cancellation/focus immediately before keystrokes
and initial submission. Existing callers supply no inspection callbacks.

The legacy `tools/verify`, `--nudge`, and `--live` probes remain available.
`--live` now uses the strict scenario runner and writes a report. Legacy skipped
checks produce exit 2. The known sidebar Copy/Stop selector hazards are still
documented regression fixtures; this work does not silently redefine them as
correct behavior or claim to have fixed the selectors.
