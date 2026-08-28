# Errol UI concept: the living canvas

**Internal design record · August 28, 2026**  
**Status:** Converged concept direction, not a finished specification

> **Errol becomes a calm, full-display generative world while it runs: currents show what is happening, motifs show what returns, and an accreting atlas shows what the conversation becomes.**

This document records a second multi-round agent-to-agent UI brainstorm. The first session produced the conversation appliance (`ui-brainstorm-conversation-appliance.md`), whose premise was nostalgia in the chrome and calm in the content. This session deliberately inverted that premise into **calm structure, living canvas**: clean contemporary controls surrounding an expressive canvas-2D world that makes the unattended run worth watching. As before, both participants spent three full divergent rounds before any evaluation, then converged layer by layer.

The framing constraint is specific to Errol: while a run is active the user largely cannot use the machine, so the display's job is to be worth watching from across the room — an ambient installation, not a utility panel containing an animation.

---

## 1. Relationship to the conversation appliance

The aesthetic direction is replaced; the underlying design discipline survives. Carried forward intact:

- The **semantic state table** — thinking, handoff, waiting, disagreement, interjection, sign-off, recoverable failure — as the world-independent list of what must be shown.
- The **migration principle**: elements travel between interface scales rather than being replaced.
- **Reduced motion as a complete mode**, never a diminished one.
- **Observable states only**: the UI never invents qualities such as confidence or agreement strength.
- **Build order as a design test**: if a state cannot be understood in the simplest rendering, animation is hiding an information-design problem.

Retired from the appliance direction: the irregular Winamp-descended head unit, the chassis system (Studio, Night Signal, Candy Relay), physical knobs, gauges, dot-matrix labels, translucent retro plastics, and the skeuomorphic machine-loading rituals. The function of those rituals — starting a run should feel like a deliberate threshold, not clicking Go — survives, carried now by the theater's entry choreography instead of physical dials.

Errol's owl identity survives as a minimal wing/caret gesture during handoffs and as the menu bar glyph, not as a persistent illustrated mascot.

---

## 2. Converged direction

Three decisions define the concept:

1. **The quiet frame.** A restrained contemporary shell — menu bar glyph, compact floating control card, calm transcript and history views — with warm neutral surfaces, sharp typography, generous spacing, soft participant colors, and translucent controls.
2. **The theater.** A fifth interface scale appended to the original four: menu bar → floating control card → panel → transcript → **full-display theater**. The theater is the primary posture of an active run; the controls are the fallback layer.
3. **The Living Atlas.** One layered generative world — current for rhythm, motif for recurrence, archipelago for content — rendered deterministically from the transcript so every run produces a unique, honest, inspectable artifact.

---

## 3. The contracts

Two contracts sit above every layer. Any generative world that implements both is swappable.

### Semantic state contract

The existing state table, re-expressed for the canvas. Every state must be legible in the world, on the status rail, and in reduced motion.

| State | Rail expression | World expression |
|---|---|---|
| Idle | flat resting traces | calm resting field, near-zero render cost |
| Thinking | active lane rises | the composing side's current stirs; pressure gathers before long deliveries |
| Handoff | delivery tick | one directional current crossing; brief wing/caret gesture |
| Waiting | destination lane armed | the receiving side's field visibly ready |
| Disagreement | explicit challenge marker | rough water, fracture, or boundary at the contested region |
| Resolved challenge | marker closes | harbor, bridge, or joined terrain |
| Human interjection | distinct note tick | a stone dropped into the world, permanently and distinctly marked |
| First sign-off | one lane's completion mark | one half of the closing composition settles |
| Mutual sign-off | both marks; run ends | final cadence; the scene contracts into its artifact |
| Recoverable failure | captioned wait segment | honest weather (see §12), never healthy-looking motion |

### Boundary grammar

How the theater is entered, touched, and left:

- **Start** expands from a real interface anchor — the world unfolds from the menu bar glyph or control card, participant colors entering from the actual screen positions of their windows.
- **Human approach** wakes the world before exposing controls. In lean-back mode the cursor fades; moving the mouse sends a disturbance through the world, and controls emerge only near the cursor's resting position.
- **Interjection** leaves a permanent, attributable mark: the user clicks a point in the world, a compact composer opens there, and the sent note drops a stone whose outward wave reaches both participants. The artifact records its coordinates and influence forever.
- **Pause** visibly suspends time: motion decelerates until particles hang, the camera settles, and a translucent plane cures across the canvas. Resume melts it and restores motion from the same geometry.
- **Reclaim** makes the canvas yield spatially — the installation peels back from a screen edge like a membrane, revealing the live desktop. The run continues in a compact floating viewport, pauses, or stops; re-entering theater stretches the membrane back without restarting the narrative.
- **Completion** contracts the living scene into its artifact: the camera frames the finished composition, provenance marks glint, and the artifact shrinks along a continuous path into a shelf card. The desktop returns exactly as it was, with a restrained completion card where the artwork disappeared.
- **Needs you** removes the world's autonomous motion and faces the viewer: currents point outward, the camera backs away, and a centered plain-language prompt appears. The world itself asks for attention; the message stays explicit and accessible.

