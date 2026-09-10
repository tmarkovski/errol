# First-run usability and predictable relay behavior

September 9, 2026; revised September 10 after review of the fixture evidence.
Discussion proposal following Codex and Claude's review of
the current application and website source. No application changes are made
by this proposal. These are code-grounded usability hypotheses; they have not
been ranked through observed first-time user sessions.

## The user's request

Consider the difficulties new users face across the whole experience: opening
both apps, granting permissions, understanding conversation types, discovering
the controls, following a run, intervening, understanding the ending, and
finding the result. Compare findings, agree on the most consequential problems,
and discuss how to address them.

The compact widget asks users to understand a process that spans two existing
applications, conversations, contexts, and tool environments. The first set of
changes should make three expectations dependable:

1. **I can get started.** Errol helps me prepare the apps and explains each
   blocker where I am looking.
2. **I know what it will affect.** The destinations and selected conversation
   instructions are visible. Existing drafts are preserved. Switching
   conversations does not silently redirect the relay.
3. **I understand what happened.** Progress, a recoverable pause, completion,
   and failure have distinct explanations and useful next actions.

## Findings in the current source

- Run checks for a nonempty prompt, but app and permission failures from
  preflight are sent to the log. Failure in the worker before the first turn
  returns the widget to editing without a summary: `hasFinishedRun` requires a
  positive turn count. Readiness problems do appear in the widget; the missing
  information is the specific result of a failed start.
- The relay uses open conversations and resolves an eligible window repeatedly.
  Destination mode, model, and title are largely tooltip information. Claude
  Code is a supported fallback when no ordinary chat window is available.
- Production delivery does not refuse an existing human draft or attachment.
  The verification harness has its own empty-composer precondition.
- Production copying and delivery overwrite the clipboard without restoring
  it. The harness captures multiple clipboard items and representations, but
  its restore is unconditional; it does not protect a newer user copy.
- Brainstorm is the default, while the selected type is inside Settings. The
  visible topic placeholder ignores the template's `topicPrompt`. A placeholder
  change alone would not explain the selection once the user has typed.
- The turn counter advances before a response arrives. The summary infers its
  ending from the counter and participant states, so a timeout on the last
  permitted turn can read as "Turn limit reached". Other failures read as
  "Run ended". A one-sided sign-off is not by itself a terminal condition.
- "New session" resets Errol's presentation and retains the prompt; it does
  not open fresh conversations in either application.
- Veil rendering is implemented but disabled in the current AppKit shell.
  Earlier descriptions of active window blurring should not be used as
  evidence of the current experience.
- Website copy promises Markdown transcripts in Documents; no corresponding
  transcript export was found in the application. The permission FAQ's
  "Nothing is sent anywhere" also misdescribes replies being submitted to the
  other assistant through its desktop app.

Relevant sources:

- [Controller and start/finish state](../../../app/Errol/Errol/RelayController.swift)
- [Widget controls](../../../app/Errol/Errol/Perch/PerchWidget.swift)
- [Destination tooltips](../../../app/Errol/Errol/Perch/PerchAvatar.swift)
- [Finished-run summary](../../../app/Errol/Errol/Perch/PerchSteering.swift)
- [Relay loop](../../../app/Errol/Errol/Core/Relay.swift)
- [Copy, paste, and response detection](../../../app/Errol/Errol/Core/RelayActions.swift)
- [Verification binding and composer guards](../../../tools/ErrolVerification/LiveRunner.swift)
- [Harness clipboard capture and restore](../../../tools/ErrolVerification/Evidence.swift)

## Direction shared in the discussion

Protect existing drafts, make destinations deliberate, show failed-start
reasons, and report actual ending outcomes. Include conversation-change
handling in the first implementation batch. Keep the first iteration focused
on returning to the original destination or stopping; redirecting an active
run requires a separate decision about context and framing.

