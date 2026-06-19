#!/usr/bin/env python3
"""Illustrated Emberwilds world atlas: paints the actual geography (Lantern's meadows north,
Wickmoor marsh west, Hollowmere crags east, the central Emberwatch caldera + the Core rift
below) and lays every map onto it as a winding trail of location pins. Reads connections from
config/world_map_data.json. Renders tools/_wm_atlas.png and prints the LAYOUT_WORLD bake block.

Each town arm is a fishbone oriented outward from the caldera: a CLIMB winds inward to Emberwatch,
the town sits between, and the LOW FRONTIER of dead-end grinding pockets fans out into the biome.
The spine/climb gently zig-zag (a winding road) so pins + labels never stack."""
import json, os, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 1780, 916
rng = random.Random(7)

# ---------------- node layout: 3 fishbone arms oriented into their biome ----------------
# angle: direction the arm OPENS (town + frontier) from the caldera. Lantern's = up (north),
# Wickmoor = left (west), Hollowmere = right (east).
ARMS = [
    (90,  "lanterns_rest", ["near_wilds","glimmerfen","tinderfields","ember_meadows",
        "firefly_hollow","meadow_path","brackenway","bramble_downs",
        "lanternwood","watchers_ruin","hollow_warren","beacon_rise",
        "old_causeway","ruins","thornroot","old_battlefield","the_reliquary","embergate"]),
    (180, "wickmoor", ["reedmire","sodden_flats","heatherreach","blackpeat",
        "glowmoss_burrow","peat_steps","the_brackens","gorse_downs",
        "willowmere","drowned_shrine","mudwarren","bogbeacon",
        "long_ford","the_sluice","mirewarren","bonemarsh","the_oubliette","marshgate"]),
    (0,   "hollowmere", ["the_shallows","craghollow","echo_downs","greymoor",
        "pebble_warren","cairn_steps","gullstone_bluffs","windward_downs",
        "mistfield","sunken_hall","hollow_deep","beacon_crag",
        "stone_span","riftway","gravewarren","shattercliffs","deepshaft","hollowgate"]),
]
CENTER = (0.50, 0.46)
CLIMB_R = [0.27, 0.235, 0.20, 0.165, 0.13, 0.095]   # c1..c6 (c6 nearest the caldera)
TOWN_R  = 0.31
SPINE_R = [0.35, 0.39, 0.43, 0.47]
POCKET  = [(0.345, 0.075),(0.340, 0.140), (0.385,-0.075),(0.380,-0.140),
           (0.425, 0.075),(0.420, 0.140), (0.465,-0.075),(0.460,-0.140)]
WIND = 0.030   # zig-zag amplitude of the winding road (spine + climb)
ASPECT = H / float(W)   # keep arms from squashing on the wide canvas

def arm_pos(angle, idx):
    a = math.radians(angle); ux, uy = math.cos(a), -math.sin(a); px, py = -math.sin(a), -math.cos(a)
    if idx < 4:          r, off = SPINE_R[idx], WIND * (1 if idx % 2 else -1)
    elif idx < 12:       r, off = POCKET[idx-4]
    else:                r, off = CLIMB_R[idx-12], WIND * (1 if idx % 2 else -1)
    x = CENTER[0] + (ux*r + px*off)
    y = CENTER[1] + (uy*r + py*off) / ASPECT * ASPECT   # y already in canvas frac
    # widen horizontal-opening arms so they fill their third; tighten the vertical arm's height
    return (x, y)

pos = {"emberwatch": CENTER}
for angle, town, names in ARMS:
    a = math.radians(angle); ux, uy = math.cos(a), -math.sin(a)
    pos[town] = (CENTER[0] + ux*TOWN_R, CENTER[1] + uy*TOWN_R)
    for i, nm in enumerate(names):
        pos[nm] = arm_pos(angle, i)
CORE_GATE = (0.50, 0.66)

cat = json.load(open(os.path.join(ROOT, "config/world_map_data.json")))["maps"]
hearths = {"lanterns_rest","wickmoor","hollowmere","emberwatch"}

