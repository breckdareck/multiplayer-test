#!/usr/bin/env python3
"""Render every weapon/armor/unique + consumable/pet/Coin as a 32x32 pixel-art PNG.

Mirrors the SVG item generators' semantics (material->color, type->shape,
archetype->silhouette, potion tier ladder) but as true pixel art for the game's
nearest-neighbor aesthetic. Transparent, borderless object only.

Output: assets/sprites/Items/generated_px/<rel>.png  (+ index.html)
Run from project root:  python tools/gen_item_icons_px.py
"""
import os, re, glob, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixelart import Canvas, hexc

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ITEMS = os.path.join(ROOT, "resources", "Items")
OUT = os.path.join(ROOT, "assets", "sprites", "Items", "generated_px")

OL = hexc("#1a1f27")
GRIP = hexc("#6e4a28"); GRIPH = hexc("#9c6b3f")
GOLD = hexc("#ffce5c"); GOLDH = hexc("#fff0b0"); GOLDD = hexc("#7a5600")
GLASS = hexc("#cfd8e0"); GLASSL = hexc("#5a626c")
WHITE = hexc("#ffffff")

# 14 material palettes: base, hi, shadow, trim(accent)
MAT = {
 "Worn":      (hexc("#8a8275"), hexc("#b8b0a0"), hexc("#3d3a33"), hexc("#9aa3ad")),
 "Rough":     (hexc("#9c7b53"), hexc("#c9a878"), hexc("#4a3824"), hexc("#caa46a")),
 "Bronze":    (hexc("#bd7a39"), hexc("#eab26a"), hexc("#5a3416"), hexc("#ffcf6b")),
 "Fine":      (hexc("#c2c8d0"), hexc("#eef2f6"), hexc("#565e68"), hexc("#dfe6ef")),
 "Iron":      (hexc("#6f747d"), hexc("#aab0ba"), hexc("#2c3036"), hexc("#aeb8c4")),
 "Steel":     (hexc("#8b94a3"), hexc("#c7cfdb"), hexc("#3a4150"), hexc("#cdd6e2")),
 "Mithril":   (hexc("#8fc1e8"), hexc("#dff0ff"), hexc("#345874"), hexc("#bfe6ff")),
 "Adamant":   (hexc("#57a474"), hexc("#a7e6bd"), hexc("#1f5236"), hexc("#7cf0a8")),
 "Pristine":  (hexc("#e3e9f0"), hexc("#ffffff"), hexc("#828b98"), hexc("#ffffff")),
 "Runic":     (hexc("#6a7bd6"), hexc("#b3c0ff"), hexc("#28306a"), hexc("#9fb0ff")),
 "Dragonbone":(hexc("#e3d7bb"), hexc("#fff7e2"), hexc("#7a6e4e"), hexc("#ffe9a8")),
 "Celestial": (hexc("#ffe199"), hexc("#fff6da"), hexc("#9a7a2a"), hexc("#fff0b0")),
 "Astral":    (hexc("#9fb0ff"), hexc("#e0e8ff"), hexc("#3a4a8a"), hexc("#c9a8ff")),
 "Eternal":   (hexc("#ffcdeb"), hexc("#ffffff"), hexc("#9a4a7a"), hexc("#ff9ad8")),
}
DEFAULT = MAT["Steel"]
KW_MAT = [("crystal","Mithril"),("dragon","Dragonbone"),("celestial","Celestial"),
 ("astral","Astral"),("eternal","Eternal"),("runic","Runic"),("mithril","Mithril"),
 ("adamant","Adamant"),("bronze","Bronze"),("iron","Iron"),("steel","Steel"),
 ("gold","Celestial"),("dawn","Celestial"),("dusk","Astral"),("shadow","Iron"),
 ("night","Iron"),("leather","Rough"),("apprentice","Fine"),("wood","Rough"),
 ("lolico","Mithril"),("falcon","Rough"),("aegis","Celestial"),("circlet","Celestial"),
 ("gladius","Steel"),("machete","Iron"),("bandana","Rough"),("jean","Mithril")]
ARCHES = ["Vanguard","Pathfinder","Nightshade","Arcanist"]
KW_ARCH = [("vanguard","Vanguard"),("aegis","Vanguard"),("sentinel","Vanguard"),
 ("pathfinder","Pathfinder"),("falcon","Pathfinder"),("ranger","Pathfinder"),
 ("nightshade","Nightshade"),("dusk","Nightshade"),("shadow","Nightshade"),
 ("cloak","Nightshade"),("pathf","Pathfinder"),
 ("arcanist","Arcanist"),("insight","Arcanist"),("robe","Arcanist"),
 ("apprentice","Arcanist"),("mage","Arcanist"),("circlet","Arcanist")]

