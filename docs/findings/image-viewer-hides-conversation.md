# An image open over Claude's conversation stops the run

Findings from the run on Sep 24 2026 that ended on "Couldn't copy Claude's
reply", and a proposed fix. Nothing here is built yet.

**Short version.** Claude's image viewer does more than cover the
conversation visually. While it is open, the conversation is gone from the
accessibility tree: the copy buttons, the "Message N" groups, the Stop
button and the composer all disappear. Errol read that as "the reply
finished", found no copy button, retried once, and stopped. The situation
can be detected: a dialog appears in the window while the composer vanishes.
The fix is to treat it as a new recoverable hold, shown with the same
full-console alert as "Please focus Claude", and continue once the viewer
is closed.

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
Claude was in front the whole time. So when the copy failed,
[the branch after the copy](../../app/Errol/Errol/Core/Relay.swift#L636)
found the window present (`destinationGuard` → `.clear`) and the app
frontmost, and took the only remaining exit: `.copyFailed`.

### Why the conversation disappears from the tree

The likely mechanism: the viewer is a modal dialog (Radix-style, with
`aria-modal="true"`). Opening it either sets `aria-hidden` on everything
behind it or lets Chromium prune the content outside the modal. Either way,
Chromium stops exposing the conversation until the dialog closes. **This is
not verified yet.** The viewer wasn't open by the time I looked. What I did
check (`swift tools/ax-dump.swift claude --find dialog`, 15:59 local) is
that Claude's window at rest has **no** dialog-role elements, so one
appearing is a clean signal.

## A second problem in the same log: the reply probably wasn't finished

The response watch only logs a line when the reading changes
([`waitForResponse`](../../app/Errol/Errol/Core/RelayActions.swift#L1005)).
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
whose conversation is missing, and the fix below suspends it instead.

## Detecting it

Two signals, both required:

1. **A dialog in the bound window.** Chromium exposes `role="dialog"` as
   `AXGroup` with subrole `AXApplicationDialog` (`AXApplicationAlertDialog`
   for `alertdialog`). None exists at rest.
2. **The conversation's own landmarks are gone.** The steadiest one is the
   composer (the window's `AXTextArea`). Every surface of both apps has one,
   and virtualization never unmounts it.

Why require both:

- A dialog alone can be a non-modal popover. Radix popovers also carry
  `role="dialog"`, and they leave the tree readable. In that case a copy
  works: AXPress acts on the element directly and doesn't hit-test what's
  drawn over it.
- A missing composer alone can mean navigation or loading, and neither is a
  thing the human needs to close.

If the capture shows Chromium exposes `AXModal` on the viewer, keying on that
is more precise than the subrole, and the composer check becomes a
confirmation.

## Proposed fix

### 1. A new hold: the conversation is covered

Add `RunBlock.covered(side: Speaker, by: String?)` in
[`Destination.swift`](../../app/Errol/Errol/Core/Destination.swift#L131).
`by` is the dialog's label, if it has one, for the log. The wording:

| | |
|---|---|
| headline | Paused: something is open over Claude's conversation |
| recovery | Close the image or dialog open in Claude to continue, or Stop. Errol continues once the conversation is showing. |
| startRefusal | An image or dialog is open over Claude's conversation. Close it, then send again. |
| logLine | Paused — a dialog ("Image preview") is open over Claude's conversation, hiding it from Errol. Close it to continue, or Stop. |
| contextClause | Claude's conversation was covered |

`contextClause` lives in
[`RunOutcome.swift`](../../app/Errol/Errol/Core/RunOutcome.swift).

Why not reuse `.notInFront`: `frontGuard` clears that hold the moment the app
is frontmost ([`Relay.swift:399`](../../app/Errol/Errol/Core/Relay.swift#L399)).
Here Claude is frontmost the whole time, so the alert would clear at once and
the copy would fail again.

### 2. Detect it in the finders, where fixtures can test it

- Add `subrole` to the
  [`ElementNode`](../../app/Errol/Errol/Core/ElementNode.swift#L15) protocol.
  `LiveElement` reads `kAXSubroleAttribute`. `FixtureElement` already decodes
  it, and `ax-dump --capture` already records it.
- Add `coveringDialog(under window:) -> Node?` in
  [`Elements.swift`](../../app/Errol/Errol/Core/Elements.swift). It returns the
  dialog only when the window has no `AXTextArea`. Add the live entry point
  `coveringDialog(in target:)` next to the others.

On cost: this adds one tree walk wherever it runs, next to the three walks
each response poll already makes. If that becomes noticeable, only run the
check when a sighting comes back dark (no affordances, no ordinal, no Stop),
which is the only shape a covered tree produces, plus at the gates.

### 3. Check it in `destinationGuard`

In [`destinationGuard`](../../app/Errol/Errol/Core/Relay.swift#L385), after
`.same` and before `frontGuard`, return `.block(.covered(…))` when a covering
dialog is found. Every path that needs it already goes through
`destinationGuard`, so this one change reaches all of them:

- **The response wait.** Its `blocked` closure
  ([`Relay.swift:588`](../../app/Errol/Errol/Core/Relay.swift#L588)) suspends
  the wait the way it does for a minimized window. No sightings are taken, the
  inactivity clock stops, and the baseline is kept. This is what fixes the
  early completion. A reply that finished while the viewer was open is seen on
  return.
- **The capture gate.**
  [`captureGuard`](../../app/Errol/Errol/Core/Relay.swift#L407) holds. It calls
  `destinationGuard` before its own `hasStopButton` check, which matters,
  because in a covered tree that check reads false.
- **The copy-failure branch.** If the viewer opens between the gate and the
  press, the copy fails, `destinationGuard` returns `.block`, and the run goes
  back to the gate instead of stopping
  ([`Relay.swift:636`](../../app/Errol/Errol/Core/Relay.swift#L636)).
- **The delivery gate, on the listener's side.** Today a covered listener
  reads as "Claude's composer can't be read": `inputArea` is nil, so
  `composerState` returns `.unreadable`. That is a hold with the wrong advice
  ("Click into Claude's message field"). The covered check runs first and
  gives the right advice.
- **Run start.** The preflight's "has no message field" refusal
  ([`Relay.swift:343`](../../app/Errol/Errol/Core/Relay.swift#L343)) should
  check for a covering dialog first and use the covered `startRefusal`
  instead.

`send`'s own `destinationHolds` doesn't need the check. The gate has just
checked, and the paste receipt already catches a viewer opened in the middle
of a send.

### 4. Reset the confirming poll when the wait suspends

[`ResponseWaitState.suspend`](../../app/Errol/Errol/Core/RelayActions.swift#L938)
should set `stableTicks` to 0. The `blocked` check and the sighting's reads
are separate walks, so a viewer opening between them yields one dark sighting
that counts toward the confirming pair. After a resume, a single poll then
completes the wait. This is a small, pure change, and a good fit for
`ResponseWaitTests`.

### 5. Show it as the focus alert

[`PerchFocusAlert.side(for:)`](../../app/Errol/Errol/Perch/PerchFocusAlert.swift#L26)
matches only `.notInFront`. Generalize it to return the side along with which
request to show:

- `.notInFront`: "Please focus Claude to continue the conversation" /
  "Click Claude's window. Errol continues on its own once it is in front."
- `.covered`: "Please close what's open in Claude to continue" /
  "An image or dialog covers Claude's conversation, so Errol can't read it.
  Errol continues on its own once it's closed."

[`PerchConsole.swift:42`](../../app/Errol/Errol/Perch/PerchConsole.swift#L42)
uses the result for the blur, `accessibilityHidden`, and the animation value.
Make that value the pair, which is `Equatable`, so switching from one request
to the other animates. Add a `#Preview("Console · conversation covered")` next
to "waiting for focus", and render it with the offscreen harness rather than a
build.

**When the alert shows.** As soon as the wait sees the cover, even if Claude
is still replying. Errol can't see the reply at all, so the human should know
the run is waiting on them. The softer alternative would be a status line
during the wait and the full alert only at capture. But a wait that is
suspended while covered never reaches capture, so if the viewer were left
open, no request would ever appear.

## Alternatives considered

- **Close the viewer automatically** (press Escape, or AXPress its close
  button). Rejected. The viewer is the human's, like a draft or the clipboard,
  and closing it under them is the kind of surprise the holds exist to avoid.
  Escape would also go to the key window, which may not be the viewer.
- **Treat "no copy button and no composer" as covered, with no dialog
  required.** This would catch overlays that don't use a dialog role. It would
  also turn any unexplained disappearance into an open-ended hold. Keep it in
  reserve, as a generic "Claude's conversation isn't showing" hold, in case
  the capture shows the viewer has no dialog role.

## Tests

- **A real capture fixture**, `claude-code-image-viewer.json`, anonymized like
  the others. The scenario asserts that `coveringDialog` finds it, and that
  `copyButtons`, `messageAffordances` and `composerElement` come back empty.
- **A sweep over every existing fixture** asserting no covering dialog. This
  guards against false positives on the screens already classified.
- **A synthetic popover fixture**: a `role="dialog"` group with the composer
  still present, which must not count as covered.
- **`ResponseWaitTests`**: suspending resets the confirming poll, and a dark
  sighting seen while blocked never completes the wait.
- **`RunReportTests`**: the covered `contextClause`.

## To settle with a capture first

Open an image in the Claude Code session, then:

```
swift tools/ax-dump.swift claude --find dialog
swift tools/ax-dump.swift claude --buttons
swift tools/ax-dump.swift claude --capture
```

From a Claude Code shell, these need the Bash sandbox disabled (see
ax-dump's header). The capture should answer:

- Is the viewer `AXGroup`/`AXApplicationDialog`? Does it expose `AXModal`?
  What is its label?
- Is the composer really gone, or only the message list? If the composer
  stays, the second signal has to become "no affordances and no Stop"
  instead.
- Does the same happen in a Claude chat (not Code), and in ChatGPT's image
  viewer? The detection doesn't depend on the app, but ChatGPT resolves its
  composer differently, so check it there too.
