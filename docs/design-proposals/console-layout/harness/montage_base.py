from PIL import Image, ImageDraw, ImageFont
import os

S = 0.55
BG = (244, 245, 247)
INK = (38, 37, 35)
SEC = (110, 108, 104)

def font(size, bold=False):
    for path in (["/System/Library/Fonts/SFNS.ttf"] + ["/System/Library/Fonts/Helvetica.ttc"]):
        try:
            f = ImageFont.truetype(path, size)
            if bold:
                try: f.set_variation_by_name("Semibold")
                except Exception: pass
            return f
        except Exception:
            continue
    return ImageFont.load_default()

def load(path):
    im = Image.open(path).convert("RGB")
    return im.resize((int(im.width * S), int(im.height * S)), Image.LANCZOS)

def text(draw, xy, s, f, fill):
    draw.text(xy, s, font=f, fill=fill)

def sheet_grid(title, subtitle, cells, cols, out):
    ims = [(cap, load(p)) for cap, p in cells]
    cw = max(im.width for _, im in ims)
    rows = [ims[i:i+cols] for i in range(0, len(ims), cols)]
    pad, gap, cap_h, head = 48, 36, 44, 120
    rh = [max(im.height for _, im in r) + cap_h for r in rows]
    W = pad * 2 + cols * cw + (cols - 1) * gap
    H = head + sum(rh) + gap * (len(rows) - 1) + pad
    out_im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(out_im)
    text(d, (pad, 34), title, font(40, True), INK)
    text(d, (pad, 84), subtitle, font(22), SEC)
    y = head
    for r, h in zip(rows, rh):
        for i, (cap, im) in enumerate(r):
            x = pad + i * (cw + gap)
            text(d, (x + 8, y + 6), cap, font(24, True), INK)
            out_im.paste(im, (x, y + cap_h))
        y += h + gap
    out_im.save(out)
    print(out, out_im.size)

def sheet_compare(title, subtitle, headers, rows, out):
    # rows: [(label, [path or None per column])]
    loaded = [(label, [load(p) if p else None for p in paths]) for label, paths in rows]
    ncol = len(headers)
    cw = [max((r[1][c].width for r in loaded if r[1][c] is not None), default=0) for c in range(ncol)]
    pad, gap, lab_h, head, hdr_h = 48, 32, 46, 120, 50
    rh = [max(im.height for im in r[1] if im is not None) for r in loaded]
    W = pad * 2 + sum(cw) + gap * (ncol - 1)
    H = head + hdr_h + sum(h + lab_h for h in rh) + gap * (len(rows) - 1) + pad
    out_im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(out_im)
    text(d, (pad, 34), title, font(40, True), INK)
    text(d, (pad, 84), subtitle, font(22), SEC)
    x = pad
    for c, hname in enumerate(headers):
        text(d, (x + 8, head), hname, font(26, True), INK)
        x += cw[c] + gap
    y = head + hdr_h
    for (label, ims), h in zip(loaded, rh):
        d.line([(pad, y + 8), (W - pad, y + 8)], fill=(214, 216, 220), width=2)
        text(d, (pad + 8, y + 14), label, font(22), SEC)
        x = pad
        for c, im in enumerate(ims):
            if im is not None:
                out_im.paste(im, (x, y + lab_h))
            x += cw[c] + gap
        y += h + lab_h + gap
    out_im.save(out)
    print(out, out_im.size)

