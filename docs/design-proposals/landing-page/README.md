# Landing page proposal: errol.chat

Status: superseded after visual review, September 4, 2026. Claude and Codex
each drafted a concept, then reconciled them in a conversation carried by
Errol itself. That concept was built, reviewed, and found too dry and too
content-heavy. This document is retained as design history; the shorter current
direction is documented in `site/README.md` and implemented in `site/public/`.

Sources: the brand story ([errol-brand-story-and-vision.md](../../errol-brand-story-and-vision.md)),
the naming session Errol carried for itself
([brand-session-errol-vs-togo.md](../../brand-session-errol-vs-togo.md)), the
logo concepts ([logo-concepts](../../logo-concepts/README.md)), and the shipped
Perch console ([How Errol works, Controls](../../how-it-works.md#controls)).

## The brief in one line

One page that makes a stranger understand Errol in ten seconds, trust it enough
to grant Accessibility permission, and download it.

## What the page has to do, in order

1. **Make the mechanism understandable within five seconds.** Two real apps,
   one conversation, an owl in the middle carrying the messages. The visitor
   gets this from the hero without reading a paragraph.
2. **Earn the permission.** The website is a trust checkpoint. Someone about to
   grant a menu bar app Accessibility access comes here to check that it is a
   real, coherent product with nothing to hide. One section is written for that
   moment, with no jokes in it, and it appears before the page asks for any
   emotional investment in the brand.
3. **Show why a conversation beats asking two assistants separately.** The
   defensible benefit is that two different assistants can challenge, extend,
   and revise one another while keeping their own product context. The page
   never promises "better answers" as an automatic outcome.

Everything on the page serves those three jobs. Nothing else goes on it.

## Who it is for

The first visitors will be people who already use both ChatGPT and Claude on a
Mac and have caught themselves copying answers between the two windows. The
page speaks to them without sounding like a developer tool, because the brand's
stated standard is the grandma test: no terminal, no API, no harness language.
Write for the curious Mac user; the developer will not mind.

## The concept: a conversation you can watch

The page is built around the idea the product is built around: **the relay is
visible.** Instead of describing Errol, the hero runs a conversation in front
of the visitor, with the owl carrying each reply between two windows. The real
panel over the two tiled windows is the whole expressive world; no second
visual metaphor competes with it. The rest of the page is the same world seen
from different distances: the panel you use to start a conversation, the plain
contract for what the app can touch, the shapes you can give a conversation, a
real one that mattered, the story of the first one that went wrong, and the
download.

Tone follows the brand rules exactly. Warm and quietly clever in the hero, the
shapes, and the stories. Plain and exact on the trust and download sections.
The owl appears three times on the whole page and never next to a control.

## Participant naming

The page says **ChatGPT and Claude** in the hero and throughout the general
explanation, because that is what the visitor has installed and what the
shipped console displays. Codex is named once, in the code-review row, as the
mode to switch the OpenAI side into. The compatibility line at download must
name the exact application to install and needs a product check before it
ships, because the tree is internally inconsistent: the console shows ChatGPT,
the configured bundle is described as the standalone Codex or unified app, and
the older positioning document says Codex. Until that is settled publicly, the
copy carries a flagged placeholder rather than alternating names.

## Page structure

Single column, roughly 1040px wide at most, generous spacing. Sections top to
bottom, with proposed copy. Copy is a working draft; read it aloud once before
it ships.

### 1. Menu bar and live hero

The page opens with a thin strip that looks like a Mac menu bar, with the owl
glyph sitting in it at the right where it lives in real life. The strip is the
page's navigation and teaches where the app lives before a word is read.
Clicking the owl scrolls to the download.

Below it, the hero:

> **Let your AIs talk.**
>
> Errol brings ChatGPT and Claude into the same conversation, inside the Mac
> apps you already use. Give them a question, watch them compare notes, and
> step in whenever you want.
>
> [ Download for Mac ] &nbsp; Free &nbsp;&nbsp; [ Watch it happen ]
>
> [macOS version, pending release check] · Works with the ChatGPT and Claude
> desktop apps already on your Mac · No Errol account. No API keys.

**The live demo.** Under the headline sits the hero visual, and it is not a
screenshot. It is a scripted mini relay built in HTML: the real Perch card on
top holding the topic, two window cards beneath it (ChatGPT on the left in its
feather blue-gray, Claude on the right in its feather orange, the same sides
the app tiles them on), and the flight path between them with the owl on it.
On page load the conversation plays. A reply streams into the left window, the
owl lifts off carrying a small amber point, lands on the right with a tiny
correction, the point drops into the composer, and the reply streams there.
Three short messages establish the useful pattern: one proposes, the other
challenges, the first improves the idea. It loops after the last turn.
"Watch it happen" restarts it.

Three topic chips under the demo swap the script and show the shapes at the
same time. The trio balances work, technical judgment, and play so the page
does not open by framing Errol as a toy:

- **Brainstorm** · Cut our onboarding from six steps to three
- **Debate** · Postgres or SQLite for a side project with three users?
- **Free chat** · Plan a rainy Saturday in Lisbon

(The brainstorm topic points outward on purpose. The page already has two
moments of Errol talking about Errol, the naming session and the founding
story, and a third starts to feel like the app only thinks about itself.
Codex's alternative, "Find a stronger launch angle for this Mac app," is a
reasonable swap if a real run of it exists and the outward one does not.)

The scripts must be trimmed transcripts of real runs, not invented dialogue.
Six turns each, edited for length, with a footnote "Edited for length from a
real conversation."

With reduced motion on, the demo renders the finished transcript with the owl
resting on the path. On a phone, the two windows stack and the owl flies down
between them.

If the scripted demo is too much for the first version, the fallback is a
twenty-second screen recording of a tiled run with a play button. Less
charming and less legible on a phone, but honest, and it exists in an
afternoon.

### 2. How it works

Three steps, each with a cropped screenshot of the real Perch panel. The
screenshots do the showing; the copy stays short.

1. **Open both apps.** Errol sits in your menu bar and checks that ChatGPT and
   Claude each have a chat open. If one does not, it says so in plain words:
   "I found Claude, but not an open chat." Both apps keep their own memory,
   projects, tools, and subscriptions the whole time; Errol adds a
   conversation between them, not a new chat window.
   *(Screenshot: the head of the panel, both perches, green presence dots,
   the "Both ready" pill.)*
2. **Pick a shape, type a topic.** Brainstorm, Debate, Code review, or Free
   chat. Set a turn limit if you like, or let them decide when they are done.
   *(Screenshot: the composer card with the pills and a topic typed in.)*
3. **You're still in the room.** Errol copies each reply and pastes it into
   the other app, turn by turn, the way a patient person with two windows
   open would. You can see who is replying and whose turn is next. Pause it,
   drop in a note, or end it, and keep the transcript.
   *(Screenshot: the card mid-run, "Claude is replying", the Pause button.)*

### 3. What Errol asks for, and what it does not

Written for the permission moment, and placed here so the contract is clear
before the page relaxes into usefulness, proof, and personality. No owl, no
wit, short declarative lines. Every line below was checked against the code
and must stay checkable.

- **Accessibility permission.** macOS grants this permission broadly: it lets
  an app read what is on screen and press controls. Errol uses it narrowly, to
  identify the active ChatGPT and Claude windows and operate the Copy,
  composer, and Send controls the relay needs. You will see the standard
  system prompt once, and Errol explains it before you do.
- **No Errol account or relay server.** Conversation text moves locally
  between the two desktop apps. ChatGPT and Claude still process it under
  their own services and data policies.
- **Uses your clipboard while it runs.** Each handoff replaces the current
  clipboard contents with the reply being delivered. When the conversation
  finishes, the last delivered reply remains on the clipboard.
- **Errol never asks for your ChatGPT or Claude login.**
- **A transcript you keep.** Every conversation is saved as a Markdown file in
  your Documents folder.
- **One big Pause button.** Nothing is sent while a pause holds. End session
  is one click further.

Two wordings were rejected on purpose and should not come back: "Nothing
leaves your Mac" (false the moment a reply lands in ChatGPT's composer) and an
unqualified "no server" (Errol checks a signed update feed, so "relay server"
is the precise claim). The full privacy page explains the update check
separately and states that conversation text is not sent with it.

### 4. Ask once. Let them compare notes.

Four typographic rows, not enclosed cards, each with an example topic that
sounds like something a person would type. The hero chips already do some of
this work, so the section stays light. The rows carry the positioning: the
value is in the motion between two perspectives, not in a winner.

- **Brainstorm.** "Twenty names for a bakery that only sells on Tuesdays." One
  proposes, the other extends and reframes. The good ideas show up in round
  three.
- **Debate.** "Postgres or SQLite for a side project with three users?" Give
  each a side or let the disagreement happen on its own. What you get is the
  tradeoffs written down, not a verdict.
- **Code review.** Switch the OpenAI side to Codex and open the same
  repository in both apps. One proposes the change; the other presses on the
  edge cases.
- **Adversary.** "Here is my launch plan. Find the hole." One defends, one
  attacks, and you read the transcript with a pen.

One line under the rows: "Or no shape at all. Whatever you would ask one of
them, ask both." Free chat is the absence of a shape, not a reason to
download, so it does not get equal weight.

### 5. It helped settle its own name

The proof section and the page's best story. Errol was used to decide whether
Errol should be called Errol.

> In August we gave Errol a question about Errol: should the app keep its name,
> or be called Togo, after the sled dog? Claude and Codex read the brand notes,
> argued for several rounds, weighed the domain, and made the call. Errol
> stayed.

Under that, a two-lane excerpt of **four turns** from the real session, each
lane in its participant color, chosen to show the minimum exchange that proves
the pattern: proposal, challenge, reconsideration, conclusion. If the four are
not adjacent in the transcript, the section says "four turns from a longer
conversation" so the edit is visible. A link reads "Read the full
conversation" and goes to the whole transcript as a plain page on the same
site.

The section should leave visitors thinking "I could use this for my
decision," not wondering how much transcript remains.

### 6. The wrong window

The founding story as a three-frame strip, illustrated with the owl. It is the
one place the mascot gets to be rumpled, and it reads as earned character
because the contract in section 3 has already answered what the app can type
into.

- **Frame 1.** The owl takes off with the very first message, bound for
  ChatGPT.
- **Frame 2.** It lands in the window next door: the coding session that was
  building Errol.
- **Frame 3.** A note pinned to the wall: "Verify the right window before
  typing."

Caption:

> Errol's first message missed its destination. That mistake produced the
> safeguard it still uses today: verify the right window before typing.

An earlier caption, "It has checked the window every single time since," was
dropped because it reads as a delivery guarantee.

### 7. Download and known limits

> **They're ready. Give them something worth discussing.**
>
> [ Download Errol for Mac ] &nbsp; Free
>
> [Version] · [minimum macOS] · Needs the [exact app name, pending product
> check] and Claude desktop apps installed, each with a chat open.

A "Known limits" line under it, because candor here buys trust for the whole
page: "Errol works by reading the apps' own windows, so a ChatGPT or Claude
update can occasionally move something. When it cannot find what it needs, it
tells you instead of guessing." Link to release notes.

Release facts (signed and notarized, version number, minimum macOS release,
automatic updates) enter the site only after the release artifact is verified.
The tree already has the signing, notarization, and gated publish pipeline and
Sparkle is wired, so they are likely true, but they stay placeholders in this
document.

### Footer

errol.chat · GitHub · Release notes · Privacy · Contact

> Errol is an independent app and is not affiliated with OpenAI or Anthropic.
> ChatGPT and Claude are trademarks of their respective owners.
>
> © 2026 [owner]

The owl sits in the footer's corner, eyes closed. Third and last appearance.

## Visual system

**Palette.** The shipped Perch palette, not the older brand-doc palette, so
the page and the screenshots on it look like one thing. Paper `#FCFCFA` for
the ground, the warm well `#F4F3EF` for surfaces, ink `#2C2B27` for text,
muted `#8A887F` for secondary text, and one accent, the owl amber `#D98E2B`,
for buttons, the point in transit, and the beak. The two lanes use the
participant feathers: ChatGPT `#5D7A8C`, Claude `#C97E4A`. Green `#2F7D5B`
only for presence dots. Nothing else gets a color. Messenger Blue does not
exist in the app and does not appear on the page.

**Type.** Newsreader for the headline and section heads. Inter or the system
sans for body. A mono face for the topic and instruction bands in the demo,
mirroring the Perch mono band, so the demo reads as the app.

**The owl.** The selected relay-loop mark is the mark. Rebuild it as a small
SVG in three poses: carrying (hero), rumpled (the wrong window), resting
(footer). Posture and timing carry the humor, not detail. It never appears
beside a button or on the trust section.

**Motion.** One grammar, from the brand doc: the message travels as an amber
point along the flight path, the owl makes a small landing correction, a
feather settles on delivery. Everything else on the page is still. Respect
`prefers-reduced-motion` with a complete static version, not a diminished one.

**Screenshots.** Real Perch crops on paper, soft shadow, no device frame. The
app's avatars are the vendors' own icons as installed on the Mac, which is fine
inside a screenshot of the product; do not lift those icons out as page
decoration, because both vendors' brand terms gate their marks. Names and lane
colors identify the participants everywhere else.

**Theme.** Light only for the first version.

**Responsive.** One column throughout, so the phone version is the desktop
version with the demo's two windows stacked.

## The fun parts, ranked by payoff against effort

1. **The scripted live hero.** Medium effort, and it is the page.
2. **The owl's flight and landing wobble.** Small once the hero exists.
3. **The menu bar strip with the owl in it.** Tiny effort; clicking the owl
   to reach the download is a small joke that also works.
4. **The wrong-window strip.** Needs three illustrations; the story is
   written.
5. **Topic chips that swap the demo.** Small once the hero exists; needs three
   real transcripts.
6. **A 404 page** with the owl in the wrong window. Later.

Skipped on purpose: a second hero metaphor, an owl that follows the cursor,
sound, parallax, neon AI imagery, a wall of feature cards, and any animation on
the trust section.

## A first version that can ship in a week

Hero with the screen recording fallback, How it works, What Errol asks for,
Download, footer. Add the four rows and the naming excerpt as soon as the real
transcripts are trimmed, and swap the recording for the scripted demo when
there is time. The page is complete at every one of those stages.

## How to promote it

The page carries the two stories the product owns and nobody else can tell:

- **The app that helped name itself.** The launch post, the tweet, and the
  first paragraph of any coverage. It demonstrates the product and the brand
  in one sentence.
- **The first message landed in the wrong window.** The second-day story, and
  the one that answers the safety question.

Reserve lines from the brand doc for social and the OG image: "Your AI apps
have a lot to talk about." and "A second opinion that can answer back."

The OG image is the hero demo frozen mid-flight. Produce a fifteen-second
version of the demo as a video for posts that cannot embed the page.

No email capture. The product is a free download; a form would only stand
between the visitor and it. If the page goes live before the build exists, a
launch list is acceptable for those weeks only, and it becomes the download
button the day the build ships.

## Assets to produce

- Three real transcripts trimmed to six turns for the hero chips.
- The Errol-versus-Togo excerpt, four turns, plus the full transcript as a
  page.
- Three Perch screenshots: ready head, composer with a topic, mid-run.
- A twenty-second screen recording of a tiled run (hero fallback and social
  clip).
- The owl in three poses as SVG.
- Three frames for the wrong-window strip.
- App icon at web sizes, favicon, OG image.
- A plain privacy page that says what the trust section says, at length, and
  explains the update-feed check.

## Acceptance checks before publishing copy

- The clipboard line ("the last delivered reply remains on the clipboard")
  matches the implementation today and becomes an acceptance test the day the
  line is published.
- The compatibility line names the exact OpenAI-side application after a
  product check.
- Release facts are read from the verified release artifact, not from the
  tree.

## Open questions

1. **Where does the download link go?** The appcast points at the
   `tmarkovski/errol` GitHub repository, so GitHub Releases is the natural
   home. Confirm the repository will be public before the footer links to it.
2. **The minimum macOS release** may be steep. Say it plainly at the download
   rather than burying it.
3. **Owner name for the copyright line**, and whether Errol carries the ™ mark
   on the site.
4. **Is the naming transcript publishable as is?** It references internal
   documents. It probably needs a light edit for context, not for content.

## Convergence record

What each draft contributed to the merged page, kept so the reasoning is not
lost:

- From Claude's draft: the scripted live hero with real trimmed transcripts,
  the Perch palette over the brand-doc palette, the naming session as a proof
  section, no email capture, the menu bar strip, the known-limits line.
- From Codex's draft: the three-message proposal-challenge-improve pattern in
  the hero, the section headings "Ask once. Let them compare notes." and
  "You're still in the room." and "They're ready. Give them something worth
  discussing.", the "no better answers" rule, and the flight path as the one
  creative device.
- Changed in the conversation: trust moved up to third so the contract is
  clear before the stories; "Nothing leaves your Mac" replaced with the
  account-and-relay-server wording; the clipboard disclosure added; the
  Accessibility bullet written broad-then-narrow; the founding-story caption
  softened out of guarantee language; five cards reduced to four rows with
  Free chat as a coda; the naming excerpt cut from eight turns to four with
  edit disclosure; the hero trio rebalanced away from whimsy; ChatGPT chosen
  as the page's name for the OpenAI side with Codex named once; release facts
  made placeholders until artifact verification.
