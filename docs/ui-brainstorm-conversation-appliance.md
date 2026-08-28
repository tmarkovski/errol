# Errol UI concept: the conversation appliance

**Internal design record · August 28, 2026**  
**Status:** Converged concept direction, not a finished specification

> **Errol is a compact conversation appliance: two abstract participants, one visible route, and one small courier carrying messages between them.**

This document records a multi-round agent-to-agent UI brainstorm about how Errol should look and feel. The session deliberately spent three rounds per participant diverging before it evaluated or narrowed the ideas. It ended in a mutual shortlist.

The central design problem was to combine the personality and irregular silhouette of Winamp or classic Windows Media Player with a calm, modern interface that remains pleasant during long conversations. The conclusion was to put **nostalgia in the chrome and calm in the content**.

---

## 1. Converged direction

The working concept is:

## Errol, the conversation appliance

Errol is not a themed two-column chat window. It is one compact, tactile object that can expand from a menu bar signal into a readable transcript.

Three metaphors work together:

- **Courier:** Errol supplies character and performs discrete message handoffs.
- **Visible route:** a cable, flight path, or light trace continuously shows direction and conversational state.
- **Instrument deck:** physical controls, gauges, lamps, counters, and an irregular chassis provide the nostalgic appliance quality.

Each metaphor has one job. The participant glyphs show continuous thinking; Errol appears for discrete delivery; the instrument states explain what the system is doing. This division keeps the mascot useful without turning it into a constantly animated assistant.

### The four interface scales

The interface should feel like one object across four levels:

1. **Menu bar:** a tiny, glanceable status glyph.
2. **Floating head unit:** an irregular, always-available Winamp-like object that shows the exchange at a glance.
3. **Instrument panel:** the head unit expands to reveal conversation controls, gauges, and status.
4. **Transcript:** a calm, conventionally resizable reading surface.

Elements should migrate between scales rather than being replaced. The menu bar glyph becomes the floating object; its status lights become gauges; its participant glyphs become transcript headers; its delivery route becomes the transcript timeline.

The head unit carries the visual personality. The transcript carries paragraphs. Keeping those responsibilities separate permits a playful silhouette and tactile controls without sacrificing readability.

---

## 2. Launch shortlist

All chassis share one layout, interaction model, semantic state system, and motion grammar.

### Studio — default

- Warm light-gray metal or high-quality matte polymer.
- Precise geometry and restrained industrial-design proportions.
- Dot-matrix or bitmap labels used sparingly.
- A few candy-colored knobs and status controls.
- Modern enough for daily use; characterful enough to be recognizable.

This is the midpoint between a contemporary Mac utility and a nostalgic appliance.

### Night Signal — retro hero

- Smoked or near-black translucent acrylic.
- Phosphor green and warm amber illumination, with red reserved for true failures.
- Hints of internal traces or components beneath the surface.
- Condensed display typography and subtle CRT or fluorescent texture.

This is the strongest descendant of Winamp and classic Windows Media Player and the likely hero treatment for screenshots and launch imagery.

### Candy Relay — playful

- Milky translucent plastic in grape, tangerine, lime, or ice-blue variants.
- Oversized jelly controls and visible construction details.
- Slightly bouncier motion, as though the shell and controls have physical flex.
- Maximum personality for the irregular silhouette.

If launch scope requires a cut, Candy Relay is the first chassis to move to a fast follow. Studio covers everyday use and Night Signal covers the bold retro expression; two polished chassis are preferable to three uneven ones.

### Held in reserve

The brainstorm produced several complete visual worlds that should remain available as future chassis packs rather than competing launch architectures:

- Night-shift telephone switchboard: walnut, Bakelite, brass, cloth cable, paper labels.
- Air-mail paper machine: folded panels, stamps, string, cancellation marks, and delivery tags.
- Arcade service panel: powder-coated metal, illuminated convex buttons, and an attract mode.
- Frosted glass: spectral gradients, caustics, and abstract colored participant fields.
- Cassette dubbing deck: reels, VU meters, record lights, and turn counters.

