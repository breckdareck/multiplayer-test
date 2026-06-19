#!/usr/bin/env python3
"""Side-profile SKETCHES of the proposed new map archetypes (concept art for sign-off).
RULES baked in: jump height = 1 tile, so every higher tier is reached by a ROPE or a
2:1 down-SLOPE you can walk up. Tiered spawns (SAFE high, clustered low) per MapleStory."""
import os
from PIL import Image, ImageDraw, ImageFont
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 1820, 1240
GRASS = (118, 178, 96); DIRT = (120, 92, 64); ROCK = (96, 92, 104); ROCKD = (58, 56, 68)
PLAT = (196, 170, 110); ROPE = (212, 192, 120); WATER = (70, 120, 180); WATERS = (120, 170, 220)
WOOD = (150, 110, 70); COL = (150, 150, 168); ENEMY = (224, 96, 96); SAFE = (110, 210, 130)
try:
    FT = ImageFont.truetype("arialbd.ttf", 26); FN = ImageFont.truetype("arial.ttf", 17); FS = ImageFont.truetype("arial.ttf", 15)
    FB = ImageFont.truetype("arialbd.ttf", 19)
except Exception:
    FT = ImageFont.load_default(); FN = FT; FS = FT; FB = FT
img = Image.new("RGB", (W, H), (12, 14, 22)); d = ImageDraw.Draw(img)
d.text((40, 16), "New map archetypes — jump = 1 tile, so every higher tier needs a ROPE (climb) or a 2:1 down-SLOPE (walk up).",
       fill=(255, 224, 150), font=FB)

def cell(cx, cy, w, h, title, sub):
    d.rectangle([cx, cy, cx + w, cy + h], outline=(46, 50, 64), width=2)
    d.text((cx + 14, cy + 8), title, fill=(255, 220, 150), font=FT)
    d.text((cx + 14, cy + 38), sub, fill=(150, 152, 165), font=FS)
    return (cx + 14, cy + 66, w - 28, h - 80)

def ground(x, y, w, h):
    d.rectangle([x, y, x + w, y + h], fill=DIRT); d.rectangle([x, y, x + w, y + 7], fill=GRASS)
def rock(x, y, w, h):
    d.rectangle([x, y, x + w, y + h], fill=ROCK); d.rectangle([x, y, x + w, y + 6], fill=(120, 116, 130))
def plat(x, y, pw=70):
    d.rectangle([x, y, x + pw, y + 8], fill=PLAT)
def ramp(x, y, w, up):  # 2:1 walkable slope, rises `up` px over width w
    d.polygon([(x, y), (x + w, y - up), (x + w, y + 10), (x, y + 10)], fill=DIRT)
    d.line([(x, y), (x + w, y - up)], fill=GRASS, width=6)
