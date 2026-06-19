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

# ---------------- WATER: ANIMATED — 4 columns = anim frames, each tile on its own row -----------
# Sheet is 4x3 tiles (64x48): row0 surface, row1 body, row2 shallow-overlay; the 4 columns are the
# animation frames (the wave/dither pattern scrolls 4px per frame -> seamless horizontal flow).
# Muted-teal, dithered (not flat), wavy highlight lines, foam crest, sparkles; tileable.
FOAM = (198, 234, 238, 255); WHI = (128, 196, 206, 255); WMD = (72, 140, 156, 255)
WLO = (48, 104, 122, 255); WDK = (34, 80, 98, 255)
WAVE = [0, 1, 1, 0, 0, -1, -1, 0]   # period-8 -> tiles horizontally
water = Image.new("RGBA", (64, 48), T)

def wput(bx, by, x, y, c):
    if 0 <= x < 16 and 0 <= y < 16: water.putpixel((bx + x, by + y), c)

def draw_water(bx, by, sh, kind):   # one 16x16 frame at (bx,by), pattern scrolled by `sh`
    for x in range(16):
        sx = (x + sh) % 16
        y0 = 2 if kind == "surface" else 0
        for y in range(y0, 16):
            if kind == "overlay":
                c = (118, 176, 184, 96)
            else:
                c = WMD
                if (sx + y) % 2 == 0 and y >= 8: c = WLO
                if (sx * 3 + y * 5) % 11 == 0 and y >= 11: c = WDK
            wput(bx, by, x, y, c)
        if kind == "surface":                          # wavy foam crest
            cy = WAVE[sx % 8]
            wput(bx, by, x, 0, T if cy < 0 else FOAM)
            wput(bx, by, x, 1, FOAM if cy <= 0 else WHI)
    rows = [5, 11] if kind == "surface" else ([6, 12] if kind == "overlay" else [2, 8, 13])
    hi = (180, 224, 230, 150) if kind == "overlay" else WHI
    for x in range(16):
        sx = (x + sh) % 16
        for ry in rows:
            yy = ry + WAVE[sx % 8]
            wput(bx, by, x, yy, hi)
            if kind != "overlay" and yy + 1 < 16: wput(bx, by, x, yy + 1, WLO)
    if kind != "overlay":
        for spx, spy in [(3, 5), (10, 9), (6, 13), (13, 3)]:
            wput(bx, by, (spx + sh) % 16, spy, FOAM)

for ti, kind in enumerate(["surface", "body", "overlay"]):
    for f in range(4):
        draw_water(f * 16, ti * 16, f * 4, kind)        # 4 frames, scroll 4px each -> 16px loop
water.save(os.path.join(ROOT, "assets/sprites/water_tiles.png"))

# ---------------- STONE COLUMNS: L/M/R x capital/shaft/base/broken ------------------------------
# 3 cols (Left/Middle/Right edge) x 4 rows (capital/shaft/base/broken). Build a column of ANY width
# by tiling L + (N-2) M + R; stack shaft rows for height. Broken row = jagged ruined top.
SC_RUB = (96, 86, 106, 255)
col = Image.new("RGBA", (48, 64), T)
JAG = [5, 3, 6, 4, 7, 5, 4, 6, 3, 5, 6, 4, 7, 5, 3, 6]
def cput(x, y, c):
    if 0 <= x < 48 and 0 <= y < 64: col.putpixel((x, y), c)
def col_tile(cc, cr, edge, piece):       # cc col, cr row; edge 0L/1M/2R; piece 0cap/1shaft/2base/3broken
    bx, by = cc * 16, cr * 16
    for x in range(16):
        for y in range(16): cput(bx + x, by + y, S_MD)
    for fx in (3, 8, 13):                 # flutes (line up across tiles)
        for y in range(16): cput(bx + fx, by + y, S_LO)
    if edge == 0:                         # left edge
        for y in range(16): cput(bx + 0, by + y, OUT); cput(bx + 1, by + y, S_HI)
    elif edge == 2:                       # right edge
        for y in range(16): cput(bx + 15, by + y, OUT); cput(bx + 14, by + y, S_LO)
    if piece == 0:                        # capital: top molding band (full width -> tiles)
        for x in range(16):
            cput(bx + x, by + 0, OUT); cput(bx + x, by + 1, S_HI); cput(bx + x, by + 2, S_HI)
            cput(bx + x, by + 3, S_MD); cput(bx + x, by + 4, OUT)
    elif piece == 2:                      # base: bottom molding band
        for x in range(16):
            cput(bx + x, by + 11, OUT); cput(bx + x, by + 12, S_HI); cput(bx + x, by + 13, S_MD)
            cput(bx + x, by + 14, S_LO); cput(bx + x, by + 15, OUT)
    elif piece == 3:                      # broken: jagged top, rubble, clear above the break
        for x in range(16):
            t = JAG[x]
            for y in range(0, t): cput(bx + x, by + y, T)
            cput(bx + x, by + t, S_HI)
            if t + 1 < 16: cput(bx + x, by + t + 1, SC_RUB)
for piece in range(4):
    for edge in range(3):
        col_tile(edge, piece, edge, piece)
col.save(os.path.join(ROOT, "assets/sprites/stone_columns.png"))

# ---------------- 8x previews ----------------
for name in ["bridge_tiles", "water_tiles", "stone_columns"]:
    im = Image.open(os.path.join(ROOT, "assets/sprites/%s.png" % name)).convert("RGBA")
    bg = Image.new("RGBA", im.size, (40, 38, 48, 255)); bg.alpha_composite(im)
    bg.resize((im.width * 10, im.height * 10), Image.NEAREST).save(os.path.join(ROOT, "tools/_preview_%s.png" % name))
print("wrote bridge_tiles.png, water_tiles.png, stone_columns.png (+ previews)")
