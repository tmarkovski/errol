# Participatory setup: connect the conversations, then start

September 10, 2026. Discussion proposal from a brainstorm between Codex and
Claude on the human's idea for a more participatory first-run experience. No
application changes are made by this proposal. It follows
[First-run usability and predictable relay behavior](../first-run-usability/README.md)
and should be read with it: that document records the findings; this one
records a setup flow that answers several of them through the user's own
actions.

**Implementation reference:** [Participatory setup and session UI spec](SPEC.md)
records the subsequent screen-by-screen decisions, native appearance, desktop
app icons, implementation sequence, and acceptance criteria. Use it for the
current build direction; the discussion below retains the earlier alternatives.

## Interactive preview

Open [the saved preview](preview.html) in a browser. It includes all ten mock
screens and starts with Accessibility. The main bar keeps a consistent capsule
shape through setup, composition, pausing, and completion. It uses system type,
compact controls, and the permission-symbol / explanation / action arrangement
from [the existing Accessibility view](../../../app/Errol/Errol/PermissionOnboardingView.swift).
Narrow layouts can grow to keep instructions readable.

During connection, the arrow nudges toward the active logo; Claude's step mirrors
the arrow and right-aligns the instructions.
Four short progress segments replace the numbered setup labels: completed
steps fill green, the current step is amber and slightly thicker, and all four
fill when both conversations are connected.
Use the screen navigation to explore the full setup and returning-user flow.
The app's existing **sliders icon** sits at the upper trailing edge of the
central content on the setup screens, with an anchored placeholder menu for
content to follow. It has no visible label and is absent from Accessibility.
On Arrange, separate icon-and-label buttons apply the chosen layout at once.
**Keep positions** is the default and leaves the windows where they currently
are; **Continue** is always available and completes the step. The progress
meter advances when continuing, rather than when the windows move.
Demo explanations are hidden by default. Necessary guidance stays inside the
bar, with destination details available on demand. In Codex, the design controls
also offer a rounded-corner alternative to the capsule at the same width.

The preview uses HTML, CSS, and JavaScript. `preview.html` is the single
editable source and opens directly in a browser; there is no generated copy
to keep in sync. Its icon library loads from a CDN and requires internet
access. Codex's optional design-tuning controls appear only inside Codex.

For design iterations, open or reload `preview.html` in the browser window
and inspect the screens and controls directly. Reuse the existing preview tab
when available. This is the default review workflow; use Playwright or other
automated checks only when a specific verification need calls for them.

## The idea

The menu bar app launches, the user grants Accessibility, and presses one
button to set up a session. Errol then walks the user through preparing the
run rather than doing it silently: open each assistant if it is not running,
arrange the two windows, connect each assistant's logo to the conversation
that will receive messages, type the topic, and start. The connection step is
a physical gesture, dragging the logo from Errol onto the window, so that
choosing where messages go is something the user does and sees, not something
Errol infers. By the time the first message is sent, the user has touched
every part of what is about to happen automatically.

## What it answers from the earlier findings

| Finding | How this flow answers it |
| --- | --- |
| Run is enabled before the apps are ready, and a failed start is silent | Setup offers the next achievable action for each app. The final Send action rechecks readiness and leaves any failed-start reason visible, including failures before turn one. |
| The destination lives in a tooltip; Claude Code is a silent fallback target | The user connects each conversation explicitly. The destination card names app, surface, and conversation. A Code session is a deliberate fork with its consequences stated. |
| A human draft in a composer gets sent | A draft becomes a "finish preparing" step during setup, and a recoverable pause during a run. |
| The conversation shape is hidden until the run starts | The shape stays visible through setup, beside the destinations it will be sent to. |
| "New session" resets Errol but not the chats | The ending offers two concrete intentions: another topic in these conversations, or set up fresh conversations. |
| Users do not know what Errol will do to their machine | The start button names its recipient and sits beside one sentence saying what happens next. The same sentence narrates the run. |
| Pause, Stop, and endings are hard to read | One running explanation and phase-appropriate Stop feedback, backed by the explicit outcomes proposed in the earlier document. |

This flow depends on the earlier proposal's destination binding, draft guards,
clipboard protection, and explicit outcomes. Connecting a window once and
explaining the next action do not implement those protections. Result access,
transcript export, and the website corrections remain separate work.

## Proposed core flow, first run

