# Chat Composer Redesign Proposals

Status: design exploration, September 1, 2026. These files are reference
material, not production UI and not part of the app build.

This directory records three related proposals for reconciling Errol's
conversation setup, prompt, run controls, steering, and session lifecycle.
They were developed while the production wireframe UI was being restructured,
so the proposals describe behavior and visual hierarchy without prescribing the
final SwiftUI component boundaries.

Open the standalone interactive studies in a browser:

- [Option A — Modern composer](option-a-modern-composer.html)
- [Option B — Modern instrument](option-b-modern-instrument.html)
- [Option C — Quick conversation types](option-c-quick-conversation-types.html)

All three studies include controls at the top for switching among the four
principal states: before a run, running, steering/pausing, and complete. Their
menus and primary actions are also interactive.

## Shared interaction model

Both options use the composer as the conversation's command surface instead of
placing setup, options, and transport controls in separate rows.

### Conversation setup

- A conversation-type control selects Brainstorm, Debate, Code review,
  Adversary, or a custom shape.
- The selected shape exposes a concise, visible preview of the instruction set.
  The preview can expand to reveal the complete opening instructions.
- The conversation-type menu should contain two distinct editing paths:
  **Customize for this session** changes only the message about to be sent;
  **Manage conversation types** opens Settings and changes saved templates.
- The topic or material remains the visually dominant editable content.
- The composer grows with input to a practical maximum, then scrolls internally.

### Run options

The current checkboxes and stepper become compact, legible controls in the
composer toolbar:

- `∞ Auto` means the agents decide when the conversation is complete.
- A selected cap reads, for example, `10 turns`; its menu contains Auto and a
  numeric cap.
- `G starts` or `C starts` names the opening side directly.
- The window-layout control reads `Tile` when side-by-side arrangement is on.
  Less frequently changed layout choices can live in its menu.

These controls are configuration, not primary actions, and should not compete
with Run.

### Primary action and session controls

One high-emphasis action changes with the session state:

| State | Primary action | Meaning |
| --- | --- | --- |
| Before run | Run | Start with the visible instructions and topic. |
| Running | Pause | Finish the current response, then hold it at the next handoff. |
| Pausing | Pausing… | Report that a safe-boundary pause is pending. |
| Paused | Resume | Deliver the held response and continue. |
| Steering | Send | Post the human direction; resume only when steering initiated the pause. |
| Complete | New session | Clear transient conversation state and return to setup. |

`Stop` is removed as a persistent peer of Run. A lower-frequency
**End session…** command lives in the session overflow menu. During a run it
requests cancellation at the next safe point. When cancellation completes, it
resets the session rather than merely making `isRunning` false.

The reset should clear the current topic or custom opening message, steering
draft, turn counter, participant conversation states, pause/holding flags, and
compact presentation state. It should preserve saved conversation types,
preferences such as tiling and turn-limit defaults, and the completed
transcript.

### Steering and pausing

Pause and Steer have different intent and should not be collapsed into a button
whose label tries to describe both. They do share one control flow:

1. Selecting Steer focuses the composer as a human-direction field.
2. If the run is not already paused, Errol requests a pause at the next
   handoff and says which agent is still finishing.
3. Sending the direction releases only a pause that Steer initiated.
4. If the user paused explicitly before steering, sending the note leaves the
   run paused until the user chooses Resume.

The live composer should say `Add a direction while they work…` before steering
and use precise state copy such as `Will pause after Claude finishes` rather
than a generic `Paused` label while a response is still in progress.

## Option A — Modern composer

Option A emphasizes familiarity, calm, and low visual density. It borrows the
interaction hierarchy of contemporary AI composers while keeping Errol's two
participants and relay identity visible.

The participant area is deliberately simplified into two readiness/state
panels joined by a quiet route. The composer carries almost all interaction:
the conversation type and its instruction preview sit above the topic, run
options sit along the lower edge, and the primary circular action anchors the
trailing side.

### States

| State | Participant area | Composer |
| --- | --- | --- |
| Before run | Both sides show detected surface and readiness. | Instruction preview and topic are visible; setup controls and Run are enabled. |
| Running | The active side says it is replying; the other waits. | Template detail collapses; the field invites optional direction; Pause is the sole prominent transport control. |
| Steer / pause | The finishing side remains visible. | An amber-accented steering field reports the pending safe-boundary pause; Send and Cancel replace setup tools. |
| Complete | Both sides report ended. | A short completion summary offers New session and Open transcript. |

### Strengths

- Immediately familiar to users of ChatGPT, Claude, and similar tools.
- Gives the opening prompt and conversation type clear hierarchy.
- Scales well when the panel is narrow or the instrument area is minimized.
- Keeps operational detail available without making it the first thing users
  must parse.

### Risk

If taken literally, this direction can make Errol look like a generic AI
composer. The relay's personality would have to come from motion, copy, and a
small number of distinctive route details.

## Option B — Modern instrument

Option B keeps the same composer interaction but treats Errol as a compact,
playful conversation appliance. It modernizes the active wireframe language
instead of replacing it.

The old instrument vocabulary is reduced to a few large, readable signals on a
soft warm surface. Rounded geometry and restrained color replace the dense
hairlines and equally weighted boxes of the current wireframe. The composer is
still the dominant interaction area.

### Instrument semantics