Reuse the existing serial worker and capture/delivery gates, preserving
[steering's focus ownership](../steering/focus-coordination.md). Adapt the
harness helpers after checking their assumptions against normal desktop use.

### Setup and destination selection

Before Run, show both target apps, modes, and conversation names where those
are observable. Distinguish a fresh conversation from an existing one. The
selected shape and starting assistant should also remain visible.

A tool-enabled destination should be an explicit selection in setup. Explain
that it retains the tools and permissions of that session. A warning tint or
tooltip alone does not establish that the user selected it. Preserve a valid
selection without asking for repeated confirmation on every run.

"Ready" should mean an eligible, intended surface is observable, its composer
is readable and empty, no unsent attachments are detected, and no response is
underway. It must not imply that provider usage limits, authentication, or all
possible approval states have been verified. Accepted modes include deliberate
Code, Cowork, and Work selections, not only ordinary Chat.

Explain the reason beside an unavailable Run action. A draft or ongoing reply
is a recoverable state with text, not just a red or amber dot. Keep final
preflight authoritative because readiness can change between the scan and
the click. A failed preflight must leave visible feedback even with zero turns.

Follow this with actionable setup for missing/closed apps and permission
recovery. Do not consider the original first-run request solved solely by
improving the guards inside the relay.

### Conversation changes: pause at capture and delivery

The proposed response is to hold at either boundary when the original
conversation is temporarily no longer displayed:

> Paused: Claude's conversation changed. Return to "Onboarding ideas" to
> continue, or Stop. Errol will resume when the original conversation is ready.

Keep the existing pending reply, response baseline, and steering note. Perform
no capture, paste, submission, or repeated focus activation while blocked.
Stop remains available. Do not navigate back on the user's behalf.

Check destination and expected message continuity while waiting for a response
as well as at both operation gates.
Otherwise polling another conversation can produce a false completion or a
timeout before the capture gate is reached. Time spent blocked on a changed
destination must not consume the original response's inactivity allowance.
Preserve the original baseline when resuming; resetting it to a completed
reply would cause the relay to wait for a reply that will never arrive.

Validate again close to copying, pasting, and submitting, including after any
activation or asynchronous wait. The gates alone cannot prevent the user
switching conversations inside a copy or delivery operation.

Proposed recovery depends on what can be established:

- **Unchanged exchange:** automatically resume when both the intended
  destination and the expected message sequence are verified and all other
  holds have cleared. A completed reply arriving during the hold is expected
  progress, not a reason to reject the conversation.
- **Revised reply, not yet forwarded:** offer a specific action such as
  "Use revised reply" when the reply is identifiable, complete, still answers
  the expected prompt, and has not been pasted or submitted to the peer.
  Replace the pending captured text deliberately and retain the steering note
  for one delivery. This is a proposed bounded recovery, not a general bypass.
- **Additional user messages or a reply already forwarded:** remain paused
  and explain the changed history. Replaying a revised answer could duplicate
  work or leave the peer answering the earlier version. Keep Stop available;
  rebasing such an exchange requires a separate design.
- **Unobservable evidence:** explain that Errol cannot verify continuity and
  remain paused for recovery or Stop. A generic Continue button must not imply
  the destination or reply has been verified. Any manual recovery should make
  the actual destination and pending message reviewable; that flow is still
  outside this first implementation proposal.

Retain the original response baseline on valid recovery. Detect permanent
target loss separately and finish with a specific explanation when recovery
is no longer possible.

### Preserve unsent work

Before each new payload is pasted, inspect the intended composer's text,
attachments, and busy state. Unreadable state does not establish emptiness.
Preserve whitespace drafts too. Keep the payload and note pending when blocked:

> Paused: Claude has an unsent draft. Finish or clear it before continuing.

Clearing an unsent draft can resolve the block. Sending the draft changes the
conversation history and requires revalidation of the expected exchange;
an empty composer alone does not authorize automatic continuation.

Distinguish a human draft from Errol's own already-pasted payload. A guard
inserted blindly into every retry would block on Errol's paste or encourage a
duplicate send. Unconfirmed submission needs its own recovery path; do not
automatically replay a message that might already have been sent.

### Holds and terminal outcomes

Represent current blocking conditions separately from the final outcome.
Destination changed and draft present are hold reasons while the run remains
recoverable. A steering hold can coexist with them: clearing one condition
must not clear another or take focus from an open steering editor.

Record an explicit terminal result and render the summary from it. Candidate
outcomes are mutual completion, user stop, reply limit reached, timeout on a
named side, copy failure, send refusal, unconfirmed submission that ends the
run, empty reply, unrecoverable target loss, and failed start with its reason.
Record a preceding sign-off or hold as context rather than inventing a separate
cause of termination. If Stop is pressed during a destination hold, the outcome
is user stop with that context.

An outcome exists independently of the turn count. Report captured replies
separately from the reply currently awaited, so a failed wait is not presented
as another completed reply. Summaries must distinguish technical completion
from whether the assistants actually produced a useful or correct answer.

### Clipboard ownership

Reuse the harness's multiple-item, multiple-representation capture as a
starting point. Production must also track changes made outside Errol and
avoid restoring an old snapshot over a later user copy. Comparing against the
last relay write only at run end is insufficient if Errol has already
overwritten an intervening user copy on another turn.

Prefer separate bounded leases for response capture and payload delivery:

1. Capture the current clipboard's available items and representations before
   the operation changes it.
2. For capture, verify the intended reply was copied and retain its text in
   memory. Release the clipboard before waiting for the delivery gate.
3. For delivery, write the payload, verify it still owns the clipboard before
   pasting, and wait for the paste receipt before releasing ownership.
4. Restore the snapshot only if the clipboard still contains the operation's
   verified write. If another copy intervenes, preserve it. During delivery,
   an unexpected clipboard change must also prevent pasting that unrelated
   content; skipping restoration alone is insufficient.

Release ownership on cancellation and errors too. Handle incomplete capture
without destructive partial restoration. These operations can include slow
app responses and retries, so do not promise a fixed subsecond duration.
Clipboard ownership and copy attribution require live validation before
describing concurrent clipboard use as supported.

## Evidence for destinations and message continuity

**Both the intended destination and the expected exchange govern automatic
continuation.** Stable conversation identifiers, when available, remain binding:
a matching payload does not override navigation to another known conversation.
Generic or automatically changing titles are hints. Message sequence evidence
can support continuity where titles are weak, but it does not make missing
evidence conclusive.

### What the checked fixtures establish

The table below describes repository fixtures, not universal capabilities of
the live apps. The README identifies the two captured home screens and the
virtualized Claude Code conversation as real captures, and most other fixtures
as synthesized. Missing data in a synthesized tree does not prove that the live
app cannot expose it. These files are under
[the fixture directory](../../../tests/ErrolKitTests/Fixtures).

| Surface and fixtures | URL/title evidence in these files | Message evidence and limit |
| --- | --- | --- |
| ChatGPT Chat (`chatgpt-chat-home`, `chatgpt-chat-conversation`) | Home window title is `ChatGPT`; home exposes an `app://` shell URL, not a conversation URL. Conversation title is `Logo brainstorm`; no conversation URL is recorded. | Conversation fixture labels User/Assistant message groups but omits their body text. |
| ChatGPT Work and Codex (`chatgpt-work-home`, `chatgpt-work-conversation`, `chatgpt-codex-conversation`) | No URLs are recorded. Work home is titled `ChatGPT`; conversation titles name the work/task. | Conversation fixtures label message roles but omit body text; no fresh Codex fixture establishes its opening transition. |
| Claude Chat (`claude-chat-home`, `claude-chat-conversation`) | Captured home window is titled `Claude` and exposes `/new`; the conversation fixture supplies `/chat/<uuid>` and a named window. | Conversation fixture has unlabeled message groups and action buttons, without `AXDocumentArticle` or body text. `EvidenceNode.messages` does not recognize those groups as written. |
| Claude Cowork (`claude-cowork-home`, `claude-cowork-conversation`) | Both fixtures use `/new`; the window title changes from `Claude` to a task name. | Conversation groups are unlabeled and lack body text. These files do not establish a stable URL or an observable full sequence. |
| Claude Code (`claude-code-collapsed`, `claude-virtualized-conversation`) | `/epitaxy/<id>` is exposed. Window title is `Claude`. | The real virtualized capture has `Message 6` through `Message 8` document articles and some text. Collapsed synthetic groups omit those labels; older messages are not guaranteed to stay mounted. |
| Claude project (`claude-project-chat`) | `/project/<uuid>` and a project-named window are exposed. A project URL does not identify an individual conversation. | Unlabeled groups/action buttons without body text do not establish full transcript observability. |

The `New` title inside the captured Claude home tree belongs to a nested
element, not its `AXWindow`; that window's title is `Claude`. Adding generic
titles to a fallback blocklist may be sensible, but these fixtures do not
demonstrate that `TargetBinding` currently acquires `title:New` there.

### Adapting the harness

`TargetBinding` is useful groundwork, but it is not yet a production identity
guarantee:

- It pins an Accessibility window element; a single window can display many
  conversations and modes. Mode should be checked independently.
- Its URL test accepts paths beyond known conversation routes. A non-home
  URL is not automatically a unique conversation identity.
- The title fallback can change during automatic naming and can be shared by
  multiple conversations. Unknown identity is distinct from verified identity.
- For a new chat, the first changed identity after submission is adopted. A
  switch to another conversation during that interval could be adopted too.
  Checking an empty composer does not rule out switching to a different empty
  destination before the opener.

`EvidenceNode.messages` and `verifyTranscript` are also starting points. The
harness identifies messages using roles, headings, or actions; some checks use
a unique test nonce. It reports normalized or hidden content as inconclusive.
It does not yet prove phase-appropriate continuity for arbitrary user prompts
on every supported surface.

Adapt those helpers to track the latest verified user payload per participant,
the expected responding message, and whether that response has been captured,
pasted, or submitted to the peer. Compare the observable suffix relevant to the
current phase; do not require the entire transcript to remain mounted. Distinguish
streaming and tool activity from the completed reply being relayed rather than
assuming every surface has exactly one assistant container per turn.

Do not promote paste-recognition heuristics into an identity check. Stripping
punctuation makes `x < 10` and `x > 10` identical, and an attachment chip does not
reveal the attachment's content. Such signals can help detect a paste arriving
inside an observed operation; they cannot independently establish unchanged
message content after navigation. Require stronger evidence or report the gap.

For fresh chats, bind the selected window, mode, and observable new-chat state
before submission, revalidate immediately before the opener, and associate any
new identity with observation of that opening message. A title change alone is
not a mismatch when independent evidence shows the same exchange. Zero detected
messages is evidence of a fresh chat only where message detection is itself
reliable and the relevant tree is observable. Define the supported evidence
before promising automatic recovery on each surface.

## Proposed delivery sequence

These are work packages within a coherent first batch, not independently
shippable promises of complete protection.

1. Define intended destinations and reliable binding; add recoverable holds
   during response observation and at capture/delivery, plus draft protection.
   Include a minimal visible destination line with these changes.
2. Add explicit outcomes, zero-turn failed-start feedback, and truthful summary
   counts. Separate blocking state from final state.
3. Make readiness actionable, retain visible shape selection, use each shape's
   topic prompt, and correct "New session" wording to match its actual behavior.
4. Add and validate clipboard preservation with external-change handling.
5. Correct the website's transcript and data-flow claims. This copy correction
   can be made independently as soon as implementation work is authorized.

Then develop the guided first-run setup, permission recovery, clearer steering
language, result access/export, and a compact state for experienced users.
Prefer a smaller initial explanation that reveals consequential choices at the
right time over a long mandatory tutorial.

## Scenarios to validate during implementation

| Scenario | Expected behavior |
| --- | --- |
| One app is closed, missing, or cannot expose a composer | Explain the actual blocker and relevant next action beside setup; no invisible Run failure. |
| Accessibility is missing or revoked | Show permission recovery; preserve the prompt and pending work. |
| Either composer contains text, whitespace, an attachment, or an active reply | Preserve existing work and explain why sending is blocked. |
| Listener switches from fresh Chat to an existing Code session while the other side replies | Hold before delivery; nothing enters Code; name the original destination. |
| Speaker switches conversations while replying | Suspend observation of the wrong conversation and hold capture; preserve the original baseline. |
| Original conversation returns unchanged after a hold | Resume only after all remaining holds clear; do not steal steering-editor focus. |
| User sends a draft or changes response history during a hold | Revalidate expected messages; do not resume solely because the composer is empty. |
| User regenerates a completed reply that has not been pasted to the peer | Offer Use revised reply only when its destination and relationship to the expected prompt are verified; replace the pending reply once. |
| User regenerates a reply already pasted or possibly submitted to the peer | Explain the changed exchange; do not replay it through a generic Continue action. |
| Role, text, or attachment content cannot be observed after navigation | Keep the evidence gap visible; do not claim automatic continuity from counts, chips, or a matching title. |
| Two payloads differ only in meaningful punctuation | Keep them distinguishable for continuity even if the paste receipt normalizer treats them alike. |
| Fresh chat gains a title/URL after the opener | Bind the identity attributable to that opening submission; do not adopt unrelated navigation. |
| Destination changes between activation, paste, and Send | Revalidate before submission; preserve uncertain delivery evidence and avoid blind retry. |
| Last allowed reply times out | Report timeout on the named side, not reply limit reached. |
| Worker fails before turn one | Keep the failed-start reason visible with a next action. |
| User copies something during the run and Errol later copies again | Preserve the user's newer clipboard contents according to the ownership design. |
| User copies something after Errol writes a payload but before it pastes | Preserve that copy and prevent its accidental submission as the relay message. |
| User presses Stop while a draft or destination hold is active | Finish promptly at a safe boundary; show user stop with the prior blocker as context. |
| User chooses the action currently called New session | Make clear whether only Errol resets or fresh provider conversations are actually created. |

Use pure state tests and recorded app fixtures for identity, holds, outcome
selection, and composer classification. Use deliberate live verification for
focus, clipboard, copy/paste ownership, and app navigation where static fixtures
cannot establish behavior. No tests or live relay runs were performed for this
documentation-only proposal.

## Decisions still to resolve

- Reliable identity signals and honest behavior for surfaces without a stable
  conversation identifier, particularly fresh conversations and task modes.
- Whether conditional automatic resume is understandable in first-time use;
  prototype the copy and compare with an explicit Continue action.
- Evidence needed for the bounded Use revised reply action, and a separate
  recovery design for additional messages or already-forwarded replies.
- Clipboard copy attribution, external-change races, and incomplete captures
  within the proposed per-operation ownership boundaries.
- How much setup remains visible after a successful first run, and where
  results and recovery actions fit in the compact widget.

Mid-run redirection, automatic creation of fresh provider conversations, and
transcript export require further design. They are not implemented or implied
by the first batch above.

## Implementation status

September 10, 2026. The engine hardening from the delivery sequence above is
in the application; the setup redesign and the website copy are not.

Landed (packages 1, 2, and 4, with the start-time half of package 3):

- **Bound destinations** (`Core/Destination.swift`). Each side is bound at
  Run to its window and to a graded identity — route, title, or nothing —
  read through the same window scan the readiness strip uses (the scan now
  keeps the conversation route; `AppSelectors` carries the hosts, route
  prefixes, and generic titles per app). The binding is checked before and
  after both gates, immediately before every paste and submit keystroke, and
  on every poll of the response wait, whose inactivity clock is suspended
  and whose baseline is kept while the conversation is out of view. A fresh
  chat adopts the route or name it gains until its first reply is captured;
  a bound route is binding; a world or surface switch is always a change;
  a quit app or closed window ends the run as `destinationLost`.
- **Holds separate from outcomes** (`RunBlock`, `.blocked` on the event
  stream). Destination changed, draft, attachment, reply underway,
  unreadable composer, and history changed are holds: the run owns no focus
  operation while standing in one, so the steering editor still opens over
  it, nothing is copied, pasted, or activated, and Stop is answered at every
  poll. A send whose pre-keystroke check fails is `withheld` and returns to
  the gate with any committed note kept in hand.
- **Unsent work** (`classifyComposer`). Both composers are classified at Run
  and the recipient's at every delivery; only an empty one admits a paste.
  Whitespace reads as empty because Claude's idle composer reports a bare
  newline; a value matching the element's own label reads as the placeholder.
- **Explicit outcomes** (`Core/RunOutcome.swift`, `.ended` on the event
  stream). `runRelay` returns and posts a `RunReport` — outcome, replies
  captured, the sign-off or hold it ended on — from which the summary is
  rendered. Failed starts, including preflight failures in the engine,
  report a reason the panel shows under the composer.
- **Clipboard leases** (`Core/ClipboardLease.swift`). Per-operation capture
  and conditional restore, in both the copy and the send; the harness now
  shares the type, using its unconditional `restore()` per case.
- Tests: `DestinationTests`, `ComposerStateTests`, `ClipboardLeaseTests`,
  `RunReportTests`, and the suspended-clock cases in `ResponseWaitTests`,
  over the recorded fixtures. No live run was made for these changes.

Not landed, and still as proposed above:

- The visible destination line, actionable readiness text, visible shape
  selection, each shape's topic prompt as the placeholder, and the "New
  session" wording (package 3's panel half; the action itself still only
  resets Errol, which the summary now says).
- The website's transcript and data-flow claims (package 5).
- "Use revised reply", recovery from a changed history beyond Stop, and
  message-sequence evidence stronger than the affordance count and ordinal
  the capture gate compares; the decisions listed above stand.
- The readiness strip's "Ready" still means window plus composer; the
  composer's contents are judged at Run, not in the strip.
