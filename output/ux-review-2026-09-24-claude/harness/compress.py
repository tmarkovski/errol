import os, shutil
from PIL import Image
try:
    import imagequant
except ImportError:
    imagequant = None

dst = "/Users/tomislav/git/tmarkovski/errol/output/ux-review-2026-09-24-claude"
os.makedirs(dst, exist_ok=True)
pairs = [
    ("sheet-1-today.png", "today-stage-by-stage.png"),
    ("sheet-2-compare.png", "compare-today-a-b.png"),
    ("sheet-3-converged.png", "compare-today-converged.png"),
    ("mocks/A1-ready.png", "a1-ready.png"), ("mocks/A2-choose.png", "a2-choose.png"),
    ("mocks/A3-running.png", "a3-running.png"), ("mocks/A4-paused.png", "a4-paused.png"),
    ("mocks/A5-finished.png", "a5-finished.png"),
    ("mocks/B1-ready.png", "b1-ready.png"), ("mocks/B2-choose.png", "b2-choose.png"),
    ("mocks/B3-running.png", "b3-running.png"), ("mocks/B5-paused.png", "b4-paused.png"),
    ("mocks/B4-finished.png", "b5-finished.png"),
] + [(f"converged/converged-{n}.png", f"converged-{n}.png") for n in
     ["1-ready", "2-choose", "3-running", "4-paused", "5-finished", "6-participant"]]
total_in = total_out = 0
for src, name in pairs:
    im = Image.open(src).convert("RGB")
    out = os.path.join(dst, name)
    if imagequant:
        q = imagequant.quantize_pil_image(im.convert("RGBA"), dithering_level=1.0, max_colors=256,
                                          min_quality=85, max_quality=100)
        q.save(out, optimize=True)
    else:
        im.save(out, optimize=True)
    total_in += os.path.getsize(src); total_out += os.path.getsize(out)
    print(f"{name:32s} {os.path.getsize(src)//1024:5d} KB -> {os.path.getsize(out)//1024:5d} KB")
print(f"total {total_in//1024} KB -> {total_out//1024} KB")