---

## 3. Signature interaction moments

### Load the machine

The user chooses a conversation shape—brainstorm, debate, interview, review, and so on—with a chunky physical mode dial. The topic appears on a removable label, telegram blank, cassette label, or luggage tag. Configuration should feel like loading an object, not completing a settings form.

### Establish the line

Starting a run illuminates the route from both ends until the signals meet in the middle. A brief modem-inspired handshake can accompany this moment when sound context permits. Frequent runs should use a shortened two-note form so the ritual does not become a toll.

### Deliver the turn

While a participant composes, its abstract glyph supplies continuous, low-attention motion. Once the message is ready, Errol collects it and performs one clear directional delivery. Thinking and sending must remain visually distinct.

### Pass a note

A human interjection is materially different from either participant's messages: a handwritten-looking slip passed under the door or inserted into the route. Errol intercepts it and includes it with the next delivery. The user is visibly leaning into the exchange, not becoming an indistinguishable third model.

### Mutual sign-off

The existing two-sided ending becomes a ceremony. Each participant activates its own sign-off indicator. Only when the second sign-off arrives do the two signals resolve into one chord, complete a seal, and finish the run artifact.

### Deliver the artifact

The completed artifact moves toward the user, breaking the fourth wall for the only time in the run. Depending on chassis, it might be a labeled cassette, stamped telegram, folded arrow, or compact instrument card.

### Put it on the shelf

History becomes a shelf of completed artifacts. Opening one defaults to the calm transcript. A small explicit play control offers a scrubbable real-time replay of the run's choreography for review or sharing.

---

## 4. State language

The UI must communicate observable system state rather than inventing qualities such as model confidence.

| State | Instrument expression | Motion expression |
|---|---|---|
| Idle | ready lamp, resting needles, stable counters | sleeping or waiting Errol; a gently relaxed route |
| Thinking | active participant lamp or gauge | participant glyph breathes, rotates, or pulses |
| Handoff | direction indicator changes | one light pulse or one Errol delivery |
| Waiting | destination lamp armed | Errol perches at the destination |
| Disagreement | participants remain separated; challenge indicator appears | returned parcel, correction ribbon, route tension, or a loose knot |
| Resolved challenge | center alignment increases | knot loosens or parcel is accepted |
| Human interjection | distinct note indicator | physical slip enters the route |
| First sign-off | one side of the completion control activates | first half of the seal appears |
| Mutual sign-off | both completion controls activate | two sounds resolve; artifact completes |
| Recoverable failure | plain-language recovery instruction | mechanical hesitation: returned parcel, jam, or loose connector |

Disagreement is an interesting conversational state, not a system error. It should look lively and unresolved rather than alarming. Avoid relying on red, lightning, or animation alone.

The alignment gauge may show activity, turn direction, an unresolved challenge, and sign-off state. It must not claim to show confidence unless a meaningful underlying measure actually exists.

---

## 5. Motion, sound, and accessibility

### One physical system

Define one shared spring and derive the application's motion from it so every component feels like part of the same object. A chassis may retune the perceived material without changing behavior:

- Studio: controlled with a small amount of overshoot.
- Night Signal: slightly heavier and more damped.
- Candy Relay: lighter and bouncier.

Motion should explain state or reward an important transition. Streaming tokens do not each need an animation.

### Sound follows focus

Offer three sound intensities:

1. Silent visual choreography.
2. Restrained studio clicks and completion cues.
3. Full nostalgic soundscape.

The full soundscape should play only while Errol is frontmost. In the background, use silent status motion and at most one soft completion cue. Significant sounds include the opening handshake, a directional handoff, note insertion, pause detent, and mutual sign-off chord.

### Reduced motion is a complete instrument mode

Reduced motion is not a diminished version of the design. Every state must remain legible through needles, lamps, counters, labels, and restrained opacity changes when travel, particles, and character movement are removed.

