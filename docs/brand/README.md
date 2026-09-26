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
- The app icon and the website's icons put the mark on a tile; see below.
- The promo film (`site/scripts/promo-film/promo.html`) inlines the paths so it
  can draw the mark stroke by stroke and slide its two bubbles together.

## App icon

The app icon is the mark on a deep charcoal tile, the front bubble in cream
and the rear bubble in courier gold, with a soft light along the tile's top
edge and a faint gold glow low down. `render_icons.py` draws it and every
variant from one function, so the app and the site change together. Run it
from this folder with `uv run render_icons.py`; it renders through Google
Chrome and writes:

- `errol-app-icon.svg`, the macOS icon at 1024 px on Apple's grid: an 824 px
  rounded square with continuous corners, a 100 px margin, and a drop shadow.
- The PNGs in the app's `AppIcon.appiconset`, from 16 to 1024 px, and its
  `Contents.json`.
- The site's `icon.svg` and `favicon.ico` (16, 32, and 48 px): the tile fills
  the square, and the mark is larger and its strokes heavier, so it still reads
  in a browser tab.
- The site's `apple-touch-icon.png`, 180 px, square and opaque, since iOS rounds
  the corners itself.

Don't edit those files by hand; change the script and render again.

The previous owl remains available in `MenuBarIcon.imageset`,
`site/public/errol.svg`, and `site/public/favicon.svg`. The traced bird that
came between the owl and the bubbles is in the git history (692a76f).
When updating the mark, keep the two paths, the stroke, and the viewBox in sync
across the source and these display variants.
