# Participatory setup and session UI — implementation spec

September 10, 2026. Implementation baseline from the reviewed interactive
preview and the subsequent design discussion. This document records the
experience to build; it does not report that the application implements it.

## Reference and precedence

- [Interactive screen reference](preview.html): open in a browser and select
  the numbered screen controls underneath it. The ten numbers in this document
  refer to those controls, not to steps shown in the product.
- The interactive reference is also the editable HTML/CSS/JavaScript source.
  Its default appearance is the reference; design-control alternatives are
  experiments.
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

Use `AppIcons.shared.icon(forBundleID:)` for the main participants. Preserve
the same app icons after setup rather than switching to bare marks when the
run starts. Load artwork from the installed applications; do not ship copies
of their icons inside Errol.

ChatGPT's optional Codex icon is a Dock preference, separate from the default
Finder icon. For `com.openai.codex`, read its `DockIconPreference` and
`DockIconResourceName` values and load the matching PNG from that app's
Resources folder. The Codex system choice follows the Mac's light/dark
appearance independently of Errol's theme. Unknown preferences or missing
files fall back to the ordinary macOS installed icon. Claude and other target
apps use the macOS installed icon directly. Never change another app's settings.

Refresh existing avatars when ChatGPT announces an icon preference change,
when the system appearance changes, when apps launch or quit, and when Errol
becomes active. Do not retain an obsolete icon until Errol restarts. The
installed versions inspected on September 13 include a 2048 × 2048 ChatGPT
PNG, 1024 × 1024 Codex light/dark PNGs, and Claude icon renditions up to
1024 × 1024, comfortably above the participant's display size. These vendor
preference keys and filenames are an optional compatibility path, not a
public cross-app Dock-icon API. The HTML preview uses fixed sample artwork;
native previews resolve the installed app and its current preference.

Participant hover feedback belongs to the icon artwork itself: darken the
image slightly while an actionable icon is hovered, with a short 0.12-second
transition. Draw no background tile, circle, border, or halo around it. Keep
the pointer target within the icon's layout slot, excluding the participant's
name and status. Opening or otherwise inactive icons have no hover treatment.
Preserve the closed/open opacity distinction and the launch bounce. Keyboard
focus remains visible independently of hover.

Keep existing run options, app configuration, appearance, and log access
available through the existing settings entry point. The setup reference now
places the existing **sliders icon** at the upper trailing edge of the
capsule's central content, beside the progress meter. Match the app's
`slider.horizontal.3` entry: icon only, no visible label or chevron, with a
quiet circular hover target and **Configure** as its accessible label and
tooltip. Keep its position consistent through Open apps, Arrange, both
connection steps, Compose, and Return, including the mirrored Claude
instruction. Compose and Return share the entry's row with the conversation
shape. Omit configuration from the Accessibility screen.

For now the reference opens an anchored placeholder containing **No options
yet.** Menu content will be designed later. It dismisses on a second click,
outside click, or Escape, and is reachable by keyboard. This placeholder is
only for the design reference; preserve the native app's existing settings
capabilities.

## Screen index

