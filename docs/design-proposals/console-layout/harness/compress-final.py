# Reduces the final renders with libimagequant (keeps colors faithful) into
# docs/design-proposals/console-layout/. Run from the folder holding final/.
import os, sys
from PIL import Image
import imagequant

dst = sys.argv[1] if len(sys.argv) > 1 else "."
names = sorted(n for n in os.listdir("final") if n.endswith(".png"))
pairs = [(os.path.join("final", n), n) for n in names] + [("compare-today-final.png", "compare-today-final.png")]
for src, name in pairs:
    im = Image.open(src).convert("RGBA")
    q = imagequant.quantize_pil_image(im, dithering_level=1.0, max_colors=256, min_quality=85, max_quality=100)
    out = os.path.join(dst, name)
    q.save(out, optimize=True)
    print(f"{name:40s} {os.path.getsize(src)//1024:5d} KB -> {os.path.getsize(out)//1024:5d} KB")
