# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "click>=8.1",
#   "imageio-ffmpeg>=0.5",
#   "numpy>=2.0",
#   "pillow>=10.0",
#   "playwright>=1.50",
#   "scipy>=1.13",
# ]
# ///
"""Render Errol's promo film in both formats, picture and sound.

    uv run render.py build                    # both formats, with sound, into out/
    uv run render.py build --format wide      # one format
    uv run render.py stills 3.3 9.3 --sheet   # frames to check while editing
    uv run render.py publish                  # web encodes of both films onto the site
"""
import base64
import json
import multiprocessing as mp
import pathlib
import re
import shutil
import subprocess
import time

import click
import imageio_ffmpeg
from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).resolve().parent
PAGE = HERE / "promo.html"
OUT = HERE / "out"
SITE_DEMOS = HERE.parent.parent / "public" / "demos"
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
# format -> (file tag, width, height)
FORMATS = {"tall": ("9x16", 1080, 1920), "wide": ("16x9", 1920, 1080)}
TARGET_LUFS = -14.0
ENCODE = [
    "-vf", "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p,"
    "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv",
    "-c:v", "libx264", "-preset", "slow", "-crf", "15", "-profile:v", "high",
    "-x264-params", "colorprim=bt709:transfer=bt709:colormatrix=bt709", "-an",
]
# The site's copy: a fifth of the master's size and indistinguishable from it on the page.
WEB_ENCODE = [
    "-c:v", "libx264", "-preset", "veryslow", "-crf", "23", "-profile:v", "high", "-pix_fmt", "yuv420p",
    "-x264-params", "colorprim=bt709:transfer=bt709:colormatrix=bt709",
    "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart",
]


def launch(p):
    args = ["--force-color-profile=srgb", "--disable-lcd-text", "--hide-scrollbars"]
    try:
        return p.chromium.launch(channel="chrome", args=args)
    except Exception:
        # Without Google Chrome, Playwright's Chromium works after:
        # uv run --with playwright playwright install chromium
        return p.chromium.launch(args=args)


def open_page(p, fmt):
    _, w, h = FORMATS[fmt]
    browser = launch(p)
    page = browser.new_page(viewport={"width": w, "height": h}, device_scale_factor=1)
    page.on("pageerror", lambda e: print(f"page error: {e}", flush=True))
    page.goto(f"{PAGE.as_uri()}?format={fmt}")
    page.wait_for_function("window.__ready === true", timeout=30000)
    return browser, page, page.context.new_cdp_session(page)


def capture(page, cdp, fmt, t):
    _, w, h = FORMATS[fmt]
    # Two animation frames let the new styles paint before the capture.
    page.evaluate("t => { renderAt(t); return new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))); }", t)
    shot = cdp.send("Page.captureScreenshot", {
        "format": "png", "optimizeForSpeed": True,
        "clip": {"x": 0, "y": 0, "width": w, "height": h, "scale": 1},
    })
    return base64.b64decode(shot["data"])


def cues(fmt):
    with sync_playwright() as p:
        browser, page, _ = open_page(p, fmt)
        data = page.evaluate("window.CUES")
        browser.close()
    return data


def _slice(job):
    """One worker: renders a run of frames and encodes them as one segment."""
    fmt, frames, fps, seg = job
    enc = subprocess.Popen([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "image2pipe",
                            "-framerate", str(fps), "-c:v", "png", "-i", "-", *ENCODE, str(seg)],
                           stdin=subprocess.PIPE)
    with sync_playwright() as p:
        browser, page, cdp = open_page(p, fmt)
        for i in frames:
            enc.stdin.write(capture(page, cdp, fmt, i / fps))
        browser.close()
    enc.stdin.close()
    if enc.wait():
        raise RuntimeError(f"ffmpeg failed on {seg}")
    return seg


