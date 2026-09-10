# Errol symbol

`errol-symbol.svg` is the default Errol symbol, traced from the supplied artwork.
It retains the navy gradients and uses compound paths for transparent eye cutouts.
The wordmark is omitted.

- The macOS status item uses `ErrolSymbol.imageset` in the app's asset catalog:
  the same paths in black, centered on a square canvas, with template rendering
  so macOS controls the color in light and dark menu bars.
- The website uses `site/public/errol-symbol.svg`, a copy of this source.
  Its existing light branding treatment is applied in CSS.
- `site/public/errol-symbol-favicon.svg` uses the same paths on a square canvas
  and adapts its color to the browser's light or dark appearance.

The previous owl remains available in `MenuBarIcon.imageset`,
`site/public/errol.svg`, and `site/public/favicon.svg`.
When updating the mark, keep the three paths and transparent cutouts in sync
across the source and these display variants.
