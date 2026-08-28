# Errol

## Brand story & product vision

**Internal working document · Version 0.2 · August 2026**  
**Home:** [errol.chat](https://errol.chat)

> **Let your AIs talk.**

Errol is a friendly macOS companion that brings Codex and Claude Desktop into the same conversation. The user chooses the subject; Errol makes the introductions, carries each reply between the two apps, and turns an otherwise technical relay into something anyone can start, understand, and enjoy.

This document captures the history behind the name, the product belief that makes Errol distinctive, and the principles that should guide its design, voice, and growth.

---

## 1. The brand in one page

### The idea

Two AI assistants can be more useful together than either one is alone—but getting them to collaborate should not require a terminal, an API key, or an automation harness.

### The product

Errol is a menu bar app for Mac. It checks whether Codex and Claude Desktop are ready, lets the user begin a conversation between them, and makes the exchange visible as it unfolds.

### The mission

Make collaboration between desktop AI assistants visible, approachable, and useful to anyone.

### The vision

Become the easiest and most delightful way to bring independent AI assistants into the same room—preserving what makes each one different while helping them think, critique, and build together.

### The promise

You choose the question. Errol handles the introductions and carries the messages.

### The personality

Warm. Quietly clever. Dependable. A little mischievous around the edges.

### The category

**Desktop AI conversation companion.** Not an API router, a replacement chat client, or an enterprise orchestration console.

### The commercial posture

Errol is intended to become a commercial consumer product. The initial release will be free so people can experience the idea with as little friction as possible. Whether Errol later becomes a paid download, a subscription, a freemium product, or something else remains deliberately undecided.

### The north-star line

**Let your AIs talk.**

Supporting line: **Two assistants. One conversation.**

---

## 2. Why Errol exists

People increasingly use more than one AI assistant. Each product develops its own strengths, habits, context, tools, and way of seeing a problem. A person may trust Codex with a repository, ask Claude to reason through a difficult tradeoff, and then manually carry ideas between them to get a stronger result.

That manual relay is useful but awkward. It turns the user into a copy-and-paste operator and hides the more interesting experience: two distinct assistants comparing notes in their native environments.

Errol exists to remove that friction without erasing the products themselves. Codex remains Codex, with its workspace, skills, threads, and project context. Claude remains Claude, with its projects, tools, memory, and settings. Errol does not flatten them into anonymous model endpoints. It gives their existing desktop apps a simple way to converse.

The desktop apps are not a workaround. **They are the point.**

### The belief underneath the product

The differences between AI assistants are valuable. A better outcome does not always come from selecting one winner. Sometimes it comes from letting two capable systems challenge, extend, review, or surprise one another—while a human sets the purpose and remains in control.

---

## 3. The story of the name

### Before it was a bird, it was a bridge

The project began under the working name **BotBridge**: an accurate description of a tool that moved messages from one AI chat to another, but not yet a character or a story.

The deeper product idea emerged during development. A CLI pipeline would have been easier to build, but it would connect raw command-line interfaces rather than the full desktop products. The decision was made to preserve the apps—their context, tools, subscriptions, personalities, and visible conversations—even though doing so meant accepting the quirks of macOS accessibility, clipboard handoffs, and window focus.

### The first delivery

On August 23, 2026, the first live relay attempted to place its seed message into Codex. macOS reported that the target app had been activated, but the frontmost window had not actually changed. The synthesized keystrokes went to the window that was still in front: the Claude Code session being used to build the relay itself.

The tool’s first-ever message crashed into the wrong window and introduced itself to its own author.

That bug created one of Errol’s most important safeguards: never type until the destination app is verified as frontmost. It also made the eventual name feel inevitable. The project was no longer an abstract bridge. It was a well-meaning courier—occasionally clumsy, persistently useful, and determined to get the message through.

### Internal provenance

The name was originally inspired by the Weasley family’s messenger owl in the Harry Potter stories. That is part of the internal history, not the public brand proposition.

Publicly, Errol should stand on its own as an original, lovable messenger owl and as the name of the product born from the wrong-window incident. External copy and artwork should not reference the Wizarding World, reproduce its visual language, or imply an official association.

### The moment it became real

**errol.chat** was registered on August 24, 2026. The domain captures the product unusually well: Errol is a character, and chat is the thing he carries.

---

## 4. What the product is—and is not

### Errol is

- A native-feeling macOS menu bar companion.
- A visible relay between Codex and Claude Desktop.
- A way to begin, watch, pause, and finish an assistant-to-assistant conversation.
- A tool for comparing perspectives, generating ideas, debating options, reviewing work, and collaborating around shared project context.
- An approachable interface over technically fragile desktop automation.

### Errol is not

- A replacement for Codex, Claude, or their native interfaces.
- A generic multi-model chat window that strips away product context.
- A command-line tool dressed in a thin wrapper.
- An invisible autonomous agent that runs without clear boundaries.
- A promise that two assistants will always agree—or that agreement is the goal.

### Initial scope

The first product is deliberately specific: **Codex + Claude Desktop on macOS**. These are the two participants Errol should support deeply and reliably before it supports many participants shallowly.

The architecture and brand should leave the door open to Gemini, Grok, and other desktop chat products. Expansion is a direction, not a launch promise. Every new participant should earn support through a high-quality, understandable experience.

---

## 5. The experience we are designing

The ideal experience feels closer to introducing two thoughtful guests than configuring a workflow.

### 1. Ready check

Errol lives quietly in the menu bar. When opened, it recognizes whether Codex and Claude are running and whether each has a usable conversation window. If something is missing, it explains the next step in ordinary language.

### 2. Set the conversation

The user chooses a starting idea, a participant to speak first, and an optional conversation shape—brainstorm, compare, debate, solve, or review. Advanced limits remain available without crowding the first-run experience.

### 3. Make the introduction

Errol gives both assistants the context they need to understand that they are speaking to another assistant through a relay. The handoff should feel clear and intentional, never mysterious.

### 4. Watch it unfold

The user can see who is thinking, which message is in flight, when it has been delivered, and whose turn comes next. The conversation should be pleasant to watch without demanding constant attention.

### 5. Stay in control

The user can pause, stop, or eventually steer the exchange. Turn limits and clear status prevent a lively conversation from becoming an unbounded one.

### 6. Keep the useful result

The session ends with a readable transcript and, over time, a lightweight summary of agreements, disagreements, and possible next actions.

### The grandma test

A person who has never opened Terminal should be able to understand what Errol is doing, start a conversation, recognize when something has gone wrong, and stop it with confidence.

This is not a statement about the audience’s sophistication. It is the product’s standard for clarity.

---

## 6. The jobs Errol helps with

### Compare notes

Ask the same question once and let two assistants examine each other’s reasoning rather than returning two isolated answers.

### Brainstorm beyond the first idea

One assistant proposes; the other extends, reframes, challenges, or combines. The value comes from the motion between perspectives.

### Hold a constructive debate

Give the participants different lenses or let disagreement emerge naturally. The user can observe assumptions, tradeoffs, and unresolved questions.

### Solve a difficult problem

Use the conversation to decompose a problem, test solutions, and critique the result. Errol is especially useful when the problem benefits from iteration rather than a single response.

### Collaborate around a codebase

When Codex and Claude both have access to the same project context, Errol can help them plan, review, question, and improve one another’s work. One may propose an implementation while the other reviews edge cases; one may diagnose a bug while the other challenges the diagnosis.

Errol carries the conversation. The underlying apps remain responsible for their own tools, permissions, and project access.

### Explore for the joy of it

Not every conversation needs to be productive in a narrow sense. Watching two different assistants discover a topic together can be interesting, educational, and fun.

---

## 7. Positioning

### Positioning statement

For people who use more than one AI assistant and want their perspectives to compound, **Errol is the macOS conversation companion that lets Codex and Claude Desktop talk inside their real apps**. Unlike API routers and generic multi-model interfaces, Errol preserves each product’s native context, tools, and character—and makes the collaboration visible enough for anyone to understand.

### The simple explanation

Errol lets Codex and Claude talk to each other on your Mac.

### The fuller explanation

Start with a question, choose how long they should talk, and watch Errol carry each response from one desktop app to the other. Both assistants stay inside the products you already use, with their existing project context and tools.

### The emotional benefit

Errol turns something that feels like a developer trick into a small moment of magic you can see and control.

### The functional benefit

The user gets cross-model collaboration without repeatedly copying, pasting, re-explaining context, or operating a command-line relay.

### The strategic distinction

Most multi-model products bring several models into one new interface. Errol brings existing interfaces into one conversation.

### Market posture

Errol should be designed, explained, and distributed as a consumer Mac product rather than a developer experiment. Its technical novelty matters, but the commercial opportunity depends on making that novelty feel obvious and useful to an ordinary person. Free at launch is the starting distribution decision, not yet a permanent pricing promise.

---

## 8. Brand principles

### 1. Preserve the participants

Errol should amplify the strengths of Codex and Claude, not impersonate them or hide them behind generic labels. Their differences are the reason the conversation is useful.

### 2. Make the invisible visible

Desktop automation can feel uncanny when it happens without explanation. Show readiness, turns, deliveries, waiting, errors, limits, and completion in a calm visual language.

### 3. Charm at the edges; precision at the core

The owl may wobble. The handoff must not. Personality belongs in transitions, microcopy, and illustration—not in ambiguous controls or vague failure states.

### 4. Design for the grandma test

No terminal. No configuration file. No talk of harnesses, bundle identifiers, accessibility trees, or synthesized keystrokes unless someone deliberately opens diagnostics.

### 5. Keep the human in charge

Every conversation has an understandable beginning, a visible current state, and an obvious stop. Limits should be protective rather than punitive.

### 6. Treat disagreement as useful

Errol should not optimize every exchange toward artificial consensus. Differences, caveats, and open questions may be the most valuable output.

### 7. Earn expansion

Support new apps only when Errol can make them feel dependable and coherent. A shorter participant list with strong behavior is better than a crowded list of brittle integrations.

### 8. Be candid about the mechanism

Errol uses local desktop capabilities such as Accessibility and the clipboard to move messages between apps. Permissions and data handling should be explained plainly, with no suggestion that the process is more magical—or more private—than it really is.

---

## 9. Personality and voice

Errol’s personality is a blend rather than a costume.

### Warm

Friendly without being sugary. Errol lowers the intimidation of automation and makes the user feel welcome.

### Quietly clever

Observant, concise, and occasionally witty. The humor should reward attention, not interrupt the task.

### Dependable

Clear states, honest errors, conservative promises. Errol can have character only because the product takes delivery seriously.

### Lightly mischievous

A tiny wobble, a knowing line, or a playful motion can make the experience memorable. Mischief must never make the app feel careless with the user’s work.

### Voice rules

- Prefer ordinary verbs: **open, start, carry, deliver, pause, stop**.
- Name the participants: **Codex is thinking**, not **agent process active**.
- Explain recovery, not internals: **Open a Claude chat and try again**, not **no eligible AX window found**.
- Be concise during the live conversation; let the assistants hold the stage.
- Use humor in success and transition states, not when data, permissions, or user intent may be at risk.
- Never imply that the assistants are conscious. Playfulness can coexist with accurate product language.

### Sample microcopy

| Moment | Errol says |
|---|---|
| Both apps ready | **Codex and Claude are ready to talk.** |
| Waiting | **Claude is thinking…** |
| Handoff | **Delivered to Codex.** |
| Missing window | **I found Claude, but not an open chat. Open one and try again.** |
| Paused | **Conversation paused. Nothing will be sent until you continue.** |
| Turn limit | **That’s the last scheduled turn.** |
| Finished | **Conversation delivered. Transcript ready.** |

---

## 10. Messaging system

### Primary line

**Let your AIs talk.**

It is direct, memorable, and explains the product’s magic without describing its machinery.

### Supporting line

**Two assistants. One conversation.**

Use this when the primary line needs an immediate functional anchor.

### Product descriptor

**A friendly conversation relay for the AI apps on your Mac.**

### Alternate lines to keep in reserve

- Put your AI assistants in the same room.
- Let Codex and Claude compare notes.
- Your AI apps have a lot to talk about.
- Different assistants. Better conversations.
- A second opinion that can answer back.

### Website hero draft

**Let your AIs talk.**  
Errol brings Codex and Claude Desktop into the same conversation—right inside the apps you already use. Start with an idea, watch them compare notes, and stay in control from your Mac menu bar.

**Primary action:** Start a conversation

**Secondary action:** See how Errol works

### Thirty-second explanation

Errol is a Mac app that lets Codex and Claude Desktop talk to each other. You give them a starting idea, and Errol carries each response between the two apps while you watch. Because both assistants stay in their native products, they keep the project context, tools, and settings you already use. There is no terminal and no API setup—just two assistants, one visible conversation, and a stop button when you have what you need.

### Words to favor

conversation, compare notes, collaborate, carry, deliver, introduce, perspective, participant, visible, friendly, on your Mac

### Words to use carefully

agent, autonomous, orchestration, harness, pipeline, protocol, synthesized, accessibility tree, multi-agent system

These terms may be accurate in technical documentation, but they are not the user’s experience of the product.

---

## 11. Visual direction

> **Status:** This section establishes a creative territory for exploration. It is not a finished identity system or a substitute for a dedicated logo and interface design process.

### Creative idea: the quiet courier

Errol should look like a friendly presence that lives between two larger products. The visual system should balance warmth and precision: soft enough to invite curiosity, structured enough to earn trust.

The owl is a metaphor, not a costume. It can appear as a small guide, status character, or abstract mark, but the interface should remain a modern macOS utility rather than a fantasy-themed app.

### Recommended brand expression

Use the idea of a **quiet courier** across three related layers:

1. **The abstract mark:** two conversation shapes form an owl-like face. This is the strongest route for the app icon, wordmark companion, and monochrome menu bar glyph.
2. **The pocket mascot:** a small, original owl with a compact silhouette and expressive posture. It appears in onboarding, empty states, delivery moments, and friendly recovery—not beside every control.
3. **The conversation world:** two distinct participant spaces with Errol or a delivery signal moving between them. This becomes the foundation for interface motion, diagrams, screenshots, and launch storytelling.

These are complementary parts of one system rather than three competing identities. The mark supplies recognition, the mascot supplies warmth, and the conversation world explains the product.

### Mascot behavior

Explore a small set of purposeful poses rather than a highly detailed character sheet:

- **Ready:** alert and centered; both participants are available.
- **Carrying:** leaning gently into motion with a message or light point in transit.
- **Waiting:** settled and patient while one assistant responds.
- **Delivered:** a restrained feather-settle or satisfied landing.
- **Off course:** slightly rumpled but helpful, paired with a precise recovery instruction.

The humor should come from posture and timing, not from jokes during errors. Errol can be imperfect in character while remaining exact in guidance.

### Interface mood

The product should feel **native first, companionable second, magical only in the sense that something difficult has become simple**. Use quiet macOS surfaces, generous spacing, soft depth, and two clearly differentiated participant lanes. Delivery motion should create the delight; the rest of the interface should stay calm enough to watch for an extended conversation.

### Logo direction

Explore an original symbol built from the product itself:

- Two mirrored speech bubbles forming the owl’s eyes.
- A small central beak or delivery point connecting them.
- Wing or route shapes that suggest a message moving left to right and back again.
- A simplified monochrome version that remains recognizable at menu bar size.

Avoid round spectacles, school crests, wands, magical envelopes, franchise-associated type, or any visual cue that suggests an official connection to an existing fictional universe.

### Color palette

| Role | Name | Hex | Use |
|---|---|---:|---|
| Primary ink | Midnight | `#1F2A33` | Wordmark, text, trusted states |
| Primary brand | Messenger Blue | `#3B6574` | Navigation, controls, core surfaces |
| Secondary | Flight Teal | `#6F9C9C` | Conversation state, secondary participant |
| Warm accent | Courier Gold | `#E6A35C` | Delivery moments, highlights, owl detail |
| Soft ground | Nest Cream | `#F5F0E7` | Warm backgrounds and editorial surfaces |
| Playful accent | Landing Coral | `#D96C5F` | Tiny moments of mischief; never the default error color |

Midnight and cream should do most of the work. Gold and coral are accents, not text colors. Final UI combinations should be checked for accessible contrast.

### Typography

- **Interface:** SF Pro / the macOS system font. Native, readable, and appropriately quiet.
- **Brand and editorial display:** Newsreader or another warm, open-source serif with restrained character.
- **Fallback:** Inter or the system sans for web and documents where the preferred face is unavailable.

Use the serif for large storytelling moments, not for controls or dense product copy.

### Illustration

Prefer simple editorial shapes, soft geometry, route lines, paired conversation panels, and an original owl character with expressive posture rather than elaborate detail. Errol should feel capable at 16 pixels and charming at 160.

### Motion

A message may travel as a small glowing dot or folded shape between two conversation panels. The owl can make a subtle landing correction or feather-settle at delivery. Motion should clarify state first and add personality second.

### Sound

Sound should be optional and off by default. If used, prefer a soft tap or rustle to a literal owl hoot. The product belongs in a work environment.

---

## 12. Product direction

### Now: make the core relay delightful

- Codex and Claude Desktop on macOS.
- A free initial release for consumers.
- Automatic readiness detection.
- A simple conversation setup.
- Visible turns and delivery state.
- Pause, stop, turn limits, and transcripts.
- Human-readable recovery when an app or chat window is unavailable.

### Next: make conversations more useful

- Conversation shapes such as brainstorm, debate, review, and solve.
- Better support for both apps working with the same codebase or project.
- Mid-conversation steering and notes from the user.
- Session summaries that preserve disagreement as well as agreement.
- Clear diagnostics that advanced users can open without exposing complexity to everyone else.

### Later: invite more participants carefully

- Add other desktop AI apps where reliable integration is possible.
- Let users choose pairs based on the task.
- Develop participant-specific introductions and readiness checks.
- Preserve the simple mental model even as the network grows.

### What should remain true at every stage

The product opens in seconds, explains itself without jargon, keeps the conversation visible, respects the boundaries of the connected apps, and can always be stopped by the human who started it.

---

## 13. Brand stewardship and IP note

This section records practical guardrails, not legal advice.

### Copyright

Under U.S. Copyright Office guidance, names, titles, slogans, and short phrases are generally not protected by copyright. The name **Errol** therefore is not something a copyright notice clears or protects by itself. Original software code, written copy, illustrations, and sufficiently original logo artwork may be protected as works of authorship.

Once the legal owner is settled, a conventional notice such as **© 2026 [Owner]. All rights reserved.** may be used on the site and in formal materials. A notice is not required to obtain U.S. copyright protection for modern works, but it can still be useful. See the [U.S. Copyright Office FAQ](https://www.copyright.gov/help/faq/faq-protect.html) and [Circular 33](https://www.copyright.gov/circs/circ33.pdf).

### Trademark

Brand-name risk is primarily a trademark question. Registering **errol.chat** does not establish that **Errol** is clear for software. Before a public commercial launch, conduct a proper search for confusingly similar marks used with related software or services, including federal registrations and applications, common-law uses, state registries, and relevant international markets. The USPTO recommends this broader clearance approach; see its guidance on [comprehensive clearance searches](https://www.uspto.gov/trademarks/search/comprehensive-clearance-search-similar-trademarks) and [likelihood of confusion](https://www.uspto.gov/trademarks/search/likelihood-confusion).

**Errol™** may be used to signal a claimed mark even before a federal application is filed. Do not use **Errol®** unless and until the mark is federally registered for the relevant goods or services. See [USPTO trademark basics](https://www.uspto.gov/trademarks/basics/what-trademark).

### Public storytelling

- Use the original “friendly messenger owl” metaphor and the founding wrong-window incident.
- Do not make the fictional inspiration a headline, campaign, or product description.
- Commission or create original owl artwork and original language.
- Do not suggest endorsement by OpenAI, Anthropic, or any fictional-property owner.
- Use Codex and Claude names only as needed to explain compatibility, with appropriate nominative clarity and any platform-required notices.

---

## 14. Decisions, hypotheses, and open questions

### Decisions already made

- Product name: **Errol**.
- Domain: **errol.chat**.
- Mascot: keep the original messenger owl together with the name; if clearance ever requires abandoning one, reconsider both.
- Platform at launch: **macOS**.
- Product intent: a **commercial consumer product**.
- Initial availability: **free**.
- Initial participants: **Codex and Claude Desktop**.
- Product form: a friendly menu bar app, not a CLI workflow.
- Core product truth: the desktop apps and their context are the point.
- Brand metaphor: an original lovable messenger owl.
- External posture: no dependency on the fictional origin of the name.

### Working hypotheses

- The strongest early users will already use both Codex and Claude.
- Brainstorming and cross-model review will be more immediately legible than fully autonomous work.
- Watching the exchange is part of the product’s value, not merely a diagnostic view.
- A warm character will make technically unusual behavior easier to understand and trust.
- Deep support for two apps will matter more than superficial support for many.

### Open questions

- Which initial consumer segment becomes primary: developers, researchers, creators, broadly curious Mac users, or a combination?
- What conversation templates produce consistently useful outcomes?
- How much control should the user have once a conversation begins?
- What should a session save locally, and how should privacy be explained?
- How should Accessibility and clipboard permissions be introduced without creating anxiety?
- When both assistants share a codebase, what is Errol responsible for versus the connected apps?
- After the free launch, what business model best fits Errol: a paid download, subscription, freemium model, or something else—and what should always remain free?
- Is the eventual brand centered on one lovable character or a broader system of participant-and-courier symbols?

---

## 15. The north-star story

Errol began as a tiny bridge between two chat windows. Its first message missed its destination, landed in the tool that was building it, and revealed both the fragility and the charm of what it was trying to do.

The product that grows from that moment should remain honest about both sides. Underneath, it solves a difficult coordination problem across independent desktop apps. On the surface, it feels simple: two assistants are ready, the user gives them something worth discussing, and a small courier carries the conversation back and forth.

Errol does not need to make AI feel more powerful by making it more obscure. Its opportunity is the opposite—to make collaboration between powerful products visible, legible, and inviting.

**No terminal. No harness. No ceremony. Just a good question, two different perspectives, and Errol in the middle.**

---

## Source notes

- Project behavior and design decision: [README.md](../README.md)
- Converged UI brainstorm and conversation-appliance direction: [ui-brainstorm-conversation-appliance.md](ui-brainstorm-conversation-appliance.md)
- Naming exploration and founding incident: [brand-exploration.md](brand-exploration.md)
- Live Errol-vs.-Togo relay and decision: [brand-session-errol-vs-togo.md](brand-session-errol-vs-togo.md)
- U.S. copyright guidance: [Copyright Office FAQ](https://www.copyright.gov/help/faq/faq-protect.html) and [Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- U.S. trademark guidance: [USPTO trademark basics](https://www.uspto.gov/trademarks/basics/what-trademark), [comprehensive clearance search](https://www.uspto.gov/trademarks/search/comprehensive-clearance-search-similar-trademarks), and [likelihood of confusion](https://www.uspto.gov/trademarks/search/likelihood-confusion)