1. **Prepare the apps.** After permission setup, **Set up a session** checks
   both assistants. Each logo carries its next useful action: "Open ChatGPT",
   then "Choose a conversation", then the connected destination. The topic and
   completed steps survive an interruption, such as the user signing in or
   switching away.

2. **Choose the arrangement.** Offer side by side, stacked, and **Keep my
   arrangement**. The user applies the choice explicitly; the windows moving
   into place is the first visible sign that these are the windows Errol will
   work in. Preview or highlight the candidate windows before applying the
   arrangement; if there are several candidates, ask the user to choose which
   windows to move first. Arranging them does not yet connect their conversations.
   Restoring the original positions stays discoverable. Automatic restoration
   at run end is an experiment below. Arrangement is separate from connection:
   connecting works wherever the windows sit.

3. **Connect each conversation.** The primary gesture is the human's:
   drag the logo from its perch onto the window. **Click to choose a window**
   sits beside it, and the picker supports keyboard navigation (Return to
   start picking, arrow keys to cycle eligible windows, Return to bind, Escape
   to cancel). Both gestures produce the same highlight on the window, the
   same destination card, and the same connected state, so the prototype can
   compare them without changing anything downstream.

4. **Resolve destination details in place.** The card shows what Errol can
   observe: app, surface (Chat, Work, Codex, Cowork, Code), the
   conversation title, and the model where the window announces one. A project
   name, where observable, is context rather than necessarily a distinct mode
   or an individual conversation identifier. The card says
   "New conversation" or "Continues this conversation" only when evidence
   supports it. Omit message counts from the core card. If tested as additional
   detail, show a visible-message count only where message recognition is
   reliable, label it as visible, and never infer a fresh conversation from
   a zero count alone. Two states get their own treatment:

   - **A Code or other work session is a deliberate choice.** For example:
     "You're connecting Claude Code. Messages can lead to actions using this
     session's tools." Choices: **Use this session** or **Choose another
     conversation**. Mode labels do not reveal the complete set of tools or
     permissions; do not claim they do.
   - **An existing draft is a finish-preparing step.** "There's an unsent
     message here. Finish it in Claude, or choose another conversation." The
     other connection and the topic stay intact. When the user returns, the
     card says what changed only when observed: "Draft cleared", or "Your
     message was sent; this conversation now includes it." An empty composer
     alone cannot distinguish those cases. When evidence is limited, say
     "The draft is no longer in the composer" and revalidate the conversation
     before allowing the run to start.

   Both connected, the bar briefly shows the two context cards together:
   "ChatGPT: new conversation" and "Claude: continues 'Naming ideas'", so the
   user sees that the assistants may start with different background.

5. **Start with a named recipient.** The topic field's button reads **Send to
   ChatGPT** or **Send to Claude**, following who starts. Beside it, one
   sentence: "Errol will bring these windows forward and exchange replies
   automatically. Use Pause before typing in them." Pressing the button sends
   the first message after a final readiness and destination check. If that check
   fails, keep the reason and next action visible with the user's topic intact.
   Setup affordances go quiet once the run starts: the bar can say
   "Destinations set for this run", the threads turn solid, and Errol's
   conversation options become unavailable. This does not lock either
   assistant's actual window or prevent navigation in it.

6. **Keep one running explanation.** The setup sentence continues as the
   run's narrator: "ChatGPT is replying", "Sending its reply to Claude",
   "Waiting for both to sign off". Pause and Stop carry discoverable meanings.
   Stop feedback follows the actual phase. While awaiting a reply, for example:
   "Stopped relaying. ChatGPT may still finish its reply." Stopping the relay
   does not itself press the assistant's Stop button and need not wait for its
   reply. If a transfer was underway, report whether delivery was confirmed or
   remains uncertain before claiming the message was not sent. The final
   summary uses the explicit outcome from the earlier proposal.

7. **End with clear next intentions.** **Another topic in these
   conversations** keeps the connections and makes continued context
   explicit. **Set up fresh conversations** guides the user through opening
   new chats and connecting them. These replace the action currently called
   New session.

## Returning users

- **Setup collapses into two destination cards** above the topic field:
  "ChatGPT · Chat · Logo brainstorm" and "Claude · Chat · Naming ideas". Each
  card expands into the original connection interaction. Errol verifies the
  destinations again on each visit; remembered details read "Last used" until
  verified.
- **Only the changed part needs attention.** If Claude is closed but ChatGPT
  still shows the chosen conversation, only the Claude card reopens. If the
  windows merely moved, offer **Arrange again**. Setup is repaired in pieces.
