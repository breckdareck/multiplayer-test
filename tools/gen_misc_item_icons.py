#!/usr/bin/env python3
"""Generate transparent SVG icons for the remaining items: consumables, pet
items, and Coin. No frame/background/border — just the object.

Potions/draughts: bottle tinted by effect (heal=red, mana=blue, exp=gold,
town=teal); tier prefix (Lesser..Supreme) raises fill + adds sparkle. Pet egg,
pet-food bowl, pet skill-book, and gold coin get bespoke shapes.

Scans resources/Items/Consumables/**, resources/Items/PetItems/**, and
resources/Items/Coin.tres. Writes mirrored SVGs under Items/generated_svg/.

Run from project root:  python tools/gen_misc_item_icons.py
"""
import os, re, glob, html

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ITEMS = os.path.join(ROOT, "resources", "Items")
OUT = os.path.join(ROOT, "assets", "sprites", "Items", "generated_svg")

# ---------------------------------------------------------------- svg helpers
def P(d, c, **kw):
    a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
    return f'<path d="{d}" fill="{c}" {a}/>'

def circle(cx, cy, r, c, **kw):
    a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{c}" {a}/>'

def rect(x, y, w, h, c, rx=0, **kw):
    a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{c}" {a}/>'

def line(x1, y1, x2, y2, c, w, **kw):
    a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
    return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{c}" '
            f'stroke-width="{w}" stroke-linecap="round" {a}/>')

def poly(pts, c, **kw):
    s = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
    return f'<polygon points="{s}" fill="{c}" {a}/>'

def g(body, **kw):
    a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
    return f"<g {a}>{body}</g>"

def sparkle(cx, cy, r, c="#fff7d6"):
    return P(f"M{cx} {cy-r} L{cx+r*.32} {cy-r*.32} L{cx+r} {cy} L{cx+r*.32} {cy+r*.32} "
             f"L{cx} {cy+r} L{cx-r*.32} {cy+r*.32} L{cx-r} {cy} L{cx-r*.32} {cy-r*.32} Z",
             c, opacity=".95")

# ---------------------------------------------------------------- liquids
LIQ = {
 "heal": dict(liq="#e8413f", hi="#ff9a8a", glass="#f0c9c5"),
 "mana": dict(liq="#3f7fe8", hi="#9ec2ff", glass="#c5d6f0"),
 "exp":  dict(liq="#ffce3c", hi="#fff0a8", glass="#efe2bd"),
 "town": dict(liq="#2bb6a0", hi="#8fe6d8", glass="#bfe6df"),
 "misc": dict(liq="#b06bff", hi="#dcc0ff", glass="#ddd0ef"),
}
GLASS_LINE = "#5a626c"

def cork(cx, topy, w=9, gold=False):
    b = [rect(cx - w / 2, topy, w, 6, "#a9744a", rx=1.5, stroke="#5a3a20", stroke_width=1),
         rect(cx - w / 2 + 1, topy - 1.8, w - 2, 2.6, "#caa46a", rx=1)]
    if gold:  # ornate gold collar for high tiers
        b.append(rect(cx - w / 2 - 1, topy + 5, w + 2, 2.4, "#ffce5c", rx=1,
                     stroke="#7a5600", stroke_width=0.6))
    return "".join(b)

def hl(d):  # glass highlight streak
    return P(d, "none", stroke="#ffffff", stroke_width=2, stroke_linecap="round", opacity=".5")

