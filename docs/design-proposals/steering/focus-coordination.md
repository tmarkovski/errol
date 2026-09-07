# Protecting steering from relay focus changes

September 6, 2026. Agreed design following Codex's proposal and Claude's review.
The implementation is now in place; its validation is recorded at the end.

Keep the existing serial relay worker. Add focus-operation ownership to
`RelayControl`, under the same lock as pause, cancellation, and the steering
mailbox. Gate response capture and message delivery separately. An open
steering editor holds both gates until the human sends the note or continues
without one.

**During a run, the worker touches focus only inside an operation, an operation
starts only through a gate, and the steering field opens only outside one.**
Automatic focus restoration at run end has a separate, immediate skip rule.

## Why the existing pause interrupts typing

In [Relay.swift](../../../app/Errol/Errol/Core/Relay.swift), `runRelay` waits for
a response, calls `copyLastResponse`, and only then calls `decideHandoff`.
The pause therefore holds delivery but does not hold copying. In
[RelayActions.swift](../../../app/Errol/Errol/Core/RelayActions.swift), copying
activates the source app because its copy handler can otherwise fail to write
the clipboard. Activation also schedules Errol's panel deactivation on the
main queue. A user can already be writing when that happens.

The worker in [RelayEngine.swift](../../../app/Errol/Errol/RelayEngine.swift)
already preserves execution order. The missing mechanism is permission to
start the next operation, not another queue or a keystroke-idle timer.

## Scope and interaction

