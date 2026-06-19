#!/usr/bin/env python3
"""Draw the new 16px map tiles (bridge planks, water, stone columns) in the country-village
palette so they blend with the existing tileset. Saves three small atlas PNGs to
assets/sprites/. They get injected as TileSet atlas sources by the map generator (same as
grass_slopes.png). Also writes 8x-scaled _preview_*.png for eyeballing."""
import os
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = (0x2d, 0x1d, 0x2e, 255)
# wood (warm, distinct from rock but same value range)
W_HI, W_MD, W_LO = (198, 150, 98, 255), (150, 104, 62, 255), (96, 62, 40, 255)
# water (muted teal — no bright blue)
A_HI, A_MD, A_LO = (118, 176, 184, 255), (66, 128, 140, 255), (44, 88, 100, 255)
# stone (desaturated mauve-gray, reuses the purple-grays #664161/#47394a family)
S_HI, S_MD, S_LO = (150, 142, 158, 255), (110, 100, 122, 255), (71, 57, 74, 255)
T = (0, 0, 0, 0)

def sheet(n):  # n tiles wide, 16 tall, RGBA
    return Image.new("RGBA", (n * 16, 16), T)

def put(im, tx, x, y, c):
    if 0 <= x < 16 and 0 <= y < 16:
        im.putpixel((tx * 16 + x, y), c)

def hline(im, tx, y, x0, x1, c):
    for x in range(x0, x1 + 1): put(im, tx, x, y, c)

def vline(im, tx, x, y0, y1, c):
    for y in range(y0, y1 + 1): put(im, tx, x, y, c)

# ---------------- BRIDGE (planks): L end, mid, R end ----------------
def plank(im, tx, post=None):
    for x in range(16):
        put(im, tx, x, 0, W_HI); put(im, tx, x, 1, W_HI)
        put(im, tx, x, 2, W_MD); put(im, tx, x, 3, W_MD)
        put(im, tx, x, 4, W_LO); put(im, tx, x, 5, OUT)
    for sx in (3, 8, 13):                      # plank seams
        vline(im, tx, sx, 0, 4, W_LO)
    if post:                                    # hanging support post on an end
        px = 2 if post == "L" else 13
        vline(im, tx, px, 6, 14, W_MD); vline(im, tx, px - 1, 6, 14, W_LO if post == "R" else W_HI)
        vline(im, tx, px + 1, 6, 14, W_LO if post == "L" else W_HI)
        put(im, tx, px, 15, OUT)
bridge = sheet(3)
plank(bridge, 0, "L"); plank(bridge, 1); plank(bridge, 2, "R")
bridge.save(os.path.join(ROOT, "assets/sprites/bridge_tiles.png"))

# ---------------- WATER: surface, body, shallow overlay (alpha) ----------------
water = sheet(3)
# 0: surface — foam crest on top, deepening down
for x in range(16):
    put(water, 0, x, 0, T); put(water, 0, x, 1, A_HI)
    for y in range(2, 16):
        water.putpixel((x, y), A_MD if y < 9 else A_LO)
for x in range(0, 16, 4):                       # crest dips
    put(water, 0, x, 1, A_MD); put(water, 0, x + 1, 1, A_MD)
hline(water, 0, 6, 0, 15, A_LO); hline(water, 0, 12, 0, 15, A_HI)
# 1: body
for x in range(16):
    for y in range(16): water.putpixel((1 * 16 + x, y), A_MD)
hline(water, 1, 4, 0, 15, A_LO); hline(water, 1, 9, 0, 15, A_HI); hline(water, 1, 13, 0, 15, A_LO)
# 2: shallow overlay (semi-transparent — drawn OVER walkable ground)
OL = (118, 176, 184, 96); OLH = (150, 200, 208, 140)
for x in range(16):
    for y in range(16): water.putpixel((2 * 16 + x, y), OL)
for x in range(0, 16, 3): put(water, 2, x, 7, OLH); put(water, 2, x + 1, 8, OLH)
water.save(os.path.join(ROOT, "assets/sprites/water_tiles.png"))

# ---------------- STONE COLUMNS: capital, shaft, base, broken ----------------
col = sheet(4)
def shaft_body(im, tx, y0=0, y1=15):
    for y in range(y0, y1 + 1):
        for x in range(3, 13):
            im.putpixel((tx * 16 + x, y), S_MD)
        put(im, tx, 3, y, S_HI); put(im, tx, 4, y, S_HI)
        put(im, tx, 11, y, S_LO); put(im, tx, 12, y, S_LO)
        put(im, tx, 7, y, S_LO); put(im, tx, 8, y, S_HI)   # central flute
        put(im, tx, 2, y, OUT); put(im, tx, 13, y, OUT)
# capital (flared top)
shaft_body(col, 0, 4, 15)
for y in range(0, 4):
    hline(col, 0, y, 1, 14, S_HI if y < 2 else S_MD)
    put(col, 0, 0, y, OUT); put(col, 0, 15, y, OUT)
hline(col, 0, 4, 1, 14, OUT)
# shaft (repeating middle)
shaft_body(col, 1)
# base (flared bottom)
shaft_body(col, 2, 0, 11)
for y in range(12, 16):
    hline(col, 2, y, 1, 14, S_MD if y < 14 else S_LO)
    put(col, 2, 0, y, OUT); put(col, 2, 15, y, OUT)
hline(col, 2, 11, 1, 14, OUT)
# broken top (jagged)
shaft_body(col, 3, 5, 15)
jag = [0, 3, 1, 4, 2, 5, 2, 4, 1, 3]
for i, x in enumerate(range(3, 13)):
    top = 5 + jag[i % len(jag)] - 2
    put(col, 3, x, max(5, top), S_HI)
    for y in range(0, max(5, top)): put(col, 3, x, y, T)
col.save(os.path.join(ROOT, "assets/sprites/stone_columns.png"))

# ---------------- 8x previews ----------------
for name in ["bridge_tiles", "water_tiles", "stone_columns"]:
    im = Image.open(os.path.join(ROOT, "assets/sprites/%s.png" % name)).convert("RGBA")
    bg = Image.new("RGBA", im.size, (40, 38, 48, 255)); bg.alpha_composite(im)
    bg.resize((im.width * 10, im.height * 10), Image.NEAREST).save(os.path.join(ROOT, "tools/_preview_%s.png" % name))
print("wrote bridge_tiles.png, water_tiles.png, stone_columns.png (+ previews)")