- **The arrangement can be remembered** as a preference. **Use your usual
  arrangement** shows a small preview and applies on press, so windows moving
  into place keeps communicating that a run is being prepared.
- **Teaching stays available on demand.** Captions collapse into the ordinary
  status sentence after the first run. **Show the guided setup** brings them
  back, and a newly encountered condition, such as connecting a Code session
  for the first time, brings back just that explanation.

A repeat confirmation through **Use these conversations**, and named reusable
setups such as "Review a design", remain experiments below. They are not extra
required steps in the compact returning flow.

Three states underlie all of this and should stay distinct in the model even
where the UI does not name them: **saved preferences** (arrangement, shape,
who starts), **remembered destinations** (last used, unverified), and
**verified connections** (observed now, bound for this run).

## Intervention during a run

- **A focus change that prevents a safe operation pauses the run.** The relay
  already refuses to type when the target is not frontmost. Instead of ending
  the run, a recoverable refusal becomes a pause: "Errol couldn't safely
  complete the transfer. Review the destination to continue, or Stop." Do not
  attribute a focus change to the user without evidence; an app or system
  dialog may have caused it. Resume follows the earlier proposal's destination,
  sequence, and delivery-evidence checks, so it cannot blindly repeat a paste
  or send. Reading the same connected conversation while an assistant replies
  does not itself trigger a pause. Navigating to another conversation or mode
  can require a hold even if the user's intention was only to read.
- **The bar describes the current activity.** "Claude is replying" and
  "Transferring the reply to ChatGPT" describe observable phases. They do not
  promise that the user has an interruption-free interval to use the keyboard
  or clipboard: the next reply can arrive at any time, and the current app
  does not provide exclusive desktop ownership. Keep "Use Pause before typing
  in either chat" available, with clipboard behavior grounded in the earlier
  proposal's ownership work.
- **Steering is learned at a boundary.** The running sentence points to Pause
  at the first handoff. Whether a real, one-time guided pause at that moment
  helps or stalls is a teaching experiment below.

## Interaction experiments

These are candidates to prototype and compare, not commitments. The core flow
above works with any outcome.

| Experiment | What it tests | Status |
| --- | --- | --- |
| Drag logo to window versus click to choose a window | Which gesture users find and remember; which fails on small screens | Prototype both; drag prominent |
| Frontmost shortcut ("bring the conversation to the front, then press ⌘⇧E") | Keyboard-only and power-user connection; shortcut conflicts and behavior across displays and Spaces need validation | Candidate third method; key combination illustrative |
| Drop hints ("Drop onto a Claude conversation", "Open a conversation here first") | Whether a failed drop teaches the gesture | With the drag prototype |
| First-run countdown ("Errol takes the keyboard and clipboard in 3, 2, 1", Escape cancels) | Whether the hands-off warning lands at the right moment or feels like a stall | Optional teaching treatment |
| Guided pause at the first handoff | Whether experiencing a real steering point teaches more than a caption | Optional teaching treatment |
| "Take turns" layout: full-size windows, active side brought forward | Small laptop screens | Prototype |
| One window per display; each app in its own Space | Two displays; full-screen users | Validation item, see below |
| Park the window under its perch (dock zones that snap the window into place) | Merging arrangement and connection into one gesture | Later |
| Pick from the app's own sidebar list, Errol presses the entry | Connection by choosing from a list and watching the app obey | Later; selected row not observable in fixtures |
| Hover draws the thread, click pins it | A persistent visible connection through the run | Later |
| Use these conversations on returning visits | Whether an extra connection action improves awareness enough to justify the repeated step | Optional returning-flow experiment |
| Named reusable setups | Whether saving layout, shape, and starting assistant helps repeated work without implying saved live connections | Later |
| Restore the original arrangement automatically at run end | Whether restoration is expected or disrupts reading the result; preserve any subsequent manual window changes | Optional layout policy; default unresolved |

**Deferred: sending the first message by hand.** The user copies the opener
from the bar, pastes it into the conversation, and Errol takes over from the
reply. Observing the opener could help establish the starting conversation
where the evidence is sufficient; the first-run proposal does not establish
this as universally reliable. It is deferred because it is a second
workflow, it binds only the starting side, and opener recognition is
unresolved on surfaces that hide message bodies or attachment content.

