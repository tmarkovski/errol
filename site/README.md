# Errol landing page

Errol's public landing page, built with React and Vinext.

## Making changes

The page is two sections: a headline with the download button, and the promo
film under it. `app/page.tsx` composes them; each has its component and
stylesheet in `components/landing/`:

- `site-header.tsx` — the brand, the GitHub link, and the compact download link, fixed at the top.
- `hero-section.tsx` — the pill, headline, introduction, download button, and the gold courier dot that drops toward the film.
- `promo-film.tsx` — the film and its player.
- `site-footer.tsx` — the footer and repository link.
- `brand.tsx`, `download-link.tsx`, and `shared.css` — the brand and button treatments they share.

`app/globals.css` holds the palette, typography, the `.shell` column, and motion
preferences. `lib/site-config.ts` is the single place for metadata, release
links, and the minimum macOS version.

The film is the 23-second promo from `scripts/promo-film/`. The films the page
plays aren't in git: CI renders them from that source and keeps them in R2 (see
Deploy below), and the page expects them in `public/demos/`. To run the site
locally, fetch them with `scripts/promo-film/films.sh fetch` after
`npx wrangler login`, or render them yourself (see that folder's README). Wide screens
get the 16:9 cut. Screens taller than 2:3, which means phones held upright, get
the 9:16 cut, whose captions stay legible at that width; turning the phone
switches cuts in place. The player:

- Plays muted and on a loop once a quarter of it is on screen, and pauses when
  it's scrolled away or the tab is hidden.
- Shows each cut's first frame as its poster, so playback starts without a jump.
- Offers "Play with sound", which starts the film over with sound; with sound
  on it plays once and holds its end card, with Replay in the corner.
- Waits for Play when the visitor prefers reduced motion or the browser refuses
  autoplay, and keeps a text description of the film for screen readers.

The film rises into place as it scrolls in, and the page snaps it just under the
header with proximity snapping; the footer is a snap point too, so it stays
reachable.

The earlier interactive walkthrough, the 10.5-second short film, and the
sections that explained the product at length (how it works, conversation
shapes, why the apps, staying in control, FAQ) are in the git history before
the promo replaced them.

## Development

```sh
npm install
npm run dev
```

## Build

```sh
npm run build
```

Static output is in `dist/client/`. The page uses React and Vinext, with no
animation library: the page's motion is CSS, and the film is an HTML video.

## Deploy to Cloudflare

The site is a Cloudflare Worker that serves the static output in `dist/client/`. Static assets are served before the Worker runs, except the films under `/demos/`: `worker/index.ts` answers their Range requests with 206 Partial Content, which the asset server doesn't do and Safari needs before it plays a video. `wrangler.jsonc` routes `/demos/*` to the Worker, and `vite.config.ts` names `worker/index.ts` as its entry, which hands every other request to vinext. The GitHub Actions workflow at `.github/workflows/site.yml` is the only deploy path: every push to `main` that touches `site/` builds the site and runs `wrangler deploy`. Do not also connect the repository under the Worker's Build settings in the Cloudflare dashboard, or both systems will deploy the same Worker on each push. If that dashboard integration is ever used instead, it needs a Build command of `npm run build`, because `wrangler deploy` on its own does not build and the assets directory will not exist.

The workflow needs both of these repository secrets and fails if either is missing:

- `CLOUDFLARE_API_TOKEN`: an API token created from the "Edit Cloudflare Workers" template
- `CLOUDFLARE_ACCOUNT_ID`: the account ID shown on the Workers & Pages overview page

The films job comes first. It hashes the films' source, and when R2 has no films
under that hash, it renders both cuts on the runner and stores them in the
`errol-promo-films` bucket, which it creates if it's missing. Any other run finds
them there in seconds, so a film renders once per change to its source. The
deploy job then fetches them into `public/demos/`, builds, and deploys. The token
needs Workers R2 Storage edit access, which the "Edit Cloudflare Workers" template
includes. Dispatching the workflow on a branch other than `main` runs only the
films job, which renders a changed film without shipping it; fetch it with
`films.sh fetch` on that branch to watch it first.

For a one-off deploy from a machine that has run `wrangler login`:

```sh
scripts/promo-film/films.sh fetch
npm run deploy
```

Cloudflare assigns a `workers.dev` address on the first deployment. A custom domain can be attached afterward in the Worker settings.

The film uses simplified interfaces and illustrative dialogue. Download buttons point to `https://github.com/tmarkovski/errol/releases`; change `downloadUrl` in `lib/site-config.ts` when a direct installer URL is available. The minimum macOS version matches the app's current Xcode deployment target (26.4).

The default symbol, two overlapping speech bubbles, comes from `docs/brand/errol-symbol.svg`. The app uses a monochrome template of the same paths in `ErrolSymbol.imageset`, and the film draws the symbol as well. The previous owl assets remain in `public/errol.svg` and `public/favicon.svg`. Product facts were checked against the root README and current Swift configuration.