# --- 6 distinct bottle silhouettes; index = tier 0..5 ---
def s_vial(p, **k):  # 0 Lesser: slim test-tube
    b = [P("M27 23 L27 43 Q27 48 32 48 Q37 48 37 43 L37 23 Z", p["glass"],
           stroke=GLASS_LINE, stroke_width=1.3, opacity=".55")]
    b.append(P("M27.6 33 L36.4 33 L36.4 43 Q36.4 47.3 32 47.3 Q27.6 47.3 27.6 43 Z",
              p["liq"], opacity=".95"))
    b.append(P("M27 23 L27 43 Q27 48 32 48 Q37 48 37 43 L37 23", "none",
              stroke=GLASS_LINE, stroke_width=1.3))
    b.append(hl("M29 28 Q28 36 30 43"))
    b.append(circle(33, 40, 1.3, p["hi"], opacity=".8"))
    b.append(cork(32, 18))
    return "".join(b)

def s_flask(p, **k):  # 1 base: round-bottom flask
    b = [circle(32, 38, 12, p["glass"], stroke=GLASS_LINE, stroke_width=1.3, opacity=".55"),
         P("M27 27 L27 20 L37 20 L37 27 Z", p["glass"], stroke=GLASS_LINE,
           stroke_width=1.2, opacity=".55")]
    b.append(P("M21.5 34 A12 12 0 0 0 42.5 34 A12 12 0 0 0 21.5 34 Z", p["liq"], opacity=".95"))
    b.append(rect(28, 24, 8, 4, p["liq"], opacity=".9"))
    b.append(circle(32, 38, 12, "none", stroke=GLASS_LINE, stroke_width=1.3))
    b.append(hl("M24 34 Q22 40 25 45"))
    b.append(circle(35, 40, 1.5, p["hi"], opacity=".8"))
    b.append(cork(32, 15))
    return "".join(b)

def s_conical(p, **k):  # 2 Greater: erlenmeyer
    b = [P("M29 20 L35 20 L35 28 L44 47 Q45 49 42 49 L22 49 Q19 49 20 47 L29 28 Z",
           p["glass"], stroke=GLASS_LINE, stroke_width=1.3, opacity=".55")]
    b.append(P("M26 38 L38 38 L43.5 47 Q44 49 41.5 49 L22.5 49 Q20 49 20.5 47 Z",
              p["liq"], opacity=".95"))
    b.append(P("M29 20 L35 20 L35 28 L44 47 Q45 49 42 49 L22 49 Q19 49 20 47 L29 28 Z",
              "none", stroke=GLASS_LINE, stroke_width=1.3))
    b.append(hl("M27 34 Q24 42 27 47"))
    b.append(circle(35, 44, 1.6, p["hi"], opacity=".8"))
    b.append(circle(29, 46, 1.1, p["hi"], opacity=".7"))
    b.append(cork(32, 15, w=8))
    return "".join(b)

def s_shouldered(p, **k):  # 3 Superior: shouldered bottle w/ label
    b = [P("M28 21 L36 21 L36 25 Q41 27 41 32 L41 46 Q41 49 38 49 L26 49 Q23 49 23 46 "
           "L23 32 Q23 27 28 25 Z", p["glass"], stroke=GLASS_LINE, stroke_width=1.3, opacity=".55")]
    b.append(P("M23.5 33 L40.5 33 L40.5 46 Q40.5 48.5 38 48.5 L26 48.5 Q23.5 48.5 23.5 46 Z",
              p["liq"], opacity=".95"))
    b.append(P("M28 21 L36 21 L36 25 Q41 27 41 32 L41 46 Q41 49 38 49 L26 49 Q23 49 23 46 "
              "L23 32 Q23 27 28 25 Z", "none", stroke=GLASS_LINE, stroke_width=1.3))
    b.append(rect(24, 35, 16, 6, "#f3ead2", rx=1, opacity=".9"))  # label
    b.append(line(27, 38, 37, 38, p["liq"], 1, opacity=".6"))
    b.append(hl("M26 28 Q25 32 26 36"))
    b.append(cork(32, 16, w=8))
    return "".join(b)

