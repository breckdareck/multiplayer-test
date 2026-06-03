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

def potion(kind, tier=1, maxtier=5):
    p = LIQ[kind]
    cx = 32
    body = []
    # bulb
    body.append(circle(cx, 38, 12, p["glass"], stroke=GLASS_LINE, stroke_width=1.3,
                       opacity=".55"))
    # neck
    body.append(P("M27 27 L27 19 L37 19 L37 27 Z", p["glass"], stroke=GLASS_LINE,
                 stroke_width=1.2, opacity=".55"))
    # liquid (clip to bulb via a path that fills lower portion)
    frac = 0.45 + 0.5 * (tier / max(1, maxtier))  # fuller with tier
    top = 50 - 24 * frac
    body.append(P(f"M20.5 {max(top,30)} "
                  f"A12 12 0 0 0 43.5 {max(top,30)} "
                  f"A12 12 0 0 0 20.5 {max(top,30)} Z", p["liq"], opacity=".95"))
    body.append(circle(cx, 38, 12, "none", stroke=GLASS_LINE, stroke_width=1.3))
    # neck liquid
    body.append(rect(28, max(top, 22), 8, 27 - max(top, 22) + 2, p["liq"], opacity=".9"))
    # glass highlight
    body.append(P("M24 34 Q22 40 25 45", "none", stroke="#ffffff", stroke_width=2,
                 stroke_linecap="round", opacity=".5"))
    # bubbles
    for bx, by, br in [(34, 40, 1.6), (30, 44, 1.1), (36, 35, 1.0)][:1 + tier // 2]:
        body.append(circle(bx, by, br, p["hi"], opacity=".8"))
    # cork
    body.append(rect(27.5, 14, 9, 6, "#a9744a", rx=1.5, stroke="#5a3a20", stroke_width=1))
    body.append(rect(28.5, 12.5, 7, 2.5, "#caa46a", rx=1))
    if tier >= maxtier - 1:  # top-tier shimmer
        body.append(sparkle(43, 22, 2.6))
        body.append(sparkle(22, 28, 1.8))
    if kind == "town":  # return swirl marker
        body.append(P("M28 38 q4 -5 8 0 q-2 4 -6 2", "none", stroke="#ffffff",
                     stroke_width=1.4, stroke_linecap="round", opacity=".7"))
    return "".join(body)

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
    return potion(liquid_kind(name), tier_of(name), maxtier=5)

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