def new():
    return Canvas(32, 32)

# ================================================== WEAPONS
def longsword(m):
    cv = new(); b, h, s, t = m
    cv.poly([(8,25),(11,25),(25,9),(22,9)], b); cv.line(24,9,10,24, h)
    cv.px(25,8,h); cv.px(26,8,b)
    cv.line(6,21,14,27, GOLD); cv.line(8,26,5,29, GRIP); cv.disc(4,30,1.6, GOLD)
    cv.outline(OL); return cv

def dirk(m):
    cv = new(); b, h, s, t = m
    cv.poly([(10,24),(12,24),(22,12),(20,11)], b); cv.line(21,12,11,23, h)
    cv.px(22,11,h); cv.line(8,21,14,26, GOLD); cv.line(10,25,7,28, GRIP)
    cv.outline(OL); return cv

def warbow(m):
    cv = new(); b, h, s, t = MAT["Rough"]; o = m[0]
    for tt in range(0,21):
        yy = 6+tt; xx = 22-int(7*(1-((tt-10)/10.0)**2))
        cv.px(xx,yy,b); cv.px(xx+1,yy,h)
    cv.line(22,6,22,26, hexc("#d8d8d8"))
    cv.line(9,16,24,16, GRIP); cv.poly([(26,16),(22,14),(22,18)], o)
    cv.poly([(9,16),(12,14),(12,18)], hexc("#d8d8d8"))
    cv.outline(OL); return cv

def spellstaff(m):
    cv = new(); b, h, s, t = MAT["Rough"]; o, oh, osh, ot = m
    cv.line(10,27,20,11, b); cv.line(11,27,21,11, h)
    cv.disc(22,9,4, o); cv.disc(21,8,1.6, oh); cv.ring(22,9,5, osh)
    cv.outline(OL); return cv

def weapon(m, wtype, name):
    n = name.lower()
    if "staff" in n or "wand" in n or wtype == 2: return spellstaff(m)
    if "bow" in n or wtype == 1: return warbow(m)
    if any(k in n for k in ("dirk","dagger","knife","machete")) or wtype == 3: return dirk(m)
    return longsword(m)

# ================================================== ARMOR
# Archetype identity (silhouette reads the weapon class; material = color/tier):
#   Vanguard  = warrior / heavy PLATE (bulky, riveted, visored, segmented)
#   Pathfinder= archer  / LEATHER + feather (jerkin, quiver strap, cuffed boots)
#   Nightshade= rogue   / dark HOOD + wrapped leather (cowl, crossed straps, slim)
#   Arcanist  = mage    / cloth ROBE + wizard hat (flowing, runes, slippers)
def _rivets(cv, pts, c):
    for (x, y) in pts:
        cv.px(x, y, c)

def helm(m, arch):
    cv = new(); b, h, s, t = m
    if arch == "Arcanist":                                   # wide-brim wizard hat
        cv.poly([(16,4),(21,22),(11,22)], b)                 # cone
        cv.px(17,7,b); cv.px(18,11,b)                        # slight bend
        cv.hline(6,26,23, b); cv.hline(6,26,24, s); cv.hline(8,24,22, h)  # wide brim
        cv.hline(11,21,20, t)                                # band
        cv.disc(16,5,1.3, GOLD); cv.disc(16,16,1.2, GOLD)    # tip + star stud
        cv.outline(OL); return cv
    if arch == "Pathfinder":                                 # leather cap + feather
        cv.poly([(9,22),(10,14),(13,11),(19,11),(22,14),(23,22)], b)
        cv.hline(8,24,22, t); cv.hline(8,24,23, s)           # brim
        cv.hline(11,21,15, h)
        cv.poly([(22,12),(29,4),(27,13),(23,15)], t)         # feather
        cv.line(25,7,24,14, s)
        cv.outline(OL); return cv
    if arch == "Nightshade":                                 # rogue hood + dark cowl
        cv.poly([(16,6),(24,16),(23,27),(9,27),(8,16)], b)   # hood outer
        cv.poly([(16,11),(21,17),(20,26),(12,26),(11,17)], OL)  # shadowed face
        cv.px(13,20,t); cv.px(14,20,t)                       # eye glint
        cv.line(8,16,10,27, s); cv.line(24,16,22,27, s)      # drape
        cv.outline(OL); return cv
    # Vanguard great helm (visor + crest, riveted)
    cv.poly([(9,15),(9,11),(12,8),(20,8),(23,11),(23,15),(23,24),(20,27),(12,27),(9,24)], b)
    cv.rect(12,14,20,18, OL, fill=OL)                        # visor opening
    cv.vline(14,14,18, b); cv.vline(17,14,18, b)             # visor bars
    cv.hline(10,22,11, h)                                    # brow
    cv.line(16,8,16,4, t); cv.poly([(16,4),(19,3),(16,6)], t)  # crest plume
    _rivets(cv, [(11,12),(21,12),(11,23),(21,23)], h)
    cv.outline(OL); return cv

