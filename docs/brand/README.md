# Errol symbol

`errol-symbol.svg` is the default Errol symbol: two overlapping speech bubbles
with opposing tails, one for each assistant in the conversation. It is drawn
with strokes, 4.5 units wide with round caps and joins, in `#343633` on a
transparent background. The rear bubble stops short of the front one, leaving
a gap a little over half a stroke wide. The viewBox is cropped to the drawing,
strokes included, which comes out square.

- The macOS status item uses `ErrolSymbol.imageset` in the app's asset catalog:
  the same paths in black, drawn at 16 pt with template rendering so macOS
  controls the color in light and dark menu bars. The mark is square, so 16 pt
  keeps it as tall as the system's own menu bar glyphs. While a run lasts, the
  status item is lit instead (`StatusIcon.swift`), the way macOS lights its
  microphone indicator while the mic is in use: the mark turns white, on a
  capsule of the theme's accent that fills the item where the system's
  pressed highlight would.
- The website uses `site/public/errol-symbol.svg`, a copy of this source, in
  the header and the footer. The site recolors it in CSS.
- `site/public/errol-symbol-favicon.svg` uses the same paths on a 32 px canvas
  and adapts its color to the browser's light or dark appearance.
- The promo film (`site/scripts/promo-film/promo.html`) inlines the paths so it
  can draw the mark stroke by stroke and slide its two bubbles together.

The previous owl remains available in `MenuBarIcon.imageset`,
`site/public/errol.svg`, and `site/public/favicon.svg`. The traced bird that
came between the owl and the bubbles is in the git history (692a76f).
When updating the mark, keep the two paths, the stroke, and the viewBox in sync
across the source and these display variants.
