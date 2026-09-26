# An image open over Claude's conversation stopped the run

Findings from the run on Sep 24 2026 that ended on "Couldn't copy Claude's
reply", confirmed by a live capture on Sep 25 2026, and fixed on Sep 26
2026.

**Short version.** Claude's image viewer does more than cover the
conversation visually. While it is open, the conversation is gone from the
accessibility tree: the copy buttons, the "Message N" groups, the Stop
button and the composer all disappear. Errol read that as "the reply
finished", found no copy button, retried once, and stopped. The situation
can be detected: a dialog appears in the window while the composer is gone.
Errol now treats it as a recoverable hold and shows the same full-console
alert as "Please focus Claude", asking for the viewer to be closed. It
continues once the viewer is closed.

## What the log shows

From `~/Library/Logs/Errol/errol-run-2026-09-24T19-28-01Z.log`, turn 2,
waiting on Claude (a Claude Code session, `/epitaxy/local_83b5…`):

```
19:43:52.113Z  Claude: waiting for response (baseline 2 message affordances)...
19:43:52.304Z    · response watch +0s: affordances 2, message 5, streaming true
   … affordances flicker 2↔3 as the virtualized list re-renders …
19:45:19.261Z    · response watch +87s: affordances 2, message 5, streaming true
19:49:47.458Z    · response watch +355s: affordances 0, message -, streaming false
19:49:48.697Z  Claude: response complete (0 message affordances)
19:49:48.765Z  Claude: no copy button found
19:49:48.765Z  Claude: retrying the copy after forcing activation
19:49:49.257Z  Claude: no copy button found
19:49:49.258Z  Stopping: could not copy response from Claude after a retry.
```

Three things changed in the same poll: the affordance count fell to 0, the
newest message's ordinal disappeared, and the Stop button went away. A reply
finishing never does all three at once. Virtualization unmounts older
messages but keeps the newest one mounted, and it never removes the Stop
button. That poll is when the image viewer opened.