def render_video(fmt, fps, workers, dur, dest):
    total = int(round(dur * fps))
    step = -(-total // workers)
    segdir = OUT / "segments" / fmt
    segdir.mkdir(parents=True, exist_ok=True)
    jobs = [(fmt, list(range(w * step, min(total, (w + 1) * step))), fps, segdir / f"{w}.mp4") for w in range(workers)]
    with mp.Pool(workers) as pool:
        segs = pool.map(_slice, jobs)
    listing = segdir / "list.txt"
    listing.write_text("".join(f"file '{s}'\n" for s in segs))
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0",
                    "-i", str(listing), "-c", "copy", "-movflags", "+faststart", str(dest)], check=True)
    shutil.rmtree(segdir)


def loudness(path):
    run = subprocess.run([FFMPEG, "-hide_banner", "-i", str(path), "-map", "a", "-af", "ebur128", "-f", "null", "-"],
                         capture_output=True, text=True)
    return float(re.findall(r"I:\s+(-?[\d.]+) LUFS", run.stderr)[-1])


def mux(video, wav, dest):
    gain = TARGET_LUFS - loudness(wav) + 0.1
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(video), "-i", str(wav),
                    "-map", "0:v", "-map", "1:a", "-c:v", "copy",
                    "-af", f"volume={gain:.2f}dB,alimiter=limit=0.84:attack=3:release=80:level=disabled",
                    "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-shortest", "-movflags", "+faststart", str(dest)],
                   check=True)
    return loudness(dest)


def contact_sheet(files, dest, cols):
    from PIL import Image, ImageDraw

    first = Image.open(files[0])
    w = 300 if first.height > first.width else 480
    h = round(w * first.height / first.width)
    rows = -(-len(files) // cols)
    sheet = Image.new("RGB", (cols * w, rows * (h + 24)), (40, 40, 40))
    draw = ImageDraw.Draw(sheet)
    for i, f in enumerate(files):
        x, y = (i % cols) * w, (i // cols) * (h + 24)
        sheet.paste(Image.open(f).convert("RGB").resize((w, h), Image.LANCZOS), (x, y + 24))
        draw.text((x + 6, y + 5), f.stem, fill=(255, 220, 150))
    sheet.save(dest)


def selected(fmt):
    return list(FORMATS) if fmt == "both" else [fmt]


FORMAT_OPTION = click.option("--format", "fmt", type=click.Choice(["tall", "wide", "both"]), default="both",
                             show_default=True, help="tall is 1080 × 1920 (9:16), wide is 1920 × 1080 (16:9).")


@click.group()
def cli():
    """Render Errol's promo film from promo.html."""


@cli.command()
@FORMAT_OPTION
@click.option("--fps", default=60, show_default=True)
@click.option("--workers", default=5, show_default=True, help="Chrome pages rendering in parallel.")
@click.option("--cover", default=10.7, show_default=True, help="Time of the frame saved as the cover image.")
@click.option("--silent", is_flag=True, help="Skip the sound track.")
def build(fmt, fps, workers, cover, silent):
    """Render the finished films into out/."""
    import sound

    OUT.mkdir(exist_ok=True)
    for f in selected(fmt):
        tag = FORMATS[f][0]
        start = time.time()
        with sync_playwright() as p:
            browser, page, cdp = open_page(p, f)
            (OUT / f"errol-promo-{tag}-cover.png").write_bytes(capture(page, cdp, f, cover))
            data = page.evaluate("window.CUES")
            browser.close()
        silent_mp4 = OUT / f"errol-promo-{tag}-silent.mp4"
        render_video(f, fps, workers, data["dur"], silent_mp4)
        if silent:
            click.echo(f"{f}: {silent_mp4.name} in {time.time() - start:.0f}s")
            continue
        wav = OUT / f"errol-promo-{tag}.wav"
        sound.synthesize(data, wav)
        lufs = mux(silent_mp4, wav, OUT / f"errol-promo-{tag}.mp4")
        click.echo(f"{f}: errol-promo-{tag}.mp4 at {lufs:.1f} LUFS, plus the silent cut and cover, in {time.time() - start:.0f}s")


@cli.command()
@FORMAT_OPTION
def publish(fmt):
    """Put web encodes of the films in out/ on the site, each with its first frame as a poster."""
    from io import BytesIO

    from PIL import Image

    SITE_DEMOS.mkdir(parents=True, exist_ok=True)
    for f in selected(fmt):
        tag = FORMATS[f][0]
        master = OUT / f"errol-promo-{tag}.mp4"
        if not master.exists():
            raise click.ClickException(f"{master.name} is missing; run build first.")
        film = SITE_DEMOS / master.name
        subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(master), *WEB_ENCODE, str(film)],
                       check=True)
        # The poster is the film's own first frame, so playback starts without a jump.
        frame = subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-i", str(film), "-frames:v", "1",
                                "-f", "image2pipe", "-c:v", "png", "-"], check=True, capture_output=True).stdout
        poster = SITE_DEMOS / f"errol-promo-{tag}-poster.webp"
        Image.open(BytesIO(frame)).convert("RGB").save(poster, quality=80, method=6)
        click.echo(f"{f}: {film.name} ({film.stat().st_size / 1e6:.1f} MB), {poster.name} "
                   f"({poster.stat().st_size / 1e3:.0f} kB)")


