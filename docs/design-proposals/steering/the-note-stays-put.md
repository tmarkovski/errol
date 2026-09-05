# The note stays put: the converged steering design

Status: converged proposal, September 5, 2026, built the same day and revised
the same evening after the human tried it. Brainstormed through Errol itself,
between Codex and Claude, with two steering notes from the human along the
way. It answers [the-note-in-flight.md](the-note-in-flight.md). The body below
is the proposal as converged; [the revision at the end](#the-revision-as-built)
is what the code does now, and where the two disagree the revision wins.

## The rule

**Write freely. Queue to let it go. Edit & pause to revise a commitment. Send
to release that editing hold, or Resume without sending to keep the revision
as a draft.**

Three things that are fused today come apart: writing a note, committing it,
and holding the run. Writing never touches the run. Queueing a fresh draft
never touches the run. Sending a revision releases the editing hold it was
written under, and nothing else. The run holds only when the human presses
Pause, or presses Edit & pause to revise a note they have already committed,
because that is the one case where a passing handoff does real harm.

## The contract

The composer steers the conversation at the next available handoff. A handoff
is the only place the relay can stop: after a reply has been captured, before
it is delivered. A queued note rides whichever handoff comes first, and its
first recipient is whoever is about to reply. The stable fact is "next
handoff"; the recipient is secondary information, named once the note is
queued, never predicted while it is being written.

Someone who needs a note to land at a specific handoff, addressed to a
specific side, pauses the run first. Every delivered note is echoed to the
other side with the following handoff, so a note that misses its intended
handoff delays the addressee's copy by one turn rather than losing it, but
only if that following handoff succeeds. A turn cap, a sign-off, or a failure
can prevent the echo, and the receipt says so.

## What changes from today

- Typing into the run-time composer no longer requests a pause. The
  steer-owned pause and its bookkeeping (`steerInitiatedPause`) go away. A
  hold created by Edit & pause takes its place. Send and Withdraw release only
  that editing hold, never a pause the human pressed. Resume without sending
  clears every hold, the editing hold and a pressed pause alike, and leaves
  the revision as a draft: it is the human pressing Resume, and Resume
  resumes.
- The note's text stays in the field from the first keystroke until delivery
  is confirmed. Only the chrome around it changes: the row above the hairline,
  the inline control at the field's trailing edge, the field's wash, and the
  foot.
- The primary circle stays Pause or Resume for the whole run, and it is the
  card's only button. Send moves to Return alone; the field's trailing edge
  carries only the Queued badge, an indicator.
- One note at a time. While a note is queued there is no second field and no
  second submission; Edit & pause is the way to change it, Withdraw the way to
  drop it.
- Delivery gets a receipt that records confirmation, not merely that a send
  was attempted, and the transcript gets the delivery outcome appended after
  the note it already records.

## The states

The row above the hairline is one line; the card keeps its height in every
state, which is why every line below is short. Where a state names two
facts, the second follows a middle dot on the same line. The row's status
describes the note; whether the run itself is running, pausing, held, or over
is the pill's and the turn line's to say, and the two never restate each
other.

| State | The field | The row above the hairline | Inline control | Primary circle | The run |
|---|---|---|---|---|---|
| Empty | Placeholder "Add a direction while they work…" | The context line: shape · options | None | Pause, or Resume if the human has paused | Unaffected |
| Draft | The text, plain | Muted: "Return queues it for the next handoff" | None | Unchanged | Unaffected. Return queues; Esc clears the draft. |
| Queued | Same text, quiet amber wash, selectable, not editable | Amber: "Queued · relay continues · ChatGPT receives it first", with Edit & pause and Withdraw as quiet text actions | Check badge reading Queued | Unchanged | Unaffected; the mailbox holds the note. If the human has paused: "Queued · pausing at the next handoff", then "Queued · sends when you resume" once the loop parks. |
| Editing | The text, plain again | Amber: "Holding the next handoff while you edit · Return sends it" (before the loop parks, "Will hold…") | None | Resume, labeled "Resume without sending" in the foot's hint slot, which is also its accessible name | Mailbox claimed and hold requested in one step. Pill Pausing then Paused; turn line "Will pause after Claude finishes" then "Paused at the handoff". Send re-queues and releases the editing hold. Withdraw clears and releases it. Neither touches a pause the human pressed. Resume without sending clears every hold and leaves the text as a draft. Esc leaves text focus and changes nothing. |
| Sending | Same text, read-only, amber wash | Amber: "Sending to ChatGPT…" | None | Unchanged | The courier has committed the handoff; a few seconds. |
| Sent | Clears, ready for the next note | Back to the context line | None | Unchanged | Foot, muted: "Sent to ChatGPT with turn 5", growing "· shared with Claude at turn 6" when that echo is itself confirmed, or "· not shared with Claude" when the run ends before the echo's handoff. |
| Unconfirmed | Keeps the text, read-only | Amber: "Delivery unconfirmed · check ChatGPT", with Dismiss and Edit as draft | None | Unchanged, or over if the send ended the run | The note is not eligible for resending until the human chooses Edit as draft and queues it again. |
| Not sent | Keeps the text, read-only | Red: "Not sent · never reached ChatGPT" | None | Run over | When the relay never attempted the submission, or the run ended with the note still queued, or the note could not fit the payload (see below). |

A keystroke into a queued field does not edit it and does not vanish either:
it draws the eye to Edit & pause, the way a locked field in the system's own
dialogs answers. When the run ends, a queued note keeps its text and becomes
Not sent; a draft keeps its text and its row reads "Draft · the run ended
before it was queued". Neither row may go on saying "relay continues" once
the relay has stopped. The last receipt and any unresolved note survive the
run's end until New session, since ending is exactly when someone inspects
what happened. The receipt's tooltip is the quick peek; click or keyboard
activation opens the full note in a popover.

The one-line fit is a layout target, not yet a verified fact: the queued row
carries the longest status and two actions. The actions are laid out first
and must survive at the panel's real width; the status text truncates with a
tail ellipsis before either action shrinks, and the recipient clause is the
first thing to go, surviving in the row's tooltip.

## Who wins a handoff

The worker and the panel both act on the mailbox, and the rule is that
exactly one of them owns each handoff, decided under one lock.

- The worker decides "hold, cancel, or commit this handoff" in a single
  locked operation that reads the pause and cancel flags and, when it
  commits, takes the note in the same step. Today the loop checks Pause and
  then separately takes the note, which leaves a gap in which a claim can win
  the mailbox and still lose the handoff; that gap closes.
- Edit & pause claims the queued note and requests the hold in one locked
  step. If the claim wins, that handoff waits. If the worker has already
  committed, the row shows Sending and editing does not begin; the committed
  text is not turned into a new draft, so the same intervention cannot be
  submitted twice by accident.
- Withdraw that loses the race likewise shows Sending, and the note goes.

## The framing sent to the agents

Both framing functions change, and the sentence claiming a pause leaves both.
The section title stays "Steering note from the human" so each side keeps
pattern-matching it.

On delivery:

> The human submitted this steering note for the conversation. It is
> included with this handoff and may concern earlier context. Claude has not
> yet received this note through the relay.

On the echo, one handoff later:

> This note was included in the input sent to ChatGPT before the reply below.

## Engine changes

- `RelayControl`: the mailbox keeps one slot. It grows a locked handoff
  decision for the worker (hold, cancel, or commit-with-note) and a
  `claimSteering(holding:)` for the panel that empties the slot and sets the
  pause flag together; `postSteering` stays a set, never an append.
- `send` returns an outcome instead of a Bool: confirmed, unconfirmed,
  abandoned (the foreground was lost during confirmation, after a submission
  may have been attempted), and refused (the foreground could not be taken
  before typing). Confirmed means both that the paste was verified in the
  composer (as text or as an attachment) and that a submission signal was
  observed. An unverified paste can never become confirmed, whatever the
  composer does afterwards, and `confirmSend`'s current path that returns
  true when neither observation signal exists becomes unconfirmed. The loop
  still ends on refused and abandoned; the receipt maps confirmed to Sent,
  unconfirmed and abandoned to Unconfirmed, refused to Not sent.
- Steering sections must arrive whole. Today `truncatedForRelay` keeps the
  beginning of the assembled payload, and the note is appended after the
  reply, so a long reply can cut some or all of the note before a send that
  then confirms. The reply is truncated to the room left after the framing
  and the steering sections, never the other way around; if a note cannot
  fit at all, it stays in the mailbox and is reported Not sent rather than
  being trimmed. The same holds for the echo. A note's receipt is never
  issued on the strength of the containing message alone.
- Relay events grow a committed event, posted when the worker takes the note
  and before the paste, and a delivered event carrying the outcome, the turn,
  and the recipient. The echo posts its own delivered event, so "shared with
  Claude" is never assumed, and a run that ends before the echo's handoff
  posts "not shared" even though no send was attempted.
- The transcript keeps writing the note before the send and appends one line
  after it with the outcome, so the permanent record never implies an
  attempted handoff succeeded.

## Held back on purpose

- A halo on the courier bead while it carries a note. Not new information,
  and the row has to prove the copy first.
- "Use original" during a revision. Esc must not restore and re-queue
  wording the human just decided to change; a deliberate action could offer
  it later.
- Choosing a recipient. The contract steers the conversation, not a side;
  Pause is the addressed-intervention path for now.
- A second line in the row. The card's constant height is a standing rule,
  so the copy stays short instead.

## The revision, as built

The proposal above was built as written, and the first thing the human saw
was two amber circles in the foot: the inline arrow beside the field and the
primary circle next to it. The arrow went the same hour. The second sitting,
with the panel in hand, replaced the rest of the chrome with a smaller rule,
which is what the code does now:

**Typing holds the run. Return queues and lets it go. The button is Queue
while there is text to queue, Pause or Resume otherwise. The head says where
the note is.**

What changed, and why:

- Writing a note requests the hold, not a separate Edit & pause action. The
  proposal kept writing inert so that an abandoned draft could not stall the
  run; in use, the cost was a field that read as text but refused keystrokes
  once queued, and an action to learn before the note could be changed. Now
  text that is not queued holds the next handoff, so the note lands where the
  human meant it to, and Esc lifts the hold with the text. The stall the
  proposal worried about is announced on the turn line ("Will pause after
  Claude finishes") and under it ("Note in progress · Return queues it · Esc
  clears it"), which is the panel telling the human what they started.
- Draft and Editing are one state. Typing into a queued note takes it back
  off the mailbox and puts the hold on, in the same locked step Edit & pause
  used (`claimSteering`). Withdraw is Esc. Edit as draft and Dismiss are gone
  with the read-only phases they served.
- The primary circle morphs instead of staying Pause. While the field holds
  text that is not queued it is Queue — the circle grows into a capsule, the
  arrow where the glyph was and the word after it, the way the option chips
  grow their labels — because a note being written already holds the run, so
  Pause would add nothing. Once the note is queued and unchanged it goes back to Pause; a
  queued note can wait a long time for its handoff, and the human keeps the
  safety action through it. It is Resume only while the human's own pause is
  on. It is never disabled.
- Queue while the human has paused leaves the pause on: the circle turns to
  Resume and the head says "Note queued · sends when you resume". An explicit
  pause is not overridden by a keystroke. Esc likewise lifts only the note's
  hold, never a pressed pause.
- The note's status leaves the composer. The row above the hairline is the
  context line for the whole run, the Queued badge is gone, and the field
  shows only the text, under the wash while the mailbox holds it. A line
  under the head's turn line, reserved for the whole run so the composer
  never moves when a note starts, says where the note is — "Note in progress
  …", "Note queued · goes to Claude with the next handoff", "Sending note to
  Claude…" — and then what became of it, as the receipt did: "Note sent to
  Claude with turn 5 · shared with ChatGPT at turn 6", "Note not sent · never
  reached Claude", with the text in the tooltip and a popover. The record
  stays until the next note or New session. The foot keeps a one-line hint
  about the keys.
- The field lets go of a note when the courier takes it: the text clears at
  the committed event, and the head carries the story from there. A note
  reported straight off the mailbox — too long to travel whole, or the run
  ended with it queued — clears the same way, with the text kept in the
  record's popover. Nothing in the field is ever read-only.
- The race the proposal drew stays closed and gets smaller. If a keystroke
  lands in the instant after the worker commits the note, the claim loses,
  the committed note goes out as it was, and the text in the field — the
  old note plus the keystroke — is simply a new note, holding the next
  handoff as any draft does. Both steering events now carry the note's text,
  so the record is made from what travelled, never from what the field
  happens to hold when the outcome lands.

What the revision keeps from the proposal: the contract (next handoff first,
recipient secondary, echo one handoff later), the one-slot mailbox and the
single locked handoff decision, the send outcome and the receipts that never
assume, and the whole-or-not-at-all rule for steering sections.

Still to check in the running app: the reserved line under the turn line
during a run with nothing to say, the queued line's length at the panel's
width with both app names in it, the wash against the well, and the popover
from the non-activating panel.