Build this state language first. If disagreement cannot be understood on the static instrument panel, an animated knot or weather effect is hiding an information-design problem.

Do not rely on color, animation, or sound as the only carrier of meaning.

---

## 6. Typography and material details

Use three typographic voices with strict roles:

- A bitmap, dot-matrix, or mechanical display face for machine labels and discrete status.
- A contemporary, highly readable sans serif for transcript prose and functional UI.
- A restrained handwritten-feel face only for human interjections.

Mechanical type can reinforce discrete events: the speaker name flips on handoff, the turn counter rolls like an odometer, and the conversation shape appears on a rotating drum.

Subtle, optional patina may accumulate from actual use rather than being painted on at installation: run hours on an odometer, a faint worn pause control, or artifacts becoming slightly handled. It should develop slowly and have an opt-out.

The owl remains an original courier metaphor, not a fantasy costume. Avoid franchise-associated props or visual language.

---

## 7. Build order

Treat implementation order as a design test:

1. Define the semantic state model.
2. Prove every state in the reduced-motion instrument panel using labels, lamps, needles, and counters.
3. Build the calm transcript and artifact history.
4. Connect the four interface scales with one spatial system.
5. Add motion choreography.
6. Add Errol only at discrete handoffs and signature rituals.
7. Polish Studio.
8. Add Night Signal.
9. Add Candy Relay if scope and quality permit.

The interface should still be understandable and enjoyable in plain gray with no mascot animation. Personality should strengthen the product's semantics, not substitute for them.

---

## 8. Divergent territory retained from the session

The following ideas did not become the primary architecture, but remain useful material for later exploration:

- A desktop creature or Tamagotchi-like familiar whose silhouette changes with state.
- A translucent cyber-stereo with stacked Winamp modules and model channel strips.
- A shape-shifting arrowhead whose two wings merge participant streams into a result.
- A two-deck DJ mixer with a leadership crossfader and consensus meter.
- A cassette dubbing deck where reels, VU needles, and stop keys embody turn-taking.
- A pneumatic message tube with capsules proportional to message length.
- A minimal spring-physics cable whose tension communicates cadence and conflict.
- A table-tennis rally where reply latency controls the ball arc.
- Colliding local weather systems that form an aurora in agreement and a pressure front in disagreement.
- A compact pinball route where challenges, retries, and tool calls become alternate paths.
- Overlapping stained-glass thought lenses that form crisp motifs or unstable moiré patterns.
- A telephone switchboard whose extra sockets represent challenge, verification, and synthesis.
- Conversation as manufacturing: every turn modifies a shared physical artifact.
- Idle attract mode as wordless onboarding through a miniature demonstration run.

These concepts are a library of interaction details and potential chassis, not mandates to combine everything. The converged architecture should stay clear.

---

## 9. Decision summary

### Jointly selected

- **Architecture:** Courier Instrument.
- **Scales:** menu bar → floating head unit → instrument panel → transcript.
- **Visual roles:** participant glyphs show thinking; Errol performs discrete delivery; instruments explain state.
- **Launch chassis:** Studio, Night Signal, and Candy Relay if scope permits.
- **Signature moments:** load the machine, establish the line, deliver the turn, pass a note, mutual sign-off, artifact delivery, and the shelf.
- **Design tests:** observable states only, reduced-motion completeness, focus-aware sound, calm transcript typography, and one coherent motion system.

### Deliberately unresolved

- The exact irregular silhouette of the floating head unit.
- Whether the route reads primarily as a cable, flight path, or internal light trace.
- The final form of the center gauge.
- The amount of persistent mascot presence in idle states.
- The representation of run artifacts across chassis.
- Which conversation controls belong in the head unit versus the expanded instrument panel.
- Whether chassis are user-selected globally, associated with conversation shapes, or both.

The next useful artifact is a state-first wireframe showing the same run at all four scales, first in reduced motion and neutral gray, followed by Studio and Night Signal visual studies.
