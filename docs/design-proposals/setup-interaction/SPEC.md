# Participatory setup and session UI — implementation spec

September 10, 2026. Implementation baseline from the reviewed interactive
preview and the subsequent design discussion. This document records the
experience to build; it does not report that the application implements it.

## Reference and precedence

- [Interactive screen reference](preview.html): open in a browser and select
  the numbered screen controls underneath it. The ten numbers in this document
  refer to those controls, not to steps shown in the product.
- [Editable reference](preview-source.html): the current HTML/CSS/JavaScript
  mockup. Its default appearance is the reference; design-control alternatives
  are experiments.
- [Setup proposal](README.md): rationale and alternatives considered.
- [First-run usability](../first-run-usability/README.md): relay behavior,
  destination evidence, and its updated implementation status.

Use this spec for the latest UI decisions. Use the relay's observed state for
what the UI can truthfully say. A demonstration's hardcoded success, example
conversation title, model, or reply count is not evidence about a live app.
Implement the product with SwiftUI and AppKit, using the existing native panel.
The HTML preview is a design reference, not an embedded product interface.

## Agreed visual direction

**One recognizable capsule.** Permission setup, app preparation, connection,
composition, running, steering, and the ending use the same main window and
normal desktop footprint. Change its contents rather than opening a differently
shaped onboarding window or widening the steering screen.

The reference capsule is 860 × 156 CSS pixels at its full desktop width. Use
approximately that footprint in native points as the initial implementation
target, then compare optically at standard text size. Define the native width
and base height once in `Perch`; do not multiply the reference values by the
existing scale a second time. All ten normal-content views should share those
dimensions. Clamp width to the available display. Longer text, localization,
and accessibility take precedence over an exact height: wrap and grow downward
when needed, keeping the top and horizontal center anchored.

Use a true `Capsule` outline with fully rounded ends. The preview's 28-pixel
rounded rectangle remains a comparison option, not a product setting or a
second shape used for selected phases. System Settings and genuine temporary
popovers retain their own native shapes.

| Element | Visual contract |
| --- | --- |
| Typography | Native system type throughout app chrome. Normal sentence case; no display/serif headings, tracked uppercase labels, or underlined web-style actions. |
| Hierarchy | Reference: 19-point main instruction, 16-point editor, 12-point supporting copy/actions, 11-point secondary metadata. Reconcile with native text metrics and accessibility rather than shrinking text to force a fit. |
| Surface | Quiet opaque surface, fine separators, restrained shadow, compact native controls. Use existing semantic palette tokens and preserve the user's appearance preference. |
| Content | One primary instruction or editor, one compact action row, and essential status. Secondary destination details open on demand. |
| Participant positions | ChatGPT on the left and Claude on the right in the reference configuration. Changing the starting assistant does not swap these positions. Use actual configured app names and identities. |
| Main icons | Installed desktop app icons, with original appearance and aspect ratio, at a consistent modest size throughout setup and the run. No extra decorative tile behind them. |
| Missing app | Same-sized initial fallback plus the app name and an actionable missing-app message. Do not substitute another app's icon. |
| Status | Text plus an unobtrusive presence/check indicator. Motion or color alone must not carry readiness, selection, or failure. |
| Temporary details | An anchored native popover or a destination overlay when needed. These do not become permanent panels beneath the capsule. |

Use `AppIcons.icon(forBundleID:)` for the main participants. The current
`PerchWidgetParticipant` prefers `AppIcons.mark`; change that preference for
this experience. Preserve the same app icons after setup rather than switching
to bare marks when the run starts.

Keep existing run options, app configuration, appearance, and log access
available through the existing settings entry point. The demo omits some of
these controls for clarity; it does not authorize removing their capabilities.

## Screen index

