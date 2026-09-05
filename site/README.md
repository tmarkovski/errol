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

The site is configured as a Cloudflare Worker with static assets. For a manual production deploy:

```sh
npm run deploy
```

The repository workflow at `.github/workflows/site.yml` deploys changes to `site/` from `main`. Add these GitHub Actions repository secrets before enabling it:

- `CLOUDFLARE_API_TOKEN`: a Cloudflare API token with Workers Scripts edit permission
- `CLOUDFLARE_ACCOUNT_ID`: the Cloudflare account ID that should own the Worker

Cloudflare assigns a `workers.dev` address on the first deployment. A custom domain can be attached afterward in the Worker settings.

The three conversation modes are illustrative examples. Download buttons point to `https://github.com/tmarkovski/errol/releases`; change `DOWNLOAD_URL` in `app/page.tsx` when a direct installer URL is available. The minimum macOS version matches the app's current Xcode deployment target (26.4).

The owl comes from the app's menu-bar asset. Product facts were checked against the root README and current Swift configuration. No files in `site/` or the previous landing-page proposals were read.
