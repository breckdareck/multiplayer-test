#!/usr/bin/env python3
"""Generate a transparent-background SVG icon for every weapon and armor piece.

No frame, no border, no background — just the item object. Tier/quality is read
from the material prefix (Worn -> Eternal) which colors the metal/cloth; slot &
discipline come from armor_type / weapon_type; archetype (Vanguard/Pathfinder/
Nightshade/Arcanist) picks the silhouette flavor. Uniques get a legendary accent.

Scans resources/Items/{Weapons,Armor,Unique}/**/*.tres, writes mirrored SVGs to
assets/sprites/Items/generated_svg/<rel path>.svg, plus an index.html contact sheet.

Run from project root:  python tools/gen_item_icons.py
"""
import os, re, glob, html

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ITEMS = os.path.join(ROOT, "resources", "Items")
OUT = os.path.join(ROOT, "assets", "sprites", "Items", "generated_svg")
SRC_DIRS = ["Weapons", "Armor", "Unique"]

# ---------------------------------------------------------------- svg helpers
def P(d, c, **kw):
    a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
    return f'<path d="{d}" fill="{c}" {a}/>'

def poly(pts, c, **kw):
    s = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
    return f'<polygon points="{s}" fill="{c}" {a}/>'

def circle(cx, cy, r, c, **kw):
    a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{c}" {a}/>'

def line(x1, y1, x2, y2, c, w, **kw):
    a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
    return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{c}" '
            f'stroke-width="{w}" stroke-linecap="round" {a}/>')

def g(body, **kw):
    a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
    return f"<g {a}>{body}</g>"

def gem(cx, cy, r, acc):
    return (poly([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], acc["g"],
                 stroke=acc["gl"], stroke_width=0.8, stroke_linejoin="round") +
            poly([(cx, cy - r), (cx + r * .5, cy - r * .2), (cx, cy)], acc["gh"], opacity=".8"))

# ---------------------------------------------------------------- palettes
# body = main metal/cloth, hi = highlight, line = outline, acc = trim/gem accent
MAT = {
 "Worn":       dict(b="#8a8275", h="#b8b0a0", l="#3d3a33", a="#9aa3ad"),
 "Rough":      dict(b="#9c7b53", h="#c9a878", l="#4a3824", a="#caa46a"),
 "Bronze":     dict(b="#bd7a39", h="#eab26a", l="#5a3416", a="#ffcf6b"),
 "Fine":       dict(b="#c2c8d0", h="#eef2f6", l="#565e68", a="#dfe6ef"),
 "Iron":       dict(b="#6f747d", h="#a2a8b2", l="#2c3036", a="#aeb8c4"),
 "Steel":      dict(b="#8b94a3", h="#c7cfdb", l="#3a4150", a="#cdd6e2"),
 "Mithril":    dict(b="#8fc1e8", h="#dff0ff", l="#345874", a="#bfe6ff"),
 "Adamant":    dict(b="#57a474", h="#a7e6bd", l="#1f5236", a="#7cf0a8"),
 "Pristine":   dict(b="#e3e9f0", h="#ffffff", l="#828b98", a="#ffffff"),
 "Runic":      dict(b="#6a7bd6", h="#b3c0ff", l="#28306a", a="#9fb0ff"),
 "Dragonbone": dict(b="#e3d7bb", h="#fff7e2", l="#7a6e4e", a="#ffe9a8"),
 "Celestial":  dict(b="#ffe199", h="#fff6da", l="#9a7a2a", a="#fff0b0"),
 "Astral":     dict(b="#9fb0ff", h="#e0e8ff", l="#3a4a8a", a="#c9a8ff"),
 "Eternal":    dict(b="#ffcdeb", h="#ffffff", l="#9a4a7a", a="#ff9ad8"),
}
DEFAULT_MAT = dict(b="#8b94a3", h="#c7cfdb", l="#3a4150", a="#cdd6e2")

# accent gem palette derived from material accent
def acc_of(mat):
    a = mat["a"]
    return dict(g=a, gl=mat["l"], gh="#ffffff")