def rope(x, y0, y1):
    yy = y0
    while yy < y1:
        d.line([x, yy, x, min(yy + 9, y1)], fill=ROPE, width=3); yy += 16
    d.text((x + 6, (y0 + y1) // 2 - 8), "rope", fill=ROPE, font=FS)
def enemies(x, y, n):
    for i in range(n): d.ellipse([x + i * 24, y - 15, x + i * 24 + 13, y - 2], fill=ENEMY)
def safe(x, y):
    d.ellipse([x, y - 17, x + 15, y - 2], fill=SAFE); d.text((x + 20, y - 18), "SAFE", fill=SAFE, font=FS)

CY = 88
# ---- 1. Terraces ----
x, y, w, h = cell(40, CY, 560, 540, "Terraces", "stacked shelves linked by ROPES (tall gaps) or 2:1 SLOPES (short gaps)")
base = y + h
ground(x, base - 50, w, 50)
ground(x + int(0.16 * w), base - 120, int(0.40 * w), 12)
ground(x + int(0.40 * w), base - 200, int(0.42 * w), 12)
enemies(x + 40, base - 50, 3); enemies(x + int(0.20 * w), base - 120, 3)
ramp(x + int(0.10 * w), base - 50, 90, 70)        # slope floor->shelf1 (walk up)
rope(x + int(0.44 * w), base - 200, base - 120)   # rope shelf1->shelf2
safe(x + int(0.44 * w) + 30, base - 200)
d.text((x, base + 4), "left ramp = walk up; rope = climb.   tiles: existing  (NO new)", fill=SAFE, font=FS)

# ---- 2. Gorge ----
x, y, w, h = cell(620, CY, 560, 540, "Gorge", "two rims + a chasm; cross the BRIDGE at walk-level, rope up for the safe ledge")
base = y + h
ground(x, base - 60, int(0.34 * w), 60); ground(x + int(0.66 * w), base - 60, int(0.34 * w), 60)
bx0, bx1, by = x + int(0.34 * w), x + int(0.66 * w), base - 60     # bridge AT rim walk level
for px in range(bx0, bx1, 14): d.rectangle([px, by, px + 10, by + 8], fill=WOOD)
plat(x + int(0.18 * w), base - 130); rope(x + int(0.20 * w), base - 130, base - 60)
enemies(x + 30, base - 60, 3); enemies(bx0 + 50, by - 2, 3); enemies(x + int(0.72 * w), base - 60, 3)
safe(x + int(0.18 * w) + 20, base - 130)
d.text((x, base + 4), "bridge = flat walk across (no jump).   tiles: existing + NEW bridge planks", fill=(255, 200, 120), font=FS)

# ---- 3. Shaft / Ropeworks ----
x, y, w, h = cell(1200, CY, 580, 540, "Shaft / Ropeworks", "tall + narrow; a rope reaches EVERY ledge (ledges are >1 tile apart)")
base = y + h
rock(x, y, 54, h); rock(x + w - 54, y, 54, h)
ground(x + 54, base - 28, w - 108, 28)
inner = x + 54; iw = w - 108
for fx, up in [(0.12, 80), (0.50, 150), (0.22, 220), (0.55, 300)]:
    lx = inner + int(fx * iw); plat(lx, base - up, 80); enemies(lx + 8, base - up, 2)
rope(inner + int(0.16 * iw), base - 220, base - 28)
rope(inner + int(0.52 * iw), base - 300, base - 150)
safe(inner + int(0.22 * iw) + 6, base - 220)
d.text((x, base + 4), "rope is the ascent (no jump-only gaps).   tiles: existing  (NO new)", fill=SAFE, font=FS)

CY2 = 650
# ---- 4. Causeway (water = scene, NOT a hazard) ----
x, y, w, h = cell(40, CY2, 560, 540, "Causeway", "WATER is backdrop only — fully walkable shallows, no swim, no damage")
base = y + h
d.rectangle([x, base - 60, x + w, base], fill=WATER)              # background water body (deep blue = scenic)
ground(x, base - 60, w, 18)                                        # continuous WALKABLE shallow path (mud/grass)
for wx in range(x, x + w, 20): d.arc([wx, base - 64, wx + 20, base - 54], 200, 340, fill=WATERS, width=2)
enemies(x + 40, base - 60, 3); enemies(x + int(0.62 * w), base - 60, 3)
plat(x + int(0.30 * w), base - 120); plat(x + int(0.52 * w), base - 120)   # +1 tile = jumpable
plat(x + int(0.42 * w), base - 190); rope(x + int(0.44 * w), base - 190, base - 120)
safe(x + int(0.42 * w) + 6, base - 190)
d.text((x, base + 4), "you WALK the whole strip; water is visual depth.   tiles: existing + NEW shallow-water overlay", fill=(255, 200, 120), font=FS)

# ---- 5. Warren (how pockets connect) ----
x, y, w, h = cell(620, CY2, 560, 540, "Warren", "rooms link by HORIZONTAL tunnels (walk) + ROPES where floors differ")
base = y + h
d.rectangle([x, y, x + w, base], fill=ROCKD)
def room(fx, fy, fw, fh):
    rx, ry, rw, rh = x + int(fx * w), y + int(fy * h), int(fw * w), int(fh * h)
    d.rectangle([rx, ry, rx + rw, ry + rh], fill=(30, 28, 38))
    d.rectangle([rx, ry + rh - 7, rx + rw, ry + rh], fill=ROCK)
    return (rx, ry, rw, rh)
R1 = room(0.05, 0.55, 0.26, 0.34); R2 = room(0.39, 0.55, 0.22, 0.34); R3 = room(0.70, 0.52, 0.25, 0.37)  # same low floor
R4 = room(0.20, 0.10, 0.24, 0.30); R5 = room(0.56, 0.12, 0.26, 0.30)                                       # upper floor
# horizontal tunnels (same-floor walk-through) = carve a channel between adjacent rooms
def tunnel(a, b):
    ay = a[1] + a[3] - 16; d.rectangle([a[0] + a[2], ay, b[0], ay + 16], fill=(30, 28, 38)); d.rectangle([a[0] + a[2], ay + 9, b[0], ay + 16], fill=ROCK)
tunnel(R1, R2); tunnel(R2, R3)
# ropes from upper rooms down into the lower corridor
rope(R4[0] + R4[2] // 2, R4[1] + R4[3], R1[1])
rope(R5[0] + R5[2] // 2, R5[1] + R5[3], R3[1])
for r in [R1, R2, R3, R4, R5]: enemies(r[0] + 12, r[1] + r[3] - 7, 2)
d.text((x, base + 4), "dead-end room = one entrance = grind pocket.   tiles: existing rock + black fill  (NO new)", fill=SAFE, font=FS)

# ---- 6. Hall / Ruins (columns) ----
x, y, w, h = cell(1200, CY2, 580, 540, "Hall / Ruins", "columns are DECORATION — floor stays open (walk past); climb a rope for the upper tier")
base = y + h
ground(x, base - 30, w, 30)                                        # one open, continuous walk floor
for fx in [0.14, 0.40, 0.66, 0.90]:                                # columns: BACKGROUND, non-colliding
    cxp = x + int(fx * w)
    d.rectangle([cxp, base - 240, cxp + 22, base - 30], fill=(72, 70, 84))   # darker = behind player
    d.rectangle([cxp - 5, base - 250, cxp + 27, base - 238], fill=(96, 94, 110))
d.text((x + 6, base - 60), "← walk freely past columns (bottom passthrough) →", fill=(150, 152, 165), font=FS)
plat(x + int(0.30 * w), base - 150); plat(x + int(0.55 * w), base - 150)     # upper broken ledges
plat(x + int(0.45 * w), base - 220)
rope(x + int(0.47 * w), base - 220, base - 30)
enemies(x + 40, base - 30, 4); enemies(x + int(0.32 * w), base - 150, 2)
safe(x + int(0.45 * w) + 6, base - 220)
d.text((x, base + 4), "columns don't block; only upper ledges are climbed.   tiles: existing + NEW columns (background)", fill=(255, 200, 120), font=FS)

img.save(os.path.join(ROOT, "tools/_archetype_sketches.png"))
print("rendered tools/_archetype_sketches.png")