def mail(m, arch):
    cv = new(); b, h, s, t = m
    if arch == "Arcanist":                                   # flowing robe + rune
        cv.poly([(11,8),(21,8),(25,28),(7,28)], b)
        cv.poly([(11,8),(6,18),(9,28)], b); cv.poly([(21,8),(26,18),(23,28)], b)  # sleeves
        cv.poly([(13,8),(16,14),(19,8)], h)                  # V-neck
        cv.vline(16,14,28, t); cv.hline(9,23,23, t)          # seam + sash
        cv.disc(16,18,1.3, GOLD)                             # rune gem
        cv.outline(OL); return cv
    if arch == "Pathfinder":                                 # leather jerkin + quiver strap
        cv.poly([(11,9),(21,9),(23,15),(22,28),(10,28),(9,15)], b)
        cv.poly([(11,9),(14,7),(18,7),(21,9)], s)            # collar
        cv.line(11,10,21,26, t); cv.line(12,10,22,26, s)     # diagonal strap
        cv.hline(11,21,24, t)                                # belt
        for y in (14,17,20): cv.px(15,y,t); cv.px(17,y,t)    # laces
        cv.outline(OL); return cv
    if arch == "Nightshade":                                 # slim wrap + crossed straps + cowl
        cv.poly([(11,11),(21,11),(22,28),(10,28)], b)
        cv.poly([(11,11),(16,7),(21,11),(16,14)], s)         # collar
        cv.poly([(16,8),(12,11),(16,14),(20,11)], OL)        # cowl shadow
        cv.line(11,13,21,25, t); cv.line(21,13,11,25, t)     # crossed straps
        cv.disc(16,19,1.2, s)                                # buckle
        cv.outline(OL); return cv
    # Vanguard plate (pauldrons + ridge + rivets)
    cv.disc(9,13,3, b); cv.disc(23,13,3, b)                  # pauldrons
    cv.disc(9,12,1.3, h); cv.disc(23,12,1.3, h)
    cv.poly([(11,12),(21,12),(23,16),(20,18),(20,28),(12,28),(12,18),(9,16)], b)
    cv.vline(16,13,27, s); cv.hline(13,19,20, s)             # ridge + ab line
    cv.hline(12,20,27, t)                                    # belt
    _rivets(cv, [(13,14),(19,14),(13,24),(19,24)], h)
    cv.outline(OL); return cv

def legs(m, arch):
    cv = new(); b, h, s, t = m
    if arch == "Arcanist":                                   # robe skirt
        cv.poly([(11,8),(21,8),(25,28),(7,28)], b)
        cv.vline(16,8,28, t); cv.hline(8,24,25, t)           # seam + hem
        cv.outline(OL); return cv
    if arch == "Pathfinder":                                 # leather pants + knee patches
        cv.poly([(11,8),(21,8),(20,27),(17,27),(16,16),(15,27),(12,27)], b)
        cv.hline(11,21,10, t)                                # belt
        cv.rect(12,17,15,21, s); cv.rect(17,17,20,21, s)     # knee patches
        cv.hline(12,15,26, t); cv.hline(17,20,26, t)         # cuffs
        cv.outline(OL); return cv
    if arch == "Nightshade":                                 # slim leggings + thigh strap
        cv.poly([(12,8),(20,8),(19,27),(17,27),(16,15),(15,27),(13,27)], b)
        cv.hline(12,20,9, s); cv.line(12,12,19,15, t)        # waist + strap
        cv.outline(OL); return cv
    # Vanguard plate greaves (segmented tassets + knee discs)
    cv.rect(10,8,22,11, b, fill=b)                           # belt plate
    cv.rect(11,11,15,27, b, fill=b); cv.rect(17,11,21,27, b, fill=b)
    cv.vline(16,12,27, OL)                                   # gap
    for y in (16,20,24): cv.hline(11,15,y, s); cv.hline(17,21,y, s)
    cv.disc(13,18,1.5, h); cv.disc(19,18,1.5, h)             # knee discs
    cv.hline(10,22,9, t)
    cv.outline(OL); return cv