| Preview screen | Product phase | Primary content and action |
| --- | --- | --- |
| [01 · Access](#screen-01-access) | Permission needed | Accessibility request in the capsule; Open Accessibility Settings… |
| [02 · Open apps](#screen-02-open-apps) | Prepare apps | Click each desktop app icon to open it; continue when prepared. |
| [03 · Arrange](#screen-03-arrange) | Choose layout | Side by side, Stacked, or Keep positions; apply explicitly. |
| [04 · ChatGPT](#screen-04-connect-chatgpt) | Connect first destination | Drag the left app icon, or click to choose a window. |
| [05 · Claude](#screen-05-connect-claude) | Connect second destination | Mirrored right-hand instruction and arrow. |
| [06 · Compose](#screen-06-compose) | Ready to start | Shape, topic, visible destination summaries; Send to the named first assistant. |
| [07 · Running](#screen-07-running) | Exchange in progress | Current activity, next recipient, Pause to steer, Stop. |
| [08 · Pause](#screen-08-pause) | Paused at a safe boundary | Steering editor inside the same capsule; send, resume, or stop. |
| [09 · Finished](#screen-09-finished) | Terminal outcome | Actual run outcome; another topic here or fresh conversations. |
| [10 · Return](#screen-10-return) | Prepare another topic | Revalidated destinations and a new topic in the compact capsule. |

### Screen 01: Access

Reuse [PermissionOnboardingView](../../../app/Errol/Errol/PermissionOnboardingView.swift),
including its permission request and automatic rechecking. Its layout is the
reference: permission symbol at the leading end, explanation in the center,
and one action at the trailing end.

- Title: **Allow Accessibility access**.
- Explanation: **Errol needs it to read replies and send messages between your
  two desktop apps.**
- Path: **System Settings › Privacy & Security › Accessibility. Turn on Errol.**
- Action: **Open Accessibility Settings…**. The first invocation may bring up
  the system permission prompt; subsequent invocations open its settings pane.
- Status: **Checks access automatically**.

When access is observed, transition in the same capsule to screen 02. The
preview's settings panel and toggle represent macOS UI; Errol must not create a
fake permission switch. Permission revocation takes precedence over setup or
running content and prevents further automation until resolved.

### Screen 02: Open apps

Check the configured applications and present each side's next useful action:
**Open ChatGPT**, **Opening…**, **Open a conversation**, or the observed ready
state. Launch only in response to the corresponding user action. A running app
is not necessarily signed in or showing a usable conversation.

Keep the other side's progress if one application needs installation, sign-in,
or a conversation opened. Show the reason in the capsule. Do not imply that
clicking an unavailable icon installs an application. The preview's **Open both
apps** is an optional convenience that can call the same two launch actions.

The normal primary action becomes **Continue** once suitable candidate windows
can be prepared. This does not yet connect or authorize a destination for a run.

### Screen 03: Arrange

Use a compact segmented selector inside the capsule: **Side by side**,
**Stacked**, **Keep positions**. Apply via **Arrange** or **Use positions**;
when successfully applied or intentionally kept, offer **Continue**.

Preview the candidate windows before moving them. If there is more than one
candidate for an app, make the target window explicit before arrangement.
Arrangement and connection remain separate actions. Respect window minimum
sizes and the display's usable frame. If a layout cannot fit, explain that and
offer Keep positions; do not squeeze either app beyond its supported size.

Save the specific windows and their original frames for a discoverable restore
action. Reapplying a layout must not replace that original snapshot with an
intermediate layout. Restore only the appropriate still-existing windows,
checking for later manual changes. Automatic restoration on completion is
deferred; closing a run should leave its conversations available to read.

### Screen 04: Connect ChatGPT

Instruction: **Drag ChatGPT onto its conversation.** Supporting copy:
**Choose where your first message will go** when ChatGPT starts; otherwise
describe it as the destination for the other assistant's replies.

The primary visual gesture starts at the desktop app icon. Place a left-pointing
arrow beside the instruction, nudging toward that icon three times, then staying
still. The reference uses about 7 points of movement and 0.9 seconds per nudge.
Hide the cue when dragging or picking begins. Respect Reduce Motion with a
static arrow. The arrow identifies what to pick up; the window highlight
identifies where to drop it.

Provide **Click to choose a window** beside the drag instruction. The picker
supports pointer selection and keyboard navigation: Return starts selection,
arrows move among eligible windows, Return chooses, and Escape cancels.
An invalid drop preserves setup and explains the next useful action.

While targeting a candidate, show its highlight and observed destination card.
For an ordinary eligible chat, dropping on that candidate or choosing it in the
picker confirms the connection; do not require an additional identical modal
confirmation. Show the connected destination beneath the app icon and continue
to screen 05. Special work surfaces require the deliberate choice described
under recovery states.

Errol owns this drag interaction. It is selecting a window, not transferring an
image file or message into the assistant's composer. Do not rely on the target
application accepting a file drop.

### Screen 05: Connect Claude

Mirror screen 04: right-pointing arrow toward Claude's icon; instruction,
supporting text, and actions right-aligned. Keep ChatGPT's connection visible.
For the default starting assistant, the supporting sentence is **Choose where
ChatGPT's replies will land.** Adapt it if Claude starts instead.

Keep progress chronological from left to right even though the instruction
block is right-aligned. Never reverse completed and remaining segments.
After the second successful connection, proceed to screen 06.

### Screen 06: Compose

Show the conversation shape, topic editor, both selected destination summaries,
and the named send action inside the normal capsule. The main action is
**Send to ChatGPT** or **Send to Claude**, following the starting-assistant
option. Keep that option discoverable in the existing session settings.

The app icons now open destination details or reconnect their side; they do
not silently change who starts. This replaces their current first-speaker
selection behavior. Starting-assistant changes must update the send label.

Show concise destination names beside/beneath the app icons, with enough visible
context to distinguish **New chat** from **Continues here**. **Destinations**
opens fuller app, surface, conversation, and observed model details on demand.
Do not require opening that popover to discover that a work surface was chosen.

Essential pre-send guidance remains inside the bar: **Errol exchanges replies
automatically. Pause before typing in either app.** Use each shape's topic
prompt as its editor placeholder. Existing custom instructions and other
conversation configurations must remain usable.

Enable Send only when the opening content is valid and both selected
destinations are currently ready. Recheck at the click. A failed start leaves
the topic intact and a specific reason beside the unavailable action; it does
not return to an unexplained blank composer or success summary.

### Screen 07: Running

Use the same capsule, now showing actual activity: **ChatGPT is replying…**,
**Sending its reply to Claude**, or the equivalent for the other side. Keep
**Pause to steer** and **Stop** available, with essential typing guidance.
Use existing transfer feedback when the corresponding copy/delivery occurs.
Do not trigger a handoff animation merely because the demo's screen advances.

Configuration that could change the running session is unavailable until the
run ends. This does not lock the external apps or prevent someone reading them.
Do not promise that the keyboard or clipboard is exclusively owned, or that
the next reply will leave an interruption-free interval.

### Screen 08: Pause

Retain the same width and normal height as the other screens. Replace the
central content with a compact note editor; do not add a separate large form.

While the relay is still reaching a safe boundary, say **Pausing after the
current handoff…**. Only say **Paused · Nothing is being copied or sent** once
that is true. Use the existing steering lifecycle and its focus coordination.

Actions: **Send note & continue**, **Resume without note**, **Stop**. State the
actual recipient order for a submitted note. Preserve a pending note through
holds and withheld deliveries; never resubmit a note just because a UI phase
was re-rendered. Long notes remain editable within the native editor's existing
growth/scroll behavior without widening the capsule.

### Screen 09: Finished

Render the actual `RunReport`. Only a completed mutual sign-off receives the
successful completion wording. User stop, timeout, turn limit, lost destination,
and uncertain delivery retain their own explanations. An assistant may continue
generating after Errol stops relaying; do not claim its generation was cancelled.

Keep two next intentions within the capsule:

- **Another topic here**: clear the next-topic editor, retain preferences, and
  revalidate these conversations for screen 10. Their earlier context remains.
- **Set up fresh conversations…**: guide the user to open new conversations in
  the assistants, then connect them. Do not clear external chats or imply that
  resetting Errol created new chats. Preserve a prepared topic if reconnecting
  was initiated during setup instead of from a finished run.

No extra permanent outcome-explanation panel below the bar. More detail can be
available through the existing log/details entry point.

### Screen 10: Return

Return directly to the compact topic editor when both destinations can be
verified again. Label remembered hints **Last used** until observed; only then
show the verified context. Reopen only the side that needs attention. A moved
window does not by itself require reconnecting the same conversation.

Keep **Destinations**, layout settings, starting-assistant selection, and a way
to revisit guided setup available. Saving a preference or conversation title
must never persist an Accessibility element as a live connection.

## Progress and motion

The four progress segments represent screens 02–05: prepare apps, arrange,
connect ChatGPT, connect Claude. Accessibility precedes that progress; composing
and the exchange are not additional setup segments.

Completed segments fill with the success color, the current segment uses the
active accent and a slightly greater thickness, and remaining segments use the
neutral track. A step completes only when its action succeeds; Keep positions
counts as an intentional layout choice. All four fill at screen 06. Hide the
setup meter once the run begins and in the ordinary returning flow.

Expose a descriptive progress value to VoiceOver, including the current step.
Keep the numerical wording accessible without displaying “1 of 4” in the bar.
Animate state changes briefly and respect Reduce Motion. Do not announce every
animation frame or repeat an attention cue on every readiness poll.

## Destination and recovery contract

**Ready** means the selected window still represents the intended supported
destination, its composer is observable and empty, there are no unsent
attachments, it is not replying, and any work-surface choice has been explicit.
The setup UI and final preflight must use the same evidence and classification.

| Condition | Required experience |
| --- | --- |
| App missing, closed, or signing in | Name the side and its next action. Keep the other side and the topic. |
| Existing draft or unsent attachment | Show **Finish preparing** and the observed reason. Let the user resolve it in the assistant or choose another conversation; never delete or send it for them. |
| Assistant already replying | Wait for it to finish before Ready. Preserve the setup state. |
| Unreadable composer or unsupported surface | Explain what cannot be established. Do not turn unknown into Ready. |
| Code, Work, Cowork, or another supported work surface | Name the actual surface and context. Say that messages may lead to actions using that session's tools; offer **Use this session** and **Choose another conversation** in the destination card. Do not infer its complete tools or permissions from its name. |
| Model or conversation context not observable | Omit the unknown field or state that it is unavailable. The demo's **Model · App default** is not a production fallback assertion. |
| Fresh chat acquires its first title/route | Treat it as provisional, then adopt identity only within the existing phase-appropriate binding rules. A generic title or zero visible messages does not prove freshness. |
| Conversation changes during setup | Invalidate that connection and explain what needs reconnecting. Keep the topic and the unaffected side. |
| Conversation changes during a run | Hold at observation/capture/delivery boundaries and identify the original destination. Resume only after identity and history continuity are established. No **Continue here** redirection in this version. |
| User merely reads a connected conversation while an assistant replies | No pause solely for reading. A focus change that blocks a safe operation requires recovery at that operation. |
| Focus prevents an operation before any typing | Preserve the pending payload and show a recoverable pause when a safe retry is possible. Do not blame the user without evidence. |
| Delivery might already have happened | Show uncertainty; do not blindly retry. Preserve the existing outcome/evidence contract. |
| Bound app quits or window closes during a run | End with the actual lost-destination outcome. Do not silently find another window. |
| Stop during a hold | Stop at a safe point promptly, keeping the previous blocker as context. |

Saved preferences, remembered destination hints, and verified live connections
are separate state. A selected window's identity and mode must reach the relay
unchanged. Re-running a general “find a chat window” search at Send can silently
pick a different window and is not sufficient.

Preserve clipboard leases and all existing copy/send guards. Current whitespace
classification accommodates Claude's idle newline; readiness work must validate
that rule against intentional drafts and observed placeholders rather than
assuming any unreadable or whitespace-bearing composer is safe.

## What is demonstration-only

Do not ship the mock desktop, assistant message samples, ten-screen navigator,
Next/Previous review controls, design-tuning panel, example reply counts, or
simulated System Settings window. Optional **Demo note** captions are review
annotations. Product instructions belong in the capsule or a contextual detail
surface when the user needs them.

The HTML drag is a local demonstration, not validation of AppKit drag tracking,
Electron hit testing, window identity, clipboard behavior, or accessibility.
Its keyboard picker and live readiness transitions are not fully implemented.
Its examples always use ChatGPT first; production must support both directions.

## Implementation map and order

The source already contains `BoundDestination`, `ComposerState`, `RunBlock`,
`RunReport`, and clipboard leases. Build on those production types rather than
porting the verification harness again. The gap is carrying user-selected
destinations through setup into those operations and exposing their state.

| Work | Existing home | Required change |
| --- | --- | --- |
| Shared capsule and geometry | [PerchPanelView](../../../app/Errol/Errol/Perch/PerchPanelView.swift), [PerchStyle](../../../app/Errol/Errol/Perch/PerchStyle.swift), [PanelNavigation](../../../app/Errol/Errol/PanelNavigation.swift), [MenuBarController](../../../app/Errol/Errol/MenuBarController.swift) | Keep a common base size and frame anchoring across the new phases; preserve native text growth. |
| Permission and participants | [PermissionOnboardingView](../../../app/Errol/Errol/PermissionOnboardingView.swift), [PerchAvatar](../../../app/Errol/Errol/Perch/PerchAvatar.swift) | Reuse the permission lifecycle; prefer desktop app icons and phase-appropriate actions. |
| Session/setup model | [RelayController](../../../app/Errol/Errol/RelayController.swift), [RelayEngine](../../../app/Errol/Errol/RelayEngine.swift) | Add explicit setup phases, per-side selection/readiness, launch actions, and independent recovery. Keep it separate from running/steering state. |
| Window selection | [Readiness](../../../app/Errol/Errol/Core/Readiness.swift), [Elements](../../../app/Errol/Errol/Core/Elements.swift), [Destination](../../../app/Errol/Errol/Core/Destination.swift), [Veil](../../../app/Errol/Errol/Veil.swift) | Enumerate candidates, implement drag/picker and its overlay, and bind the selected element with the available identity evidence. |
| Arrangement | [Arrangement](../../../app/Errol/Errol/Core/Arrangement.swift) | Add stacked layout and Keep positions; act on explicit windows, and retain/restore the correct original frames. |
| Start and relay continuity | [Relay](../../../app/Errol/Errol/Core/Relay.swift), [RelayActions](../../../app/Errol/Errol/Core/RelayActions.swift) | Accept selected bindings from setup; scope composer/copy/send resolution to those windows; preserve guards and outcome reporting. |
| Running, steering, ending | [PerchWidget](../../../app/Errol/Errol/Perch/PerchWidget.swift), [PerchSteering](../../../app/Errol/Errol/Perch/PerchSteering.swift), [RunOutcome](../../../app/Errol/Errol/Core/RunOutcome.swift), [TransferOverlay](../../../app/Errol/Errol/TransferOverlay.swift) | Match screens 06–10 without losing current note delivery, focus coordination, or accurate endings. |

Implement in these reviewable stages:

1. Establish the shared native shell, desktop icons, and previews for all ten
   phases. Keep unimplemented setup controls confined to native previews.
2. Build explicit candidate selection and prove drag-out/hit-testing alongside
   the accessible picker. Define how selected bindings enter the engine before
   enabling the new Send path.
3. Wire permission, launch, readiness, arrangement, and connection progress.
   Confirm the user sees the same destination the engine will use.
4. Wire named Send, compact steering, outcome actions, and return/reconnect
   behavior to the existing relay lifecycle.
5. Exercise real apps and recovery scenarios, then enable the integrated flow.

Do not duplicate setup progress as an independent counter: derive it from the
completed actions. Do not replace the controller's report with a UI guess based
on turn count or elapsed time.

## Acceptance and validation

| Review | Pass condition |
| --- | --- |
| Native visual pass | Screens 01–10 use system type and the same normal desktop capsule footprint, including 08. App icons stay recognizable and consistent. |
| Permission | Initial grant, return from Settings, and revocation behave in the shared panel without a second Errol onboarding window. |
| Setup progression | Closed apps, sign-in, multiple windows, layout failure, cancellation, and retry preserve unrelated setup work. Progress follows successful actions. |
| Connection gestures | Drag and pointer/keyboard pick select the same observed window. Wrong-app drops do nothing destructive. Escape cancels. No icon image is pasted into an assistant. |
| Accessibility | Keyboard-only setup is complete; VoiceOver reads progress, identity, readiness, and recovery; Reduce Motion removes bouncing and transfer motion. |
| First send | Both starting-assistant choices name the correct recipient. A changed destination or new draft between Ready and Send blocks delivery without losing the topic. |
| Bound operations | With multiple windows open, capture, composer checks, paste, and submit all use the selected windows; general candidate discovery cannot substitute another one. |
| Steering and holds | The editor appears within the same shell. Notes survive holds and are delivered once in the stated order. Reading alone does not interrupt an idle wait. |
| Outcomes and return | Timeout on the last permitted reply still says timeout; uncertain delivery stays uncertain; another topic keeps context; fresh setup actually requires new selected conversations. |
| Layout resilience | Light/dark appearance, smaller displays, longer titles/topics/notes, and changed window minimum sizes keep essential instructions and controls readable. |

Use existing fixture-driven engine tests for binding, composer state, response
waits, clipboard leases, and outcomes. Add focused state-transition tests for
setup and selected-window routing; use native previews and manual visual review
for typography and geometry. Live gesture validation must precede claims that
dragging works across applications. Cross-display and cross-Space arrangements
remain unpromised until tested on those configurations.

Defer manual first-send, mandatory countdowns or teaching pauses, mid-run
redirection, named reusable setups, automatic fresh-chat creation, and automatic
layout restoration. These are not prerequisites for the agreed initial flow.

## Implementation status

September 10, 2026. The first pass of stages 1–4 landed in the app; stage 5
(real apps and recovery scenarios) has not been run. What is built:

- **The shell.** One 860 × 156-point capsule for every phase, with the
  installed desktop app icons at the ends (`PerchParticipant`), the four-segment
  meter over the center through screens 02–06 (`PerchProgressMeter`), labeled
  capsule actions beside it (`PerchButtons`), and the settings entry point in
  every state. Previews for all ten screens are in `PerchPreviews.swift`, on a
  preview engine that answers setup actions with canned windows.
- **The state.** `Core/Setup.swift` holds the pure flow — presence per app,
  candidates per window, steps completing only on their actions, connections
  judged by the same evidence the preflight uses, a lost conversation
  reopening only its side — with state-transition tests
  (`SetupStateTests`, `WindowCandidateTests`, `ArrangementTests`).
- **Selected windows reach the engine unchanged.** A connection binds the
  chosen `AXUIElement` (`BoundDestination(target:window:)`) and every finder is
  scoped to it through `TargetApp.boundWindow`; `chatWindow(in:)` answers with
  the bound window or nothing. `runRelay` takes the bindings, rechecks them at
  Send, and refuses with the reason rather than re-finding a window. Before a
  paste the bound window must also be the app's front window, raised there if
  it can be, else the run holds ("behind another ChatGPT window").
- **Readiness.** The sweep that drove the strip now also refreshes the engine's
  window registry, offers candidates with frames, and verifies each binding
  (`ReadinessReport`); the setup UI and the preflight read the same
  classification. Ready means the window still shows the connection, the
  composer is readable and empty, nothing is generating, and any work surface
  was accepted explicitly.
- **Arrangement.** Side by side, Stacked, and Keep positions, applied to the
  specific windows; a window that will not take its frame puts both back and
  reports it. The original frames are kept from the first arrangement, and
  restore skips windows moved by hand since. No automatic restoration.
- **Connection.** The keyboard picker (Return starts, arrows move, Return
  connects, Escape cancels) with the accent highlight over the candidate
  window (`WindowHighlight`), pointer selection on the rows, a Code session
  offered as a deliberate choice with **Use this session** in the destination
  details, remembered destinations shown as **Last used** and pre-highlighted
  in the picker, never as live connections.
- **Send, pause, ending, return.** **Send to ChatGPT** / **Send to Claude** by
  the starting-assistant setting, enabled only when both destinations read
  ready, with the reason beside it otherwise; the pause states worded as
  agreed; **Another topic here** revalidates both connections; **Set up fresh
  conversations…** returns to the connect steps.

Not built, deliberately:

- **The drag from the icon onto a window.** The picker and the icon click are
  the connection gestures; both end in `SetupController.connect(_:to:)`, which
  the drag will call too. The connect instruction reads "Connect ChatGPT to its
  conversation" until the drag lands, since "Drag ChatGPT onto its conversation"
  would not be true.
- **Live validation** of the picker's keys inside the non-activating panel,
  of `AXFocusedWindow` and `AXRaise` on the Electron windows, of the arrangement
  read-back, and of cross-display and cross-Space behavior. None of these has
  been exercised against the real apps yet.
- The website copy, mandatory countdowns, mid-run redirection, named setups,
  and automatic fresh-chat creation, as the spec defers them.
