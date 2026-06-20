#!/usr/bin/env python3
"""Overlay the Emberwilds location network (58 map pins + roads) onto the real painted world map
(assets/sprites/ui/world_map_bg.png), so we can align the dots to the actual terrain before wiring
it into the in-game M-map. Renders tools/_wm_overlay.png and prints the LAYOUT_WORLD bake block.

Three fishbone arms radiate from the central caldera: Lantern's into the northern meadows, Wickmoor
into the western fens, Hollowmere into the eastern crags. Each arm = a CLIMB winding inward to
Emberwatch + the town + a LOW FRONTIER of dead-end pockets fanning into the biome."""
import json, os, math
from PIL import Image, ImageDraw, ImageFont
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG = os.path.join(ROOT, "assets/sprites/ui/world_map_bg.png")

# arm = (angle_deg_opening_outward, reach_scale, town, [names in slot order s1-4,p1a-p4b,c1-6])
ARMS = [
    (90, 0.92, "lanterns_rest", ["near_wilds","glimmerfen","tinderfields","ember_meadows",
        "firefly_hollow","meadow_path","brackenway","bramble_downs",
        "lanternwood","watchers_ruin","hollow_warren","beacon_rise",
        "old_causeway","ruins","thornroot","old_battlefield","the_reliquary","embergate"]),
    (180, 1.02, "wickmoor", ["reedmire","sodden_flats","heatherreach","blackpeat",
        "glowmoss_burrow","peat_steps","the_brackens","gorse_downs",
        "willowmere","drowned_shrine","mudwarren","bogbeacon",
        "long_ford","the_sluice","mirewarren","bonemarsh","the_oubliette","marshgate"]),
    (0, 1.06, "hollowmere", ["the_shallows","craghollow","echo_downs","greymoor",
        "pebble_warren","cairn_steps","gullstone_bluffs","windward_downs",
        "mistfield","sunken_hall","hollow_deep","beacon_crag",
        "stone_span","riftway","gravewarren","shattercliffs","deepshaft","hollowgate"]),
]
CENTER = (0.500, 0.445)
CORE_GATE = (0.487, 0.655)
CLIMB_R = [0.205, 0.170, 0.138, 0.110, 0.086, 0.066]   # c1..c6 (c6 nearest the caldera)
TOWN_R  = 0.245
SPINE_R = [0.285, 0.320, 0.355, 0.390]
POCKET  = [(0.278, 0.072),(0.272, 0.122), (0.318,-0.072),(0.312,-0.122),
           (0.358, 0.072),(0.352, 0.122), (0.392,-0.072),(0.386,-0.122)]
WIND = 0.024

def arm_pos(angle, scale, idx):
    a = math.radians(angle); ux, uy = math.cos(a), -math.sin(a); px, py = -math.sin(a), -math.cos(a)
    if idx < 4:    r, off = SPINE_R[idx], WIND * (1 if idx % 2 else -1)
    elif idx < 12: r, off = POCKET[idx-4]
    else:          r, off = CLIMB_R[idx-12], WIND * (1 if idx % 2 else -1)
    return (CENTER[0] + (ux*r + px*off)*scale, CENTER[1] + (uy*r + py*off)*scale)

pos = {"emberwatch": CENTER}
for angle, scale, town, names in ARMS:
    a = math.radians(angle); ux, uy = math.cos(a), -math.sin(a)
    pos[town] = (CENTER[0] + ux*TOWN_R*scale, CENTER[1] + uy*TOWN_R*scale)
    for i, nm in enumerate(names):
        pos[nm] = arm_pos(angle, scale, i)

cat = json.load(open(os.path.join(ROOT, "config/world_map_data.json")))["maps"]
hearths = {"lanterns_rest","wickmoor","hollowmere","emberwatch"}
img = Image.open(BG).convert("RGBA"); W, H = img.size
veil = Image.new("RGBA",(W,H),(10,8,12,70)); img = Image.alpha_composite(img, veil)
d = ImageDraw.Draw(img)
def _font(sz, bold=False):
    for nm in ((["arialbd.ttf","arial.ttf"]) if bold else ["arial.ttf"]):
        try: return ImageFont.truetype(nm, sz)
        except Exception: pass
    return ImageFont.load_default()
F=_font(15); FS=_font(12); FC=_font(18, True)
def P(m): return (pos[m][0]*W, pos[m][1]*H)
def lvl(m):
    info=cat.get(m,{})
    if m in hearths: return "TOWN"
    lo,hi=info.get("min_level"),info.get("max_level")
    if lo is None: return ""
    return "Lv %d"%lo if lo==hi else "Lv %d-%d"%(lo,hi)
def ctext(xy,s,font,fill,sh=(0,0,0)):
    x,y=xy; b=d.textbbox((0,0),s,font=font); x-=(b[2]-b[0])/2
    for ox,oy in [(-1,-1),(1,-1),(-1,1),(1,1)]: d.text((x+ox,y+oy),s,font=font,fill=sh)
    d.text((x,y),s,font=font,fill=fill)