Protect the entire steering session in Errol, including time spent thinking,
selecting text, pasting, or composing with an input method. Opening the field
requests the hold; closing it releases the hold. A quiet keyboard or a change
of first responder does not release it. Preserve the current Return,
Shift-Return, Continue, Clear note, and two-stage Escape behavior described in
[the built steering design](the-note-stays-put.md#the-revisions-as-built).

This version does not detect typing in arbitrary other applications. It does
not change message capture to Accessibility text extraction, whose fidelity
would need separate investigation, especially for code blocks.

| Situation | Editor and controls | Relay behavior |
| --- | --- | --- |
| Relaying | Field closed; Pause to steer, or Pause to edit for a queued note. | Normal response detection and handoffs. |
| Pause requested with no operation active | Open the field and focus it immediately. | The current agent may finish generating; the next capture or delivery waits. |
| Pause requested during an operation | Field stays closed. Keep the circle in the field, dimmed, reading “Pausing…”. Turn line: “Finishing the handoff”. Repeated presses do nothing; Stop remains available. | Finish the current operation to a safe outcome. The request blocks the next operation. |
| Steering granted | Field open with the existing Continue or send control. | Read-only response detection may continue. No focus or clipboard operation starts. |
| Reply detected while steering | Keep the field open. Turn line: “Paused at the handoff”. | Capture waits; do not claim the reply text is already captured. |
| Send or Continue | Close the field, preserving the existing queued-note presentation. | Queue the note, if any, before releasing the hold. Continue in the existing order. |
| Stop or run completion | Cancel any pending editor opening; use the existing terminal note accounting. | No new operation or delayed editor grant starts. |

Pending steering and granted steering are distinct controller states; both
count as a hold request. “Will pause after Claude finishes” must not describe
an operation already copying or sending a finished reply.

Update the `ConversationStatus.replied` comment in `Relay.swift` (currently
line 224) and review the hold log and its accompanying comment (around line
389): the capture gate has detected a reply, while the delivery gate has
captured it. The perch says “Reply ready”; the turn line and steering line
keep their separate purposes rather than repeating that status.

## Two operation boundaries

The serial sequence is:

1. Wait for the source response using read-only detection.
2. Pass the capture gate, which checks cancel and hold and marks an operation
   active in one locked step. It never reads or consumes the steering mailbox.
3. Copy the reply, including activation, copy-button expansion, clipboard
   observation, and bounded retries. Resolve failure or terminal reply
   conditions before granting a pending editor request.
4. End the capture operation. A pending editor request now wins over delivery.
5. Prepare framing, then pass `decideHandoff`. In one locked step it checks
   cancel and hold, takes the note if applicable, and marks delivery active.
   Preserve its whole-note fit check and its `unfit` result.
6. Deliver, including clipboard writes, activation, paste verification,
   submission, and confirmation. Record the actual outcome, then end the
   operation. A pending editor request can now open while the recipient replies.

The opening message also uses the delivery ownership gate, before any
clipboard write. It does not consume a steering note or reinterpret one as
part of the opener. A note written during startup stays queued for the first
ordinary handoff.

Do not combine capture and delivery. A pause during capture must let the user
steer the handoff about to happen. Do not commit the note at the capture gate:
an empty reply, mutual sign-off, capture failure, or turn cap may end the run
before delivery is appropriate.

The gates park the existing worker; they do not enqueue speculative future
turns or retain Accessibility elements to replay later. Resolve the relevant
controls when the operation executes. User-directed changes to either chat
while a run is held are outside this version's isolation guarantee.

## Ownership in RelayControl

Keep the synchronization in [Logging.swift](../../../app/Errol/Errol/Core/Logging.swift)'s
`RelayControl`. Add the active operation and pending editor request to its
state. Do not create another coordinator with an independently acquired lock.
Never hold the control lock across Accessibility calls, sleeps, main-queue
work, or UI event delivery.

The following is an API sketch, not implementation-ready Swift:

```swift
enum HoldGrant { case now, afterOperation, cancelled }
enum OperationDecision { case proceed, hold, cancel }
enum OperationKind { case capture, delivery }

func requestHold() -> HoldGrant
func claimSteering() -> (note: String?, grant: HoldGrant)
func beginOperation(_ kind: OperationKind) -> OperationDecision
func decideHandoff(carries: (String) -> Bool) -> HandoffDecision
func endOperation(continuingRun: Bool) -> Bool // true means post field-may-open
func finishSteering(note: String?)
func cancel()
```

- Both operation gates give cancellation precedence over hold. A successful
  gate marks the operation active before unlocking. No second operation can
  begin while one is active.
- `requestHold` rejects a cancelled or finished run; otherwise it sets the hold
  immediately. It grants the editor now only when no operation is active;
  otherwise it records a pending request.
- `claimSteering` takes an available note and requests the hold together. A
  lost claim still requests a hold for a new note, matching the controller's
  current overall behavior. If delivery already committed the old note, that
  delivery finishes and the editor then opens empty.
- `finishSteering` publishes the optional note and releases the hold together.
  Call it only after the editor has synchronously stopped accepting input and
  any required text composition has completed. A SwiftUI state assignment
  alone must not leave an editable text view alive while delivery starts.
- `endOperation` releases ownership only after completion fencing described
  below. A pending request is granted only if the run continues and has not
  been cancelled. It retains the hold when granting, so the worker cannot
  start the next operation before the main thread opens the field.
- Deliver the field-may-open event through the existing event bus. The
  controller accepts it only while its pending flag is set and the run is
  active. Stop clears that flag synchronously on the main thread before any
  later grant can be handled. Every run event precedes its finished event,
  and a new run cannot start until the finished event is handled. Preserve
  those ordering rules: the pending flag makes stale grants inert without
  adding request IDs or a generation counter.
- `cancel` sets cancellation and invalidates pending grants in one locked
  step. Do not clear pause and then set cancellation in separate calls: the
  worker could pass a gate between them. Cancellation need not clear pause,
  because both gates check cancellation first.

Use guaranteed cleanup for every acquired operation, including failure and
cancellation returns. When capture discovers a terminal reply or delivery
ends the run, mark the run finished in control state and invalidate the pending
request before releasing ownership. Reject fresh requests too, even if the UI
has not received the finished event. Do not briefly open the field and then
close it on that event.

Keep the existing short polling approach for held gates, approximately 200 ms.
Stop is observed on a subsequent poll; it does not require a new condition
variable or scheduler. Waiting on a user hold must not consume an operation's
activation or clipboard timeout.

## Completing an operation safely

A steering request does not interrupt an operation halfway through paste or
its activation retry. Keep the editor closed until the operation has reached
an observed outcome and stopped issuing side effects. This does not require
every operation to succeed, and it does not authorize unsafe keystrokes after
focus is lost. Preserve refusal, abandonment, and unconfirmed outcomes. Do
not replay an entire uncertain delivery on resumption.

Stop prevents subsequent operations immediately in control state. An operation
already in progress follows its existing safe cancellation and outcome paths;
it may already have submitted. Do not promise that Stop retracts a message or
that ownership requires submitting regardless of cancellation or lost focus.

Main-queue ordering needs an explicit completion fence. The asynchronous
deactivation in `resignOurOwnKeyStatus` can still be queued when the worker
finishes. Posting a field-may-open event after it protects a pending grant,
but does not protect a fresh request that sees the operation as already idle.
Keep the operation active until the live worker makes a synchronous hop to the
main queue (`DispatchQueue.main.sync`) at operation end, after its queued focus
callbacks. That step calls `endOperation` to release ownership and settle any
grant. The worker waits for this step before attempting its next gate. A
fire-and-forget release must not arrive late and clear the next operation's
ownership; waiting avoids needing a generation counter to distinguish them.
Do not hold the control lock while making the hop. The main thread must never
wait for the worker at all, with or without that lock, or the hop deadlocks.

All forced-activation retries remain inside the operation. No Errol callback
from that operation may still deactivate the panel after its completion fence.
External activation effects are a remaining boundary: a LaunchServices request
may take effect after an activation timeout. The fence orders Errol's own work;
it cannot guarantee cancellation of operating-system work already requested.
Check this behavior in live validation and document any observed residual.

The waits inside copy and send have deadlines, but their retries can accumulate
and external calls are not a proven hard latency bound. Measure the pending
state in live use; do not promise a fixed maximum or a subsecond pause.

## End-of-run focus and adjacent paths

Do not enqueue restoration for later. At run end, skip `refocus(to: origin)`
when Errol's panel is key or a steering request/session still owns the hold,
as well as when the origin is already in front. Inspect AppKit key-window
state on the main thread. Make this decision before terminal cleanup clears
the editing state. Restoration is optional and must not reopen a race by
saving an action to perform after the user finishes writing.

Tiling is already serialized on the same worker and disabled during a run;
it is not another runnable operation to add here. Readiness scanning is parked
during a run, and the veils cannot become key. Preserve those restrictions.
Any future focus-changing work allowed during steering must join this ownership
contract rather than call the activation helpers independently.

## Validation for implementation

Add control-state tests beside the existing `decideHandoff` and `claimSteering`
tests in [RelayFramingTests.swift](../../../tests/ErrolKitTests/RelayFramingTests.swift):

- An idle hold grants immediately and blocks both gates without taking a note.
- Requests during capture and delivery grant only at operation completion.
  Capture preserves the mailbox; only delivery commits it.
- A hold that wins the capture-to-delivery race keeps the note on that handoff;
  a claim that loses to delivery opens empty after it.
- Cancel wins over hold, takes no pending note, and cannot admit a new operation
  through a transient unpaused state. Stale grants cannot reopen the editor.
- Copy failure, terminal replies, turn caps, refused delivery, and every early
  return release ownership without granting an editor on a finished run.
- A queued deactivation followed by a fresh hold request cannot receive an
  immediate grant until the main-queue completion fence has run.
- Sending a note stops editor input before releasing the hold; startup delivery
  leaves that note for the first ordinary handoff.

Extend `PerchPreviewEngine` to play pending-during-copy and pending-during-send,
then verify the circle, wording, focus transfer, and Stop behavior in the panel.
Live-check sustained typing through response completion, long pauses between
keys, paste and input-method composition, activation retries, and run-end focus.
Passing control tests alone does not establish that macOS focus behaves as
intended.

## Implementation and validation

Implemented with capture and delivery ownership in `RelayControl`, a synchronous
main-queue completion fence in the live engine, and a pending steering state in
the controller and panel. The opener is gated without consuming the note.
Terminal paths close ownership and reject further editor grants; run-end focus
restoration respects the panel and any remaining steering hold.

`TextEditorSession` stops native input before releasing the hold. It restores a
reused editor on reopening and disables any view it replaces, so SwiftUI's
closing animation cannot leave an editable view behind. Return and Escape defer
to an active input-method composition. The preview engine has scenarios for a
pause during capture and during delivery.

Verification completed:

- `swift test`: 111 tests, 2 opt-in live tests skipped, no failures. New tests
  cover competing hold/capture requests, mailbox ownership, cancellation,
  terminal paths, startup delivery, and the main-queue completion fence.
- Debug app build with `xcodebuild`: passed.
- An isolated AppKit/controller harness using a fake relay: passed pending and
  immediate grants, both gates during typing, synchronous editor shutdown,
  close/reopen reuse, input-method composition, two-stage Escape, and a stale
  grant after Stop. It sent no messages to agent apps.

The real copy/send cycle against the agent apps, including delayed operating-
system activation effects, has not been exercised for this change. The isolated
harness establishes editor behavior, not end-to-end focus behavior or visual
acceptance of the panel.
