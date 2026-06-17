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


LADDER_COL = (210, 168, 96)   # warm wood
ROPE_COL = (232, 212, 158)    # pale rope


def draw_ladder(d, x, y0, y1):
    w = 7
    d.line([(x - w, y0), (x - w, y1)], fill=LADDER_COL + (255,), width=3)
    d.line([(x + w, y0), (x + w, y1)], fill=LADDER_COL + (255,), width=3)
    yy = y0 + 7
    while yy < y1:
        d.line([(x - w, yy), (x + w, yy)], fill=LADDER_COL + (255,), width=3)
        yy += 13


def draw_rope(d, x, y0, y1):
    pts, yy, t = [], y0, 0
    while yy <= y1:
        pts.append((x + (4 if t % 2 == 0 else -4), yy))
        yy += 9
        t += 1
    pts.append((x, y1))
    d.line(pts, fill=ROPE_COL + (255,), width=3, joint="curve")


PORTAL_COL = (90, 220, 255)   # glowing cyan doorway
SPAWN_COL = (120, 240, 130)   # lime player-start flag


def draw_portal(d, x, yt, yb, dest, fnt):
    hw = 15
    d.ellipse([x - hw, yt, x + hw, yb], outline=PORTAL_COL + (255,), width=3)
    d.ellipse([x - hw + 4, yt + 5, x + hw - 4, yb - 5], outline=PORTAL_COL + (110,), width=2)
    d.text((x, yt - 3), dest, font=fnt, fill=(220, 245, 255, 255), anchor="mb",
           stroke_width=3, stroke_fill=(0, 0, 0, 190))


def draw_spawn(d, x, y, h=30):
    # a planted flag marking where the player drops in
    d.line([(x, y - h), (x, y + 4)], fill=SPAWN_COL + (255,), width=3)
    d.polygon([(x, y - h), (x + 19, y - h + 7), (x, y - h + 15)],
              fill=SPAWN_COL + (255,), outline=(255, 255, 255, 255))


def annotate(entry):
    name = entry["name"]
    base = Image.open(os.path.join(PREV, entry["png"])).convert("RGBA")
    base = base.resize((base.width * SCALE, base.height * SCALE), Image.NEAREST)

    pins = []
    for sp in entry["spawners"]:
        col = hex2rgb(sp["color"])
        for x, y in sp["markers"]:
            pins.append((x * SCALE, y * SCALE, col))
    portals = entry.get("portals", [])
    pspawn = entry.get("player_spawn") or {}

    # Pad the canvas so pins/portals/flags that sit just outside the tile bbox still fit.
    m = R + 4
    xs = [p[0] for p in pins]
    ys = [p[1] for p in pins]
    for pt in portals:
        xs.append(pt["x"] * SCALE)
        ys += [pt["y_top"] * SCALE, pt["y_bottom"] * SCALE]
    if pspawn:
        xs.append(pspawn["x"] * SCALE)
        ys.append(pspawn["y"] * SCALE - 60)
    xs = xs or [0]
    ys = ys or [0]
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

    # Proposed connectors (ropes/ladders) — drawn under the pins.
    conns = entry.get("connectors", [])
    for cn in conns:
        x = cn["x"] * SCALE + pad_l
        yt = cn["y_top"] * SCALE + pad_t
        yb = cn["y_bottom"] * SCALE + pad_t
        (draw_ladder if cn["type"] == "ladder" else draw_rope)(d, x, yt, yb)

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

    n_lad = sum(1 for c in conns if c["type"] == "ladder")
    n_rope = sum(1 for c in conns if c["type"] == "rope")
    conn_rows = (1 if n_lad else 0) + (1 if n_rope else 0)

    fh, fs, fr = font(BOLD, 18), font(BOLD, 12), font(REG, 14)
    pad, sw, rowh = 12, 16, 26
    panel_w = 320
    panel_h = pad * 2 + 24 + 22 + (len(groups) + conn_rows + len(portals) + (1 if pspawn else 0)) * rowh
    px, py = 12, 12
    d.rounded_rectangle([px, py, px + panel_w, py + panel_h], radius=10,
                        fill=(18, 21, 29, 228), outline=(255, 255, 255, 45), width=1)
    tx, ty = px + pad, py + pad
    d.text((tx, ty), name.replace("_", " ").title(), font=fh, fill=(255, 236, 200, 255)); ty += 24
    types = f"{len(groups)} type" + ("s" if len(groups) != 1 else "")
    d.text((tx, ty), f"Spawns: {total} points  •  {types}", font=fs, fill=(170, 180, 195, 255)); ty += 22
    if pspawn:
        draw_spawn(d, tx + sw // 2, ty + sw - 1, h=15)
        d.text((tx + sw + 9, ty - 1), "Player start", font=fr, fill=(220, 255, 220, 255)); ty += rowh
    for enemy, g in groups.items():
        col = hex2rgb(g["color"])
        d.rounded_rectangle([tx, ty, tx + sw, ty + sw], radius=3, fill=col + (255,), outline=(255, 255, 255, 130))
        d.text((tx + sw + 9, ty - 1), f"{enemy}   ×{g['points']}   (pool {g['pool']})",
               font=fr, fill=(235, 238, 242, 255))
        ty += rowh
    if n_lad:
        draw_ladder(d, tx + sw // 2, ty + 1, ty + sw - 1)
        d.text((tx + sw + 9, ty - 1), f"Ladder  ×{n_lad}  (proposed)", font=fr, fill=(235, 238, 242, 255)); ty += rowh
    if n_rope:
        draw_rope(d, tx + sw // 2, ty + 1, ty + sw - 1)
        d.text((tx + sw + 9, ty - 1), f"Rope  ×{n_rope}  (proposed)", font=fr, fill=(235, 238, 242, 255)); ty += rowh
    for pt in portals:
        d.ellipse([tx + 3, ty, tx + sw - 3, ty + sw], outline=PORTAL_COL + (255,), width=2)
        d.text((tx + sw + 9, ty - 1), f"Portal  →  {pt['dest']}", font=fr, fill=(220, 245, 255, 255)); ty += rowh

    # Portal doorways drawn last so the edge ones sit on top of the legend, not behind it.
    for pt in portals:
        draw_portal(d, pt["x"] * SCALE + pad_l, pt["y_top"] * SCALE + pad_t,
                    pt["y_bottom"] * SCALE + pad_t, pt["dest"], font(BOLD, 13))
    if pspawn:
        draw_spawn(d, pspawn["x"] * SCALE + pad_l, pspawn["y"] * SCALE + pad_t)

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