# roads
seen=set()
for m in pos:
    for t in cat.get(m,{}).get("connections",[]):
        if t not in pos: continue
        k=tuple(sorted((m,t)))
        if k in seen: continue
        seen.add(k); a=P(m); b=P(t)
        d.line([a,b],fill=(20,14,10,220),width=5); d.line([a,b],fill=(214,176,110),width=2)
d.line([P("emberwatch"),(CORE_GATE[0]*W,CORE_GATE[1]*H)],fill=(150,80,60),width=3)

# pins
R=9
for m in pos:
    x,y=P(m); is_town=m in hearths
    col=(238,196,96) if is_town else (150,210,120) if pos[m][1]<0.40 else (110,200,210) if pos[m][0]<0.34 else (210,200,180)
    if is_town:
        d.rectangle([x-R-2,y-R-2,x+R+2,y+R+2],fill=col,outline=(24,18,12),width=2)
    else:
        d.ellipse([x-R,y-R,x+R,y+R],fill=col,outline=(20,16,12),width=2)
        d.ellipse([x-3,y-4,x-1,y-2],fill=(255,255,255))
    nm=cat.get(m,{}).get("display_name") or m
    ctext((x,y+R+2),nm,FC if is_town else F,(255,236,180) if is_town else (236,228,210))
    ll=lvl(m)
    if ll and not is_town: ctext((x,y+R+18),ll,FS,(160,235,255))
# caldera + core
cx,cy=P("emberwatch"); gx,gy=CORE_GATE[0]*W,CORE_GATE[1]*H
ctext((cx,cy-30),"EMBERWATCH",FC,(255,228,170),sh=(40,20,10))
d.ellipse([gx-13,gy-13,gx+13,gy+13],fill=(150,80,180),outline=(235,215,255),width=2)
ctext((gx,gy+16),"The Core  v",FC,(232,205,245),sh=(30,16,30))

img.convert("RGB").save(os.path.join(ROOT,"tools/_wm_overlay.png"))
print("overlay: %d pins, %d roads on %dx%d" % (len(pos), len(seen), W, H))
print("=== WORLD layout (bake into LAYOUT_WORLD) ===")
print('\t"emberwatch": Vector2(%.3f, %.3f),' % CENTER)
for angle, scale, town, names in ARMS:
    print('\t"%s": Vector2(%.3f, %.3f),' % ((town,)+pos[town]))
    for nm in names: print('\t"%s": Vector2(%.3f, %.3f),' % ((nm,)+pos[nm]))
print('CORE_GATE Vector2(%.3f, %.3f)' % CORE_GATE)

# ---- emit the editable scene node block (background + pins) for local_player_ui.tscn ----
MA, MH = 1408, 768   # MapArea native size (= the art); pins are children in this pixel space
def pin_node(parent, name, mid, nx, ny):
    x, y = nx * MA, ny * MH
    return ('\n[node name="%s" type="Control" parent="%s"]\n'
            'layout_mode = 1\noffset_left = %.1f\noffset_top = %.1f\noffset_right = %.1f\noffset_bottom = %.1f\n'
            'mouse_filter = 2\nscript = ExtResource("wm_pin")\nmap_id = "%s"\n'
            % (name, parent, x, y, x, y, mid))
PINP = "MoveableWindows/WorldMap/MapArea/Pins"
blk = (
    '\n[node name="MapArea" type="TextureRect" parent="MoveableWindows/WorldMap"]\n'
    'layout_mode = 1\nanchor_left = 0.5\nanchor_top = 0.5\nanchor_right = 0.5\nanchor_bottom = 0.5\n'
    'offset_left = -704.0\noffset_top = -384.0\noffset_right = 704.0\noffset_bottom = 384.0\n'
    'grow_horizontal = 2\ngrow_vertical = 2\nmouse_filter = 2\ntexture = ExtResource("wm_bg")\n'
    'expand_mode = 1\nstretch_mode = 0\n'
    '\n[node name="Edges" type="Control" parent="MoveableWindows/WorldMap/MapArea"]\n'
    'layout_mode = 1\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\n'
    'grow_horizontal = 2\ngrow_vertical = 2\nmouse_filter = 2\nscript = ExtResource("wm_edges")\n'
    '\n[node name="Pins" type="Control" parent="MoveableWindows/WorldMap/MapArea"]\n'
    'layout_mode = 1\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\n'
    'grow_horizontal = 2\ngrow_vertical = 2\nmouse_filter = 2\n'
)
blk += pin_node(PINP, "emberwatch", "emberwatch", *CENTER)
for angle, scale, town, names in ARMS:
    blk += pin_node(PINP, town, town, *pos[town])
    for nm in names:
        blk += pin_node(PINP, nm, nm, *pos[nm])
blk += pin_node(PINP, "CoreGate", "__core__", *CORE_GATE)
open(os.path.join(ROOT, "tools/_world_pins.txt"), "w").write(blk)
print("wrote tools/_world_pins.txt (%d chars)" % len(blk))

