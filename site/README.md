# Errol landing page

A standalone, original landing page for Errol. This project is independent of the existing `site/` directory.

## Development

```sh
npm install
npm run dev
```

## Build

```sh
npm run build
```

Static output is in `dist/client/`. The page uses React, Vinext, and the starter's accessible Base UI tabs. All motion is CSS or requestAnimationFrame; there is no animation-library dependency. It respects reduced-motion preferences and includes a pause control.

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

The three conversation modes are illustrative examples. Download buttons point to `https://github.com/tmarkovski/errol/releases`; change `DOWNLOAD_URL` in `app/page.tsx` when a direct installer URL is available. The minimum macOS version matches the app's current Xcode deployment target (26.4).

The owl comes from the app's menu-bar asset. Product facts were checked against the root README and current Swift configuration. No files in `site/` or the previous landing-page proposals were read.