| Preview screen | Product phase | Primary content and action |
| --- | --- | --- |
| [01 · Access](#screen-01-access) | Permission needed | Accessibility request in the capsule; Open Accessibility Settings… |
| [02 · Open apps](#screen-02-open-apps) | Prepare apps | Click each app's logo to open it; a five-second countdown on Continue advances once both are open. |
| [03 · Arrange](#screen-03-arrange) | Choose layout | Keep positions (the default), Side by side, or Stacked; a choice applies at once, and Continue is offered from the start. |
| [04 · ChatGPT](#screen-04-connect-chatgpt) | Connect first destination | Draw a line from the left app icon to the marked message field, or click to choose a window. |
| [05 · Claude](#screen-05-connect-claude) | Connect second destination | Mirrored right-hand instruction, arrow, and drag line to Claude’s message field. |
| [06 · Compose](#screen-06-compose) | Ready to start | Shape, topic, visible destination summaries; Send to the named first assistant. |
| [07 · Running](#screen-07-running) | Exchange in progress | Current activity, next recipient, Pause to steer, Stop. |
| [08 · Pause](#screen-08-pause) | Paused at a safe boundary | Steering editor inside the same capsule; send, resume, or stop. |
| [09 · Finished](#screen-09-finished) | Terminal outcome | Actual run outcome; another topic here or fresh conversations. |
| [10 · Return](#screen-10-return) | Prepare another topic | Revalidated destinations and a new topic in the compact capsule. |

Across the guided screens the capsule keeps one structure: the participant
columns at the ends, each the app's icon over a compact label, with a second
line only for useful destination or recovery information; the center between two hairlines, with the progress meter at its top
left and the settings entry point at its top right; the step's copy under
them; and the step's actions under the copy, in the compact pill buttons of
the reference, never in a column of their own.

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

Use a single 17-point-high label slot beneath each app icon. An open app shows
only its name; remove **App open** everywhere in setup and do not reserve an
empty status row. For a closed app, hovering its icon or focusing it by
keyboard slides the name downward out of the slot and brings **Click to
open** in from above, over 0.18 seconds. Hold the hint for one full second,
then reverse the transition to restore the name, even if the pointer stays.
Repeat only on a new hover/focus entry. Leaving the icon, launching the app,
or changing screens cancels the hint. The label itself is not a hover target.

**Opening…** or **Checking…** temporarily uses that same label slot. Restore
the app name once open. Preserve essential recovery text such as **Not
installed**, and destination details in later steps, as a second line when
needed. Keep the icon's accessible app name and **Open [app]** action stable;
with Reduce Motion, swap the label instantly while keeping the one-second
hold. Launch only in response to the corresponding user action. The step asks only that both
apps be open: a running app is not necessarily signed in or showing a usable
conversation, and that is the connect steps' concern, not this one's.

An app that is not open has a faded icon at 45% opacity. Keep it faded while
**Opening…**; once the app is observed running, bring it to full opacity over
0.22 seconds. A failed launch stays faded. Labels remain at normal opacity,
so the icon still reads as an available action. With Reduce Motion, update
opacity immediately.

While a user-requested launch is pending, the corresponding app icon makes a
Dock-style vertical hop: 12 points up and back over 0.6 seconds, a smaller
4-point rebound over 0.24 seconds, then 0.16 seconds at rest. Repeat this
one-second cycle only while that side reads **Opening…**. Move only the icon;
keep the label slot, button target, and the capsule's geometry fixed. Both the
individual icon and **Open both apps** trigger this feedback, independently
for each app that actually needs to launch. An already-running app does not
bounce when brought forward. Stop when launch succeeds, fails, or setup is
left, and return the icon to its resting position. With Reduce Motion, keep
the icon still and retain **Opening…** as the progress feedback. This is an
animation of Errol's icon, following the familiar Dock behavior.

The browser reference simulates a 1.6-second launch so the opening state can
be reviewed; the native app follows observed launch state without adding a
delay. Duplicate clicks while opening do not start another launch.

Keep the other side's progress if one application needs installation or
opening. Show the reason in the capsule. Do not imply that clicking an
unavailable icon installs an application. **Open both apps** calls the same
launch action for whichever app is not open.

The one primary action sits under the copy: **Open both apps** until both are
open, then **Continue · 5**. Once both are detected, including when they were
already open on entry, count down for five seconds. A soft fill moves left to
right inside Continue, beneath its readable label, while the number counts
down. Keep the control's size stable as the digits change. Ready copy reads
**Both apps are open.** and **Next, choose how to arrange the windows.**

Clicking Continue or pressing Return advances immediately. There is no
secondary countdown action. Users return through earlier segments in the
progress bar. Returning to Open apps leaves an ordinary Continue button and
suppresses automatic continuation for the rest of that setup, even after
another readiness check or app launch. Fresh setup restores the countdown.
Repeated readiness checks must not restart an active countdown. If either
app stops being open during the initial countdown, cancel it; detecting both
again starts a fresh five seconds.
Leaving the step cancels its pending work. Recheck the phase and both apps'
presence when advancing, so a late callback cannot skip another step.

At timeout or on Continue, fade the Open apps instructions and controls out
and the Arrange content in over about 0.3 seconds. Keep the capsule, icons,
settings entry point, and layout anchors in place; the progress meter updates
to Arrange with its amber marker sliding from segment one to segment two
over the same 0.3 seconds, leaving the completed segment green. Keep the four
tracks fixed while the single thicker marker moves between their positions.
Do not fade or recreate the later prompt editor. Reduce Motion
keeps the numeric countdown but removes the moving fill and transition.
Going on does not yet connect or authorize a destination for a run, and does
not arrange any windows until a layout is chosen.

### Screen 03: Arrange

Use three separate compact action buttons inside the capsule: **Side by side**,
**Stacked**, **Keep positions**, with Keep positions selected at first. Each
has a layout icon and label; the selected choice has a checkmark and a subtle
accent. Give each button its own boundary and spacing, without a shared
segmented track. The buttons communicate an immediate window action, and
the selection records the current choice. A choice applies as it is made:
Side by side or Stacked moves the windows at once, and Keep positions leaves
their current frames alone, including after trying another layout. It does
not restore their original frames.

Supporting copy initially reads **Choose a layout to move both windows now,
or continue as they are.** After a move, confirm **Windows are side by side.
Continue when you’re ready.** or the stacked equivalent. Keep keyboard focus
on the chosen button and announce the result. There is no separate apply
action; **Continue** is offered from the start and waits
only while a move is in progress. A moving layout chosen while an app has no
window to move applies once one appears. Arranging again and putting the
windows back are the settings' **Arrange windows now** and **Restore window
positions**.

Preview the candidate windows before moving them. If there is more than one
candidate for an app, make the target window explicit before arrangement.
Arrangement and connection remain separate actions. Respect window minimum
sizes and the display's usable frame. If a layout cannot fit, put both windows
back, explain that, and leave Continue available; do not squeeze either app
beyond its supported size.

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
static arrow. The arrow identifies what to pick up. As the drag begins, run a
lead out of the icon to the pointer, with a plug at its end, so the gesture
reads as connecting the app's perch to its conversation; bring the app forward
beneath the console and draw a drop area over each showing conversation's
message field, the way the transfer outline marks the receiving
composer during a run; the drop area identifies where to drop it, and where
Errol will write. A field whose geometry cannot be read gets the whole window
as its area. Say what the drop does on the area itself ("Drop here", "Errol
pastes messages here and sends them"), so the gesture teaches how Errol drives
the app.

The lead uses the current theme's accent, a continuous rounded stroke and a
slight downward curve, anchored at the icon's edge. It follows the pointer
without easing; the icon stays in its perch. Use a 2.5-point stroke and a
5-point-radius round plug with a 2-point paper-colored edge. Over a valid
field, increase the stroke to 3 points and the plug radius to 7 points. The
line sits above the capsule; the field marker sits beneath it. There is no
idle line to the window title bar or persistent connection line after release.

| Gesture state | Capsule and icon | Message field and line |
| --- | --- | --- |
| Ready | Original instruction, arrow and **Drag to connect**; click alternative available. | No line or field marker. |
| Dragging | Hide the arrow; icon status **Drag to the field**. Supporting copy becomes **Drop it on the marked message field. That is where Errol pastes and sends.** | Line follows the pointer. Mark each eligible field with a 2-point accent outline and 12% accent tint. Center an accent chip with **Drop here** and **Errol pastes messages here and sends them**. |
| Over a field | Icon status **Release to connect**. | Increase the outline to 3 points and tint to 24%; enlarge the plug. Chip reads **Release to connect**, with the conversation's name and observed state underneath. |
| Released on a field | Show the connected destination and advance to the other app, or Compose. | Remove the line and marker. No extra confirmation for an ordinary eligible conversation. |
| Cancelled | Escape or release over the capsule returns to Ready without an error. A release elsewhere explains **Drop onto the marked message field in [app], or click to choose a window.** | Remove the line and marker; preserve the other connection. |

The chip uses 13-point semibold headline and 11-point detail, a rounded
8-point background, and the theme's on-accent text. Omit the detail when the
actual field is less than 64 points tall. The reference shows a taller field
to expose both lines. Keep the conversation itself visible during the drag;
the full destination card belongs to the picker. Color changes supplement
text and geometry. Reduce Motion removes the introductory nudge; the line
still follows the user's pointer directly without autonomous animation.

The saved reference provides **Ready**, **Dragging**, and **Over message
field** review controls above the mock desktop on screens 04 and 05. They
hold a gesture state for inspection without requiring an active drag; they
are not part of the application. Dragging the icon also exercises the local
preview: only its own marked message field accepts the release.

Provide **Click to choose a window** beside the drag instruction. The picker
supports pointer selection and keyboard navigation: Return starts selection,
arrows move among eligible windows, Return chooses, and Escape cancels.
An invalid drop preserves setup and explains the next useful action.

While the pointer is over a drop area, it reads as ready to take the drop and
names the conversation and its observed state. The drop resolves against the
drawn areas, not against whatever window is under the pointer: releasing over
an area connects its window; releasing elsewhere leaves setup intact and says
where to drop; releasing back over the console puts the icon back and says
nothing. For an ordinary eligible chat, dropping on its area or choosing it in
the picker confirms the connection; do not require an additional identical
modal confirmation. Show the connected destination beneath the app icon and
continue to screen 05. A Code session connects the same way; its name under
the icon says what it is.

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
Do not require opening that popover to discover that a work surface is connected.

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
neutral track. In the native meter, a single active marker slides to the next
segment over 0.3 seconds while the completed track changes to green. The
Open apps → Arrange reference synchronizes this movement with the content
fade, for both timeout and immediate Continue. Reduce Motion updates the
position and colors immediately. The meter's bounds and spacing stay fixed.
Each earlier segment is a button with a 24-point-high target within the
existing toolbar, a step-name tooltip, a keyboard focus indication, and a
spoken step label. Current and future segments are unavailable. Later steps
still require both apps to be open; navigation waits for a pending window
move or connection to finish. Navigating closes any temporary picker or drag
overlay and preserves the selected layout, bound conversations, and draft.
Keep the active marker on the revisited step even if it was completed before.
A revisited connection offers Continue with its existing binding, so inspecting
an earlier screen never forces the user to reconnect. The meter is hidden
during a run and cannot reopen setup then.
A step completes on its action: Continue or its countdown on
prepare, Continue on arrange, and a successful connection on each connect step. The arrangement
itself does not complete the arrange step; going on with the windows as they
are, moved or kept, does. All four fill at screen 06. Hide the
setup meter once the run begins and in the ordinary returning flow.

Expose a descriptive progress value to VoiceOver, including the current step.
Keep the numerical wording accessible without displaying “1 of 4” in the bar.
Animate state changes briefly and respect Reduce Motion. Do not announce every
animation frame or repeat an attention cue on every readiness poll.

## Destination and recovery contract

**Ready** means the selected window still represents the intended supported
destination, its composer is observable and empty, there are no unsent
attachments, and it is not replying.
The setup UI and final preflight must use the same evidence and classification.

| Condition | Required experience |
| --- | --- |
| App missing, closed, or signing in | Name the side and its next action. Keep the other side and the topic. |
| Existing draft or unsent attachment | Show **Finish preparing** and the observed reason. Let the user resolve it in the assistant or choose another conversation; never delete or send it for them. |
| Assistant already replying | Wait for it to finish before Ready. Preserve the setup state. |
| Unreadable composer or unsupported surface | Explain what cannot be established. Do not turn unknown into Ready. |
| Code, Work, Cowork, or another supported work surface | Name the actual surface and context under the icon and in the destination card, and connect it like any conversation: an existing session is where the human wants the relay to land. Do not infer its complete tools or permissions from its name. |
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

The HTML pointer-tracked drag is a local demonstration, not validation of AppKit
drag tracking, native message-field discovery, window identity, clipboard
behavior, or accessibility. It creates no browser image/file drop. The mock
desktop contains one field per app; the native whole-window fallback when
field geometry is unavailable is described above but not simulated.
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
| Installed artwork | ChatGPT's default/Codex choice and the Codex system light/dark variant match the selected Dock artwork. Preference changes refresh existing avatars. Missing assets or unknown preferences retain the installed macOS icon; missing applications retain the initial fallback. |
| Permission | Initial grant, return from Settings, and revocation behave in the shared panel without a second Errol onboarding window. |
| Setup progression | Closed apps, sign-in, multiple windows, layout failure, cancellation, and retry preserve unrelated setup work. Progress follows successful actions. |
| Automatic prepare continuation | Detecting both apps starts one five-second fill on Continue. Continue skips the wait. The progress bar returns to earlier steps; returning to Open apps suppresses its countdown. Readiness loss or leaving the screen prevents stale advancement. The handoff fades only the step content, with a still alternative for Reduce Motion. |
| Connection gestures | A line follows the pointer from the icon to the marked message field; the field label and plug change when armed. Release connects the same window as pointer/keyboard pick. Release over the capsule or Escape cancels; wrong-field drops preserve setup. Line and markers disappear on completion or cancellation. No icon image is pasted into an assistant. |
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

September 12, 2026. Screens 02–05 now follow the updated reference. The native
Xcode previews for those four screens were inspected, the app built, and 30
focused setup, arrangement, and window-hit tests passed. A check against the
compiled native controller also covered immediate arrangement, Continue gating,
Keep positions, coalesced pointer queries, cancellation, invalid drops, and
fresh target resolution at release. Real-app and recovery validation remains
incomplete. What is built:

- **The shell.** One 860 × 156-point capsule for every phase, with the
  installed desktop app icons at the ends (`PerchParticipant`), the four-segment
  meter over the center through screens 02–06 (`PerchProgressMeter`), labeled
  capsule actions beside it (`PerchButtons`), and the settings entry point in
  every console state, omitted from Accessibility. Configure uses only the
  existing sliders icon, beside the progress meter, and opens the existing
  native settings popover. Previews for all ten screens are in `PerchPreviews.swift`, on a
  preview engine that answers setup actions with canned windows.
- **Selected app artwork (September 13).** The shared observable `AppIcons`
  loader reads ChatGPT's optional Dock preference and loads its selected
  Codex artwork from the installed bundle, with the macOS icon as fallback.
  Claude continues to use its installed icon. App and appearance notifications
  invalidate cached images and redraw the existing participants. The app build
  passed, and native closed/ready previews showed the user's selected Codex
  icon. A read-only check resolved both 1024 px variants from the installed
  preference and checked default/unknown preference fallback. Live switching
  in ChatGPT and a system appearance change have not been manually exercised.
- **Open-app feedback (September 13).** The production `PerchParticipant`
  uses one name/action label during preparation. Hover or keyboard focus
  briefly reveals **Click to open**, returning to the app name after a
  one-second hold. **Opening…** occupies the same slot; **App open** and
  its empty status row are removed. Closed icons are faded, bounce while
  the real launch is pending, and reach full opacity once observed running.
  Hover darkens only the icon artwork. A custom icon button style preserves
  full opacity for open apps even when their icons have no action. The native
  closed and ready appearances were inspected and the app build passed; live
  hover timing and launch motion remain unverified. Reduce Motion keeps the bounce and
  label slide still, while retaining the status and timed hint. Connection
  details and recovery messages keep their second line when needed.
- **Automatic prepare continuation (September 13).** Both detected apps mount
  a five-second countdown on Continue, with an elapsed fill inside the button
  and immediate manual continuation. Its view-owned task cancels when
  readiness is lost or the step disappears; the existing state guard checks
  presence and phase again before advancing. The shared setup center fades
  from Open apps to Arrange over 0.3 seconds. Reduce Motion retains the
  countdown digits without the fill or fade. The HTML reference mirrors this
  flow and restarts an initial countdown when a hidden preview becomes visible.
  Progress segments now return to earlier screens while preserving setup;
  an intentional return to Open apps waits for Continue. The current and
  future segments are disabled, and in-flight moves or binding block navigation.
  The native build passed and the Open apps preview advanced to Arrange.
  Offline checks against the preview's actual script covered five-second
  timing, repeat renders, immediate Continue, readiness loss,
  redetection, navigation, and Reduce Motion. The short native fade has not
  been visually reviewed in motion.
- **Progress navigation (September 13).** Earlier segments have mouse and
  keyboard actions, with the original thin tracks inside taller hit targets.
  Navigation preserves setup and closes temporary selection UI. Open apps
  waits for manual Continue after returning through the meter. A revisited
  bound connection also supports Continue/Return without rebinding. Native
  build and preview-script checks passed. The setup state suite passes all
  23 tests against the compiled app, including back navigation, preserved
  connections, prerequisite guards, and countdown suppression. Fresh native
  click inspection is blocked by Xcode's "Failed to launch app in reasonable
  time" preview error; the displayed cached canvas is not current validation.
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
  composer is readable and empty, and nothing is generating; a Code session
  reads like any other conversation.
- **Arrangement.** Side by side, Stacked, and Keep positions, applied to the
  specific windows; a window that will not take its frame puts both back and
  reports it. The original frames are kept from the first arrangement, and
  restore skips windows moved by hand since. Separate icon-and-label action
  buttons show the current choice with a checkmark. Choices apply immediately;
  Continue completes the step. Keep positions preserves the current frames.
  Completion is announced to VoiceOver. No automatic restoration.
- **Connection.** The keyboard picker (Return starts, arrows move, Return
  connects, Escape cancels) with the accent highlight over the candidate
  window (`WindowHighlight`), pointer selection on the rows, a Code session
  connecting like any chat and named as one under the icon, remembered
  destinations shown as **Last used** and pre-highlighted
  in the picker, never as live connections.
- **Drag connection.** `PerchConnectionDragHandle` tracks the active icon's
  pointer outside the capsule without creating a pasteboard item or external
  file drop. As the drag begins `ConnectionDropOverlay` runs a lead from the
  icon's edge to the pointer on a click-through panel over the console, and the
  engine brings the app forward beneath the console (`connectionDropZones`),
  waits for the window server to show its windows, and reads each eligible
  window's message field the way the transfer outline does — the field the app
  draws, widened past the group that merely pads it; the overlay draws
  an area over each field, saying what the drop does, and the lead's plug
  swells with the area under it. The areas are the drop targets: the pure geometry in
  `Core/WindowHitTesting.swift` (`WindowHitTestingTests`) gives a window no
  area while the server does not show it or another window covers its field,
  so an area never floats over something else. The pointer over an area arms
  it; release there calls the same binding as the picker. Escape cancels; a
  release elsewhere leaves setup intact and says where to drop; a release over
  the console puts the icon back. Screens 04 and 05 use the mirrored drag
  instruction, with the click/keyboard alternative still available.
- **Send, pause, ending, return.** **Send to ChatGPT** / **Send to Claude** by
  the starting-assistant setting, enabled only when both destinations read
  ready, with the reason beside it otherwise; the pause states worded as
  agreed; **Another topic here** revalidates both connections; **Set up fresh
  conversations…** returns to the connect steps.

Remaining validation and deferred work:

- **Live validation** of drag tracking and target resolution across applications,
  the picker's keys inside the non-activating panel,
  of `AXFocusedWindow` and `AXRaise` on the Electron windows, of the arrangement
  read-back, and of cross-display and cross-Space behavior. None of these has
  been exercised against the real apps yet.
- The website copy, mandatory countdowns, mid-run redirection, named setups,
  and automatic fresh-chat creation, as the spec defers them.