def s_handled(p, **k):  # 4 Grand: round flask w/ side handles + gem cork
    b = [f'<path d="M22 30 Q15 32 19 40" fill="none" stroke="{GLASS_LINE}" stroke-width="2"/>',
         f'<path d="M42 30 Q49 32 45 40" fill="none" stroke="{GLASS_LINE}" stroke-width="2"/>']
    b.append(circle(32, 37, 12, p["glass"], stroke=GLASS_LINE, stroke_width=1.3, opacity=".55"))
    b.append(P("M27 26 L27 20 L37 20 L37 26 Z", p["glass"], stroke=GLASS_LINE,
              stroke_width=1.2, opacity=".55"))
    b.append(P("M20.8 31 A12 12 0 0 0 43.2 31 A12 12 0 0 0 20.8 31 Z", p["liq"], opacity=".95"))
    b.append(rect(28, 24, 8, 4, p["liq"], opacity=".9"))
    b.append(circle(32, 37, 12, "none", stroke=GLASS_LINE, stroke_width=1.3))
    b.append(hl("M24 33 Q22 39 25 44"))
    b.append(circle(35, 39, 1.6, p["hi"], opacity=".8"))
    b.append(cork(32, 13, gold=True))
    b.append(gem_small(32, 11, p["hi"]))
    b.append(sparkle(45, 20, 2.2))
    return "".join(b)

def s_crystal(p, **k):  # 5 Supreme: faceted crystal flask, glowing
    b = [circle(32, 36, 15, p["liq"], opacity=".18")]  # aura (still transparent bg, just object glow)
    b.append(poly([(32, 22), (43, 32), (39, 48), (25, 48), (21, 32)], p["glass"],
                  stroke=GLASS_LINE, stroke_width=1.3, opacity=".55"))
    b.append(poly([(32, 33), (40.5, 36), (38, 47.5), (26, 47.5), (23.5, 36)], p["liq"], opacity=".95"))
    b.append(poly([(32, 22), (43, 32), (39, 48), (25, 48), (21, 32)], "none",
                  stroke=GLASS_LINE, stroke_width=1.3))
    # facets
    b.append(P("M32 22 L32 48 M21 32 L43 32 M25 48 L32 33 L39 48", "none",
              stroke="#ffffff", stroke_width=0.7, opacity=".4"))
    b.append(P("M27 26 L37 26 L37 21 L27 21 Z", p["glass"], stroke=GLASS_LINE,
              stroke_width=1, opacity=".55"))
    b.append(cork(32, 15, gold=True))
    b.append(gem_small(32, 13, p["hi"]))
    b.append(sparkle(44, 24, 3))
    b.append(sparkle(21, 26, 2))
    b.append(sparkle(40, 44, 1.8))
    return "".join(b)

def gem_small(cx, cy, hi):
    return (poly([(cx, cy - 3), (cx + 3, cy), (cx, cy + 3), (cx - 3, cy)], "#ffce5c",
                 stroke="#7a5600", stroke_width=0.7) +
            poly([(cx, cy - 3), (cx + 1.6, cy - 1), (cx, cy)], "#fff0b0"))

POTION_SHAPES = [s_vial, s_flask, s_conical, s_shouldered, s_handled, s_crystal]

# emblem stamped on the base/simple potions so heal/mana/exp/town differ
def emblem(kind):
    cx, cy = 32, 39
    if kind == "heal":   # heart
        return P(f"M{cx} {cy+3} C{cx-5} {cy-2} {cx-2} {cy-5} {cx} {cy-2} "
                 f"C{cx+2} {cy-5} {cx+5} {cy-2} {cx} {cy+3} Z", "#ffffff", opacity=".85")
    if kind == "mana":   # droplet
        return P(f"M{cx} {cy-5} C{cx+4} {cy-1} {cx+3} {cy+4} {cx} {cy+4} "
                 f"C{cx-3} {cy+4} {cx-4} {cy-1} {cx} {cy-5} Z", "#ffffff", opacity=".85")
    if kind == "exp":    # star
        return sparkle(cx, cy, 5, "#ffffff")
    if kind == "town":   # return swirl
        return P(f"M{cx-4} {cy} q4 -6 8 -1 q-1 5 -6 3", "none", stroke="#ffffff",
                 stroke_width=1.8, stroke_linecap="round", opacity=".9")
    return ""

