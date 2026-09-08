# Session controls at the foot

Status: built September 8, 2026, in `app/Errol/Errol/Perch/` (PerchComposer,
PerchSteering, PerchHead, PerchChrome). [session-controls.html](session-controls.html)
shows the run start to finish and the three weights tried for Stop.

## What changed

- The round primary button stays in the foot's corner and changes in place:
  Run, then Pause when the run starts, then Continue or Send while the field
  is open, then New session when the run is over. It no longer springs into the
  middle of the field as Pause to steer.
- Stop appears beside Pause for the length of the run: an outlined circle of
  the primary's own size, so the two read as a pause/stop pair and the fill
  alone says which is the safety action. (It was first drawn a size smaller;
  equal size won on the second look — the larger target matters when the end
  is wanted, and the outline keeps it secondary.) It asks for the end at the
  next safe point, dims once it has, and the foot's line says the end is
  coming. End session left the title strip's ··· menu.
- The closed field carries a notice while the run is on: don't type into
  ChatGPT or Claude while the session runs, type here to steer instead. A
  queued note takes the notice's place, dimmed rather than blurred, since
  nothing stands over it any more. Clicking the field does what Pause does.
- Where the note is and what became of it moved from the head to the foot's
  leading line, where the key hints already were: writing (who the note is for
  and what Return and Esc do), sending, queued with Clear note beside it, and
  the receipt afterwards.
- When the run ends, Pause and Stop go away and a summary takes the field's
  place: how it ended as the headline (Run complete, Run stopped, Turn limit
  reached, Run ended), the turn count and the clock, and the last note's
  record. New session is the one button at the foot; the context
  row above the hairline keeps the run's shape and options until it is pressed.
- The head is the same two rows in every state. Its turn line keeps to the
  count once the run is over ("Run complete · 6 turns"); the clock and the
  ending are the summary's.

## Stop, three weights

| Weight | What it is | Why, or why not |
| --- | --- | --- |
| A · Outlined circle (shipped) | The primary's size, paper with the chip edge, stop glyph | Reads as Pause's unfilled twin; distinct from the option chips at a glance. |
| B · Bare glyph | The chips' idiom: glyph only, hover wash | Quietest, but the chips are toggles, so it can read as an option; easy to miss in a hurry. |
| C · Word capsule | "End", the old New session capsule | Says what it does, but the word outweighs the glyph beside it and competes with Clear note. |

Switching between them is a change to `stopButton` in PerchComposer only.