The copy button you could see through the viewer's translucent backdrop was
not in the tree Errol reads. The press didn't fail. `copyButtons` returned
nothing, so no press was ever made
([`pressCopyButton`](../../app/Errol/Errol/Core/RelayActions.swift#L67)).

The retry couldn't help, because it fixes a different problem. It forces a
LaunchServices activation for the case where Claude isn't in front
([`copyLastResponse`](../../app/Errol/Errol/Core/RelayActions.swift#L37)).
Claude was in front the whole time. So when the copy failed, the branch
after the copy found the window present (`destinationGuard` → `.clear`) and
the app frontmost, and took the only remaining exit: `.copyFailed`.

## A second problem in the same log: the reply probably wasn't finished

The response watch only logs a line when the reading changes
([`waitForResponse`](../../app/Errol/Errol/Core/RelayActions.swift#L1010)).
So every poll from +87s to +355s read exactly `affordances 2, message 5,
streaming true`, which means Claude's Stop button was still showing until the
viewer opened. Unless Claude finished within one 1.2-second poll of the
click, **Claude was still replying when the image was opened**.

The viewer hid the Stop button along with everything else, and that looked
like the streaming transition.
[`responseArrived`](../../app/Errol/Errol/Core/RelayActions.swift#L883)
returns true on `sawStreaming` once streaming reads false. Two such polls
completed the wait: "response complete (0 message affordances)".

In this run that ended in the copy failure. If the viewer had been closed a
second later, `captureGuard` would have seen Stop again and held on
`.replying`. That line reads "Claude is replying to something else", which is
the wrong message, but the hold is safe, and the finished reply would have
been copied afterwards. So the early completion wouldn't have relayed a
partial reply. Still, the wait shouldn't draw any conclusion from a tree
whose conversation is missing, and the fix suspends it instead.

## What the capture showed

On Sep 25 2026 an image was opened in the viewer of a Claude Code session
while a watcher took `tools/ax-dump.swift` snapshots. The capture is now the
fixture `tests/ErrolKitTests/Fixtures/claude-code-image-viewer.json`, with
the embedded image and the session ID replaced.

- **The viewer is a dialog.** It is an `AXGroup` with subrole
  `AXApplicationDialog`, role description "dialog", and title and
  description "Image preview". It fills the window. Inside it are only a
  heading, a Close button (which has keyboard focus), a zoom toggle, and the
  image.
- **Everything behind it is pruned.** The window went from about 870
  elements to 66. The containers stay, but empty: no composer (no
  `AXTextArea` at all), no copy buttons, no "Message N", no Stop button, no
  message text.
- **There is no `AXModal` attribute**, so detection keys on the subrole and
  the missing composer.
- **Focus sits on the viewer's Close button**, so a paste while it is open
  would go nowhere. The delivery side needs the hold as much as the copy.
- **A check can catch the conversation already gone and the dialog not yet
  there.** The watcher's first look saw no composer and no dialog; a second
  later the dialog was in the tree. Whether that is a real in-between state
  or the watcher's two walks straddling the click, the fix doesn't depend on
  a single check.
- At rest, Claude's window has no dialog-role elements at all, and none of
  the other fixtures reads as covered (a test sweeps them).

## The fix

**Detection** lives in the finders, so the fixtures test the same code the
relay runs.
[`ElementNode`](../../app/Errol/Errol/Core/ElementNode.swift#L18) now
carries `subrole`.
[`coveringDialog`](../../app/Errol/Errol/Core/Elements.swift#L252) returns
the open dialog only when the window has no text area, and `dialogName`
names it by its title ("Image preview"). The live entry point is
[`coveringDialogName(in:)`](../../app/Errol/Errol/Core/Elements.swift#L326).
Both signals are required. A dialog alone can be a popover that leaves the
conversation readable, and in that case a copy works, because AXPress acts
on the element directly and doesn't hit-test. A missing composer alone says
nothing the human could close.

**A new hold**,
[`RunBlock.covered(side:by:)`](../../app/Errol/Errol/Core/Destination.swift#L165),
where `by` is the dialog's name. Its wording:

| | |
|---|---|
| headline | Paused: Claude's conversation is covered |
| recovery | Close “Image preview” in Claude to continue, or Stop. Errol resumes once the conversation is showing. |
| startRefusal | “Image preview” is open over Claude's conversation. Close it, then send again. |
| logLine | Paused — “Image preview” is open over Claude's conversation, which hides it from Errol. Close it to continue, or Stop. |
| contextClause | Claude's conversation was covered |
| shortStatus | conversation covered |

A dialog with no name reads as "A dialog" and "the dialog". It isn't
`.notInFront` reused: `frontGuard` clears that hold the moment the app is
frontmost, and here Claude is frontmost the whole time.

**Where it is checked.**
[`destinationGuard`](../../app/Errol/Errol/Core/Relay.swift#L404) returns
the hold before `frontGuard` whenever a covering dialog is found. Every path
that needs it already goes through that guard:

- **The response wait** suspends, the way it does for a minimized window.
  No sightings are taken, the inactivity clock stops, and the baseline is
  kept, so a reply that finished while the viewer was open is seen on
  return.
- **The capture gate** holds. `captureGuard` calls `destinationGuard` before
  its own Stop check, which would read false in a covered tree.
- **The delivery gate** holds, with the right advice, instead of "Claude's
  composer can't be read".
- **The copy-failure branch.** If the viewer opens between the gate and the
  press, the copy finds nothing. The branch then waits 0.8 s and asks
  `destinationGuard` again before ending the run, to cover the moment when
  the conversation is gone and the dialog not yet in the tree. On a hold it
  goes back to the gate.

`ComposerState` gains `.covered(by:)`.
[`composerState(in:)`](../../app/Errol/Errol/Core/Destination.swift#L117)
returns it when the composer is missing and a dialog is found, and
`deliveryBlock` maps it to the new hold. Through that one change:

- the run's preflight refuses with the covered `startRefusal`, where it
  used to say "has no message field";
- a connected side's readiness reads as something to finish first, with
  the same refusal;
- the readiness scan records the dialog (`WindowScan.coveredBy`), so the
  window's state line reads "Covered by “Image preview”".

**The wait's confirming pair starts over on a hold.**
[`ResponseWaitState.suspend`](../../app/Errol/Errol/Core/RelayActions.swift#L942)
resets `stableTicks`. Without that, one dark poll taken as the viewer
opened counts toward the two-poll confirmation, and a single poll after the
viewer closes completes the wait.

**The console** shows the focus alert for both holds.
[`PerchFocusAlert.ask(for:)`](../../app/Errol/Errol/Perch/PerchFocusAlert.swift#L38)
returns the side along with what to ask:

- for `.notInFront`: "Please focus Claude to continue the conversation" /
  "Click Claude's window. Errol continues on its own once it is in front."
- for `.covered`: "Please close “Image preview” in Claude to continue" /
  "It hides the conversation from Errol, which continues once it is closed."

The alert shows as soon as the wait sees the cover, even while Claude is
still replying. Errol can't see the reply at all, and a wait suspended while
covered would never reach the capture to ask later. There is a new canvas,
"Running · Claude's conversation covered" (`conversationCovered`, canvas 25
in `tools/console-preview/render`).

## Alternatives considered

- **Close the viewer automatically** (press Escape, or AXPress its close
  button). Rejected. The viewer is the human's, like a draft or the
  clipboard, and closing it under them is the kind of surprise the holds
  exist to avoid. Escape would also go to the key window, which may not be
  the viewer.
- **Treat "no copy button and no composer" as covered, with no dialog
  required.** This would catch overlays that don't use a dialog role, but it
  would also turn any unexplained disappearance into an open-ended hold. The
  capture showed the viewer does carry a dialog role, so this isn't needed.

## Tests

- `CoveredConversationTests` runs the real capture: the dialog is found and
  named, and the copy buttons, affordances, ordinal, composer and Stop
  button are all missing. It also checks that the tree, read as a sighting,
  would complete the wait, which is why the wait must not read it. It covers
  the scan, the candidate's state line, and the readiness refusal, and it
  sweeps every other fixture to confirm none reads as covered. A synthetic
  popover over a readable conversation, and a bare window with no composer,
  don't count as covered. The wording of the hold is pinned.
- `ResponseWaitTests.testAHoldStartsTheConfirmingPairOver` replays the
  run's sequence (streaming, one dark poll, a hold, then a finished reply)
  and fails without the `stableTicks` reset.
- `ComposerStateTests` maps `.covered` to the hold.

Not covered: a live run with the viewer opened mid-reply. The app wasn't
built for this change (agent builds break its Accessibility grant). The code
was typechecked with Xcode's flags, `swift test` passed, and the alert was
rendered offscreen.

Also unobserved: Claude's chat surface (not Code) and ChatGPT's image viewer.
The detection doesn't depend on the app, but neither has been captured.