def potion(kind, tier=1, simple=False):
    shape = POTION_SHAPES[max(0, min(5, tier))]
    svg = shape(LIQ[kind])
    if simple:
        svg += emblem(kind)
    return svg

# ---------------------------------------------------------------- pet / misc
def egg(name):
    col = "#bfe0ff" if "bird" in name.lower() else "#ffe1c2"
    spot = "#7fb6e8" if "bird" in name.lower() else "#e0a878"
    b = [P("M32 16 C42 16 44 34 38 44 C35 49 29 49 26 44 C20 34 22 16 32 16 Z",
           col, stroke="#5a6b7a", stroke_width=1.3, stroke_linejoin="round")]
    b.append(P("M28 22 Q26 30 28 38", "none", stroke="#ffffff", stroke_width=2,
              stroke_linecap="round", opacity=".5"))
    for sx, sy, r in [(34, 28, 2.2), (29, 35, 1.8), (35, 39, 1.6), (31, 24, 1.4)]:
        b.append(circle(sx, sy, r, spot, opacity=".85"))
    return "".join(b)

def petfood(name):
    premium = "premium" in name.lower()
    rim = "#ffce5c" if premium else "#b9c2cd"
    bowl = "#d68a4a" if premium else "#7e8794"
    b = [P("M18 34 L46 34 Q44 48 32 48 Q20 48 18 34 Z", bowl, stroke="#3a4350",
           stroke_width=1.3, stroke_linejoin="round")]
    b.append(P("M16 33 Q32 28 48 33 Q48 37 32 38 Q16 37 16 33 Z", rim, stroke="#3a4350",
              stroke_width=1.2, stroke_linejoin="round"))
    # kibble mound
    for kx, ky, r, c in [(27, 31, 3, "#c98a4a"), (33, 30, 3.2, "#b87333"),
                         (38, 32, 2.6, "#caa46a"), (30, 33, 2.4, "#a9744a")]:
        b.append(circle(kx, ky, r, c, stroke="#5a3a20", stroke_width=0.6))
    if premium:
        b.append(sparkle(32, 22, 3.2, "#fff0b0"))
        b.append(sparkle(43, 27, 1.8))
    return "".join(b)

def skillbook(name):
    low = name.lower()
    cover = "#3f9f5a"; rune = "#bff0c8"  # buff (green) default
    if "pot" in low or "auto" in low:
        cover = "#c0392b"; rune = "#ffc6bd"
    elif "magnet" in low:
        cover = "#3f6fe8"; rune = "#bcd2ff"
    b = [P("M20 16 L42 16 Q45 16 45 20 L45 46 Q45 48 42 48 L22 48 Q20 48 20 46 Z",
           cover, stroke="#1e2a20", stroke_width=1.3, stroke_linejoin="round")]
    b.append(rect(20, 16, 4, 32, "#1e2a20", opacity=".55"))  # spine
    b.append(P("M27 16 L27 48", "none", stroke="#ffffff", stroke_width=0.8, opacity=".25"))
    b.append(rect(24, 44, 21, 3, "#efe6cf", rx=1))  # pages
    # rune emblem
    b.append(circle(35, 30, 7, "none", stroke=rune, stroke_width=1.6, opacity=".9"))
    b.append(sparkle(35, 30, 4.4, rune))
    return "".join(b)

