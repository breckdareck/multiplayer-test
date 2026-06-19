#!/usr/bin/env python3
"""Generate + preview the radial world-map layout, then print coords to bake into
scripts/UI/world_map.gd LAYOUT. The main path (Lantern's Rest -> spoke1 ->
Emberwatch -> Core -> Warlord) is laid as ONE rim-to-centre spiral; the outer ring
is an even loop; spokes 2/3 interpolate hearth->Emberwatch.
Output: tools/_world_map_preview.png  + printed LAYOUT block.
"""
import json, re, os, math
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageFont

W, H = 1780, 916
CX, CY = 0.5, 0.5
RX, RY = 0.46, 0.43         # perimeter radii (normalized)
TURNS = 1.35                # spiral turns rim->centre
R_START = 0.56              # spiral start radius (well inside the ring)
R_FLOOR = 0.15             # inner core nodes ring around the boss (don't collapse to centre)
ANG0 = 90                   # spiral start angle (deg)

ring = ["lanterns_rest","near_wilds","meadow_path","wickmoor","tinderfields",
        "ember_meadows","hollowmere","bramble_downs","brackenway"]
main = ["ruins","old_battlefield","thornroot","mines","the_undercroft","emberwatch",
        "deep_woods","keep","mustering_fields","the_scorchline","emberscar",
        "cinderwaste","weave","the_unraveling","ashvigil","warlord"]
spoke2 = ["three_terraces","bandit_bluffs","dust_warren"]   # wickmoor -> emberwatch
spoke3 = ["mirefen","stonereach"]                            # hollowmere -> emberwatch

def polar(rf, ang):
    a = math.radians(ang)
    return (CX + RX*rf*math.cos(a), CY - RY*rf*math.sin(a))

pos = {}
# outer ring evenly around perimeter, Lantern's Rest at top, clockwise
n = len(ring)
for i, m in enumerate(ring):
    pos[m] = polar(1.0, 90 - i*(360.0/n))
# main spiral (ruins..ashvigil sit on a floored spiral; warlord alone at the centre)
inner = main[:-1]   # exclude warlord
k = len(inner)
for i, m in enumerate(inner):
    t = i/(k-1)
    rf = R_FLOOR + (R_START - R_FLOOR)*(1.0 - t)
    pos[m] = polar(rf, ANG0 - TURNS*360.0*t)
pos["warlord"] = (0.5, 0.5)
# spokes 2/3 interpolate
def interp(a, b, t): return (a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t)
emb = pos["emberwatch"]
for i, m in enumerate(spoke2): pos[m] = interp(pos["wickmoor"], emb, (i+1)/(len(spoke2)+1))
for i, m in enumerate(spoke3): pos[m] = interp(pos["hollowmere"], emb, (i+1)/(len(spoke3)+1))

# --- render ---
cat = json.load(open(os.path.join(ROOT, "config/world_map_data.json")))["maps"]
hearths = {"lanterns_rest","wickmoor","hollowmere","emberwatch","ashvigil"}
def px(m): return (pos[m][0]*W, pos[m][1]*H)
img = Image.new("RGB", (W, H), (8, 10, 18)); d = ImageDraw.Draw(img)
try: fsm = ImageFont.truetype("arial.ttf", 14); ftt = ImageFont.truetype("arial.ttf", 17)
except Exception: fsm = ImageFont.load_default(); ftt = fsm
seen = set()
for m, info in cat.items():
    if m not in pos: continue
    for t in info.get("connections", []):
        if t not in pos: continue
        key = tuple(sorted((m, t)))
        if key in seen: continue
        seen.add(key); d.line([px(m), px(t)], fill=(150,138,96), width=3)
R = 14
for m in pos:
    x, y = px(m)
    col = (230,90,90) if m == "warlord" else (255,209,77) if m in hearths else (128,199,140)
    if m in hearths or m == "warlord": d.rectangle([x-R,y-R,x+R,y+R], fill=col, outline=(20,20,20))
    else: d.ellipse([x-R,y-R,x+R,y+R], fill=col, outline=(20,20,20))
    name = cat.get(m, {}).get("display_name") or m
    tb = d.textbbox((0,0), name, font=fsm)
    d.text((x-(tb[2]-tb[0])/2, y+R+2), name, fill=(228,228,228), font=fsm)
d.text((20,16), f"Radial world preview — {len(pos)} maps, {len(seen)} edges (TURNS={TURNS}, R_START={R_START})", fill=(150,150,160), font=ftt)
img.save(os.path.join(ROOT, "tools/_world_map_preview.png"))

# --- print LAYOUT block to bake ---
order = ring + ["emberwatch"] + [m for m in main if m != "emberwatch"] + spoke2 + spoke3
print("=== paste into world_map.gd LAYOUT ===")
for m in order:
    if m in pos: print(f'\t"{m}": Vector2({pos[m][0]:.3f}, {pos[m][1]:.3f}),')
print("wrote tools/_world_map_preview.png ; maps:", len(pos), "edges:", len(seen))
