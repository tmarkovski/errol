# Errol landing page

Errol's public landing page, built with React and Vinext.

## Making changes

`app/page.tsx` composes the page sections and connects the demo's playback state
to the background motion. Each section has its own component and stylesheet in
`components/landing/`:

- `site-header.tsx` — navigation and the compact download link.
- `hero-section.tsx` — headline, introduction, atmosphere, and the demo.
- `how-it-works.tsx` — the three steps and practical notes.
- `download-section.tsx` — the closing download section.
- `site-footer.tsx` — the footer and repository link.
- `brand.tsx`, `download-link.tsx`, and `shared.css` — reused brand and button treatments.

Keep section copy and styling together when iterating. `app/globals.css` holds
the shared palette, typography, layout helpers, and motion preferences.
`lib/site-config.ts` is the single place for metadata, release links, and the
minimum macOS version. `hooks/use-landing-motion.ts` owns the decorative pointer
and scroll effects. The demo's scene, player, script, and styling remain isolated
in `components/hero-demo/`.

## Development

```sh
npm install
npm run dev
```

## Build

```sh
npm run build
```

Static output is in `dist/client/`. The page uses React, Vinext, and Base UI. All motion is CSS or requestAnimationFrame; there is no animation-library dependency. It respects reduced-motion preferences and includes a pause control.

The hero contains the 57-second Errol demonstration in `components/hero-demo/`.
It opens with a typed introduction, switches from Free chat to Debate, and types
the topic into a simplified composer. The start button keeps its size as it moves
to the prompt area's center and morphs into Pause. The header and participants stay clear.
Pause stays visible during the relay. The returning pointer hovers while the
control expands to “Pause to steer,” then clicks to open the note field.
Errol's owl illustrates automated handoffs: it moves over the prompt, its border
lights up, and the message sends. The owl pulses once over each finished reply
as Copy highlights. A short, tapered amber trail follows the moving owl and
fades as it stops; reduced motion omits the trail. The mouse pointer only illustrates the person's setup and
steering actions. ChatGPT opens, Claude responds, and ChatGPT answers again
before the person intervenes. Their note travels with ChatGPT's reply to Claude;
Claude responds to the new direction, then Errol relays that answer to ChatGPT
for the final turn. The uninterrupted first exchange makes it clear that steering
is optional. `timeline.js` holds the script and camera
timing; the React component provides the scene and accessible playback controls.
The demonstration starts when visible, pauses offscreen or in a background tab,
and supports pause, replay, and seeking. Reduced motion starts on a completed
response with playback paused. The camera pulls back as ChatGPT and Claude start
their opening replies, so the full desktop is visible before each reply finishes.
The return to ChatGPT stays in the full desktop view. After the steering note,
the camera holds the full desktop for the remaining exchange.
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