### Honesty rules

1. **Visual claims derive from inspectable signals.** The renderer works from humble evidence — repeated phrases, semantic similarity, questions, explicit disagreement markers, speaker, message length, turn order, timing — never from an invented theory of the discussion.
2. **Every generated feature can reveal its transcript provenance.** Hover or click any island, fault, motif, or stone and the passages that produced it open. The artifact is an index into the transcript, not merely a picture of it.

---

## 4. The quiet frame

- **Menu bar glyph:** tiny, glanceable status.
- **Floating control card:** conversation shape, topic, participants, run controls.
- **Transcript and history:** calm, conventional, highly readable.
- **Theater:** the full-display world.
- **Status rail in theater:** a thin, mostly hidden strip; only essential state persists until the user approaches (see §8).

No decorative instrumentation. Typography does the labeling; the world does the expressing.

---

## 5. Theater choreography

One continuous spatial take per chapter:

- **Glyph-to-World expansion** for entry; a pulse leaves the menu bar glyph, traces a horizon, and the canvas unfolds from that line.
- **The slow camera** narrates: it drifts toward the composing side before delivery, pulls wide for handoffs, pushes in on a fresh challenge. It never cuts within a chapter — a cut is reserved punctuation for chapter boundaries only.
- **Chapters** are detected from observable phase shifts: the first explicit challenge, an explicit challenge resolving, a sustained topic pivot, a human interjection, or sign-off. Chapter titles are embedded in the world, not full-screen cards. Exactly two full-screen typographic moments exist per run: an opening title while the world builds, and the closing card where the artifact lands.
- **Three-meter mode** is the default posture: color temperature says who is speaking, large slow motion says healthy progress, and one unmistakable peripheral state says "needs you." Lean-in (provenance, fine detail, controls) wakes on approach; no mode toggle.
- **The fireworks budget:** the resting state is genuinely calm, big moments are foreshadowed (pressure gathering during a long compose), and full-screen spectacle is rationed to roughly three moments per run — opening, first substantive challenge, mutual sign-off. Scarcity is what keeps an installation watchable for an hour.
- **Resting heart rate:** calm must be computationally cheap. The resting state renders in almost nothing; expense is spent only where the fireworks budget already permits spectacle. Fans spinning up during idle drift would break the fiction more thoroughly than any visual flaw.

---

## 6. The Living Atlas

One world, three layers, each answering a different question:

| Layer | Question | Source signals |
|---|---|---|
| **Current** | What is happening right now? | turn order, message length, timing, deliveries, waits — primitive relay data only |
| **Motif** | What keeps coming back? | repeated phrases and concepts; a small generative alphabet (arc, bar, dot, loop, notch); recurrence reuses a recognizable glyph, qualification transforms it rather than replacing it |
| **Archipelago** | What is this conversation about? | semantic accretion: recurring themes grow island regions, new directions surface as distant points, synthesis builds harbors and bridges; challenges leave fractures and rough water |

Handoffs travel as currents between regions; the camera has real places to visit; the final artifact is a deterministic map of the run.

### Build order and graceful degradation

The layers are built **currents first, motifs second, accretion last**, and each must make the theater better without depending on the layer above it. This is also the acceptance test — Living Atlas must remain complete at three capability levels:

1. **Currents only:** fully legible live state and a satisfying final flow print.
2. **Currents + motifs:** recurrence becomes visible and audible.
3. **Full Atlas:** content regions accrete only when the evidence supports them.

A failed or low-confidence extraction produces a simpler honest artifact — never invented geography. Content extraction is the most speculative subsystem in the plan; the world must be beautiful and truthful when the extractor finds nothing.

---

## 7. Determinism

The composition is deterministically derived from the transcript. Same conversation, same seed, same artifact. Live physics may vary microscopically during playback — particles may take slightly different paths — but the run always resolves to the same composition. Consequences:

- The shelf becomes a gallery of honest fingerprints.
- Old transcripts can be re-rendered into the visual world retroactively.
- Two runs on the same topic are visually comparable.
- Replay and the shareable timelapse are rendered from data, not screen-recorded.

---

## 8. The Duet Score status rail

The thin status rail in theater is a miniature two-lane trace — one lane per participant. It shows **observable events only**: activity, turn duration, deliveries, waits, interjections, explicit challenge markers, and chapter ticks. No synthesized "divergence" or "agreement" measure may appear unless grounded in an observable signal; otherwise the rail quietly reintroduces the fake gauge this design retired.

The rail migrates across scales: it is the scrubber in replay, the progress strip on the shelf card, and the timeline in the transcript view. One element, three scales.

---

## 9. Artifact, provenance, and the gallery

The final composition is a **clickable run portrait**. Every major feature — island, fault, motif, current trace, human stone — opens the passages that produced it. Human stones remain visibly distinct and equally clickable.

### The rendering contract is versioned

Each artifact is pinned to: transcript, seed, renderer version, extraction/schema version, and the accessibility mode it was rendered under. An app update must never silently repaint the gallery. A **remaster** — re-rendering under a newer renderer — creates a new sibling rendition linked to the original; it never replaces the historical artifact.

### Derived objects

From each artifact Errol can produce:

- A gallery thumbnail.
- The full interactive portrait.
- A chaptered transcript index.
- A short deterministic timelapse (**the Twenty-Second Cut**) — the whole choreography compressed to about twenty seconds, generated from data at any resolution. This is the shareable object.
- A replay using the same seed, scrubbable via the rail.

### The Long Gallery

History is a chronological wall of artifacts — implemented initially as a clean 2D wall/grid, not a navigable virtual room. Deterministic rendering makes it more than storage: runs on the same topic hang as a visibly related series, and comparisons across months or across models become a genre study.

---

## 10. Sound

A sparse generative score, not discrete UI chimes:

- Two restrained tonal beds, one per composing participant.
- State-specific weather texture.
- A tiny motif vocabulary for genuine recurrence. **Audio motifs derive from the same seed and recurrence events as visual motifs** — hearing an idea return and seeing it return are the same fact through two senses.

The three-intensity ladder (silent / restrained / full) and focus-awareness rules carry over unchanged. Distinct cues exist for: opening handshake, first substantive challenge, human stone, needs-attention, and the mutual sign-off cadence. Ordinary handoffs stay quiet enough that a long run never becomes metronomic.

---

## 11. Reduced motion: Still-Life Theater

Reduced motion renders the theater as a sequence of deterministic held compositions — a slideshow of paintings, not a degraded animation:

- Slow crossfades between held frames.
- Static currents as directional traces.
- Discrete camera reframing instead of drift.
- Still weather states with explicit captions.
- No traveling particles, elastic motion, or parallax dependency.

Still-Life must generate the same final artifact and provenance as full motion. It is also the design test: if the Atlas cannot hold a wall as a series of stills, the information design is leaning on motion, and that gets fixed first.

---

## 12. Waits and failures: honest weather

Tool calls, retries, backoffs, and long thinks become diegetic weather rather than spinners: fog settles during a long tool call, a retry passes as a squall, a backoff is an ebb tide the world visibly waits on. Two rules:

1. Each observable cause gets its own distinct weather.
2. Lean-in reveals a plain-language caption ("waiting on web search, 12s").

The theater never freezes and never lies about why it is slow. Animation must never make waiting look healthy when the relay is actually stuck.

---

## 13. Worlds are the new chassis

The retired chassis system leaves behind its architectural slot, and alternate worlds fill it. Any world implementing the two contracts is swappable. Launch ships one excellent world; the first alternates are:

- **Living Loom** — a warmer, tactile expression: each response weaves a ribbon into a central composition; challenges pull strands loose; sign-off tightens the weave; the human stone becomes a fastening pin.
- **Argument Strata** — the quiet analytical expression: turns deposit translucent geological layers; challenges create visible faults; resolutions span them; the final cross-section preserves history without replay. The strongest native fit for Still-Life mode; the human stone becomes a vertical core sample.

**Ink Meridian** (calligraphic strokes, seal-stamp sign-off) is reserved as a visual treatment of the motif layer rather than a separate world.

---

## 14. Implementation order