# keyword fallbacks for non-generated names
KW_MAT = [
 ("crystal", "Mithril"), ("dragon", "Dragonbone"), ("celestial", "Celestial"),
 ("astral", "Astral"), ("eternal", "Eternal"), ("runic", "Runic"),
 ("mithril", "Mithril"), ("adamant", "Adamant"), ("bronze", "Bronze"),
 ("iron", "Iron"), ("steel", "Steel"), ("gold", "Celestial"), ("dawn", "Celestial"),
 ("dusk", "Astral"), ("shadow", "Iron"), ("night", "Iron"), ("leather", "Rough"),
 ("apprentice", "Fine"), ("wood", "Rough"), ("blue lolico", "Mithril"),
 ("falcon", "Rough"), ("aegis", "Celestial"), ("circlet", "Celestial"),
 ("gladius", "Steel"), ("machete", "Iron"), ("bandana", "Rough"), ("jean", "Mithril"),
]
ARCHES = ["Vanguard", "Pathfinder", "Nightshade", "Arcanist"]
KW_ARCH = [
 ("vanguard", "Vanguard"), ("aegis", "Vanguard"), ("sentinel", "Vanguard"),
 ("pathfinder", "Pathfinder"), ("falcon", "Pathfinder"), ("ranger", "Pathfinder"),
 ("nightshade", "Nightshade"), ("dusk", "Nightshade"), ("shadow", "Nightshade"),
 ("cloak", "Nightshade"), ("rogue", "Nightshade"),
 ("arcanist", "Arcanist"), ("insight", "Arcanist"), ("robe", "Arcanist"),
 ("apprentice", "Arcanist"), ("mage", "Arcanist"), ("circlet", "Arcanist"),
]

# ============================================================ WEAPON shapes
def w_longsword(m, acc):
    b = []
    grp = []
    # blade tip-up, vertical, then rotate for dynamic pose
    grp.append(poly([(32, 9), (35, 16), (35, 38), (29, 38), (29, 16)], m["b"],
                    stroke=m["l"], stroke_width=1.3, stroke_linejoin="round"))
    grp.append(poly([(32, 9), (35, 16), (32, 38), (32, 12)], m["h"], opacity=".55"))
    grp.append(line(32, 13, 32, 36, m["h"], 1, opacity=".7"))
    # crossguard
    grp.append(poly([(24, 38), (40, 38), (39, 41), (25, 41)], acc["g"],
                    stroke=m["l"], stroke_width=1))
    # grip + pommel
    grp.append(line(32, 41, 32, 51, "#6e4a28", 3))
    grp.append(line(32, 41, 32, 51, "#caa46a", 1, opacity=".6"))
    grp.append(gem(32, 53.5, 3, acc))
    b.append(g("".join(grp), transform="rotate(-42 32 32)"))
    return "".join(b)

def w_dirk(m, acc):
    grp = []
    grp.append(poly([(32, 13), (35, 20), (33, 36), (31, 36), (29, 20)], m["b"],
                    stroke=m["l"], stroke_width=1.2, stroke_linejoin="round"))
    grp.append(line(32, 16, 32, 34, m["h"], 1, opacity=".7"))
    grp.append(poly([(25, 36), (39, 36), (38, 39), (26, 39)], acc["g"],
                    stroke=m["l"], stroke_width=1))
    grp.append(line(32, 39, 32, 48, "#5a3a20", 2.6))
    grp.append(gem(32, 50, 2.6, acc))
    return g("".join(grp), transform="rotate(-42 32 32)")

def w_warbow(m, acc):
    b = []
    b.append(f'<path d="M40 12 Q14 32 40 52" fill="none" stroke="{m["b"]}" '
             f'stroke-width="4" stroke-linecap="round"/>')
    b.append(f'<path d="M40 12 Q16 32 40 52" fill="none" stroke="{m["h"]}" '
             f'stroke-width="1.4" stroke-linecap="round" opacity=".6"/>')
    b.append(line(40, 12, 40, 52, m["a"], 1.2, opacity=".85"))  # string
    # nocked arrow
    b.append(line(20, 32, 48, 32, "#caa46a", 1.8))
    b.append(poly([(50, 32), (45, 29), (45, 35)], m["a"], stroke=m["l"], stroke_width=0.8))
    b.append(poly([(20, 32), (24, 29.5), (24, 34.5)], m["h"]))
    b.append(gem(40, 12, 2.4, acc))
    b.append(gem(40, 52, 2.4, acc))
    return "".join(b)

