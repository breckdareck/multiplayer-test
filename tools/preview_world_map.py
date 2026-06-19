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
from PIL import Image, ImageDraw, ImageFont, ImageFilter
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
    (90,  "lanterns_rest", ["near_wilds","glimmerfen","tinderfields","ember_meadows",
        "firefly_hollow","meadow_path","brackenway","bramble_downs",
        "lanternwood","watchers_ruin","hollow_warren","beacon_rise",
        "old_causeway","ruins","thornroot","old_battlefield","the_reliquary","embergate"]),
    (210, "wickmoor", ["reedmire","sodden_flats","heatherreach","blackpeat",
        "glowmoss_burrow","peat_steps","the_brackens","gorse_downs",
        "willowmere","drowned_shrine","mudwarren","bogbeacon",
        "long_ford","the_sluice","mirewarren","bonemarsh","the_oubliette","marshgate"]),
    (330, "hollowmere", ["the_shallows","craghollow","echo_downs","greymoor",
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
def _font(sz, bold=False):
    for nm in ((["arialbd.ttf","arial.ttf"]) if bold else ["arial.ttf"]):
        try: return ImageFont.truetype(nm, sz)
        except Exception: pass
    return ImageFont.load_default()
F=_font(13); FS=_font(11); FT=_font(20, True); FC=_font(15, True)

# aged-map palette (dark war-table parchment, warm amber ink)
PAPER=(28,22,16); PAPER2=(40,32,23); INK=(214,196,160); INK_DIM=(150,134,104)
ROAD=(150,124,78); ROAD_GLOW=(70,54,30); GRAT=(52,42,30); FRAME=(120,96,58)
C_TOWN=(238,196,96); C_BOSS=(214,86,74); C_FIELD=(150,176,120); C_GATE=(168,128,210)
REGION_COLORS={"lanterns_rest":(96,120,56),"wickmoor":(54,104,96),"hollowmere":(84,98,138)}

def lvl_label(m):
    info = cat.get(m, {})
    if m in hearths or info.get("is_town"):
        return "TOWN"
    lo, hi = info.get("min_level"), info.get("max_level")
    if lo is None:
        return ""
    return ("Lv %d" % lo) if lo == hi else ("Lv %d-%d" % (lo, hi))

def ctext(d, xy, s, font, fill, anchor_cx=True, shadow=(0,0,0)):
    x, y = xy
    if anchor_cx:
        b=d.textbbox((0,0),s,font=font); x -= (b[2]-b[0])/2
    d.text((x+1,y+1), s, font=font, fill=shadow); d.text((x,y), s, font=font, fill=fill)

def compass(d, cx, cy, r):
    d.ellipse([cx-r,cy-r,cx+r,cy+r], outline=FRAME, width=2)
    d.ellipse([cx-r*0.62,cy-r*0.62,cx+r*0.62,cy+r*0.62], outline=(FRAME[0],FRAME[1],FRAME[2]), width=1)
    for ang,lab in [(90,"N"),(0,"E"),(270,"S"),(180,"W")]:
        a=math.radians(ang); tx,ty=cx+math.cos(a)*r*0.9, cy-math.sin(a)*r*0.9
        d.polygon([(cx+math.cos(a)*r*0.78, cy-math.sin(a)*r*0.78),
                   (cx+math.cos(a+2.6)*r*0.22, cy-math.sin(a+2.6)*r*0.22),
                   (cx+math.cos(a-2.6)*r*0.22, cy-math.sin(a-2.6)*r*0.22)],
                  fill=INK if lab=="N" else INK_DIM)
        ctext(d,(tx,ty-7),lab,FS,INK)

def render(pos, gate, gate_label, fname, title, regions=None):
    img=Image.new("RGBA",(W,H),PAPER+(255,)); d=ImageDraw.Draw(img)
    def px(m): return (pos[m][0]*W, pos[m][1]*H)
    # paper grain + a warm centre glow
    grain=Image.effect_noise((W,H),16).convert("L")
    img=Image.composite(Image.new("RGBA",(W,H),PAPER2+(255,)), img, grain.point(lambda v:min(60,v//3)))
    glow=Image.new("RGBA",(W,H),(0,0,0,0)); gd=ImageDraw.Draw(glow)
    gd.ellipse([W*0.5-W*0.42,H*0.5-H*0.42,W*0.5+W*0.42,H*0.5+H*0.42],fill=(70,52,30,60))
    img=Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(120)))
    # biome region washes (soft territory shading per arm)
    if regions:
        wash=Image.new("RGBA",(W,H),(0,0,0,0)); wd=ImageDraw.Draw(wash)
        for cx,cy,col,rad in regions:
            rpx=rad*min(W,H)
            wd.ellipse([cx*W-rpx,cy*H-rpx,cx*W+rpx,cy*H+rpx],fill=col+(58,))
        img=Image.alpha_composite(img, wash.filter(ImageFilter.GaussianBlur(70)))
    d=ImageDraw.Draw(img)
    # faint graticule (map coordinate lines)
    for gx_ in range(1,10): d.line([(W*gx_/10,40),(W*gx_/10,H-40)],fill=GRAT,width=1)
    for gy_ in range(1,10): d.line([(40,H*gy_/10),(W-40,H*gy_/10)],fill=GRAT,width=1)
    # double border frame + corner ticks
    for ins in (16,22): d.rectangle([ins,ins,W-ins,H-ins],outline=FRAME,width=2 if ins==16 else 1)
    # roads: soft underglow then a crisp tan path
    seen=set(); roads=[]
    for m in pos:
        for t in cat.get(m,{}).get("connections",[]):
            if t not in pos: continue
            k=tuple(sorted((m,t)))
            if k in seen: continue
            seen.add(k); roads.append((px(m),px(t)))
    rl=Image.new("RGBA",(W,H),(0,0,0,0)); rd=ImageDraw.Draw(rl)
    for a,b in roads: rd.line([a,b],fill=ROAD_GLOW+(150,),width=7)
    img=Image.alpha_composite(img, rl.filter(ImageFilter.GaussianBlur(3))); d=ImageDraw.Draw(img)
    for a,b in roads: d.line([a,b],fill=ROAD,width=2)
    gx=(gate[0]*W,gate[1]*H); d.line([px("emberwatch"),gx],fill=(96,84,120),width=2)
    # nodes
    R=9
    for m in pos:
        x,y=px(m); is_town=m in hearths; is_boss=(m=="warlord")
        col=C_BOSS if is_boss else (C_TOWN if is_town else C_FIELD)
        if is_town or is_boss:
            s=R+3; d.rectangle([x-s,y-s,x+s,y+s],fill=col,outline=(24,18,12),width=2)
        else:
            d.ellipse([x-R,y-R,x+R,y+R],fill=col,outline=(24,18,12),width=2)
            d.ellipse([x-R*0.45-2,y-R*0.45-2,x-R*0.45+2,y-R*0.45+2],fill=(255,255,255,90))
        nm=cat.get(m,{}).get("display_name") or m
        ctext(d,(x,y+R+3),nm,FC if is_town else F,INK if is_town else (226,214,186))
        ll=lvl_label(m)
        if ll and not is_town:
            ctext(d,(x,y+R+19),ll,FS,(196,170,120))
    # gateway node (descent to the Core)
    d.ellipse([gx[0]-15,gx[1]-15,gx[0]+15,gx[1]+15],fill=C_GATE,outline=(232,222,255),width=2)
    d.ellipse([gx[0]-8,gx[1]-8,gx[0]+8,gx[1]+8],outline=(28,22,34),width=1)
    ctext(d,(gx[0],gx[1]+19),gate_label,FC,(214,196,236))
    compass(d, W-70, H-70, 34)
    # title cartouche
    tb=d.textbbox((0,0),title,font=FT); tw=tb[2]-tb[0]
    d.rectangle([34,30,34+tw+28,30+40],fill=(20,15,10,230),outline=FRAME,width=2)
    ctext(d,(34+14,40),title,FT,INK,anchor_cx=False)
    img.convert("RGB").save(os.path.join(ROOT,fname)); return len(seen)

def arm_region(arm):
    angle, town, names = arm
    ms=[town]+names; xs=[world[m][0] for m in ms]; ys=[world[m][1] for m in ms]
    return (sum(xs)/len(xs), sum(ys)/len(ys), REGION_COLORS[town], 0.26)
regions=[arm_region(a) for a in ARMS]+[(0.5,0.5,(156,98,46),0.14)]
e1=render(world, CORE_GATE, "The Core  v", "tools/_wm_world.png", "The Emberwilds", regions)
e2=render(core, SURFACE_GATE, "^ The Surface", "tools/_wm_core.png", "The Core")
print("WORLD view:", len(world), "maps,", e1, "edges  |  CORE view:", len(core), "maps,", e2, "edges")
print("=== WORLD layout (bake into LAYOUT_WORLD) ===")
for m in world_order:
    print(f'\t"{m}": Vector2({world[m][0]:.3f}, {world[m][1]:.3f}),')
print("=== CORE layout (bake into LAYOUT_CORE) ===")
for m in core_order + ["warlord"]:
    print(f'\t"{m}": Vector2({core[m][0]:.3f}, {core[m][1]:.3f}),')
print(f"CORE_GATE Vector2({CORE_GATE[0]}, {CORE_GATE[1]})   SURFACE_GATE Vector2({SURFACE_GATE[0]}, {SURFACE_GATE[1]})")
