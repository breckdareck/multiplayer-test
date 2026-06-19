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

# ---------------- WATER: surface, body, shallow overlay — juiced (dither + waves + foam) -----
# Muted-teal palette with 5 values (matches the country style); dithering instead of flat bands,
# wavy highlight lines, a foam crest, and sparkles. Body tile is seamlessly tileable.
FOAM = (198, 234, 238, 255); WHI = (128, 196, 206, 255); WMD = (72, 140, 156, 255)
WLO = (48, 104, 122, 255); WDK = (34, 80, 98, 255)
WAVE = [0, 1, 1, 0, 0, -1, -1, 0]   # period-8 offset so highlight lines tile horizontally
water = sheet(3)

def body_px(tx, x, y):              # tileable body fill: dither deep into the lower half + sparse DK
    c = WMD
    if (x + y) % 2 == 0 and y >= 8: c = WLO
    if (x * 3 + y * 5) % 11 == 0 and y >= 11: c = WDK
    put(water, tx, x, y, c)

def waves(tx, rows):                # wavy HI highlight lines + a few foam sparkles
    for x in range(16):
        for ry in rows:
            yy = ry + WAVE[x % 8]
            put(water, tx, x, yy, WHI)
            if yy + 1 < 16: put(water, tx, x, yy + 1, WLO)
    for sx, sy in [(3, 5), (10, 9), (6, 13), (13, 3)]:
        put(water, tx, sx, sy, FOAM)

# 0: surface — wavy foam crest, then juiced body
for x in range(16):
    for y in range(2, 16): body_px(0, x, y)
for x in range(16):
    cy = WAVE[x % 8]                                  # crest rides the wave
    put(water, 0, x, 0, T if cy < 0 else FOAM)
    put(water, 0, x, 1, FOAM if cy <= 0 else WHI)
waves(0, [5, 11])
# 1: body — fully juiced, tileable
for x in range(16):
    for y in range(16): body_px(1, x, y)
waves(1, [2, 8, 13])
# 2: shallow overlay (semi-transparent — for wading-over-ground use)
OL = (118, 176, 184, 96); OLH = (180, 224, 230, 150)
for x in range(16):
    for y in range(16): water.putpixel((2 * 16 + x, y), OL)
for x in range(16):
    put(water, 2, x, 6 + WAVE[x % 8], OLH); put(water, 2, x, 12 + WAVE[x % 8], OLH)
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
