# Errol landing page

Errol's public landing page, built with React and Vinext.

## Making changes

The page is two screens, each as tall as the window: a headline with the
download button, and the promo film under it, with the footer along the film
screen's bottom edge. Scrolling snaps to one screen or the other, never between. `app/page.tsx` composes them; each has its component and
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
`npx wrangler login`, or render them yourself (see that folder's README).

Keep the films once you have them. `public/demos/` (the web encodes the page
plays) and `scripts/promo-film/out/` (the full renders with sound, the silent
cuts, and the covers) are both ignored by git, so the films stay out of the
repository but stay on disk between sessions, and there's no reason to render
or fetch them again until their source changes. `scripts/promo-film/films.sh key`
prints the hash of that source, which is also the R2 key CI stores them under.
Don't `git clean -x` the site folder, or you'll be rendering again. Wide screens
get the 16:9 cut. Screens taller than 2:3, which means phones held upright, get
the 9:16 cut, whose captions stay legible at that width; turning the phone
switches cuts in place. The player:

- Plays muted once its screen has scrolled all the way in and snapped under the
  header, not while it's on the way, and pauses when it's scrolled away or the
  tab is hidden. Coming back resumes where it left off.
- Plays once and holds its end card, with a gold Replay in the corner.
- Has a scrubber between the play and sound buttons: drag anywhere along it and
  the film holds still under the pointer, then plays on from where it's
  dropped. A drag back from the end card plays on too; a paused film stays
  paused. Arrow keys, Page Up and Down, Home, and End seek from the keyboard.
- Shows each cut's first frame as its poster, so playback starts without a jump.
- Offers "Play with sound", which starts the film over with sound.
- Waits for Play when the visitor prefers reduced motion or the browser refuses
  autoplay, and keeps a text description of the film for screen readers.

The film rises into place as its screen scrolls in. The footer is pulled up
into the bottom of that screen, which leaves room for it, so the page is exactly
two screens tall. On narrow frames the scrubber takes a row of its own above
the buttons, and on phones the footer drops its tagline to stay one row.

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

The films jobs come first, one per cut, side by side. Each hashes the films'
source, and when R2 has no film of its cut under that hash, renders it on the
runner and stores it in the `errol-promo-films` bucket, which it creates if it's
missing. A render takes about 17 minutes on a GitHub runner, against about two
on a Mac, because the runner has no GPU and four slower cores. Any other run finds
the films there in seconds, so a film renders once per change to its source. The
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

The default symbol, two overlapping speech bubbles, comes from `docs/brand/errol-symbol.svg`. The app uses a monochrome template of the same paths in `ErrolSymbol.imageset`, and the film draws the symbol as well. The previous owl assets remain in `public/errol.svg` and `public/favicon.svg`. Product facts were checked against `docs/how-it-works.md` and current Swift configuration.
