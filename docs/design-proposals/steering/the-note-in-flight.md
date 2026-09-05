# The note in flight: what steering does today, and where the panel goes quiet

Status: problem framing, September 5, 2026. Written before any redesign, from a
reading of `RelayController.swift`, `Core/Relay.swift`, `Core/Logging.swift`,
and `Perch/PerchComposer.swift`. It describes what a steering note does today,
where the panel goes quiet, and what the redesign has to deliver.

## How a steering note lives today

A note passes through four phases, and the panel shows only two of them.

1. **Idle in a run.** The composer offers "Add a direction while they work…",
   the foot says "Type a note and we'll pause so you can finish it", and the
   primary circle is Pause. The title pill reads Running.

2. **Drafting.** The first non-blank keystroke does two things at once in
   `RelayController.setSteeringText`: it marks a steer as in progress, and it
   requests a pause, remembering that the steer owns that pause. The panel
   shows this phase well. The context row becomes the amber hold notice, the
   foot says "Esc clears the note", the circle becomes Send, the pill says
   Pausing, and the turn line says "Will pause after Claude finishes". If
   Claude finishes before the note is sent, the loop parks at the handoff, the
   pill turns to Paused, and the notice changes to "Paused. Your note will go
   to ChatGPT when you resume."

3. **Posted, waiting for the handoff.** Return or the circle calls
   `sendSteering`, which drops the note into a one-slot mailbox on
   `RelayControl`, empties the editor, ends the steer, and releases the pause
   if the steer had asked for it. Every visible thing then reverts to phase 1.
   The only trace is a log line, and the log lives in the debug window behind
   the owl's right-click menu, not on the panel. If the speaker is still
   replying, the note waits in the mailbox with no sign of it anywhere. If the
   run was holding, it resumes at once and the note goes out.

4. **Delivered.** At the handoff the loop takes the note out of the mailbox,
   appends it after the reply, and frames it for the reader as "The human
   paused the relay and wrote this note after Claude's message above." One
   turn later it is echoed to the other side. Nothing on the panel marks
   either moment.

## The gaps

- **A posted note is invisible.** Phase 3 is pixel-identical to phase 1, so
  after pressing Return the user cannot tell whether the note was taken,
  dropped, or is waiting. Even when the run stays held after a send, because
  the user paused it by hand first, the Resume button says nothing about the
  note it will carry.

- **Drafting and pausing are one gesture.** There is no way to write a note
  without requesting a hold, and the foot copy promises the hold. The two
  intents "hold the run for me" and "slip this in at the next handoff, don't
  wait" have no separate expression, and a third intent, "I'm thinking out
  loud and haven't decided to send", has none at all.

- **The requested pause is speculative, and the panel cannot say which way it
  will go.** If the note is sent before the speaker finishes, the pause is
  released and never happened; the pill goes Running, Pausing, Running with
  nothing having paused. If the speaker finishes first, the run stops and
  waits on the user. Both look like the same Pausing state until one of them
  happens.

- **A posted note cannot be reviewed, edited, or withdrawn.** The editor is
  emptied on send. Typing again starts a fresh steer, and sending that
  silently overwrites the first note, because `postSteering` assigns to a
  single slot rather than appending to a queue.

- **Delivery has no receipt.** The user never sees "went to ChatGPT with turn
  4", and cannot distinguish "not yet" from "already gone" without opening
  the log.

- **The framing sent to the agents asserts a pause.** If drafting stops
  pausing, that sentence in `steeringNoteSection` becomes untrue and has to
  change with the design.

## What the redesign has to deliver

1. A visible, persistent sign that a note is queued and will be appended at
   the next handoff, from the moment it is posted until the moment it goes
   out.
2. A clear answer, at every moment, to "will the run stop for me?" Yes while
   the note is still being typed or edited, no once it has been sent.
3. Possibly, room to draft without committing: type something, keep it, and
   decide later whether it goes out, without the run reacting to keystrokes.
   The hypothesis is that this is common; the current design assumes it never
   happens.

One term to pin down: "appended at the next run" is read here as the next
handoff, the next time the relay carries a reply across, since "run"
elsewhere in the app means a whole session.

## Tensions the brainstorm has to resolve

- If typing stops pausing, a note written while Claude finishes can miss the
  handoff it was meant for and land a turn late, framed as a reply to
  something it was not. That is exactly what the pause prevents today.
- The mailbox is read only at the handoff boundary, so edit and withdraw
  until then are cheap to build; the question is purely how the panel shows a
  posted note as still the user's.
- Where the queued note lives on the panel: in the composer as a card above
  the editor, on the flight path as something the bead will carry, or in the
  head's turn line.
- Whether two notes in one turn should queue, merge, or replace with a
  warning.
