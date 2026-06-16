"""Draw spawn-point pins + a meowdb-style legend onto each rendered map preview.

Reads docs/map_previews/spawns.json (written by tools/render_map_previews.gd) and the
clean per-map PNGs, then writes <name>_annotated.png next to them: every spawn marker
becomes a numbered, colour-coded pin, and a legend panel lists each enemy with its
spawn-point count + pool size -- like https://meowdb.com map pages.
"""
import json, os
from PIL import Image, ImageDraw, ImageFont

PREV = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "map_previews")
SCALE = 2          # upscale the 16px-tile art so pins + text stay crisp
R = 10             # pin radius (post-scale px)

BOLD = ["C:/Windows/Fonts/arialbd.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"]
REG = ["C:/Windows/Fonts/arial.ttf", "arial.ttf", "DejaVuSans.ttf"]


def font(paths, size):
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            pass
    return ImageFont.load_default()


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def annotate(entry):
    name = entry["name"]
    base = Image.open(os.path.join(PREV, entry["png"])).convert("RGBA")
    base = base.resize((base.width * SCALE, base.height * SCALE), Image.NEAREST)

    pins = []
    for sp in entry["spawners"]:
        col = hex2rgb(sp["color"])
        for x, y in sp["markers"]:
            pins.append((x * SCALE, y * SCALE, col))

    # Pad the canvas so pins that sit just outside the tile bbox still fit.
    m = R + 4
    xs = [p[0] for p in pins] or [0]
    ys = [p[1] for p in pins] or [0]
    pad_l = int(max(0, m - min(xs)))
    pad_t = int(max(0, m - min(ys)))
    pad_r = int(max(0, (max(xs) + m) - base.width))
    pad_b = int(max(0, (max(ys) + m) - base.height))
    if pad_l or pad_t or pad_r or pad_b:
        canvas = Image.new("RGBA", (base.width + pad_l + pad_r, base.height + pad_t + pad_b), (20, 24, 33, 255))
        canvas.paste(base, (pad_l, pad_t))
        base = canvas

    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    fnum = font(BOLD, 12)

    # Pins, numbered in spawn-order.
    for i, (x, y, col) in enumerate(pins, 1):
        cx, cy = x + pad_l, y + pad_t
        d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=col + (255,), outline=(255, 255, 255, 255), width=2)
        d.text((cx, cy - 1), str(i), font=fnum, fill=(255, 255, 255, 255), anchor="mm",
               stroke_width=2, stroke_fill=(0, 0, 0, 170))

    # Legend, grouped by enemy.
    groups = {}
    for sp in entry["spawners"]:
        g = groups.setdefault(sp["enemy"], {"color": sp["color"], "points": 0, "pool": 0})
        g["points"] += len(sp["markers"])
        g["pool"] += sp["pool_size"]
    total = sum(g["points"] for g in groups.values())

    fh, fs, fr = font(BOLD, 18), font(BOLD, 12), font(REG, 14)
    pad, sw, rowh = 12, 16, 26
    panel_w = 320
    panel_h = pad * 2 + 24 + 22 + len(groups) * rowh
    px, py = 12, 12
    d.rounded_rectangle([px, py, px + panel_w, py + panel_h], radius=10,
                        fill=(18, 21, 29, 228), outline=(255, 255, 255, 45), width=1)
    tx, ty = px + pad, py + pad
    d.text((tx, ty), name.replace("_", " ").title(), font=fh, fill=(255, 236, 200, 255)); ty += 24
    types = f"{len(groups)} type" + ("s" if len(groups) != 1 else "")
    d.text((tx, ty), f"Spawns: {total} points  •  {types}", font=fs, fill=(170, 180, 195, 255)); ty += 22
    for enemy, g in groups.items():
        col = hex2rgb(g["color"])
        d.rounded_rectangle([tx, ty, tx + sw, ty + sw], radius=3, fill=col + (255,), outline=(255, 255, 255, 130))
        d.text((tx + sw + 9, ty - 1), f"{enemy}   ×{g['points']}   (pool {g['pool']})",
               font=fr, fill=(235, 238, 242, 255))
        ty += rowh

    out = Image.alpha_composite(base, overlay).convert("RGB")
    path = os.path.join(PREV, f"{name}_annotated.png")
    out.save(path)
    print("wrote", os.path.normpath(path), out.size)


def main():
    data = json.load(open(os.path.join(PREV, "spawns.json")))
    for e in data:
        annotate(e)


if __name__ == "__main__":
    main()
