# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright==1.61.0", "pillow>=11"]
# ///
"""Draws Errol's app icon and the website's icons from one design, and renders them.

The icon is the Errol symbol on a deep charcoal tile: the front bubble in cream,
the rear bubble in courier gold. Every variant comes from `icon_svg()` below, so
a change here reaches the app and the site together. From this folder:

    uv run render_icons.py

writes:

- `errol-app-icon.svg`, the macOS icon at 1024 px, on Apple's grid: an 824 px
  rounded square with continuous corners, a 100 px margin, and a drop shadow;
- the app's `AppIcon.appiconset`, every size macOS asks for, and its `Contents.json`;
- the site's `icon.svg` and `favicon.ico`, a tile that fills its square, with a
  larger mark and heavier strokes so it holds up at 16 px;
- the site's `apple-touch-icon.png`, square and opaque, since iOS rounds the
  corners itself.

It renders with Google Chrome through Playwright, falling back to Playwright's
Chromium when Chrome isn't installed.
"""

import io
import json
import math
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = Path(__file__).parent
ROOT = HERE.parent.parent
APPICONSET = ROOT / "app/Errol/Errol/Assets.xcassets/AppIcon.appiconset"
PUBLIC = ROOT / "site/public"

# The symbol, as in errol-symbol.svg, and the box its drawing fills, strokes included.
FRONT = "M 18 47 C 14.2 43.4 12 38.4 12 33 C 12 21.95 20.95 13 32 13 C 43.05 13 52 21.95 52 33 C 52 44.05 43.05 53 32 53 H 12 Z"
REAR = "M 59 32 C 67 39 68 51 61 60 L 66 67 H 47 C 40.5 67 35.5 64.5 31 60"
BOX = (9.75, 10.75, 58.5)


def squircle(x: float, y: float, size: float, n: float = 5.0, steps: int = 360) -> str:
    """A superellipse, the continuous-corner shape of Apple's icons."""
    half = size / 2
    cx, cy = x + half, y + half
    points = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        px = cx + half * math.copysign(abs(c) ** (2 / n), c)
        py = cy + half * math.copysign(abs(s) ** (2 / n), s)
        points.append(f"{px:.2f} {py:.2f}")
    return "M" + " L".join(points) + " Z"


def rounded(x: float, y: float, size: float, r: float) -> str:
    return (
        f"M{x + r} {y} H{x + size - r} A{r} {r} 0 0 1 {x + size} {y + r} "
        f"V{y + size - r} A{r} {r} 0 0 1 {x + size - r} {y + size} "
        f"H{x + r} A{r} {r} 0 0 1 {x} {y + size - r} V{y + r} A{r} {r} 0 0 1 {x + r} {y} Z"
    )