def w_spellstaff(m, acc):
    b = []
    b.append(line(24, 52, 40, 14, "#6e4a28", 3.4))
    b.append(line(24, 52, 40, 14, m["h"], 1, opacity=".5"))
    # head: prongs cradling orb
    cx, cy = 41, 14
    b.append(f'<path d="M{cx-7} {cy+4} Q{cx-9} {cy-8} {cx} {cy-7} Q{cx+9} {cy-8} {cx+7} {cy+4}" '
             f'fill="none" stroke="{m["b"]}" stroke-width="2.6" stroke-linecap="round"/>')
    b.append(circle(cx, cy - 1, 5.5, acc["g"], stroke=m["l"], stroke_width=1))
    b.append(circle(cx, cy - 1, 5.5, acc["g"], opacity=".5"))
    b.append(circle(cx - 1.6, cy - 2.6, 2, "#ffffff", opacity=".85"))
    b.append(circle(cx, cy - 1, 7.5, "none", stroke=acc["g"], stroke_width="0.8", opacity=".45"))
    return "".join(b)

WEAP = {"sword": w_longsword, "dagger": w_dirk, "bow": w_warbow, "staff": w_spellstaff}
WEAP_TYPE = {0: "sword", 1: "bow", 2: "staff", 3: "dagger"}

def weapon_glyph(m, acc, wtype, name):
    n = name.lower()
    if "staff" in n or "wand" in n or wtype == 2:
        return w_spellstaff(m, acc)
    if "bow" in n or wtype == 1:
        return w_warbow(m, acc)
    if any(k in n for k in ("dirk", "dagger", "knife", "machete")) or wtype == 3:
        return w_dirk(m, acc)
    return w_longsword(m, acc)

# ============================================================ ARMOR shapes
def trim(d, acc, w=1.4):
    return P(d, "none", stroke=acc["g"], stroke_width=w, stroke_linecap="round")

# ---- HEAD ----
def head_vanguard(m, acc):
    b = [P("M20 26 Q20 13 32 13 Q44 13 44 26 L44 40 Q44 46 38 46 L26 46 Q20 46 20 40 Z",
           m["b"], stroke=m["l"], stroke_width=1.4, stroke_linejoin="round")]
    b.append(P("M30 22 L34 22 L34 40 L30 40 Z", "#11151c", opacity=".75"))  # visor slit
    b.append(P("M24 16 Q32 11 40 16", "none", stroke=acc["g"], stroke_width=1.6))  # crest base
    b.append(poly([(31, 11), (33, 11), (33, 6), (31, 6)], acc["g"]))  # plume mount
    b.append(line(22, 26, 22, 40, m["h"], 1, opacity=".5"))
    return "".join(b)

def head_pathfinder(m, acc):
    b = [P("M18 40 Q20 18 32 16 Q44 18 46 40 Q40 44 32 44 Q24 44 18 40 Z",
           m["b"], stroke=m["l"], stroke_width=1.4, stroke_linejoin="round")]
    b.append(P("M32 16 Q34 24 32 40", "none", stroke=m["l"], stroke_width=1, opacity=".6"))
    # feather
    b.append(P("M40 18 Q50 12 48 26 Q44 24 40 22 Z", acc["g"], stroke=m["l"], stroke_width=1,
              stroke_linejoin="round"))
    b.append(P("M18 38 Q32 42 46 38", "none", stroke=acc["g"], stroke_width=1.6))  # brim trim
    return "".join(b)

