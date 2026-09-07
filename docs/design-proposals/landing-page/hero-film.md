# Errol hero film

Motion study, September 5, 2026. This is a simulated product demonstration with
simplified interfaces and illustrative dialogue. It is not a captured relay run.

## Format

Author the experience as a deterministic, scripted animation of a Mac desktop.
Keep the windows, text, pointer, and camera editable independently. This makes
it possible to change the topic or timing without recording the applications
again, and to direct a separate portrait composition for phones.

The landing-page animation runs for 34 seconds and includes pause, replay, and scrubbing.
It uses an HTML/CSS scene with one animation clock. It follows the viewer's
appearance, pauses when offscreen, and starts paused when reduced motion is
enabled. For the landing page, the production recommendation is a silent MP4
with a poster image and playback controls, with WebM as an optional alternate
encode. Keep the editable animation as the source. The video files have not
been exported in this design pass.

## What a viewer should understand

Errol operates the AI apps already open on the Mac. The person starts a
conversation, and Errol copies replies back and forth automatically. Let ChatGPT
start its second reply before the person adds a note while that reply continues.
Steering holds the next handoff; it does not interrupt the assistant's typing.
The next reply should visibly respond to that
note, so steering has a consequence the viewer can recognize.

## Sequence

| Time | Picture and action | Purpose |
| --- | --- | --- |
| 0–4 s | Type “What if your AIs could talk to each other?” on a quiet title screen. Fade directly into a close-up of Errol. | Introduce the premise before the interface. |
| 4–8 s | Free chat is selected first. The person's pointer visibly selects Debate, then types “Should we launch on the web or build a native Mac app?” Pull back near the end of typing. | Establish what the person provides and reveal the desktop before starting. |
| 8–12 s | Press Play with a click ring. Once ChatGPT is in front, a golden dot leaves the typed topic and arcs to ChatGPT's prompt in about half a second, dissolving into a bloom as the topic appears and the prompt's outline lights; then the message sends. After delivery, fade Errol's setup out and its running state in, with Pause centered; no button movement or morph. Focus on ChatGPT, then ease back over about 1.5 seconds as its answer streams. | Make the first handoff immediate and keep attention on the reply. |
| 12–16 s | In the full desktop view, ChatGPT's response gains an amber outline as Copy highlights. Once Claude is in front, the dot leaves the Copy control and arcs into Claude's composer; the outline lights, the reply appears, and the message sends. | Make the relay visible through the dot and the message surfaces. |
| 16–20 s | Claude begins replying. Use the same gentle pullback while its response continues. The finished reply's container gains its outline as Copy highlights. Pause remains visible in Errol. | Prepare the automatic return handoff. |
| 20–22 s | Hold the full desktop as the dot carries Claude's reply back to ChatGPT. ChatGPT starts “Those features matter…” automatically. | Show the conversation returning to ChatGPT without requiring the person to act. |
| 22–26 s | Move halfway toward Errol as ChatGPT continues typing. Keep the reply and Errol visible together. The pointer hovers to expand Pause into “Pause to steer,” then opens the blank note field. Type “Assume our users work offline every day” and send it while ChatGPT is still writing. | Show steering during an ongoing reply, with both actions visible at once. |
| 26–31 s | Pull back as the note finishes, keeping its text visible with no dot yet. When ChatGPT finishes, both sources gain amber outlines and ChatGPT's Copy control highlights. Two dots leave the Copy control and the note together and follow separate arcs that converge inside Claude's prompt, where one bloom marks the arrival. The reply and note appear together and send as one message. Claude quickly types its recommendation for native because daily offline work is central. | Make both sources of the next message visible, then show the effect of steering. |
| 31–34 s | Fade from the desktop to the Errol mark and “Let your AIs talk.” | Leave the product's purpose clear, ending on the steered reply. |

## Visual direction

Use a restrained Mac screen frame, a quiet sage desktop, system display type,
warm neutral app surfaces, and the app's amber accent. The app windows retain
their title bars, traffic lights, messages, Copy controls, and composers; omit
sidebars, histories, model selectors, and incidental tools. Actual app icons and
names identify ChatGPT and Claude within the simplified interfaces. Errol's setup
keeps the conversation-shape selector, topic, and start icon; it omits tile/turn
options, the secondary instructions, and the separator.

Use a neutral pointer for the person's setup and steering actions. For automated
handoffs, draw the same transfer dot the app's overlay draws: a small golden dot
that leaves the finished reply's Copy control (or Errol's prompt) once the
receiving app is in front, follows an upward quadratic arc to the composer in
0.55 seconds, and dissolves into a bloom on arrival while the composer's outline
rises and fades. A short, softly glowing wake follows its recent path, tapers
away behind it, and catches up with the dot when it stops. Reduced motion omits
the dot and wake and shows only the outline. For copying, the response container
gains an amber outline in sync with the Copy highlight, and the highlight clears
when the handoff moves on. This is an illustration of Errol's work, not a
literal mouse recording. Paste each
reply as a block; stream only assistant replies and the person's typing.

For the steering handoff, wait until ChatGPT finishes before showing either dot.
Both leave together, the note on a shallower arc, and their wakes stay separate
until they meet in Claude's composer, where one bloom marks the arrival before
the reply and note submit together. The person types at about 32 characters per
second and the assistants stream at about 50; ChatGPT's second reply is the
exception, streaming until the note is sent. Claude's steered reply types in
under two seconds and closes the demo, bringing the runtime to 34 seconds.

Keep windows in consistent positions. Pull back during app changes so the
viewer can orient themselves. Fade the background Errol panel during tight
chat close-ups so it does not cover message content, then restore it in the
wider view. The steering shot uses a moderate zoom that includes Errol and
ChatGPT's streaming response together. On phones, preserve both text areas in
that shot; use closer framing for the opening and the same pullbacks to
reveal the desktop during replies. The scene carries the narrative without a
separate caption or chapter counter, and the sequence works without sound.

## Product details preserved

The study follows the current Perch controls in `PerchComposer.swift`,
`PerchHead.swift`, `PerchSteering.swift`, and `RelayController.swift`: a topic
and conversation shape at setup, a compact running state, Pause to steer,
holding at the handoff, and a note sent with the next relayed message. The start
control is an icon; “Send note” is an expanded label for clarity. The incoming
note is visually separated for legibility; the actual app sends framed text.
The first-message ground rules are omitted from the simplified chat UI.

The integrated demo uses ChatGPT and Claude. Before a production video is
described as a real conversation, replace the illustrative dialogue with a
reviewed excerpt from an actual run.