@cli.command()
@click.argument("times", nargs=-1, type=float, required=True)
@FORMAT_OPTION
@click.option("--sheet", is_flag=True, help="Also tile the frames into one contact sheet.")
def stills(times, fmt, sheet):
    """Render single frames at TIMES (seconds) into out/stills/."""
    for f in selected(fmt):
        folder = OUT / "stills" / f
        folder.mkdir(parents=True, exist_ok=True)
        files = []
        with sync_playwright() as p:
            browser, page, cdp = open_page(p, f)
            for t in times:
                path = folder / f"t{t:05.2f}.png"
                path.write_bytes(capture(page, cdp, f, t))
                files.append(path)
            browser.close()
        if sheet:
            dest = OUT / "stills" / f"sheet-{f}.png"
            contact_sheet(files, dest, 6 if f == "tall" else 4)
            click.echo(f"{f}: {dest}")
        else:
            click.echo(f"{f}: {len(files)} frames in {folder}")


@cli.command()
@click.argument("at", type=float)
@click.argument("seconds", type=float)
def hold(at, seconds):
    """Lengthen the film by SECONDS at time AT: every story time from AT on moves later."""
    lines = PAGE.read_text().split("\n")
    first = next(i for i, line in enumerate(lines) if line.startswith("const DUR="))
    last = next(i for i, line in enumerate(lines) if line.startswith("const EYEBROWS="))
    # Times follow a colon, bracket, or comma in STORY; offsets like BEAT.start-.62 stay put.
    number = re.compile(r"(?<=[:\[,])(\d+\.\d+|\d+|\.\d+)")

    def later(m):
        x = float(m.group(1))
        return m.group(1) if x < at else f"{x + seconds:.3f}".rstrip("0").rstrip(".")

    for i in range(first + 1, last + 1):
        if "TURN_LIMIT" not in lines[i] and not lines[i].lstrip().startswith("//"):
            lines[i] = number.sub(later, lines[i])
    dur = float(re.search(r"const DUR=([\d.]+)", lines[first]).group(1))
    lines[first] = f"const DUR={dur + seconds:g};"
    PAGE.write_text("\n".join(lines))
    click.echo(f"Added {seconds:g} s at {at:g} s; the film now runs {dur + seconds:g} s.")


@cli.command("cues")
@FORMAT_OPTION
def dump_cues(fmt):
    """Print the timeline the sound design follows."""
    for f in selected(fmt):
        click.echo(json.dumps(cues(f), indent=1))


if __name__ == "__main__":
    cli()