def boots(m, arch):
    cv = new(); b, h, s, t = m
    if arch == "Arcanist":                                   # curled cloth slipper
        cv.poly([(12,15),(16,15),(16,23),(24,23),(26,20),(25,26),(12,26)], b)
        cv.hline(12,25,26, s); cv.hline(12,16,16, t)         # sole + ankle band
        cv.px(26,19,b); cv.px(27,20,b); cv.px(26,21,b)       # curl tip
        cv.outline(OL); return cv
    if arch == "Pathfinder":                                 # ranger boot, folded cuff + laces
        cv.poly([(11,11),(17,11),(17,22),(24,22),(24,27),(11,27)], b)
        cv.hline(11,24,27, s)                                # sole
        cv.rect(10,9,18,13, h)                               # folded cuff
        cv.vline(13,15,21, t); cv.vline(15,15,21, t)         # laces
        cv.outline(OL); return cv
    if arch == "Nightshade":                                 # slim pointed boot + wraps
        cv.poly([(12,12),(16,12),(16,22),(26,24),(24,27),(12,27)], b)
        cv.hline(12,24,27, s)                                # sole
        cv.hline(12,16,15, t); cv.hline(12,16,18, t)         # wrap straps
        cv.outline(OL); return cv
    # Vanguard sabaton (plated armored boot)
    cv.poly([(11,9),(17,9),(17,21),(25,21),(25,27),(11,27)], b)
    cv.hline(11,25,27, s); cv.hline(11,25,26, OL)            # heavy sole
    cv.rect(18,21,24,25, h)                                  # plated toe
    cv.hline(12,16,14, s); cv.hline(12,16,18, s)             # shin segments
    cv.hline(11,17,10, t)                                    # cuff
    _rivets(cv, [(13,12),(20,23)], h)
    cv.outline(OL); return cv

ARMOR_FN = {0: helm, 1: mail, 2: legs, 3: boots}

def armor(m, atype, arch):
    return ARMOR_FN.get(atype, mail)(m, arch)

# ================================================== POTIONS
RED=(hexc("#e8413f"),hexc("#ff9a8a"),hexc("#7a1410"))
BLUE=(hexc("#3f7fe8"),hexc("#9ec2ff"),hexc("#163a78"))
TEAL=(hexc("#2bb6a0"),hexc("#8fe6d8"),hexc("#0e4a40"))
GOLDLIQ=(hexc("#ffce3c"),hexc("#fff0a8"),hexc("#7a5600"))
PURPLE=(hexc("#b06bff"),hexc("#dcc0ff"),hexc("#3a1a6a"))
LIQ={"heal":RED,"mana":BLUE,"town":TEAL,"exp":GOLDLIQ,"misc":PURPLE}

def _cork(cv, cx, topy, gold=False):
    cv.rect(cx-2, topy, cx+2, topy+3, hexc("#5a3a20"), fill=hexc("#a9744a"))
    if gold: cv.hline(cx-3, cx+3, topy+4, GOLD)

def _spark(cv, x, y):
    cv.px(x,y,GOLDH); cv.px(x-1,y,GOLD); cv.px(x+1,y,GOLD); cv.px(x,y-1,GOLD); cv.px(x,y+1,GOLD)

def pv_vial(liq):
    cv=new(); b,h,s=liq
    cv.rect(12,11,19,27,None,fill=GLASS); cv.rect(13,18,18,26,None,fill=b); cv.vline(14,19,25,h)
    cv.rect(12,11,19,27,GLASSL); _cork(cv,15,8); cv.outline(OL); return cv

def pv_flask(liq, emblem=None):
    cv=new(); b,h,s=liq
    cv.disc(16,21,8,GLASS); cv.rect(13,10,18,14,None,fill=GLASS)
    cv.disc(16,22,7,b); cv.disc(13,20,2,h); cv.ring(16,21,8,GLASSL); _cork(cv,15,7)
    if emblem=="heart":
        for (x,y) in [(15,20),(17,20),(14,21),(16,21),(18,21),(15,22),(17,22),(16,23)]: cv.px(x,y,WHITE)
    elif emblem=="drop":
        cv.disc(16,22,2,WHITE); cv.px(16,18,WHITE); cv.px(16,19,WHITE)
    elif emblem=="swirl":
        cv.line(13,21,18,19,WHITE); cv.line(18,19,18,23,WHITE)
    elif emblem=="star":
        _spark(cv,16,21)
    cv.outline(OL); return cv