| Element | Information represented |
| --- | --- |
| Gauges | Observable activity for each side. They do not claim model confidence, agreement, or response quality. |
| Ready lamps | Whether the corresponding app and composer are relayable. |
| Think lamps | Which side is currently composing. |
| Route | The progress and direction of the current handoff. |
| Errol courier | The relay itself: carrying, holding, or delivering a response. |
| Odometer | The current response number; `00` outside a session. |
| Status copy | Exact state that the analog cues cannot express, such as a pending safe-boundary pause. |

### States

| State | Instrument behavior | Composer |
| --- | --- | --- |
| Before run | Both Ready lamps are lit, needles rest, the counter reads `00`, and the route names the opening side. | Same setup hierarchy as Option A. |
| Running | The composing side's needle rises and Think lamp illuminates; the courier and route lean toward the next handoff; the counter advances. | Template detail collapses, a direction can be started, and Pause becomes primary. |
| Steer / pause | Activity settles as the current response finishes; the route stops short of delivery and status says the handoff will hold. | The composer becomes an amber-accented human-direction field with Send and Cancel. |
| Complete | Needles return to rest, the route completes, both sides say Ended, and the counter preserves the final turn count. | Completion summary offers New session and transcript access. |

### Strengths

- Preserves the memorable personality of the current wireframe skin.
- Makes otherwise invisible relay behavior understandable at a glance.
- Uses motion and physical metaphor only for facts Errol actually observes.
- Creates a distinctive product silhouette without sacrificing the modern
  composer workflow.

### Risk

The instrument can once again become visually dominant if every state receives
its own lamp, label, or bezel. The final design should retain only information
that helps answer: Are both sides ready? Who is working? Where is the handoff?
What turn is this? Is the run paused or ending?

## Option C — Quick conversation types

Option C keeps Option A's calm participant area and composer but replaces the
conversation-type dropdown with a one-click row of frequently used shapes.

The default row contains **Free chat**, **Brainstorm**, **Debate**, and
**More**. Free chat adds no preset structure. Brainstorm and Debate apply their
instruction sets immediately. More opens the full list, including Code review,
Adversary, Interview, Custom, and the route to edit saved conversation types.

When a shape selected through More is active, its name replaces the word
`More` in the row. This keeps the current selection visible without permanently
allocating space to every possible shape.

### States

| State | Type selector | Composer |
| --- | --- | --- |
| Before run | The most common shapes are directly selectable; More reveals the remaining list. | The selected shape's instruction preview and the topic are visible. |
| Running | The shape row and instruction detail collapse. | The field invites optional direction and Pause is the prominent action. |
| Steer / pause | The selected shape remains session context but is not editable mid-run. | The composer becomes the same amber-accented steering field as Option A. |
| Complete | The selector remains collapsed. | Completion summary offers New session and transcript access. |

### Strengths

- Reduces the most common shape selection to one click.
- Makes Free chat a clear, first-class alternative to structured conversations.
- Teaches the available conversation shapes without requiring menu discovery.
- Scales to user-created shapes through More while keeping the composer calm.

### Risk

The quick row consumes more horizontal space and implies a product-level
ranking of conversation shapes. The visible set and order therefore need a
stable rule. On narrow layouts the row should wrap cleanly rather than shrink
labels or become a horizontal scroller.

## Reconciliation direction

The most promising unified direction is Option A's composer and control
hierarchy, Option C's quick type selector, and a simplified version of Option
B's instrument head.

- Preserve the warm neutral palette, restrained green/amber signals, gauges,
  route, and turn counter from Option B.
- Preserve Option A's instruction preview, compact run options, morphing
  primary action, session overflow, and completion flow.
- Use Option C's Free chat / Brainstorm / Debate / More row when the available
  width can support it; the More menu owns the complete collection and template
  management.
- Keep participant identity and readiness in the instrument; avoid duplicating
  them as a second pair of status cards.
- During a run, collapse the instruction preview but keep the composer itself
  available for steering. Compact mode should reduce the instruments, not
  remove the human's entry point.
- Let exact status copy carry edge cases. Instruments should reinforce state,
  not force a novel pictogram for every transition.

## Decisions still open

- Whether the instruction preview defaults to two lines or shows the full
  template on first use.
- Whether selecting the active conversation type opens an inline session edit
  before sending the user to Settings.
- Whether the visible quick types are fixed product defaults, user-pinnable, or
  determined by recent use; the proposal currently assumes fixed defaults.
- How a shape selected from More stays represented when the row wraps at narrow
  widths.
- How small the instrument head can become during a run while keeping the turn
  counter and active-side signal useful.
- Whether the first-speaker control remains in the composer or is selected by
  clicking an agent instrument.
- Whether End session requires confirmation during a live response, and
  whether New session preserves the previously selected conversation type.
- The exact amount of color and motion appropriate for reduced-motion and
  high-contrast appearances.

## Relationship to the current implementation

The existing controller already models most of this lifecycle: Start, a
safe-handoff Pause, a distinct holding state, and steering that owns and
conditionally releases its pause. A unified implementation will additionally
need an explicit session-reset operation and presentation that distinguishes
running, pausing, held, steering, stopping, complete, and reset states.

Because the production wireframe is being restructured concurrently, this
proposal intentionally avoids naming new source files or dictating view
ownership. It should be reconciled against the new component boundaries once
that work lands.
