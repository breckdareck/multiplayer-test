#!/usr/bin/env python3
"""Generate + preview the TWO-VIEW radial world map and print both LAYOUT blocks to
bake into scripts/UI/world_map.gd.
  WORLD view  = outer ring + 3 spokes + Emberwatch + a synthetic "The Core" gateway.
  CORE view   = Emberwatch (entry) + the deep descent spiral to the Warlord + a
                synthetic "Surface" back gateway.
Renders tools/_wm_world.png and tools/_wm_core.png.
"""
import json, re, os, math
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageFont
W, H = 1780, 916
CX, CY = 0.5, 0.5

# ---- WORLD view positions: the Lantern's Rest ARM (crossway, Stage 2) ----
# Explicit coordinates kept in lockstep with LAYOUT_WORLD in scripts/UI/world_map.gd.
# Town far-left; a branchy low-frontier lens funnels at Ember-Meadows; the climb arcs
# along the bottom up into the centred Emberwatch. Right/top thirds open for future arms.
world = {
    "lanterns_rest":   (0.295, 0.500),
    "near_wilds":      (0.235, 0.500),
    "glimmerfen":      (0.175, 0.500),
    "tinderfields":    (0.115, 0.500),
    "ember_meadows":   (0.058, 0.500),
    "firefly_hollow":  (0.252, 0.372),
    "meadow_path":     (0.212, 0.268),
    "brackenway":      (0.172, 0.628),
    "bramble_downs":   (0.132, 0.732),
    "lanternwood":     (0.098, 0.372),
    "watchers_ruin":   (0.050, 0.268),
    "hollow_warren":   (0.040, 0.628),
    "beacon_rise":     (0.078, 0.732),
    "old_causeway":    (0.420, 0.500),
    "ruins":           (0.520, 0.500),
    "thornroot":       (0.620, 0.500),
    "old_battlefield": (0.715, 0.500),
    "the_reliquary":   (0.808, 0.500),
    "embergate":       (0.888, 0.500),
    "emberwatch":      (0.958, 0.500),
}
world_order = list(world.keys())
CORE_GATE = (0.950, 0.660)   # synthetic gateway DIRECTLY below Emberwatch (line's right end)

# ---- CORE view positions: an inward SPIRAL descent (Emberwatch -> Warlord centre) ----
# It's a spiral on purpose (a descent into the core), but spread out: the radius
# eases from the rim down to a healthy FLOOR (never collapsing onto the centre) and
# the turns are gentle, so consecutive maps stay well apart. Warlord is the centre.
core_order = ["emberwatch","deep_woods","keep","mustering_fields","the_scorchline","emberscar","cinderwaste","weave","the_unraveling","ashvigil"]
core = {}
CRX, CRY, CT, RFLOOR = 0.48, 0.44, 1.15, 0.26
N = len(core_order)
for i, m in enumerate(core_order):
    t = i/(N-1)                      # 0..1 rim->innermost
    rf = RFLOOR + (1.0 - RFLOOR) * (1 - t)   # 1.0 at rim -> RFLOOR at the last map
    ang = math.radians(90 - CT*360*t)
    core[m] = (0.5 + CRX*rf*math.cos(ang), 0.5 - CRY*rf*math.sin(ang))
core["warlord"] = (0.5, 0.5)
SURFACE_GATE = (0.085, 0.09)        # synthetic back-to-world gateway in the core view

cat = json.load(open(os.path.join(ROOT,"config/world_map_data.json")))["maps"]
hearths = {"lanterns_rest","wickmoor","hollowmere","emberwatch","ashvigil"}
try: F=ImageFont.truetype("arial.ttf",15); FT=ImageFont.truetype("arial.ttf",18)
except Exception: F=ImageFont.load_default(); FT=F

def lvl_label(m):
    info = cat.get(m, {})
    if m in hearths or info.get("is_town"):
        return "TOWN"
    lo, hi = info.get("min_level"), info.get("max_level")
    if lo is None:
        return ""
    return ("Lv %d" % lo) if lo == hi else ("Lv %d-%d" % (lo, hi))

def render(pos, gate, gate_label, fname, title):
    img=Image.new("RGB",(W,H),(8,10,18)); d=ImageDraw.Draw(img)
    def px(m): return (pos[m][0]*W, pos[m][1]*H)
    seen=set()
    for m in pos:
        for t in cat.get(m,{}).get("connections",[]):
            if t not in pos: continue
            k=tuple(sorted((m,t)))
            if k in seen: continue
            seen.add(k); d.line([px(m),px(t)],fill=(150,138,96),width=3)
    # gateway edge: emberwatch <-> gate
    gx=(gate[0]*W,gate[1]*H)
    d.line([px("emberwatch"),gx],fill=(120,150,200),width=3)
    R=14
    for m in pos:
        x,y=px(m); col=(230,90,90) if m=="warlord" else (255,209,77) if m in hearths else (128,199,140)
        (d.rectangle if (m in hearths or m=="warlord") else d.ellipse)([x-R,y-R,x+R,y+R],fill=col,outline=(20,20,20))
        nm=cat.get(m,{}).get("display_name") or m
        tb=d.textbbox((0,0),nm,font=F); d.text((x-(tb[2]-tb[0])/2,y+R+2),nm,fill=(228,228,228),font=F)
        ll=lvl_label(m)
        if ll:
            tb2=d.textbbox((0,0),ll,font=F)
            d.text((x-(tb2[2]-tb2[0])/2,y+R+19),ll,fill=(255,209,77) if ll=="TOWN" else (120,196,255),font=F)
    # gateway node (purple, double ring)
    d.ellipse([gx[0]-19,gx[1]-19,gx[0]+19,gx[1]+19],fill=(150,110,210),outline=(230,220,255))
    d.ellipse([gx[0]-11,gx[1]-11,gx[0]+11,gx[1]+11],outline=(20,16,30))
    tb=d.textbbox((0,0),gate_label,font=FT); d.text((gx[0]-(tb[2]-tb[0])/2,gx[1]+22),gate_label,fill=(210,190,255),font=FT)
    d.text((20,16),title,fill=(150,150,160),font=FT)
    img.save(os.path.join(ROOT,fname)); return len(seen)

e1=render(world, CORE_GATE, "The Core  v", "tools/_wm_world.png", "WORLD view — Lantern's Rest arm (Lv2-47) -> Emberwatch + The Core gateway")
e2=render(core, SURFACE_GATE, "^ The Surface", "tools/_wm_core.png", "CORE view — Emberwatch -> the descent -> Warlord")
print("WORLD view:", len(world), "maps,", e1, "edges  |  CORE view:", len(core), "maps,", e2, "edges")
print("=== WORLD layout (bake into LAYOUT_WORLD) ===")
for m in world_order:
    print(f'\t"{m}": Vector2({world[m][0]:.3f}, {world[m][1]:.3f}),')
print("=== CORE layout (bake into LAYOUT_CORE) ===")
for m in core_order + ["warlord"]:
    print(f'\t"{m}": Vector2({core[m][0]:.3f}, {core[m][1]:.3f}),')
print(f"CORE_GATE Vector2({CORE_GATE[0]}, {CORE_GATE[1]})   SURFACE_GATE Vector2({SURFACE_GATE[0]}, {SURFACE_GATE[1]})")
