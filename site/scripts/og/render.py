# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright==1.61.0"]
# ///
"""Captures og.html into public/og.png, the 1200 × 630 image shared links show.

From this folder: `uv run render.py`. It uses Google Chrome through Playwright,
falling back to Playwright's Chromium, and loads Geist from Google Fonts.
"""

from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).parent
OUT = HERE.parent.parent / "public/og.png"

with sync_playwright() as p:
    try:
        browser = p.chromium.launch(channel="chrome")
    except Exception:
        browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": 1200, "height": 630}, device_scale_factor=1)
    page.goto((HERE / "og.html").as_uri(), wait_until="networkidle")
    page.wait_for_function("document.fonts.status === 'loaded' && document.body.dataset.ready === 'true'")
    page.locator(".card").screenshot(path=OUT)
    browser.close()
print(f"wrote {OUT}")
