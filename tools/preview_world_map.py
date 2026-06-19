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

# ---- WORLD view positions (outer ring + spokes + emberwatch) ----
RX, RY = 0.44, 0.42
def polar(rf, ang, rx=RX, ry=RY):
    a = math.radians(ang); return (CX + rx*rf*math.cos(a), CY - ry*ry/ry*rf*math.sin(a)) if False else (CX + rx*rf*math.cos(a), CY - ry*rf*math.sin(a))
ring = ["lanterns_rest","near_wilds","meadow_path","wickmoor","tinderfields","ember_meadows","hollowmere","bramble_downs","brackenway"]
world = {}
for i, m in enumerate(ring):
    world[m] = polar(1.0, 90 - i*(360.0/len(ring)))
# spoke1 spiral (rim->emberwatch), like the single-view spiral but ending at emberwatch
spoke1 = ["ruins","old_battlefield","thornroot","mines","the_undercroft","emberwatch"]
for i, m in enumerate(spoke1):
    t = i/(len(spoke1)-1)
    world[m] = polar(0.56*(1-t)+0.18*t*0, 90 - 1.05*360*t) if False else polar(0.56 - 0.40*t, 90 - 1.05*360*t)
emb = world["emberwatch"]
def interp(a,b,t): return (a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t)
for i,m in enumerate(["three_terraces","bandit_bluffs","dust_warren"]): world[m]=interp(world["wickmoor"],emb,(i+1)/4)
for i,m in enumerate(["mirefen","stonereach"]): world[m]=interp(world["hollowmere"],emb,(i+1)/3)
CORE_GATE = (0.50, 0.58)   # synthetic gateway in the world view (clearly below Emberwatch)

# ---- CORE view positions (emberwatch entry + deep descent spiral to warlord) ----
core_order = ["emberwatch","deep_woods","keep","mustering_fields","the_scorchline","emberscar","cinderwaste","weave","the_unraveling","ashvigil"]
core = {}
CRX, CRY, CT = 0.42, 0.40, 1.5
for i, m in enumerate(core_order):
    t = i/len(core_order)            # 0..(<1); warlord is the centre
    core[m] = (CX + CRX*(1-t)*math.cos(math.radians(90 - CT*360*t)),
               CY - CRY*(1-t)*math.sin(math.radians(90 - CT*360*t)))
core["warlord"] = (0.5, 0.5)
SURFACE_GATE = (0.085, 0.09)        # synthetic back-to-world gateway in the core view

cat = json.load(open(os.path.join(ROOT,"config/world_map_data.json")))["maps"]
hearths = {"lanterns_rest","wickmoor","hollowmere","emberwatch","ashvigil"}
try: F=ImageFont.truetype("arial.ttf",15); FT=ImageFont.truetype("arial.ttf",18)
except Exception: F=ImageFont.load_default(); FT=F

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
    # gateway node (purple, double ring)
    d.ellipse([gx[0]-19,gx[1]-19,gx[0]+19,gx[1]+19],fill=(150,110,210),outline=(230,220,255))
    d.ellipse([gx[0]-11,gx[1]-11,gx[0]+11,gx[1]+11],outline=(20,16,30))
    tb=d.textbbox((0,0),gate_label,font=FT); d.text((gx[0]-(tb[2]-tb[0])/2,gx[1]+22),gate_label,fill=(210,190,255),font=FT)
    d.text((20,16),title,fill=(150,150,160),font=FT)
    img.save(os.path.join(ROOT,fname)); return len(seen)

e1=render(world, CORE_GATE, "The Core  v", "tools/_wm_world.png", "WORLD view — rim + spokes + The Core gateway")
e2=render(core, SURFACE_GATE, "^ The Surface", "tools/_wm_core.png", "CORE view — Emberwatch -> the descent -> Warlord")
print("WORLD view:", len(world), "maps,", e1, "edges  |  CORE view:", len(core), "maps,", e2, "edges")
world_order = ring + ["ruins","old_battlefield","thornroot","mines","the_undercroft","emberwatch","three_terraces","bandit_bluffs","dust_warren","mirefen","stonereach"]
print("=== WORLD layout (bake into LAYOUT_WORLD) ===")
for m in world_order:
    print(f'\t"{m}": Vector2({world[m][0]:.3f}, {world[m][1]:.3f}),')
print("=== CORE layout (bake into LAYOUT_CORE) ===")
for m in core_order + ["warlord"]:
    print(f'\t"{m}": Vector2({core[m][0]:.3f}, {core[m][1]:.3f}),')
print(f"CORE_GATE Vector2({CORE_GATE[0]}, {CORE_GATE[1]})   SURFACE_GATE Vector2({SURFACE_GATE[0]}, {SURFACE_GATE[1]})")
