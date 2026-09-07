# Errol landing page

Errol's public landing page, built with React and Vinext.

## Making changes

`app/page.tsx` composes the page sections and connects the demo's playback state
to the background motion. Each section has its own component and stylesheet in
`components/landing/`:

- `site-header.tsx` — navigation and the compact download link.
- `hero-section.tsx` — headline, introduction, atmosphere, and the demo.
- `demo-comparison.tsx` — the saved comparison of the short film and full walkthrough (currently hidden).
- `how-it-works.tsx` — the three steps and practical notes.
- `download-section.tsx` — the closing download section.
- `site-footer.tsx` — the footer and repository link.
- `brand.tsx`, `download-link.tsx`, and `shared.css` — reused brand and button treatments.

Keep section copy and styling together when iterating. `app/globals.css` holds
the shared palette, typography, layout helpers, and motion preferences.
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

The landing page currently shows only the original 45-second walkthrough.
The 10.5-second film and comparison layout are retained for further work but
are not mounted on the page. To bring the comparison back, replace `HeroDemo`
with `DemoComparison` in `components/landing/hero-section.tsx`. The saved layout
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
Pressing Play shows a click ring and sends the owl from the middle of the typed
topic toward ChatGPT's prompt. After delivery, Errol fades out of its setup state and into its running
state with Pause centered in the prompt area. The button does not move or morph.
Pause stays visible during the relay. The returning pointer hovers while the
control expands to “Pause to steer,” then clicks to open the note field.
Errol's owl illustrates automated handoffs: it moves over the prompt, its border
lights up, and the message sends. The owl pulses once over each finished reply
as the response container gains an amber outline and Copy highlights. A short, tapered amber trail follows the moving owl and
fades as it stops; reduced motion omits the trail. The mouse pointer only illustrates the person's setup and
steering actions. ChatGPT opens, Claude responds, and ChatGPT begins answering
again before the person intervenes. As “Those features matter” streams, the
camera moves halfway toward Errol while keeping ChatGPT's response in view.
The person opens the note field and sends their note while ChatGPT is still
typing. The camera pulls back as the note finishes, keeping the submitted text
visible with no owl yet. When ChatGPT finishes, two owls appear and copy the
reply and user note simultaneously. Their separate amber trails converge inside Claude's prompt,
where both texts appear together before one message sends. This handoff fits
within a 45-second runtime. The final Claude and ChatGPT replies type in under
two seconds each, bringing the ending forward by five seconds.
Claude responds to the new direction, then Errol relays that answer to ChatGPT
for the final turn. The uninterrupted first exchange makes it clear that steering
is optional. `timeline.js` holds the script and camera
timing; the React component provides the scene and accessible playback controls.
The demonstration starts when visible, pauses offscreen or in a background tab,
and supports pause, replay, and seeking. Reduced motion starts on a completed
response with playback paused. The camera pulls back as ChatGPT and Claude start
their opening replies, so the full desktop is visible before each reply finishes.
The steering view keeps Errol and ChatGPT visible together, including on phones.
After the steering note, the camera returns to the full desktop for the remaining exchange.
Narrow containers use closer portrait framing for typing and the same desktop reveals.
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

The owl comes from the app's menu-bar asset. Product facts were checked against the root README and current Swift configuration.
