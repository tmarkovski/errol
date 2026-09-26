# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright==1.61.0"]
# ///
"""Captures background.html into background.png and background@2x.png.

From this folder: `uv run render_background.py`. It uses Google Chrome through
Playwright, falling back to Playwright's Chromium, and loads Geist from Google
Fonts. make_dmg.py hands both files to dmgbuild, which joins them into one
image so the window stays sharp on Retina screens.
"""

from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).parent

with sync_playwright() as p:
    try:
        browser = p.chromium.launch(channel="chrome")
    except Exception:
        browser = p.chromium.launch()
    for scale, name in [(1, "background.png"), (2, "background@2x.png")]:
        page = browser.new_page(viewport={"width": 640, "height": 420}, device_scale_factor=scale)
        page.goto((HERE / "background.html").as_uri(), wait_until="networkidle")
        page.wait_for_function("document.fonts.status === 'loaded' && document.body.dataset.ready === 'true'")
        page.locator(".window").screenshot(path=HERE / name)
        page.close()
        print(f"wrote {HERE / name}")
    browser.close()