def coin():
    b = [circle(32, 32, 14, "#e0a52e", stroke="#7a5600", stroke_width=1.6)]
    b.append(circle(32, 32, 14, "#ffce5c", opacity=".4"))
    b.append(circle(32, 32, 10.5, "none", stroke="#fff0b0", stroke_width=1.2, opacity=".7"))
    b.append(P("M32 24 L32 40 M28 27 L36 27 M28 37 L36 37", "none", stroke="#7a5600",
              stroke_width=2, stroke_linecap="round"))  # stylized coin mark
    b.append(P("M24 27 Q22 32 24 37", "none", stroke="#ffffff", stroke_width=1.6,
              stroke_linecap="round", opacity=".5"))
    return "".join(b)

# ---------------------------------------------------------------- classify
TIERS = ["lesser", "", "greater", "superior", "grand", "supreme"]
def tier_of(name):
    low = name.lower()
    for i, t in enumerate(TIERS):
        if t and t in low:
            return i
    return 1  # base

def liquid_kind(name):
    low = name.lower()
    if "mana" in low:
        return "mana"
    if "exp" in low:
        return "exp"
    if "town" in low:
        return "town"
    if any(k in low for k in ("heal", "health", "grape", "hp", "draught")):
        return "heal"
    return "misc"

def build(info):
    cls, name = info["cls"], info["name"]
    if cls == "PetFoodData":
        return petfood(name)
    if cls == "PetSkillBookData":
        return skillbook(name)
    if cls == "ItemData":
        return coin()  # only Coin uses bare ItemData here
    # ConsumableData: egg vs potion
    if "egg" in name.lower():
        return egg(name)
    is_draught = "draught" in name.lower()
    return potion(liquid_kind(name), tier_of(name), simple=not is_draught)

def wrap(body):
    df = ('<defs><filter id="s" x="-20%" y="-20%" width="140%" height="140%">'
          '<feDropShadow dx="0" dy="0.8" stdDeviation="0.7" flood-color="#000" '
          'flood-opacity="0.45"/></filter></defs>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" '
            'height="64" shape-rendering="geometricPrecision">' + df +
            g(body, filter="url(#s)") + "</svg>")

def parse(tres):
    txt = open(tres, encoding="utf-8").read()
    cls = re.search(r'script_class="(\w+)"', txt)
    name = re.search(r'^name\s*=\s*"([^"]+)"', txt, re.M)
    return dict(cls=cls.group(1) if cls else "",
                name=name.group(1) if name else os.path.basename(tres))

def main():
    targets = (glob.glob(os.path.join(ITEMS, "Consumables", "**", "*.tres"), recursive=True) +
               glob.glob(os.path.join(ITEMS, "PetItems", "**", "*.tres"), recursive=True) +
               [os.path.join(ITEMS, "Coin.tres")])
    rows = []
    for tres in sorted(targets):
        if not os.path.exists(tres):
            continue
        info = parse(tres)
        rel = os.path.relpath(tres, ITEMS)
        outp = os.path.join(OUT, os.path.splitext(rel)[0] + ".svg")
        os.makedirs(os.path.dirname(outp), exist_ok=True)
        svg = wrap(build(info))
        open(outp, "w", encoding="utf-8").write(svg)
        rows.append((info["name"], svg))
    cells = "".join(f'<figure>{s}<figcaption>{html.escape(n)}</figcaption></figure>'
                    for n, s in rows)
    page = f'''<!doctype html><meta charset=utf-8><title>Misc item icons</title>
<style>body{{background:#2b2f36;color:#cdd6e2;font:13px system-ui;margin:24px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,116px);gap:12px}}
figure{{margin:0;text-align:center;background:#1b1e24;border-radius:6px;padding:6px}}
figure svg{{width:96px;height:96px;display:block;margin:0 auto}}
figcaption{{font-size:10px;margin-top:2px;color:#9aa6b4}}</style>
<h1>Misc items &mdash; {len(rows)}</h1><div class="grid">{cells}</div>'''
    open(os.path.join(OUT, "index_misc.html"), "w", encoding="utf-8").write(page)
    print(f"Generated {len(rows)} misc item SVG icons -> {OUT}")

if __name__ == "__main__":
    main()