**Set aside for the initial prototype: a narrated, slowed first exchange.**
Compare the simpler caption and optional guided pause first. Whether either
teaches the mechanism as effectively is a usability question, not a finding.

## What the app can establish today

Reusable now, from the current source:

- The readiness scanner selects an eligible window and reports surface, title,
  and model when exposed. This is not yet a user-selected, verified connection
  ([Readiness.swift](../../../app/Errol/Errol/Core/Readiness.swift)).
- Helpers request side-by-side tiling and restore saved frames over Accessibility.
  Stacked layouts, automatic end-of-run restoration, and restoring the exact
  user-connected window need additional work. Current restoration resolves an
  eligible window again and can therefore affect a different window
  ([Arrangement.swift](../../../app/Errol/Errol/Core/Arrangement.swift)).
- A click-through overlay that follows a window's frame, currently the
  disabled veil ([Veil.swift](../../../app/Errol/Errol/Veil.swift)); it provides
  drawing groundwork for a destination highlight, not a completed picker.
- Per-display drawing for the transfer dot and the receiving outline
  ([TransferOverlay.swift](../../../app/Errol/Errol/TransferOverlay.swift)),
  which the threads can reuse.
- The frontmost check that refuses to type into the wrong app, and the hold
  loop the steering pause uses
  ([RelayActions.swift](../../../app/Errol/Errol/Core/RelayActions.swift),
  [Relay.swift](../../../app/Errol/Errol/Core/Relay.swift)).
- The panel is configured to join all Spaces and act as a full-screen auxiliary
  ([MenuBarController.swift](../../../app/Errol/Errol/MenuBarController.swift)).

Needs validation before the flow can promise it:

- **Dragging out of the non-activating panel onto another app's window.**
  Errol does not need the target app to accept a drop; it needs to track the
  pointer during the drag and read the window under it when the mouse is
  released. Whether the Electron windows answer a position query reliably,
  and how the drag interacts with the panel's first-click behavior, is
  unverified.
- **Conversation identity** has the limits recorded in the first-run
  proposal. The checked ChatGPT fixtures do not supply a conversation URL;
  the Cowork fixtures reuse `/new`. Those fixtures do not establish universal
  live-app behavior. Fresh-chat identity acquisition and automatic naming
  need phase-appropriate evidence. "Continues this conversation" must rest
  on what is observed rather than the presence of a title alone.
- **Launching an app from the logo** when it is installed but not running,
  and detecting "signed in with a conversation open" afterwards, is not
  implemented.
- **Cross-display and cross-Space behavior** of arrangement, the threads,
  and the relay's activation is not established by the existing code paths.
- **Remembered destinations across launches** need a fresh observation and,
  where possible, a stable identifier. Live Accessibility element references
  must be reacquired after the target process relaunches or rebuilds its tree;
  they cannot serve as durable saved connections. Saved title and surface text
  can be retained as hints, but neither their persistence in the target app
  nor their uniqueness is guaranteed.

## The usability test

Before the first send, a participant should be able to answer, unprompted:

1. Which two conversations will receive messages.
2. Whether each assistant continues existing context or starts fresh.
3. What Errol is about to do automatically, including that it will bring the
   windows forward and use the keyboard.
4. Where they can pause it, and what Stop leaves behind.

Compare the gestures across participants and screen/input conditions. Record
comprehension, independent completion, mistaken connections, and recovery.
One successful or unsuccessful trial does not settle prominence, and a mouse
preference does not remove the need for an accessible keyboard path.

## Decisions still to resolve

- Whether drag or click-to-pick is primary after testing, and whether the
  frontmost shortcut ships as a visible third method or an accessibility
  path.
- How much of the first-run teaching survives into the returning flow by
  default, and what brings it back.
- The exact contract for a focus change during copy or delivery: what counts
  as interference, what the pause says, and how Resume verifies the
  destination before continuing (the first-run proposal's sequence checks
  apply).
- Whether remembered destinations are offered at all on surfaces with no
  stable identity, or whether those surfaces always ask to reconnect.
- How the arrangement choice behaves on a screen too small for side by side.
- Whether automatic restoration, repeat connection confirmation, or named
  setups add enough value to become defaults or core features.

## Review status

Codex reviewed this draft against the earlier findings and current source on
September 10, 2026, and corrected capability claims and operation-dependent
copy. Only Markdown proposal text changed. Relative links and whitespace were
checked; no application tests, live relay runs, or gesture prototypes were run.
