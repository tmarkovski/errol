# The note stays put: the converged steering design

Status: converged proposal, September 5, 2026, built the same day, revised
twice that evening as the human tried each arrangement, and confirmed in the
running app the same night. Brainstormed through Errol itself,
between Codex and Claude, with two steering notes from the human along the
way. It answers [the-note-in-flight.md](the-note-in-flight.md). The body below
is the proposal as converged; [the revisions at the end](#the-revisions-as-built)
are what the code does now, and where they disagree with the body the last one wins.

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

## The revisions, as built

The proposal above was built as written, and the first thing the human saw
was two amber circles in the foot: the inline arrow beside the field and the
primary circle next to it. The arrow went the same hour. The second sitting
replaced the rest of the chrome with a smaller rule — typing holds the run,
Return queues, the button is Queue while there is text to queue and Pause or
Resume otherwise — and that was built and tried too. It did not survive the
trying either: a field that is always open makes every keystroke an act on
the run, and the button changing meaning under the typing hand was one more
thing to read. The third sitting turned the field the other way round, and
that is what the code does now:

**The field is closed while the agents work. Pause to steer opens it and
holds the run. Return sends the note and closes it again. The head says
where the note is.**

The states, in the order a run meets them:

- *Relaying.* The field is closed to typing, and the one filled circle stands
  in the middle of it as a capsule reading Pause to steer. The foot's corner,
  where the circle lives before and after a run, is empty. The turn line says
  "Turn 4 · Claude is replying".
- *Steering.* The press requests the hold (the engine's pause flag; the run
  keeps going until the next handoff, and the turn line says "Will pause after
  Claude finishes" and then "Paused at the handoff"), the circle springs down
  to the foot's corner — one view moving through a shared geometry space,
  not one leaving and another arriving — and the field opens with the
  keyboard already in it. It lands as a capsule reading Continue while the
  field is empty — a bare play glyph there did not say whether it went on
  with nothing or was waiting for words — and closes to the arrow circle
  once there are words. Under the turn line: "Steering · write a note, or
  continue", then "Writing a note for Claude".
- *Queued.* Return, or the arrow, sends: the mailbox takes the trimmed note,
  the field closes with the text still in it under a blur, the circle springs
  back to the middle reading Pause to edit, and the hold lifts. The run goes
  on; the note rides the next handoff. Under the turn line: "Note queued ·
  goes to Claude with the next handoff". At the foot, Clear note.
- *Editing.* Pause to edit takes the note back off the mailbox and puts the
  hold on in one locked step (`claimSteering`) — the same claim the earlier
  arrangements used for typing into a queued note — and opens the field with
  the text in it. Sending again queues the new text; if the claim lost to the
  worker's commit, the committed event says so and the field opens empty.
- *Sent.* When the courier takes the note the blurred text clears, and the
  head carries the story: "Sending note to Claude…", then the receipt as
  before — "Note sent to Claude with turn 5 · shared with ChatGPT at turn 6",
  "Note not sent · never reached Claude" — with the text in the tooltip and
  a popover, until the next note or New session.

Dropping a note has two routes, both explicit. In the open field Esc empties
it, and a second Esc on the empty field closes it and continues without a
note, so Esc twice drops a note whether it was queued before or not; Continue
on an empty field does the same. While a note is queued, Clear note at the foot
takes it off the mailbox without opening the field. Nothing is dropped by a
keystroke that meant something else.

What changed from the second arrangement, and why:

- Writing no longer acts on the run; opening the field does. The hold has one
  request — the press — so the turn line and the pill never have to explain a
  hold nobody asked for, and a half-typed thought cannot stall the relay
  because the human was deciding whether to say it. The cost the first
  proposal worried about, an action to learn before the note can be written,
  is paid by a button that says what it does in the place the note goes.
- The circle has one place per state instead of one meaning per keystroke.
  It stands in the field while the field is closed and in the corner while
  it is open, and moves between the two; it changes only in the corner,
  Continue to the send arrow, as words arrive. A separate Cancel was
  considered and left out: with an empty field Continue is the cancel, and
  once there are words a Cancel would discard them on a click, which Esc
  twice does deliberately.
- Sending continues the run. The second arrangement kept a pressed pause
  through Queue so that a note could wait for the human's Resume; here there
  is no pause apart from steering, so there is nothing to keep, and the
  note's send is the run's go. A human who wants to hold the run without a
  note holds the field open.
- The queued note is shown, not held in the field. It sits blurred behind the
  circle: readable enough to know it is there, plainly not for editing, and
  gone when the courier takes it. The amber wash is gone with it.
- Esc means less. It empties, then closes; it never withdraws a queued note
  by itself, since a queued note is not in the open field until Pause to
  edit brings it back — and then Esc twice drops it, as it drops anything.

What the arrangement keeps from the proposal: the contract (next handoff
first, recipient secondary, echo one handoff later), the one-slot mailbox and
the single locked handoff decision, the send outcome and the receipts that
never assume, the whole-or-not-at-all rule for steering sections, and the
head's reserved line under the turn line.

Checked in the running app on September 5: the circle's spring between the
field and the corner, the Continue capsule closing to the arrow as words
arrive, the blurred note against the well, and the empty corner while the
run relays. The human's verdict was that this is the one. Not yet looked at:
the popover from the non-activating panel.