def _font(sz, bold=False):
    for nm in ((["arialbd.ttf","arial.ttf"]) if bold else ["arial.ttf"]):
        try: return ImageFont.truetype(nm, sz)
        except Exception: pass
    return ImageFont.load_default()
F=_font(12); FS=_font(10); FT=_font(22, True); FC=_font(14, True); FR=_font(26, True)

# ---------------- palette ----------------
SEA=(20,26,30)                       # the void / unknown beyond the coast
PAPER=(232,214,176)                  # parchment (under terrain, for coasts/labels bg)
MEADOW=(120,150,74); MEADOW2=(150,176,96); FOREST=(64,104,56)
MARSH=(78,116,104); MARSH2=(96,134,118); WATER=(70,120,138); WATER2=(104,158,170)
CRAG=(132,120,108); CRAG2=(166,156,142); ROCK=(96,86,78); SNOW=(226,224,228)
LAVA=(232,128,52); LAVA2=(255,196,96); CALD=(86,52,40)
COAST=(54,44,32); INK=(34,28,20); INK2=(70,58,42)
ROAD=(70,52,32); TOWN_C=(226,176,72); BOSS_C=(196,64,52); GATE_C=(150,70,180)

def P(xy): return (xy[0]*W, xy[1]*H)
def lvl(m):
    info=cat.get(m,{})
    if m in hearths or info.get("is_town"): return "TOWN"
    lo,hi=info.get("min_level"),info.get("max_level")
    if lo is None: return ""
    return "Lv %d"%lo if lo==hi else "Lv %d-%d"%(lo,hi)
def ctext(d,xy,s,font,fill,cx=True,sh=(0,0,0)):
    x,y=xy
    if cx:
        b=d.textbbox((0,0),s,font=font); x-=(b[2]-b[0])/2
    d.text((x+1,y+1),s,font=font,fill=sh); d.text((x,y),s,font=font,fill=fill)

# ---------------- terrain ----------------
def blob(cx, cy, rx, ry, jitter, n=26, seed=0):
    r=random.Random(seed); pts=[]
    for i in range(n):
        a=2*math.pi*i/n; jr=1.0+r.uniform(-jitter,jitter)
        pts.append((cx+math.cos(a)*rx*jr, cy+math.sin(a)*ry*jr))
    return pts

def soft_region(base_layers, pts, color, blur=22):
    lyr=Image.new("RGBA",(W,H),(0,0,0,0)); ImageDraw.Draw(lyr).polygon(pts, fill=color+(255,))
    base_layers.append((lyr.filter(ImageFilter.GaussianBlur(blur)), pts, color))

def draw_tree(d,x,y,s):
    d.line([(x,y),(x,y-s*0.5)],fill=(70,52,34),width=max(1,int(s*0.18)))
    for k,c in [(1.0,FOREST),(0.7,MEADOW),(0.4,MEADOW2)]:
        rr=s*0.55*k
        d.ellipse([x-rr,y-s*0.5-rr,x+rr,y-s*0.5+rr*0.6],fill=c)
def draw_mtn(d,x,y,s):
    d.polygon([(x-s,y),(x,y-s*1.4),(x+s,y)],fill=ROCK)
    d.polygon([(x,y-s*1.4),(x+s,y),(x+s*0.15,y)],fill=CRAG)         # lit right? keep simple
    d.polygon([(x-s,y),(x,y-s*1.4),(x-s*0.1,y)],fill=CRAG2)
    d.polygon([(x,y-s*1.4),(x-s*0.28,y-s*0.85),(x+s*0.28,y-s*0.85)],fill=SNOW)
def draw_reed(d,x,y,s):
    for k in (-1,0,1):
        d.line([(x+k*s*0.4,y),(x+k*s*0.4,y-s)],fill=(96,128,72),width=1)
def draw_water(d,x,y,rx,ry):
    d.ellipse([x-rx,y-ry,x+rx,y+ry],fill=WATER)
    d.ellipse([x-rx*0.6,y-ry*0.55,x+rx*0.2,y-ry*0.1],fill=WATER2)