1. Contracts and the observable event schema.
2. Duet Score rail and Still-Life state studies.
3. Deterministic current renderer and the flow-print artifact.
4. Boundary choreography and the one-take theater.
5. Provenance navigation and the versioned gallery.
6. Seeded visual/audio motifs.
7. Semantic accretion into the full Living Atlas.
8. Sound polish, the Twenty-Second Cut, and alternate worlds.

As before, order is a design test: each step must produce a complete, honest experience before the next begins.

---

## 15. Retired, reserved, folded

**Retired:** classic-media-player chrome as the main direction; the chassis system; constant mascot performance; decorative gauges; fake confidence or agreement measurements; token-by-token spectacle; animation that makes a stuck relay look healthy.

**Reserved:** Metaball Dialogue and Idea Ecology — visually lively but less naturally inspectable. **Typographic Murmuration** is reserved specifically as the style experiment for the Twenty-Second Cut: streamed quotes murmuring and settling may be spectacular in twenty seconds and exhausting over an hour, so it is quarantined where exhaustion cannot occur.

**Folded into shared systems:** Halftone Field becomes a rendering style option; Duet Score becomes the status rail and timeline; weather becomes the wait-state vocabulary rather than its own world.

---

## 16. Divergent territory retained

The session generated more than the shortlist. Kept as a library:

**Rhythm worlds:** Signal Garden (two organisms exchanging seeds; interjections as foreign pollen leaving a permanent growth ring); Vector Current (force fields bending particle flows; the frozen field as a long-exposure print); Kinetic Constellation (idea clusters and illuminated routes; revisited ideas orbit closer); Soft-Machine Playground (elastic 2D physics vocabulary); Metaball Dialogue (soft-body fields whose marbling encodes vocabulary overlap, not persuasion); Duet Score (two-lane trace); Halftone Field (interference patterns in a dot grid; the strongest freeze-frame legibility).

**Content worlds:** Semantic Archipelago; Motif Grammar; Prismatic Argument (themes as wavelengths refracted and recombined); Idea Ecology (concepts as species with motion behaviors; abandoned threads settle into sediment); Argument Strata; Ink Meridian; Typographic Murmuration (the animation made of the conversation's own glyphs).

**Theater ideas:** the Slow Camera; chapter detection and cards; the Fireworks Budget; the After-Hours Gallery (an architectural room whose ambient light tracks the real clock, so an overnight run reads nocturnal); Three-Meter Mode; Weather for the Waits; the Score Beneath; Still-Life Theater; the Long Gallery; the Twenty-Second Cut; Resting Heart Rate.

**Boundary ideas:** Glyph-to-World Expansion; the Quiet Threshold (desaturating desktop as falling house lights); Cursor as Visitor; Drop a Stone; Hold the Scene; Peel Back the Machine; Return of the Desktop.

---

## 17. Decision summary

### Jointly selected

- **Premise:** calm structure, living canvas — the installation is what Errol becomes while it occupies the machine; controls are the fallback layer.
- **Contracts:** the semantic state table, the boundary grammar, and the two honesty rules (inspectable signals; universal provenance).
- **Shell:** the quiet frame; five scales ending in theater.
- **Choreography:** one-take camera, embedded chapter titles, two full-screen typographic moments, three-meter default posture, fireworks budget, resting heart rate.
- **World:** Living Atlas — current, then motif, then accretion — with graceful degradation as an acceptance test.
- **Rail:** observational Duet Score, migrating across scales.
- **Artifacts:** deterministic clickable portraits; fully versioned rendering contract; remaster as sibling, never replacement; the Long Gallery; the Twenty-Second Cut.
- **Sound:** sparse seeded score sharing the motif system; intensity ladder and focus rules retained.
- **Reduced motion:** Still-Life Theater, producing identical artifacts and provenance.
- **Alternates:** Living Loom and Argument Strata as the first swappable worlds.

### Deliberately unresolved

- The Atlas's concrete art direction: palette, texture, whether the halftone treatment becomes its default rendering style.
- The precise extraction signal set and its schema.
- Chapter-detection heuristics and their failure modes.
- Whether theater auto-starts on run start or is entered explicitly, and behavior on multi-display setups.
- The motif alphabet's size and transformation rules.
- The composer affordance for Drop a Stone during reduced motion.
- How much of the After-Hours Gallery (room, raking light, clock-tracked ambience) survives into the shipped theater versus remaining a style layer.
- Concrete sound design beyond the structural rules.

The next useful artifact is a currents-only prototype: the deterministic current renderer driving the theater's entry, one handoff, one wait, and completion — first in Still-Life, then in full motion — with the Duet Score rail live throughout.
