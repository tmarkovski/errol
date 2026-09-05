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

The hero contains the 49-second Errol demonstration in `components/hero-demo/`.
It opens with a typed introduction, switches from Free chat to Debate, and types
the topic into a simplified composer. The icon-only start button moves to the
center while the surrounding content blurs, before the camera leaves Errol.
The demo then shows automatic Copy/paste/Send handoffs and a steering
note changing the next response. `timeline.js` holds the script and camera
timing; the React component provides the scene and accessible playback controls.
The demonstration starts when visible, pauses offscreen or in a background tab,
and supports pause, replay, and seeking. Reduced motion starts on a completed
response with playback paused. The camera pulls back as ChatGPT and Claude start
their opening replies, so the full desktop is visible before each reply finishes.
After the steering note, the camera holds the full desktop for the remaining exchange.
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
