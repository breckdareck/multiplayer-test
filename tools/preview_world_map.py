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
# Emberwatch is the DEAD CENTRE of the wheel; all THREE spokes run STRAIGHT into
# it (no spiral). 4/4/4 spokes: each town is 4 maps from Emberwatch.
world["emberwatch"] = (0.500, 0.500)
emb = world["emberwatch"]
def interp(a,b,t): return (a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t)
spoke1 = ["ruins","old_battlefield","thornroot","the_reliquary"]                 # Lantern's delve
spoke2 = ["three_terraces","bandit_bluffs","dust_warren","wolfsreach"]           # Wickmoor overland
spoke3 = ["mirefen","stonereach","mines","the_undercroft"]                       # Hollowmere deep road
for i,m in enumerate(spoke1): world[m]=interp(world["lanterns_rest"],emb,(i+1)/(len(spoke1)+1))
for i,m in enumerate(spoke2): world[m]=interp(world["wickmoor"],emb,(i+1)/(len(spoke2)+1))
for i,m in enumerate(spoke3): world[m]=interp(world["hollowmere"],emb,(i+1)/(len(spoke3)+1))
CORE_GATE = (0.50, 0.63)   # synthetic gateway DIRECTLY below the centred Emberwatch

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

e1=render(world, CORE_GATE, "The Core  v", "tools/_wm_world.png", "WORLD view — rim + spokes + The Core gateway")
e2=render(core, SURFACE_GATE, "^ The Surface", "tools/_wm_core.png", "CORE view — Emberwatch -> the descent -> Warlord")
print("WORLD view:", len(world), "maps,", e1, "edges  |  CORE view:", len(core), "maps,", e2, "edges")
world_order = ring + ["emberwatch"] + spoke1 + spoke2 + spoke3
print("=== WORLD layout (bake into LAYOUT_WORLD) ===")
for m in world_order:
    print(f'\t"{m}": Vector2({world[m][0]:.3f}, {world[m][1]:.3f}),')
print("=== CORE layout (bake into LAYOUT_CORE) ===")
for m in core_order + ["warlord"]:
    print(f'\t"{m}": Vector2({core[m][0]:.3f}, {core[m][1]:.3f}),')
print(f"CORE_GATE Vector2({CORE_GATE[0]}, {CORE_GATE[1]})   SURFACE_GATE Vector2({SURFACE_GATE[0]}, {SURFACE_GATE[1]})")