def head_nightshade(m, acc):
    b = [P("M32 12 Q46 20 42 44 L22 44 Q18 20 32 12 Z", m["b"],
           stroke=m["l"], stroke_width=1.4, stroke_linejoin="round")]
    b.append(P("M32 18 Q40 24 38 42 L26 42 Q24 24 32 18 Z", "#11151c", opacity=".55"))  # inner shadow
    b.append(poly([(28, 32), (33, 30), (32, 34)], acc["g"]))  # eye glint
    b.append(P("M22 44 Q32 40 42 44", "none", stroke=acc["g"], stroke_width=1.4, opacity=".8"))
    return "".join(b)

def head_arcanist(m, acc):
    b = [P("M14 44 Q32 38 50 44 Q44 40 36 40 L42 16 Q32 28 22 40 Q20 40 14 44 Z",
           m["b"], stroke=m["l"], stroke_width=1.3, stroke_linejoin="round")]  # floppy hat
    b.append(P("M14 44 Q32 39 50 44", "none", stroke=acc["g"], stroke_width=1.6))  # brim band
    b.append(gem(42, 16, 3, acc))  # tip gem
    b.append(P("M30 30 l1.5 3 l3 .4 l-2 2.2 l.6 3 l-3 -1.6 l-3 1.6 l.6 -3 l-2 -2.2 l3 -.4 z",
              acc["g"], opacity=".9"))  # star
    return "".join(b)

# ---- CHEST ----
def chest_vanguard(m, acc):
    b = [P("M20 22 L44 22 L46 28 L42 32 L42 48 Q32 52 22 48 L22 32 L18 28 Z",
           m["b"], stroke=m["l"], stroke_width=1.4, stroke_linejoin="round")]
    b.append(P("M32 22 L32 50", "none", stroke=m["l"], stroke_width=1, opacity=".6"))
    b.append(circle(16, 26, 4, m["h"], stroke=m["l"], stroke_width=1))  # pauldron L
    b.append(circle(48, 26, 4, m["h"], stroke=m["l"], stroke_width=1))  # pauldron R
    b.append(gem(32, 30, 3, acc))
    b.append(P("M24 40 L40 40", "none", stroke=acc["g"], stroke_width=1.4, opacity=".7"))
    return "".join(b)

def chest_pathfinder(m, acc):
    b = [P("M22 22 L42 22 L44 30 L40 50 Q32 53 24 50 L20 30 Z",
           m["b"], stroke=m["l"], stroke_width=1.4, stroke_linejoin="round")]
    b.append(P("M32 22 L29 38 L35 38 L32 50", "none", stroke=m["l"], stroke_width=1.2, opacity=".7"))  # lacing
    for y in (30, 34, 38):
        b.append(line(29, y, 35, y, acc["g"], 1))
    b.append(P("M22 22 L26 18 L38 18 L42 22", "none", stroke=m["l"], stroke_width=1.4))  # collar
    return "".join(b)

def chest_nightshade(m, acc):
    b = [P("M22 20 L42 20 L40 50 Q32 53 24 50 Z", m["b"],
           stroke=m["l"], stroke_width=1.4, stroke_linejoin="round")]
    b.append(P("M32 20 L26 22 L31 50 M32 20 L38 22 L33 50", "#11151c",
              stroke="none", opacity=".0"))
    b.append(P("M32 20 L24 26 L32 50 L40 26 Z", "#11151c", opacity=".5"))  # open coat V
    b.append(P("M22 20 L28 16 L36 16 L42 20", "none", stroke=acc["g"], stroke_width=1.4))  # collar
    b.append(circle(32, 36, 1.6, acc["g"]))
    return "".join(b)

def chest_arcanist(m, acc):
    b = [P("M22 20 L42 20 L46 50 Q32 54 18 50 Z", m["b"],
           stroke=m["l"], stroke_width=1.3, stroke_linejoin="round")]
    b.append(P("M28 20 L32 30 L36 20", m["h"], opacity=".5"))  # V-neck
    b.append(P("M32 30 L32 50", "none", stroke=acc["g"], stroke_width=1.6))  # center seam
    b.append(P("M20 38 Q32 42 44 38", "none", stroke=acc["g"], stroke_width=1.4, opacity=".7"))  # sash
    b.append(gem(32, 26, 2.4, acc))
    return "".join(b)

