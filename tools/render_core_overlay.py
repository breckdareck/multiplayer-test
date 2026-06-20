#!/usr/bin/env python3
"""Overlay the Core descent pins onto the painted Core map (assets/sprites/ui/core_map_bg.png):
a spiral from the rim (Emberwatch, the descent entry) inward to the Warlord on the throne at the
dead centre. Renders tools/_wm_core_overlay.png and emits the CoreArea scene block to
tools/_core_pins.txt. Mirrors render_world_overlay.py (anchor-normalised, centred 24px hit-boxes)."""
import json, os, math
from PIL import Image, ImageDraw, ImageFont
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG = os.path.join(ROOT, "assets/sprites/ui/core_map_bg.png")

# descent order, rim -> centre (matches the portal chain emberwatch..warlord)
ORDER = ["emberwatch", "deep_woods", "keep", "mustering_fields", "the_scorchline",
         "emberscar", "cinderwaste", "weave", "the_unraveling", "ashvigil", "warlord"]
CENTER = (0.500, 0.470)     # the Warlord's throne
RX, RY = 0.430, 0.400       # rim radii (normalised)
TURNS = 1.55                # spiral turns rim -> centre
START = 90.0                # rim entry at top
SURFACE_GATE = (0.078, 0.090)

pos = {}
N = len(ORDER)
for i, m in enumerate(ORDER):
    if m == "warlord":
        pos[m] = CENTER; continue
    t = i / float(N - 1)
    rf = 1.0 - t
    ang = math.radians(START - TURNS * 360.0 * t)
    pos[m] = (CENTER[0] + RX * rf * math.cos(ang), CENTER[1] - RY * rf * math.sin(ang))

cat = json.load(open(os.path.join(ROOT, "config/world_map_data.json")))["maps"]
hearths = {"lanterns_rest", "wickmoor", "hollowmere", "emberwatch"}
img = Image.open(BG).convert("RGBA"); W, H = img.size
img = Image.alpha_composite(img, Image.new("RGBA", (W, H), (8, 6, 10, 70)))
d = ImageDraw.Draw(img)
def _font(sz, bold=False):
    for nm in ((["arialbd.ttf", "arial.ttf"]) if bold else ["arial.ttf"]):
        try: return ImageFont.truetype(nm, sz)
        except Exception: pass
    return ImageFont.load_default()
F = _font(15); FS = _font(12); FC = _font(18, True)
def P(m): return (pos[m][0] * W, pos[m][1] * H)
def lvl(m):
    info = cat.get(m, {})
    if m in hearths: return "TOWN"
    lo, hi = info.get("min_level"), info.get("max_level")
    if lo is None: return ""
    return "Lv %d" % lo if lo == hi else "Lv %d-%d" % (lo, hi)
def ctext(xy, s, font, fill, sh=(0, 0, 0)):
    x, y = xy; b = d.textbbox((0, 0), s, font=font); x -= (b[2] - b[0]) / 2
    for ox, oy in [(-1, -1), (1, -1), (-1, 1), (1, 1)]: d.text((x + ox, y + oy), s, font=font, fill=sh)
    d.text((x, y), s, font=font, fill=fill)

seen = set()
for m in pos:
    for t in cat.get(m, {}).get("connections", []):
        if t not in pos: continue
        k = tuple(sorted((m, t)))
        if k in seen: continue
        seen.add(k); a = P(m); b = P(t)
        d.line([a, b], fill=(20, 10, 8, 220), width=5); d.line([a, b], fill=(220, 150, 90), width=2)
R = 9
for m in pos:
    x, y = P(m); is_boss = (m == "warlord"); is_town = m in hearths
    col = (214, 86, 74) if is_boss else (238, 196, 96) if is_town else (210, 170, 150)
    if is_town or is_boss:
        d.rectangle([x - R - 2, y - R - 2, x + R + 2, y + R + 2], fill=col, outline=(20, 14, 12), width=2)
    else:
        d.ellipse([x - R, y - R, x + R, y + R], fill=col, outline=(20, 14, 12), width=2)
        d.ellipse([x - 3, y - 4, x - 1, y - 2], fill=(255, 255, 255))
    nm = cat.get(m, {}).get("display_name") or m
    ctext((x, y + R + 2), nm, FC if (is_town or is_boss) else F, (255, 230, 190))
    ll = lvl(m)
    if ll and not is_town: ctext((x, y + R + 18), ll, FS, (255, 190, 150))
gx, gy = SURFACE_GATE[0] * W, SURFACE_GATE[1] * H
d.ellipse([gx - 13, gy - 13, gx + 13, gy + 13], fill=(150, 110, 70), outline=(235, 215, 180), width=2)
ctext((gx, gy + 16), "^ The Surface", FC, (235, 215, 180))
img.convert("RGB").save(os.path.join(ROOT, "tools/_wm_core_overlay.png"))
print("core overlay: %d pins, %d roads on %dx%d" % (len(pos), len(seen), W, H))

# ---- emit the CoreArea scene block (sibling of MapArea under WorldMap) ----
def pin_node(parent, name, mid, nx, ny):
    return ('\n[node name="%s" type="Control" parent="%s"]\n'
            'layout_mode = 1\nanchor_left = %.4f\nanchor_top = %.4f\nanchor_right = %.4f\nanchor_bottom = %.4f\n'
            'offset_left = -12.0\noffset_top = -12.0\noffset_right = 12.0\noffset_bottom = 12.0\n'
            'mouse_filter = 2\nscript = ExtResource("wm_pin")\nmap_id = "%s"\n'
            % (name, parent, nx, ny, nx, ny, mid))
CP = "MoveableWindows/WorldMap/CoreArea/CorePins"
blk = (
    '\n[node name="CoreArea" type="TextureRect" parent="MoveableWindows/WorldMap"]\n'
    'visible = false\nlayout_mode = 1\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\n'
    'grow_horizontal = 2\ngrow_vertical = 2\nmouse_filter = 2\ntexture = ExtResource("core_bg")\nexpand_mode = 1\n'
    '\n[node name="CoreEdges" type="Control" parent="MoveableWindows/WorldMap/CoreArea"]\n'
    'layout_mode = 1\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\n'
    'grow_horizontal = 2\ngrow_vertical = 2\nmouse_filter = 2\nscript = ExtResource("wm_edges")\n'
    '\n[node name="CorePins" type="Control" parent="MoveableWindows/WorldMap/CoreArea"]\n'
    'layout_mode = 1\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\n'
    'grow_horizontal = 2\ngrow_vertical = 2\nmouse_filter = 2\n'
)
for m in ORDER:
    blk += pin_node(CP, m, m, *pos[m])
blk += pin_node(CP, "SurfaceGate", "__surface__", *SURFACE_GATE)
open(os.path.join(ROOT, "tools/_core_pins.txt"), "w").write(blk)
print("wrote tools/_core_pins.txt (%d chars)" % len(blk))