def icon_svg(
    canvas: float,
    shape: str,
    *,
    body: float,
    mark: float,
    stroke: float = 4.5,
    detail: bool = True,
    shadow: bool = False,
) -> str:
    """One variant of the icon.

    `canvas` is the square the SVG draws on, `body` the tile's side, centered on it;
    `shape` is "squircle", "rounded", or "square"; `mark` is the symbol's width as a
    share of the tile; `stroke` its line weight in the symbol's own units; `detail`
    adds the rim light and the glow; `shadow` drops the tile's shadow (Apple's grid).
    """
    x = (canvas - body) / 2
    outline = {
        "squircle": lambda: squircle(x, x, body),
        "rounded": lambda: rounded(x, x, body, body * 0.22),
        "square": lambda: f"M{x} {x} H{x + body} V{x + body} H{x} Z",
    }[shape]()
    left, top, side = BOX
    scale = body * mark / side
    # The symbol's box, centered on the tile.
    tx = canvas / 2 - (left + side / 2) * scale
    ty = canvas / 2 - (top + side / 2) * scale
    u = body / 824  # one unit on Apple's 1024 grid

    rim = ""
    glow = ""
    if detail:
        glow = f'<path d="{outline}" fill="url(#glow)"/>'
        rim = f'<path d="{outline}" fill="none" stroke="url(#rim)" stroke-width="{3 * u:.2f}"/>'
    tile_shadow = (
        f'<filter id="drop" x="-20%" y="-20%" width="140%" height="150%">'
        f'<feDropShadow dx="0" dy="{12 * u:.2f}" stdDeviation="{14 * u:.2f}" flood-color="#000" flood-opacity="0.38"/></filter>'
        if shadow
        else ""
    )
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{canvas:g}" height="{canvas:g}" viewBox="0 0 {canvas:g} {canvas:g}">
  <title>Errol</title>
  <defs>
    <linearGradient id="ground" x1="0" y1="{x:g}" x2="0" y2="{x + body:g}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#2d2a24"/>
      <stop offset="1" stop-color="#121210"/>
    </linearGradient>
    <radialGradient id="glow" cx="{canvas / 2:g}" cy="{x + body * 0.98:g}" r="{body * 0.62:g}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#edba72" stop-opacity="0.2"/>
      <stop offset="1" stop-color="#edba72" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="rim" x1="0" y1="{x:g}" x2="0" y2="{x + body:g}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#fff" stop-opacity="0.22"/>
      <stop offset="0.3" stop-color="#fff" stop-opacity="0.04"/>
      <stop offset="1" stop-color="#fff" stop-opacity="0.02"/>
    </linearGradient>
    <linearGradient id="cream" x1="0" y1="13" x2="0" y2="53" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#fbf4e4"/>
      <stop offset="1" stop-color="#e8dbc0"/>
    </linearGradient>
    <linearGradient id="gold" x1="0" y1="32" x2="0" y2="67" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#f5cb8d"/>
      <stop offset="1" stop-color="#dc9d52"/>
    </linearGradient>
    <filter id="lift" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="{body * 0.012:.2f}" stdDeviation="{body * 0.014:.2f}" flood-color="#000" flood-opacity="0.45"/>
    </filter>
    {tile_shadow}
  </defs>
  <g{' filter="url(#drop)"' if shadow else ''}>
    <path d="{outline}" fill="url(#ground)"/>
    {glow}
    {rim}
  </g>
  <g filter="url(#lift)" transform="translate({tx:.3f} {ty:.3f}) scale({scale:.4f})" fill="none" stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round">
    <path d="{REAR}" stroke="url(#gold)"/>
    <path d="{FRONT}" stroke="url(#cream)"/>
  </g>
</svg>
"""


# macOS: the 824 px squircle on the 1024 grid, with its shadow.
APP = icon_svg(1024, "squircle", body=824, mark=0.63, stroke=5, shadow=True)
# Browser tabs: the tile fills the square, the mark is larger and heavier.
FAVICON = icon_svg(64, "rounded", body=64, mark=0.78, stroke=6, detail=False)
# iOS home screens round the corners themselves and want no transparency.
TOUCH = icon_svg(180, "square", body=180, mark=0.63, stroke=5)

APP_SIZES = [  # (point size, scale)
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]


def render(page, svg: str, px: int) -> Image.Image:
    page.set_content(
        f'<html><body style="margin:0;background:transparent">'
        f'<div style="width:{px}px;height:{px}px">{svg.replace("<svg ", f"<svg style=\"display:block;width:{px}px;height:{px}px\" ", 1)}</div>'
        f"</body></html>"
    )
    png = page.locator("div").screenshot(omit_background=True)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def main() -> None:
    (HERE / "errol-app-icon.svg").write_text(APP)
    (PUBLIC / "icon.svg").write_text(FAVICON)

    with sync_playwright() as p:
        try:
            browser = p.chromium.launch(channel="chrome")
        except Exception:
            browser = p.chromium.launch()
        page = browser.new_page(device_scale_factor=1)

        images = []
        for points, scale in APP_SIZES:
            px = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            render(page, APP, px).save(APPICONSET / name)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
        contents = {"images": images, "info": {"author": "xcode", "version": 1}}
        (APPICONSET / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

        # Each favicon size drawn at its own size, so the strokes land on the pixel grid as well as they can.
        sizes = [16, 32, 48]
        frames = [render(page, FAVICON, px) for px in sizes]
        frames[-1].save(PUBLIC / "favicon.ico", sizes=[(s, s) for s in sizes], append_images=frames[:-1])

        render(page, TOUCH, 180).convert("RGB").save(PUBLIC / "apple-touch-icon.png")
        browser.close()
    print("wrote the app icon set, errol-app-icon.svg, icon.svg, favicon.ico, and apple-touch-icon.png")


if __name__ == "__main__":
    main()