# ---- LEGS ----
def legs_base(m, acc, plated=False, robe=False):
    b = []
    if robe:
        b.append(P("M22 14 L42 14 L48 50 Q32 54 16 50 Z", m["b"], stroke=m["l"],
                  stroke_width=1.3, stroke_linejoin="round"))
        b.append(P("M32 14 L32 52", "none", stroke=acc["g"], stroke_width=1.4))
        b.append(P("M16 46 Q32 50 48 46", "none", stroke=acc["g"], stroke_width=1.4, opacity=".7"))
        return "".join(b)
    b.append(P("M22 14 L42 14 L42 24 L37 50 L33 50 L32 30 L31 50 L27 50 L22 24 Z",
              m["b"], stroke=m["l"], stroke_width=1.4, stroke_linejoin="round"))
    b.append(line(22, 18, 42, 18, acc["g"], 1.6))  # belt
    b.append(gem(32, 18, 2, acc))
    if plated:
        for y in (30, 38):
            b.append(P(f"M24 {y} L31 {y+1} M33 {y+1} L40 {y}", "none", stroke=m["h"],
                      stroke_width=1, opacity=".55"))
    return "".join(b)

# ---- FEET ----
def feet_base(m, acc, armored=False, curl=False):
    b = []
    b.append(P("M24 18 L33 18 L33 38 L44 38 L44 46 L24 46 Z", m["b"],
              stroke=m["l"], stroke_width=1.4, stroke_linejoin="round"))
    b.append(P("M24 46 L44 46", "none", stroke=m["l"], stroke_width=2.4))  # sole
    b.append(line(24, 24, 33, 24, acc["g"], 1.6))  # cuff trim
    if armored:
        b.append(P("M33 38 L40 38 L40 44 L33 44 Z", m["h"], opacity=".4"))
        b.append(line(28, 30, 28, 38, m["h"], 1, opacity=".5"))
    if curl:
        b.append(P("M44 38 Q50 38 48 44", "none", stroke=m["b"], stroke_width=2.4,
                  stroke_linecap="round"))
    b.append(gem(28, 21, 1.8, acc))
    return "".join(b)

ARMOR_SHAPES = {
 (0, "Vanguard"): head_vanguard, (0, "Pathfinder"): head_pathfinder,
 (0, "Nightshade"): head_nightshade, (0, "Arcanist"): head_arcanist,
 (1, "Vanguard"): chest_vanguard, (1, "Pathfinder"): chest_pathfinder,
 (1, "Nightshade"): chest_nightshade, (1, "Arcanist"): chest_arcanist,
 (2, "Vanguard"): lambda m, a: legs_base(m, a, plated=True),
 (2, "Pathfinder"): lambda m, a: legs_base(m, a),
 (2, "Nightshade"): lambda m, a: legs_base(m, a),
 (2, "Arcanist"): lambda m, a: legs_base(m, a, robe=True),
 (3, "Vanguard"): lambda m, a: feet_base(m, a, armored=True),
 (3, "Pathfinder"): lambda m, a: feet_base(m, a),
 (3, "Nightshade"): lambda m, a: feet_base(m, a),
 (3, "Arcanist"): lambda m, a: feet_base(m, a, curl=True),
}

def armor_glyph(m, acc, atype, arch):
    fn = ARMOR_SHAPES.get((atype, arch)) or ARMOR_SHAPES.get((atype, "Vanguard"))
    return fn(m, acc)

# ============================================================ legendary sparkle
def sparkles(acc):
    pts = [(16, 18, 2.4), (48, 20, 1.8), (46, 46, 2.2), (18, 44, 1.6)]
    out = []
    for cx, cy, r in pts:
        out.append(P(f"M{cx} {cy-r} L{cx+r*.32} {cy-r*.32} L{cx+r} {cy} L{cx+r*.32} {cy+r*.32} "
                     f"L{cx} {cy+r} L{cx-r*.32} {cy+r*.32} L{cx-r} {cy} L{cx-r*.32} {cy-r*.32} Z",
                     "#fff7d6", opacity=".9"))
    return "".join(out)

