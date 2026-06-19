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
# THREE radial fishbone arms (opt7) around the centred Emberwatch. Each arm: name lists in slot
# order [s1-4, p1a-p4b, c1-6]; the climb runs INWARD to Emberwatch, town sits between climb and
# frontier, pockets branch perpendicular off the spine (sides alternate).
ARMS = [
    (66,  "lanterns_rest", ["near_wilds","glimmerfen","tinderfields","ember_meadows",
        "firefly_hollow","meadow_path","brackenway","bramble_downs",
        "lanternwood","watchers_ruin","hollow_warren","beacon_rise",
        "old_causeway","ruins","thornroot","old_battlefield","the_reliquary","embergate"]),
    (186, "wickmoor", ["reedmire","sodden_flats","heatherreach","blackpeat",
        "glowmoss_burrow","peat_steps","the_brackens","gorse_downs",
        "willowmere","drowned_shrine","mudwarren","bogbeacon",
        "long_ford","the_sluice","mirewarren","bonemarsh","the_oubliette","marshgate"]),
    (306, "hollowmere", ["the_shallows","craghollow","echo_downs","greymoor",
        "pebble_warren","cairn_steps","gullstone_bluffs","windward_downs",
        "mistfield","sunken_hall","hollow_deep","beacon_crag",
        "stone_span","riftway","gravewarren","shattercliffs","deepshaft","hollowgate"]),
]
SPINE_R = [0.355, 0.395, 0.435, 0.475]
POCKET = [(0.348, 0.060),(0.342, 0.115), (0.388,-0.060),(0.382,-0.115),
          (0.428, 0.060),(0.422, 0.115), (0.468,-0.060),(0.462,-0.115)]
CLIMB_R = [0.275, 0.235, 0.195, 0.155, 0.115, 0.075]   # c1..c6 (c6 nearest the centre)
def arm_pos(angle, idx):
    a = math.radians(angle); ux, uy = math.cos(a), -math.sin(a); px, py = -math.sin(a), -math.cos(a)
    if idx < 4:    r, off = SPINE_R[idx], 0.0
    elif idx < 12: r, off = POCKET[idx-4]
    else:          r, off = CLIMB_R[idx-12], 0.0
    return (0.5 + ux*r + px*off, 0.5 + uy*r + py*off)
world = {"emberwatch": (0.5, 0.5)}
for angle, town, names in ARMS:
    a = math.radians(angle); ux, uy = math.cos(a), -math.sin(a)
    world[town] = (0.5 + ux*0.315, 0.5 + uy*0.315)
    for i, nm in enumerate(names):
        world[nm] = arm_pos(angle, i)
world_order = list(world.keys())
CORE_GATE = (0.5, 0.605)   # gateway in the lower gap between the two bottom arms

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
try: F=ImageFont.truetype("arial.ttf",12); FT=ImageFont.truetype("arial.ttf",16)
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