def pv_conical(liq):
    cv=new(); b,h,s=liq
    cv.poly([(13,10),(18,10),(18,15),(24,27),(7,27)],GLASS)
    cv.poly([(11,20),(20,20),(23,26),(8,26)],b); cv.line(11,21,9,25,h)
    cv.poly([(13,10),(18,10),(18,15),(24,27),(7,27)],GLASSL); _cork(cv,15,7); cv.outline(OL); return cv

def pv_shouldered(liq):
    cv=new(); b,h,s=liq
    cv.poly([(12,10),(19,10),(19,13),(22,16),(22,27),(9,27),(9,16),(12,13)],GLASS)
    cv.rect(10,17,21,26,None,fill=b)
    cv.rect(9,19,22,23,GLASSL,fill=hexc("#f3ead2")); cv.hline(11,20,21,b)
    cv.poly([(12,10),(19,10),(19,13),(22,16),(22,27),(9,27),(9,16),(12,13)],GLASSL)
    _cork(cv,15,7); cv.outline(OL); return cv

def pv_handled(liq):
    cv=new(); b,h,s=liq
    cv.line(8,16,6,21,GLASSL); cv.line(24,16,26,21,GLASSL)
    cv.disc(16,20,8,GLASS); cv.rect(13,9,18,13,None,fill=GLASS)
    cv.disc(16,21,7,b); cv.disc(13,19,2,h); cv.ring(16,20,8,GLASSL)
    _cork(cv,15,6,gold=True); cv.poly([(16,2),(18,4),(16,6),(14,4)],GOLD)
    _spark(cv,25,10); cv.outline(OL); return cv

def pv_crystal(liq):
    cv=new(); b,h,s=liq
    cv.poly([(16,9),(24,17),(21,27),(11,27),(8,17)],hexc("#dfe8ff"))
    cv.poly([(16,16),(21,19),(19,26),(13,26),(11,19)],b); cv.vline(16,12,26,h)
    _cork(cv,15,7,gold=True); cv.poly([(16,2),(18,4),(16,6),(14,4)],GOLD)
    _spark(cv,24,11); _spark(cv,9,12); _spark(cv,22,25); cv.outline(OL); return cv

PSHAPE=[pv_vial,pv_flask,pv_conical,pv_shouldered,pv_handled,pv_crystal]
TIERS=["lesser","","greater","superior","grand","supreme"]

def tier_of(name):
    low=name.lower()
    for i,t in enumerate(TIERS):
        if t and t in low: return i
    return 1

def liquid_kind(name):
    low=name.lower()
    if "mana" in low: return "mana"
    if "exp" in low: return "exp"
    if "town" in low: return "town"
    if any(k in low for k in ("heal","health","grape","hp","draught")): return "heal"
    return "misc"

def emblem_of(name):
    k=liquid_kind(name)
    return {"heal":"heart","mana":"drop","town":"swirl","exp":"star"}.get(k)

def potion(name):
    kind=liquid_kind(name); tier=tier_of(name)
    if "draught" in name.lower():
        return PSHAPE[max(0,min(5,tier))](LIQ[kind])
    return pv_flask(LIQ[kind], emblem_of(name))

# ================================================== MISC
def egg(name):
    cv=new()
    col=hexc("#bfe0ff") if "bird" in name.lower() else hexc("#ffe1c2")
    spot=hexc("#7fb6e8") if "bird" in name.lower() else hexc("#e0a878")
    cv.ellipse(16,20,7,9,col); cv.vline(12,18,24,hexc("#ffffff"))
    for (x,y) in [(18,16),(14,21),(19,23),(15,17)]: cv.disc(x,y,1.4,spot)
    cv.outline(OL); return cv

def petfood(name):
    cv=new(); prem="premium" in name.lower()
    rim=GOLD if prem else hexc("#b9c2cd"); bowl=hexc("#d68a4a") if prem else hexc("#7e8794")
    cv.poly([(8,17),(24,17),(22,25),(10,25)],bowl)
    cv.rect(7,15,25,18,None,fill=rim)
    for (x,y,c) in [(13,15,hexc("#c98a4a")),(17,14,hexc("#b87333")),(20,16,hexc("#caa46a")),(15,16,hexc("#a9744a"))]:
        cv.disc(x,y,2,c)
    if prem: _spark(cv,16,9); _spark(cv,23,12)
    cv.outline(OL); return cv

