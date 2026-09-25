# Errol landing page

Errol's public landing page, built with React and Vinext.

## Making changes

`app/page.tsx` composes the page sections and connects the demo's playback state
to the background motion. Each section has its own component and stylesheet in
`components/landing/`:

- `site-header.tsx` — navigation and the compact download link.
- `hero-section.tsx` — headline, introduction, and atmosphere.
- `demo-section.tsx` — the walkthrough demo, sized to fit one viewport.
- `demo-comparison.tsx` — the saved comparison of the short film and full walkthrough (currently hidden).
- `how-it-works.tsx` — the three steps.
- `conversation-shapes.tsx` — the Free chat, Brainstorm, and Debate cards with an example prompt each.
- `why-the-apps.tsx` — why Errol drives the desktop apps instead of the API, plus the Accessibility note.
- `in-control.tsx` — pause to steer, end whenever, keep the transcript.
- `faq.tsx` — the four questions people ask before downloading.
- `download-section.tsx` — the closing download section.
- `site-footer.tsx` — the footer and repository link.
- `brand.tsx`, `download-link.tsx`, and `shared.css` — reused brand and button treatments.

Every section carries the `slide` class from `app/globals.css`: one viewport
high with its content centered, and the page snaps to slide starts (mandatory on
every viewport, phones included; a slide taller than the screen stays reachable
because every scroll position it covers counts as a snap position).
The header is fixed, so each slide's top padding is `--header-h`. The closing
section and the footer share one slide.

Keep section copy and styling together when iterating. `app/globals.css` holds
the shared palette, typography, layout helpers, the `.band` section rhythm and
`.band-heading` copy block the sections after the demo share, the `.rise`
scroll-in animation, and motion preferences.
`lib/site-config.ts` is the single place for metadata, release links, and the
minimum macOS version. `hooks/use-landing-motion.ts` owns the decorative pointer
and scroll effects. The demo's scene, player, script, and styling remain isolated
in `components/hero-demo/`. The short video player lives in
`components/short-demo/`.

## Development

```sh
npm install
npm run dev
```

## Build

```sh
npm run build
```

Static output is in `dist/client/`. The page uses React, Vinext, and Base UI.
The interactive walkthrough uses CSS and requestAnimationFrame; the short film
uses a standard HTML video player. There is no animation-library dependency.
Both respect reduced-motion preferences and include playback controls.

The landing page currently shows only the original 34-second walkthrough.
The 10.5-second film and comparison layout are retained for further work but
are not mounted on the page. To bring the comparison back, replace `HeroDemo`
with `DemoComparison` in `components/landing/demo-section.tsx`. The saved layout
places the films side by side on wide screens and stacks them on smaller screens.
The short film shows a prompt entering ChatGPT, a reply moving to Claude, and
two dots carrying Claude's reply and a steering note into ChatGPT together.
Each arrival dissolves into a golden prompt outline. It plays once when visible,
pauses offscreen or in a background tab, and provides native playback controls.
Reduced motion shows its poster until the visitor chooses Play.
The MP4 and poster are in `public/demos/`; the standalone macOS renderer and
regeneration instructions are in `scripts/short-demo/`.

The full walkthrough remains in `components/hero-demo/`.
It opens with a typed introduction, switches from Free chat to Debate, and types
the topic into a simplified composer. The camera pulls back near the end of typing.
Pressing Play shows a click ring, and the transfer dot leaves the typed topic
for ChatGPT's prompt once that window is in front. After delivery, Errol fades out of its setup state and into its running
state with Pause centered in the prompt area. The button does not move or morph.
Pause stays visible during the relay. The returning pointer hovers while the
control expands to “Pause to steer,” then clicks to open the note field.
The relay's transfer dot illustrates automated handoffs the way the app's own
overlay draws them: a small golden dot leaves the finished reply's Copy control
(or Errol's prompt) once the receiving app is in front, arcs to its composer in
about half a second, and dissolves into a bloom as the pasted text lights the
composer's outline. A short, tapered wake follows the dot and catches up with it
as it stops; reduced motion omits the dot and shows only the outline. Each
finished reply's container gains an amber outline as Copy highlights. The mouse
pointer only illustrates the person's setup and steering actions. ChatGPT opens, Claude responds, and ChatGPT begins answering
again before the person intervenes. As “Those features matter” streams, the
person opens the note field and sends their note while ChatGPT is still
typing. The submitted text stays visible with no dot yet. When ChatGPT finishes, its reply and the note are copied
together, and two dots leave the Copy control and the note field at the same
moment. Their separate wakes converge inside Claude's prompt, where both texts
appear together before one message sends. This handoff fits within a 34-second
runtime. The person types at about 32 characters per second and the assistants
stream at about 50, except that ChatGPT's second reply keeps streaming until the
note is sent. Claude's steered reply types in under two seconds and closes the
demo. The uninterrupted first exchange makes it clear that steering is optional. `timeline.js` holds the script and camera
timing; the React component provides the scene and accessible playback controls.
The demonstration starts when visible, pauses offscreen or in a background tab,
and supports pause, replay, and seeking. Reduced motion starts on a completed
response with playback paused. The camera moves once: it opens close on Errol while
the topic is typed and pulls back to the full desktop before Play is pressed.
The relay, the steering note, and both replies play out on the full desktop with
no further camera moves, so Errol and both apps stay visible together.
Narrow containers use closer portrait framing for the opening close-up and the
same desktop view afterwards.
ChatGPT and Claude use their actual app icons from `public/app-icons/`.

## Deploy to Cloudflare

The site is a Cloudflare Worker that serves the static output in `dist/client/`. The GitHub Actions workflow at `.github/workflows/site.yml` is the only deploy path: every push to `main` that touches `site/` builds the site and runs `wrangler deploy`. Do not also connect the repository under the Worker's Build settings in the Cloudflare dashboard, or both systems will deploy the same Worker on each push. If that dashboard integration is ever used instead, it needs a Build command of `npm run build`, because `wrangler deploy` on its own does not build and the assets directory will not exist.

The workflow needs both of these repository secrets and fails if either is missing:

- `CLOUDFLARE_API_TOKEN`: an API token created from the "Edit Cloudflare Workers" template
- `CLOUDFLARE_ACCOUNT_ID`: the account ID shown on the Workers & Pages overview page

For a one-off deploy from a machine that has run `wrangler login`:

```sh
npm run deploy
```

Cloudflare assigns a `workers.dev` address on the first deployment. A custom domain can be attached afterward in the Worker settings.

The demonstration uses simplified interfaces and illustrative dialogue. Download buttons point to `https://github.com/tmarkovski/errol/releases`; change `downloadUrl` in `lib/site-config.ts` when a direct installer URL is available. The minimum macOS version matches the app's current Xcode deployment target (26.4).

The default symbol, two overlapping speech bubbles, comes from `docs/brand/errol-symbol.svg`. The app uses a monochrome template of the same paths in `ErrolSymbol.imageset`, and the demo's menu bar and closing card show the symbol as well. The previous owl assets remain in `public/errol.svg` and `public/favicon.svg`. Product facts were checked against the root README and current Swift configuration.