# ============================================================ parse + drive
def parse(tres):
    txt = open(tres, encoding="utf-8").read()
    cls = re.search(r'script_class="(\w+)"', txt)
    cls = cls.group(1) if cls else ""
    name = re.search(r'^name\s*=\s*"([^"]+)"', txt, re.M)
    name = name.group(1) if name else os.path.basename(tres)
    def num(field, default=0):
        mm = re.search(rf'^{field}\s*=\s*(\d+)', txt, re.M)
        return int(mm.group(1)) if mm else default
    return dict(cls=cls, name=name, level=num("item_level"),
                armor_type=num("armor_type"), weapon_type=num("weapon_type"),
                rarity=num("rarity"))

def material_of(name):
    first = name.split()[0]
    if first in MAT:
        return first
    low = name.lower()
    for k, v in KW_MAT:
        if k in low:
            return v
    return None

def arch_of(name):
    for a in ARCHES:
        if a.lower() in name.lower():
            return a
    low = name.lower()
    for k, v in KW_ARCH:
        if k in low:
            return v
    return "Vanguard"

def build_svg(info):
    matname = material_of(info["name"])
    m = MAT.get(matname, DEFAULT_MAT)
    acc = acc_of(m)
    is_weapon = info["cls"] == "WeaponData"
    if is_weapon:
        body = weapon_glyph(m, acc, info["weapon_type"], info["name"])
    else:
        body = armor_glyph(m, acc, info["armor_type"], arch_of(info["name"]))
    extra = sparkles(acc) if info["rarity"] >= 4 else ""
    inner = ('<defs><filter id="s" x="-20%" y="-20%" width="140%" height="140%">'
             '<feDropShadow dx="0" dy="0.8" stdDeviation="0.7" flood-color="#000" '
             'flood-opacity="0.45"/></filter></defs>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" '
            'height="64" shape-rendering="geometricPrecision">' + inner +
            g(body, filter="url(#s)") + extra + "</svg>")

def main():
    rows = []
    for sd in SRC_DIRS:
        for tres in sorted(glob.glob(os.path.join(ITEMS, sd, "**", "*.tres"), recursive=True)):
            info = parse(tres)
            if info["cls"] not in ("WeaponData", "ArmorData"):
                continue
            rel = os.path.relpath(tres, ITEMS)
            outp = os.path.join(OUT, os.path.splitext(rel)[0] + ".svg")
            os.makedirs(os.path.dirname(outp), exist_ok=True)
            svg = build_svg(info)
            open(outp, "w", encoding="utf-8").write(svg)
            rows.append((sd, info, svg, rel))
    # contact sheet (sample-friendly: group by category)
    groups = {}
    for sd, info, svg, rel in rows:
        key = (info["cls"], info["weapon_type"] if info["cls"] == "WeaponData"
               else info["armor_type"])
        groups.setdefault(sd, []).append((info["name"], svg))
    cells = ""
    for sd in SRC_DIRS:
        items = groups.get(sd, [])
        cells += f'<h2>{sd} &mdash; {len(items)}</h2><div class="grid">'
        for name, svg in items:
            cells += f'<figure>{svg}<figcaption>{html.escape(name)}</figcaption></figure>'
        cells += "</div>"
    page = f'''<!doctype html><meta charset=utf-8><title>Item icons</title>
<style>body{{background:#2b2f36;color:#cdd6e2;font:13px system-ui;margin:24px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,116px);gap:12px;margin:0 0 26px}}
figure{{margin:0;text-align:center;background:#1b1e24;border-radius:6px;padding:6px}}
figure svg{{width:96px;height:96px;display:block;margin:0 auto}}
figcaption{{font-size:10px;margin-top:2px;color:#9aa6b4;line-height:1.1}}
h2{{border-bottom:1px solid #444;padding-bottom:4px}}</style>
<h1>Item icons &mdash; {len(rows)} generated</h1>{cells}'''
    open(os.path.join(OUT, "index.html"), "w", encoding="utf-8").write(page)
    print(f"Generated {len(rows)} item SVG icons -> {OUT}")

if __name__ == "__main__":
    main()