# ---------------- render ----------------
def render():
    img=Image.new("RGBA",(W,H),SEA+(255,));
    # parchment grain base inside the coast
    grain=Image.effect_noise((W,H),20).convert("L").point(lambda v:min(40,v//4))
    # paint biome lobes onto a land mask
    land=Image.new("RGBA",(W,H),(0,0,0,0)); ld=ImageDraw.Draw(land)
    mead=blob(0.50*W,0.205*H,0.30*W,0.205*H,0.16,seed=1)
    mars=blob(0.165*W,0.52*H,0.205*W,0.40*H,0.18,seed=2)
    crag=blob(0.835*W,0.55*H,0.195*W,0.40*H,0.18,seed=3)
    cald=blob(0.50*W,0.50*H,0.16*W,0.24*H,0.12,seed=4)
    for pts,col in [(mars,MARSH),(crag,CRAG),(mead,MEADOW),(cald,CALD)]:
        ld.polygon(pts,fill=col+(255,))
    land=land.filter(ImageFilter.GaussianBlur(10))
    img=Image.alpha_composite(img,land)
    # coastlines (darker outline around each lobe)
    d=ImageDraw.Draw(img)
    for pts in [mars,crag,mead]:
        d.line(pts+[pts[0]],fill=COAST,width=3)
    # interior shading + texture per biome
    tex=Image.new("RGBA",(W,H),(0,0,0,0)); td=ImageDraw.Draw(tex)
    # simple point-in-polygon
    def inside(poly,x,y):
        c=False; n=len(poly); j=n-1
        for i in range(n):
            xi,yi=poly[i]; xj,yj=poly[j]
            if ((yi>y)!=(yj>y)) and (x < (xj-xi)*(y-yi)/(yj-yi+1e-9)+xi): c=not c
            j=i
        return c
    node_px=[P(p) for p in pos.values()]+[P(CORE_GATE)]
    def far(x,y,dist=42):
        return all((x-nx)**2+(y-ny)**2>dist*dist for nx,ny in node_px)
    def scatter(poly, fn, count, smin, smax):
        xs=[p[0] for p in poly]; ys=[p[1] for p in poly]
        x0,x1,y0,y1=min(xs),max(xs),min(ys),max(ys); placed=0; tries=0
        while placed<count and tries<count*12:
            tries+=1; x=rng.uniform(x0,x1); y=rng.uniform(y0,y1)
            if inside(poly,x,y) and far(x,y):
                fn(td,x,y,rng.uniform(smin,smax)); placed+=1
    # marsh: water pools + reeds
    for _ in range(16):
        xs=[p[0] for p in mars]; ys=[p[1] for p in mars]
        x=rng.uniform(min(xs),max(xs)); y=rng.uniform(min(ys),max(ys))
        if inside(mars,x,y) and far(x,y,48): draw_water(td,x,y,rng.uniform(14,30),rng.uniform(8,16))
    scatter(mars, lambda d,x,y,s: draw_reed(d,x,y,s), 60, 8, 16)
    # meadow: trees
    scatter(mead, lambda d,x,y,s: draw_tree(d,x,y,s), 60, 12, 22)
    # crags: mountains
    scatter(crag, lambda d,x,y,s: draw_mtn(d,x,y,s), 46, 14, 26)
    img=Image.alpha_composite(img,tex); d=ImageDraw.Draw(img)
    # ---- central caldera + Core rift ----
    cx,cy=P(CENTER)
    for rr,c in [(150,CALD),(116,(120,70,46)),(86,LAVA),(58,LAVA2)]:
        d.ellipse([cx-rr,cy-rr*0.8,cx+rr,cy+rr*0.8],fill=c)
    # core rift below, glowing
    gx,gy=P(CORE_GATE)
    d.polygon([(cx-26,cy+10),(cx+26,cy+10),(gx+50,gy),(gx-50,gy)],fill=(24,14,12))
    for rr in (40,26,14): d.ellipse([gx-rr,gy-rr*0.6,gx+rr,gy+rr*0.6],fill=(min(232,120+rr*2),60+rr,40))
    # ---- roads (winding trails) ----
    seen=set()
    for m in pos:
        for t in cat.get(m,{}).get("connections",[]):
            if t not in pos: continue
            k=tuple(sorted((m,t)))
            if k in seen: continue
            seen.add(k); a=P(pos[m]); b=P(pos[t])
            d.line([a,b],fill=(40,30,18),width=5)
    for m in pos:
        for t in cat.get(m,{}).get("connections",[]):
            if t not in pos: continue
            a=P(pos[m]); b=P(pos[t]); d.line([a,b],fill=ROAD,width=2)
    d.line([P(CENTER),(gx,gy)],fill=(80,40,30),width=3)
    # ---- pins ----
    R=8
    for m in pos:
        x,y=P(pos[m]); is_town=m in hearths
        col=TOWN_C if is_town else (MEADOW2 if pos[m][1]<0.42 else (WATER2 if pos[m][0]<0.34 else CRAG2))
        if is_town:
            d.rectangle([x-R-2,y-R-2,x+R+2,y+R+2],fill=col,outline=INK,width=2)
            d.rectangle([x-R+2,y-R+2,x+R-2,y+R-2],outline=(90,60,20),width=1)
        else:
            d.ellipse([x-R,y-R,x+R,y+R],fill=col,outline=INK,width=2)
            d.ellipse([x-3,y-4,x-1,y-2],fill=(255,255,255))
        nm=cat.get(m,{}).get("display_name") or m
        ctext(d,(x,y+R+2),nm,FC if is_town else F,(40,30,18) if is_town else INK,sh=(238,222,188))
        ll=lvl(m)
        if ll and not is_town: ctext(d,(x,y+R+15),ll,FS,(120,40,30),sh=(238,222,188))
    # caldera + core labels
    ctext(d,(cx,cy-10),"Emberwatch",FC,(255,230,180),sh=(40,20,10))
    ctext(d,(gx,gy+20),"The Core  v",FC,(230,200,240),sh=(30,16,30))
    # region name banners
    ctext(d,(0.50*W,0.045*H),"THE  LANTERN  MEADOWS",FR,(60,46,26),sh=(150,176,96))
    ctext(d,(0.13*W,0.10*H),"WICKMOOR  FENS",FR,(40,60,56),sh=(120,160,150))
    ctext(d,(0.86*W,0.10*H),"HOLLOWMERE  CRAGS",FR,(60,54,46),sh=(180,170,156))
    # ---- frame, compass, title ----
    for ins,wd in [(14,4),(22,2)]: d.rectangle([ins,ins,W-ins,H-ins],outline=(150,120,72),width=wd)
    ccx,ccy=W-78,H-78
    d.ellipse([ccx-36,ccy-36,ccx+36,ccy+36],outline=(150,120,72),width=2)
    for ang,lab,big in [(90,"N",1),(0,"E",0),(270,"S",0),(180,"W",0)]:
        a=math.radians(ang)
        d.polygon([(ccx+math.cos(a)*30,ccy-math.sin(a)*30),
                   (ccx+math.cos(a+2.5)*9,ccy-math.sin(a+2.5)*9),
                   (ccx+math.cos(a-2.5)*9,ccy-math.sin(a-2.5)*9)],
                  fill=(210,170,90) if big else (150,120,72))
        ctext(d,(ccx+math.cos(a)*46,ccy-math.sin(a)*46-7),lab,FS,(220,200,160))
    tb=d.textbbox((0,0),"The Emberwilds",font=FT); tw=tb[2]-tb[0]
    d.rectangle([34,28,34+tw+30,28+44],fill=(28,20,12),outline=(150,120,72),width=2)
    ctext(d,(34+15,38),"The Emberwilds",FT,(226,200,150),cx=False)
    img.convert("RGB").save(os.path.join(ROOT,"tools/_wm_atlas.png"))
    print("atlas: %d maps, %d roads" % (len(pos), len(seen)))

render()
print("=== WORLD layout (bake into LAYOUT_WORLD) ===")
print('\t"emberwatch": Vector2(%.3f, %.3f),' % CENTER)
for angle, town, names in ARMS:
    print('\t"%s": Vector2(%.3f, %.3f),' % ((town,)+pos[town]))
    for nm in names: print('\t"%s": Vector2(%.3f, %.3f),' % ((nm,)+pos[nm]))
print('CORE_GATE Vector2(%.3f, %.3f)' % CORE_GATE)
