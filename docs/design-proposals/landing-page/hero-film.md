# Errol hero film

Motion study, September 5, 2026. This is a simulated product demonstration with
simplified interfaces and illustrative dialogue. It is not a captured relay run.

## Format

Author the experience as a deterministic, scripted animation of a Mac desktop.
Keep the windows, text, pointer, and camera editable independently. This makes
it possible to change the topic or timing without recording the applications
again, and to direct a separate portrait composition for phones.

The landing-page animation runs for 49 seconds and includes pause, replay, and scrubbing.
It uses an HTML/CSS scene with one animation clock. It follows the viewer's
appearance, pauses when offscreen, and starts paused when reduced motion is
enabled. For the landing page, the production recommendation is a silent MP4
with a poster image and playback controls, with WebM as an optional alternate
encode. Keep the editable animation as the source. The video files have not
been exported in this design pass.

## What a viewer should understand

Errol operates the AI apps already open on the Mac. The person starts a
conversation, Errol copies each reply into the other app, and the person can
pause at a handoff to add a note. The next reply should visibly respond to that
note, so steering has a consequence the viewer can recognize.

## Sequence

| Time | Picture and action | Purpose |
| --- | --- | --- |
| 0–4 s | Type “What if your AIs could talk to each other?” on a quiet title screen. Fade directly into a close-up of Errol. | Introduce the premise before the interface. |
| 4–9 s | Free chat is selected first. The person's pointer visibly selects Debate, then types “Should we launch on the web or build a native Mac app?” | Establish what the person provides. |
| 9–11 s | Press the round start icon. It moves into the center of Errol and grows, while the surrounding content blurs. Hold briefly, then restore the content and release the camera. | Give the start action a clear, separate moment. |
| 11–17 s | Pull out, then focus on ChatGPT. Errol pastes the opening topic and presses Send. Let the first words appear, then ease back over 3.3 seconds; reach the full desktop while its answer is still streaming. | Keep attention on the reply as the desktop gradually comes into view. |
| 17–21 s | In the full desktop view, the gold pointer labeled Errol presses Copy. Move into Claude. The reply appears in its composer; Errol presses Send. | Make the relay mechanism explicit. |
| 21–26 s | Claude begins replying. Let the first words appear, then use the same gentle 3.3-second pullback while its response continues. Move toward Errol and press Pause to steer. The current reply finishes, is copied, and the handoff waits. | Show a second perspective and how a person intervenes. |
| 26–31 s | Close-up on Errol. Type “Assume our users work offline every day.” Send the note. | Show steering as a small addition to the ongoing discussion. |
| 31–38 s | Pull back from Errol and hold the full desktop. Claude's reply and the person's note arrive together in ChatGPT. ChatGPT changes its recommendation to native because offline work is central. | Make the effect of steering visible. |
| 38–46 s | Keep the full desktop in view as Errol copies the revised reply and delivers it to Claude. Claude proposes a small first release focused on offline work. | Establish that the relay continues after the intervention. |
| 46–49 s | Fade from the desktop to the Errol mark and “Let your AIs talk.” | Leave the product's purpose clear. |

## Visual direction

Use a restrained Mac screen frame, a quiet sage desktop, system display type,
warm neutral app surfaces, and the app's amber accent. The app windows retain
their title bars, traffic lights, messages, Copy controls, and composers; omit
sidebars, histories, model selectors, and incidental tools. Actual app icons and
names identify ChatGPT and Claude within the simplified interfaces. Errol's setup
keeps the conversation-shape selector, topic, and start icon; it omits tile/turn
options, the secondary instructions, and the separator.

Use a neutral pointer for the person's actions and an amber pointer labeled
Errol for automated actions. The amber pointer is an editorial visualization
of button presses, not a claim that the actual relay moves the mouse cursor.
Highlight the pressed Copy and Send controls. Paste each reply as a block;
stream only assistant replies and the person's typing.

Keep windows in consistent positions. Pull back during app changes so the
viewer can orient themselves. Fade the background Errol panel during tight
chat close-ups so it does not cover message content, then restore it in the
wider view. On phones, use closer framing for typing and the same pullbacks to
reveal the desktop during replies. Captions explain one action at a time and the
sequence works without sound.

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