def skillbook(name):
    cv=new(); low=name.lower()
    cover=hexc("#3f9f5a"); rune=hexc("#bff0c8")
    if "pot" in low or "auto" in low: cover=hexc("#c0392b"); rune=hexc("#ffc6bd")
    elif "magnet" in low: cover=hexc("#3f6fe8"); rune=hexc("#bcd2ff")
    cv.rect(9,7,23,26,None,fill=cover); cv.rect(9,7,12,26,None,fill=hexc("#1e2a20"))
    cv.rect(11,24,24,27,None,fill=hexc("#efe6cf"))
    cv.ring(18,16,4,rune); cv.line(18,13,18,19,rune); cv.line(15,16,21,16,rune)
    cv.outline(OL); return cv

def coin():
    cv=new()
    cv.disc(16,16,9,GOLD); cv.ring(16,16,9,GOLDD); cv.ring(16,16,6,GOLDH)
    cv.vline(16,11,21,GOLDD); cv.hline(13,19,13,GOLDD); cv.hline(13,19,19,GOLDD)
    cv.outline(OL); return cv

# ================================================== drive
def material_of(name):
    first=name.split()[0]
    if first in MAT: return MAT[first]
    low=name.lower()
    for k,v in KW_MAT:
        if k in low: return MAT[v]
    return DEFAULT

def arch_of(name):
    for a in ARCHES:
        if a.lower() in name.lower(): return a
    low=name.lower()
    for k,v in KW_ARCH:
        if k in low: return v
    return "Vanguard"

def parse(tres):
    txt=open(tres,encoding="utf-8").read()
    cls=re.search(r'script_class="(\w+)"',txt); cls=cls.group(1) if cls else ""
    name=re.search(r'^name\s*=\s*"([^"]+)"',txt,re.M); name=name.group(1) if name else os.path.basename(tres)
    def num(f):
        mm=re.search(rf'^{f}\s*=\s*(\d+)',txt,re.M); return int(mm.group(1)) if mm else 0
    return dict(cls=cls,name=name,armor_type=num("armor_type"),weapon_type=num("weapon_type"))

def build(info):
    c=info["cls"]; n=info["name"]
    if c=="WeaponData": return weapon(material_of(n), info["weapon_type"], n)
    if c=="ArmorData": return armor(material_of(n), info["armor_type"], arch_of(n))
    if c=="PetFoodData": return petfood(n)
    if c=="PetSkillBookData": return skillbook(n)
    if c=="ItemData": return coin()
    if c=="ConsumableData":
        return egg(n) if "egg" in n.lower() else potion(n)
    return coin()

def main():
    targets=glob.glob(os.path.join(ITEMS,"**","*.tres"),recursive=True)
    rows=[]
    for tres in sorted(targets):
        info=parse(tres)
        if info["cls"] not in ("WeaponData","ArmorData","ConsumableData","PetFoodData","PetSkillBookData","ItemData"):
            continue
        rel=os.path.relpath(tres,ITEMS); outp=os.path.join(OUT,os.path.splitext(rel)[0]+".png")
        os.makedirs(os.path.dirname(outp),exist_ok=True)
        build(info).to_png(outp)
        rows.append((rel.replace("\\","/"), info["name"]))
    # contact sheet (sampled: every item, but file list can be long)
    cells="".join(f'<figure><img src="{r.rsplit(".",1)[0]}.png"><figcaption>{n}</figcaption></figure>' for r,n in rows)
    html=f'''<!doctype html><meta charset=utf-8><title>Item pixel icons</title>
<style>body{{background:#2b2f36;color:#cdd6e2;font:12px system-ui;margin:18px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,84px);gap:8px}}
figure{{margin:0;text-align:center;background:#1b1e24;border-radius:5px;padding:4px}}
img{{width:64px;height:64px;image-rendering:pixelated;display:block;margin:0 auto}}
figcaption{{font-size:9px;color:#9aa6b4;line-height:1.05}}</style>
<h1>Item pixel icons &mdash; {len(rows)}</h1><div class="grid">{cells}</div>'''
    open(os.path.join(OUT,"index.html"),"w",encoding="utf-8").write(html)
    print(f"Generated {len(rows)} item pixel icons -> {OUT}")

if __name__=="__main__":
    main()
