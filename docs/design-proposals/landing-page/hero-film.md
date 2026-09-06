# Errol hero film

Motion study, September 5, 2026. This is a simulated product demonstration with
simplified interfaces and illustrative dialogue. It is not a captured relay run.

## Format

Author the experience as a deterministic, scripted animation of a Mac desktop.
Keep the windows, text, pointer, and camera editable independently. This makes
it possible to change the topic or timing without recording the applications
again, and to direct a separate portrait composition for phones.

The landing-page animation runs for 45 seconds and includes pause, replay, and scrubbing.
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
| 4–9 s | Free chat is selected first. The person's pointer visibly selects Debate, then types “Should we launch on the web or build a native Mac app?” Pull back near the end of typing. | Establish what the person provides and reveal the desktop before starting. |
| 9–15 s | Press Play with a click ring and send the owl from the middle of the typed topic toward ChatGPT's prompt. Its border lights up, the topic appears, and the message sends. After delivery, fade Errol's setup out and its running state in, with Pause centered; no button movement or morph. Focus on ChatGPT, then ease back over 3.3 seconds as its answer streams. | Make the first handoff immediate and keep attention on the reply. |
| 15–19 s | In the full desktop view, the owl pulses once over the middle of ChatGPT's reply; the response gains an amber outline and Copy highlights. The owl moves into Claude's composer; its border lights up, the reply appears, and the message sends. | Make the relay visible through the owl and the message surfaces. |
| 19–24 s | Claude begins replying. Use the same gentle 3.3-second pullback while its response continues. The owl pulses over the finished reply, outlining its container as Copy highlights. Pause remains visible in Errol. | Prepare the automatic return handoff. |
| 24–26 s | Hold the full desktop as the owl carries Claude's reply back to ChatGPT. ChatGPT starts “Those features matter…” automatically. | Show the conversation returning to ChatGPT without requiring the person to act. |
| 26–31 s | Move halfway toward Errol as ChatGPT continues typing. Keep the reply and Errol visible together. The pointer hovers to expand Pause into “Pause to steer,” then opens the blank note field. Type “Assume our users work offline every day” and send it while ChatGPT is still writing. | Show steering during an ongoing reply, with both actions visible at once. |
| 31–36 s | Pull back as the note finishes, keeping its text visible with no owl yet. When ChatGPT finishes, two owls appear over the reply and user note together. Both sources gain amber outlines, and ChatGPT's Copy control highlights. The owls follow separate amber trails that converge inside Claude's prompt. The reply and note appear together and send as one message. Claude quickly types its recommendation for native because daily offline work is central. | Make both sources of the next message visible, then show the effect of steering. |
| 36–42 s | Keep the full desktop in view as Errol copies Claude's answer and delivers it to ChatGPT. ChatGPT quickly types its agreement to start with one reliable offline Mac workflow and add web sharing later. | Show the conversation continuing automatically after the intervention. |
| 42–45 s | Fade from the desktop to the Errol mark and “Let your AIs talk.” | Leave the product's purpose clear. |

## Visual direction

Use a restrained Mac screen frame, a quiet sage desktop, system display type,
warm neutral app surfaces, and the app's amber accent. The app windows retain
their title bars, traffic lights, messages, Copy controls, and composers; omit
sidebars, histories, model selectors, and incidental tools. Actual app icons and
names identify ChatGPT and Claude within the simplified interfaces. Errol's setup
keeps the conversation-shape selector, topic, and start icon; it omits tile/turn
options, the secondary instructions, and the separator.

Use a neutral pointer for the person's setup and steering actions. Use the
Errol owl in an amber circle for automated handoffs, with no pointer or action
label attached. A short, softly glowing amber tail follows its recent path,
tapers away behind it, and fades when it stops. Reduced motion omits the tail.
It arrives over a composer and lights its border as the message
appears and sends. For copying, it pulses once over the center of the reply and
the response container gains an amber outline in sync with the Copy highlight.
Both highlights clear when the handoff moves on. The owl never targets Copy or Send buttons. This
is an illustration of Errol's work, not a literal mouse recording. Paste each
reply as a block; stream only assistant replies and the person's typing.

For the steering handoff, wait until ChatGPT finishes before showing either owl.
Both owls copy their respective texts simultaneously, then leave together.
Keep the note owl's trail separate from the owl carrying ChatGPT's reply until
they meet in Claude's composer. Briefly merge the two marks there, then submit
the reply and note together. The final Claude and ChatGPT replies each type in under two seconds, bringing
the runtime to 45 seconds.

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
