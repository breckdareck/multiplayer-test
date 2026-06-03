#!/usr/bin/env python3
"""Generate a unique, weapon-themed SVG icon for every ability.

Scans resources/Abilities/<Weapon>/*.tres, reads each ability_name, and emits a
self-contained 64x64 SVG with a beveled metal frame (tinted per weapon) and a
hand-mapped glyph drawn from the ability's name/identity.

Output: assets/sprites/Abilities/generated_svg/<Weapon>/<A_Name>.svg
Also writes generated_svg/index.html as a contact sheet for review.

Run from the project root:  python tools/gen_ability_icons.py
"""
import os, re, glob, html

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ABIL = os.path.join(ROOT, "resources", "Abilities")
OUT = os.path.join(ROOT, "assets", "sprites", "Abilities", "generated_svg")
WEAPONS = ["Sword", "Bow", "Staff", "Dagger"]

# ---------------------------------------------------------------- themes
THEMES = {
    "Sword":  dict(bg1="#5d1717", bg2="#260909", glow="#ff7a66", ring="#c0392b", lab="#e8b4a0"),
    "Bow":    dict(bg1="#184a23", bg2="#08210f", glow="#8ff58a", ring="#27ae60", lab="#bfe9b0"),
    "Staff":  dict(bg1="#222d63", bg2="#0c0f2e", glow="#8aa6ff", ring="#5b6dd6", lab="#bcb0ff"),
    "Dagger": dict(bg1="#163f3c", bg2="#0a2024", glow="#5ff0d0", ring="#16a085", lab="#a9b8e0"),
}
# elemental palette overrides for glyph colors
FIRE   = dict(fill="#ff8a3c", hi="#ffd27a", line="#7a2c08")
ICE    = dict(fill="#9fe6ff", hi="#e6fbff", line="#1d5b78")
BOLT   = dict(fill="#ffe45c", hi="#fff6c0", line="#7a5a00")
STEEL  = dict(fill="#dfe6ef", hi="#ffffff", line="#3a4350")
GOLD   = dict(fill="#ffce5c", hi="#fff0b0", line="#7a5600")
BLOOD  = dict(fill="#e84141", hi="#ff9a8a", line="#5a0e0e")
POISON = dict(fill="#86e34a", hi="#d6ff9a", line="#23561a")
SHADOW = dict(fill="#7d6fb0", hi="#c5b8ff", line="#241a40")

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
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{c}" stroke-width="{w}" stroke-linecap="round" {a}/>'

def g(body, **kw):
    a = " ".join(f'{k.replace("_","-")}="{v}"' for k, v in kw.items())
    return f"<g {a}>{body}</g>"

# ---------------------------------------------------------------- glyph library
# All glyphs are authored around centre (32,32), usable box ~ (14..50).

def blade(pal=STEEL, ang=0, cx=32, cy=32, ln=20, w=4):
    """vertical sword, tip up, pommel down, before rotation"""
    half = w / 2
    tipy = cy - ln
    guardy = cy + ln * 0.40
    b = []
    # blade
    b.append(poly([(cx, tipy), (cx + half, tipy + 5), (cx + half, guardy),
                   (cx - half, guardy), (cx - half, tipy + 5)], pal["fill"],
                  stroke=pal["line"], stroke_width=1.2, stroke_linejoin="round"))
    # fuller / highlight
    b.append(line(cx, tipy + 4, cx, guardy - 2, pal["hi"], 1))
    # crossguard
    b.append(poly([(cx - 7, guardy), (cx + 7, guardy), (cx + 6, guardy + 2.6),
                   (cx - 6, guardy + 2.6)], GOLD["fill"], stroke=GOLD["line"], stroke_width=1))
    # grip + pommel
    b.append(line(cx, guardy + 2.6, cx, guardy + 8, "#7a4a22", 2.6))
    b.append(circle(cx, guardy + 9.5, 2, GOLD["fill"], stroke=GOLD["line"], stroke_width=1))
    grp = "".join(b)
    if ang:
        grp = g(grp, transform=f"rotate({ang} {cx} {cy})")
    return grp

def dagger(pal=STEEL, ang=0, cx=32, cy=32):
    b = []
    b.append(poly([(cx, cy - 13), (cx + 2.4, cy - 8), (cx + 2.4, cy + 5),
                   (cx - 2.4, cy + 5), (cx - 2.4, cy - 8)], pal["fill"],
                  stroke=pal["line"], stroke_width=1.1, stroke_linejoin="round"))
    b.append(line(cx, cy - 11, cx, cy + 3, pal["hi"], 0.9))
    b.append(poly([(cx - 5.5, cy + 5), (cx + 5.5, cy + 5), (cx + 4.5, cy + 7), (cx - 4.5, cy + 7)],
                  GOLD["fill"], stroke=GOLD["line"], stroke_width=0.8))
    b.append(line(cx, cy + 7, cx, cy + 12, "#6e4520", 2.2))
    grp = "".join(b)
    if ang:
        grp = g(grp, transform=f"rotate({ang} {cx} {cy})")
    return grp

def arrow(pal=STEEL, ang=0, cx=32, cy=32, ln=22):
    half = ln / 2
    b = []
    # shaft
    b.append(line(cx, cy + half, cx, cy - half + 4, "#caa46a", 2))
    # head
    b.append(poly([(cx, cy - half), (cx + 4, cy - half + 7), (cx, cy - half + 5),
                   (cx - 4, cy - half + 7)], pal["fill"], stroke=pal["line"], stroke_width=1,
                  stroke_linejoin="round"))
    # fletching
    b.append(poly([(cx, cy + half - 6), (cx + 4, cy + half), (cx, cy + half - 2)], pal["hi"]))
    b.append(poly([(cx, cy + half - 6), (cx - 4, cy + half), (cx, cy + half - 2)], pal["fill"]))
    grp = "".join(b)
    if ang:
        grp = g(grp, transform=f"rotate({ang} {cx} {cy})")
    return grp

def bow(cx=32, cy=32):
    b = []
    b.append(f'<path d="M{cx+8} {cy-15} Q{cx-12} {cy} {cx+8} {cy+15}" fill="none" '
             f'stroke="#caa46a" stroke-width="3" stroke-linecap="round"/>')
    b.append(line(cx + 8, cy - 15, cx + 8, cy + 15, "#e8e8e8", 1))
    return "".join(b)

def shield(pal=STEEL, cx=32, cy=31, s=1.0):
    w = 13 * s
    top = cy - 13 * s
    bot = cy + 14 * s
    d = (f"M{cx-w} {top} L{cx+w} {top} L{cx+w} {cy+4*s} "
         f"Q{cx+w} {bot-3} {cx} {bot} Q{cx-w} {bot-3} {cx-w} {cy+4*s} Z")
    b = [P(d, pal["fill"], stroke=pal["line"], stroke_width=1.4, stroke_linejoin="round")]
    b.append(P(d.replace(str(cx-w), str(cx-w+2)), "none"))
    b.append(line(cx, top + 2, cx, bot - 3, pal["hi"], 1.2, opacity="0.6"))
    return "".join(b)

def banner(cx=32, cy=32, col="#c0392b"):
    b = []
    b.append(line(cx - 8, cy - 16, cx - 8, cy + 16, "#caa46a", 2))
    b.append(P(f"M{cx-8} {cy-15} L{cx+12} {cy-15} L{cx+8} {cy-7} L{cx+12} {cy+1} L{cx-8} {cy+1} Z",
               col, stroke="#5a0e0e", stroke_width=1, stroke_linejoin="round"))
    b.append(circle(cx - 8, cy - 16, 1.8, GOLD["fill"], stroke=GOLD["line"], stroke_width=0.8))
    b.append(P(f"M{cx} {cy-12} l2 4 l4 .5 l-3 3 l1 4 l-4 -2 l-4 2 l1 -4 l-3 -3 l4 -.5 z",
               GOLD["fill"]))
    return "".join(b)

def slash(cx=32, cy=32, ang=-30, col="#fff2e0", n=1):
    b = []
    for i in range(n):
        off = (i - (n - 1) / 2) * 7
        b.append(f'<path d="M{cx-16+off} {cy+10} Q{cx+off} {cy-20} {cx+16+off} {cy+2}" '
                 f'fill="none" stroke="{col}" stroke-width="3.2" stroke-linecap="round" opacity="0.95"/>')
        b.append(f'<path d="M{cx-16+off} {cy+10} Q{cx+off} {cy-20} {cx+16+off} {cy+2}" '
                 f'fill="none" stroke="#ffffff" stroke-width="1" stroke-linecap="round"/>')
    return g("".join(b), transform=f"rotate({ang} {cx} {cy})")

def crescent(cx=32, cy=32, col="#dff0ff"):
    return (f'<path d="M{cx-15} {cy+6} A18 18 0 1 1 {cx+15} {cy+6} '
            f'A22 22 0 1 0 {cx-15} {cy+6} Z" fill="{col}" stroke="#9fb6c8" '
            f'stroke-width="1" opacity="0.95"/>')

def crack(cx=32, cy=30, col="#ffb347"):
    return (f'<path d="M{cx} {cy-14} l-3 9 l4 1 l-2 8 l5 -7 l-3 -1 l4 -10 z" '
            f'fill="{col}" stroke="#7a3a00" stroke-width="1" stroke-linejoin="round"/>')

def ground_crack(cx=32, cy=42, col="#a9744a"):
    b = [P(f"M{cx-16} {cy} L{cx+16} {cy}", "none", stroke="#6e4326", stroke_width="2",
           stroke_linecap="round")]
    b.append(crack(cx, cy - 2, col))
    b.append(P(f"M{cx-8} {cy} l-2 6 M{cx+9} {cy} l3 5", "none", stroke="#6e4326",
               stroke_width="1.4", stroke_linecap="round"))
    return "".join(b)

def drop(cx, cy, col=BLOOD, s=1.0):
    return (f'<path d="M{cx} {cy-6*s} C{cx+5*s} {cy} {cx+4*s} {cy+6*s} {cx} {cy+6*s} '
            f'C{cx-4*s} {cy+6*s} {cx-5*s} {cy} {cx} {cy-6*s} Z" fill="{col["fill"]}" '
            f'stroke="{col["line"]}" stroke-width="1"/>'
            f'<circle cx="{cx-1.3*s}" cy="{cy+1*s}" r="{1.2*s}" fill="{col["hi"]}" opacity="0.8"/>')

def eye(cx=32, cy=32, iris="#37d0ff"):
    b = [P(f"M{cx-14} {cy} Q{cx} {cy-12} {cx+14} {cy} Q{cx} {cy+12} {cx-14} {cy} Z",
           "#f3f6fb", stroke="#2a3340", stroke_width=1.3)]
    b.append(circle(cx, cy, 5.5, iris, stroke="#10303d", stroke_width=1))
    b.append(circle(cx, cy, 2.4, "#0a1620"))
    b.append(circle(cx - 1.6, cy - 1.6, 1.2, "#ffffff"))
    return "".join(b)

def crosshair(cx=32, cy=32, col="#ffe45c"):
    b = [circle(cx, cy, 12, "none", stroke=col, stroke_width=2)]
    b.append(circle(cx, cy, 5, "none", stroke=col, stroke_width=1.4))
    for dx, dy in [(0, -16), (0, 16), (-16, 0), (16, 0)]:
        b.append(line(cx + dx * 0.55, cy + dy * 0.55, cx + dx * 0.95, cy + dy * 0.95, col, 2))
    b.append(circle(cx, cy, 1.6, col))
    return "".join(b)

def skull(cx=32, cy=31, col="#eef1f5"):
    b = [P(f"M{cx-9} {cy-3} A9 10 0 0 1 {cx+9} {cy-3} L{cx+8} {cy+5} "
           f"L{cx+4} {cy+5} L{cx+4} {cy+9} L{cx-4} {cy+9} L{cx-4} {cy+5} "
           f"L{cx-8} {cy+5} Z", col, stroke="#3a4350", stroke_width=1.2, stroke_linejoin="round")]
    b.append(circle(cx - 4, cy - 1, 2.6, "#222b36"))
    b.append(circle(cx + 4, cy - 1, 2.6, "#222b36"))
    b.append(P(f"M{cx} {cy+2} l-1.6 3 l3.2 0 z", "#222b36"))
    return "".join(b)

def flame(cx=32, cy=32, pal=FIRE, s=1.0):
    return (f'<path d="M{cx} {cy-15*s} C{cx+10*s} {cy-4*s} {cx+8*s} {cy+10*s} {cx} {cy+12*s} '
            f'C{cx-8*s} {cy+10*s} {cx-10*s} {cy-2*s} {cx-2*s} {cy-6*s} '
            f'C{cx-3*s} {cy} {cx} {cy+3*s} {cx+2*s} {cy} '
            f'C{cx+4*s} {cy-6*s} {cx} {cy-9*s} {cx} {cy-15*s} Z" '
            f'fill="{pal["fill"]}" stroke="{pal["line"]}" stroke-width="1" stroke-linejoin="round"/>'
            f'<path d="M{cx} {cy-6*s} C{cx+4*s} {cy} {cx+2*s} {cy+7*s} {cx} {cy+8*s} '
            f'C{cx-3*s} {cy+6*s} {cx-3*s} {cy} {cx} {cy-6*s} Z" fill="{pal["hi"]}" opacity="0.85"/>')

def snowflake(cx=32, cy=32, col="#bfeeff", s=1.0):
    b = []
    for a in range(0, 180, 60):
        b.append(g(line(cx, cy - 14 * s, cx, cy + 14 * s, col, 2) +
                   line(cx, cy - 14 * s, cx - 3, cy - 10 * s, col, 1.4) +
                   line(cx, cy - 14 * s, cx + 3, cy - 10 * s, col, 1.4) +
                   line(cx, cy + 14 * s, cx - 3, cy + 10 * s, col, 1.4) +
                   line(cx, cy + 14 * s, cx + 3, cy + 10 * s, col, 1.4),
                   transform=f"rotate({a} {cx} {cy})"))
    b.append(circle(cx, cy, 2, "#eafaff"))
    return "".join(b)

def ice_spike(cx=32, cy=32, pal=ICE):
    return (poly([(cx, cy - 16), (cx + 5, cy + 2), (cx + 2, cy + 12), (cx - 2, cy + 12),
                  (cx - 5, cy + 2)], pal["fill"], stroke=pal["line"], stroke_width=1.2,
                 stroke_linejoin="round") +
            line(cx, cy - 13, cx, cy + 10, pal["hi"], 1.2, opacity="0.8"))

def bolt(cx=32, cy=32, pal=BOLT):
    return P(f"M{cx+4} {cy-16} L{cx-7} {cy+2} L{cx-1} {cy+2} L{cx-5} {cy+16} "
             f"L{cx+8} {cy-3} L{cx+1} {cy-3} Z", pal["fill"], stroke=pal["line"],
             stroke_width=1.2, stroke_linejoin="round")

def windswirl(cx=32, cy=32, col="#d8f5e6"):
    b = []
    b.append(f'<path d="M{cx-15} {cy-6} Q{cx+6} {cy-12} {cx+10} {cy-4} Q{cx+12} {cy+2} {cx+4} {cy-1}" '
             f'fill="none" stroke="{col}" stroke-width="2.6" stroke-linecap="round"/>')
    b.append(f'<path d="M{cx-15} {cy+3} Q{cx+10} {cy-2} {cx+14} {cy+7} Q{cx+15} {cy+13} {cx+6} {cy+10}" '
             f'fill="none" stroke="{col}" stroke-width="2.6" stroke-linecap="round"/>')
    b.append(f'<path d="M{cx-13} {cy+11} Q{cx} {cy+9} {cx+6} {cy+12}" '
             f'fill="none" stroke="{col}" stroke-width="2.2" stroke-linecap="round" opacity="0.8"/>')
    return "".join(b)

def smoke(cx=32, cy=33, col="#9aa6b4"):
    b = []
    for r, dx, dy, o in [(8, -4, 2, .9), (7, 5, 0, .85), (6, 0, -5, .95), (5, -7, -3, .8), (5, 7, 6, .8)]:
        b.append(circle(cx + dx, cy + dy, r, col, opacity=o))
    b.append(circle(cx - 2, cy - 3, 5, "#c3cdd8", opacity=".7"))
    return "".join(b)

def orb(cx=32, cy=32, col="#8aa6ff", core="#dfe8ff"):
    return (circle(cx, cy, 11, col, opacity=".35") +
            circle(cx, cy, 7.5, col, stroke="#2a3a8a", stroke_width=1) +
            circle(cx - 2.4, cy - 2.4, 2.6, core, opacity=".9") +
            circle(cx, cy, 12, "none", stroke=core, stroke_width="0.8", opacity=".5"))

def beam(cx=32, cy=32, col="#b89bff", ang=-35):
    b = [poly([(cx - 16, cy + 2), (cx + 14, cy - 8), (cx + 16, cy - 5), (cx - 15, cy + 5)],
              col, stroke="#3a2a7a", stroke_width=1),
         poly([(cx + 13, cy - 7), (cx + 19, cy - 6.5), (cx + 15, cy - 4.5)], "#eae0ff")]
    return g("".join(b), transform=f"rotate({ang} {cx} {cy})")

def rings(cx=32, cy=32, col="#8aa6ff"):
    return (circle(cx, cy, 14, "none", stroke=col, stroke_width=1.6, opacity=".5") +
            circle(cx, cy, 9.5, "none", stroke=col, stroke_width=1.8, opacity=".75") +
            circle(cx, cy, 5, "none", stroke=col, stroke_width=2) +
            circle(cx, cy, 1.8, col))

def star(cx, cy, r, col, ri=None):
    import math
    ri = ri or r * 0.45
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else ri
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    return poly(pts, col, stroke="#7a5600", stroke_width=0.8, stroke_linejoin="round")

def burst(cx=32, cy=32, col="#ffd27a"):
    import math
    b = []
    for i in range(8):
        ang = i * math.pi / 4
        x1, y1 = cx + 4 * math.cos(ang), cy + 4 * math.sin(ang)
        x2, y2 = cx + 15 * math.cos(ang), cy + 15 * math.sin(ang)
        b.append(line(x1, y1, x2, y2, col, 2.4 if i % 2 == 0 else 1.4))
    b.append(circle(cx, cy, 4, "#fff6c0"))
    return "".join(b)

def boot(cx=32, cy=32, col="#d8c08a"):
    return P(f"M{cx-7} {cy-12} L{cx-1} {cy-12} L{cx-1} {cy+4} L{cx+10} {cy+4} "
             f"L{cx+10} {cy+10} L{cx-7} {cy+10} Z", col, stroke="#5a4416",
             stroke_width=1.2, stroke_linejoin="round")

def footprint(cx=32, cy=32, col="#cdd6e2"):
    b = [P(f"M{cx-3} {cy+10} q-4 -2 -4 -8 q0 -7 4 -7 q4 0 4 7 q0 6 -4 8 z", col,
           stroke="#3a4350", stroke_width=0.8)]
    for i, (dx, dy) in enumerate([(-3, -14), (-0.5, -15), (2, -14.5), (4, -13)]):
        b.append(circle(cx + dx, cy + dy, 1.6, col, stroke="#3a4350", stroke_width=0.6))
    return "".join(b)

def vial(cx=32, cy=32, liquid=POISON):
    b = [P(f"M{cx-4} {cy-13} L{cx+4} {cy-13} L{cx+4} {cy-9} L{cx+6} {cy+6} "
           f"Q{cx+6} {cy+13} {cx} {cy+13} Q{cx-6} {cy+13} {cx-6} {cy+6} "
           f"L{cx-4} {cy-9} Z", "#dfe8ef", stroke="#3a4350", stroke_width=1.2,
           stroke_linejoin="round", opacity=".9")]
    b.append(P(f"M{cx-5} {cy+1} L{cx+5} {cy+1} Q{cx+5.5} {cy+12} {cx} {cy+13} "
               f"Q{cx-5.5} {cy+12} {cx-5} {cy+1} Z", liquid["fill"], opacity=".95"))
    b.append(P(f"M{cx-3.5} {cy-15} L{cx+3.5} {cy-15} L{cx+3.5} {cy-12.5} L{cx-3.5} {cy-12.5} Z",
               "#7a4a22"))
    b.append(circle(cx - 1.5, cy + 5, 1.4, liquid["hi"], opacity=".8"))
    return "".join(b)

def caltrop(cx=32, cy=32, col="#c9d2dd"):
    import math
    b = []
    for ang in (-90, 30, 150):
        r = math.radians(ang)
        b.append(poly([(cx, cy), (cx + 3, cy + 3), (cx + 14 * math.cos(r), cy + 14 * math.sin(r)),
                       (cx - 3, cy - 3)], col, stroke="#3a4350", stroke_width=1, stroke_linejoin="round"))
    b.append(circle(cx, cy, 3.5, "#aeb8c4", stroke="#3a4350", stroke_width=1))
    return "".join(b)

def portal(cx=32, cy=32, col="#b89bff"):
    b = [f'<ellipse cx="{cx}" cy="{cy}" rx="9" ry="14" fill="none" stroke="{col}" stroke-width="2.4"/>',
         f'<ellipse cx="{cx}" cy="{cy}" rx="5" ry="9" fill="{col}" opacity=".3"/>',
         f'<ellipse cx="{cx}" cy="{cy}" rx="9" ry="14" fill="none" stroke="#eae0ff" stroke-width=".8" opacity=".6"/>']
    return "".join(b)

def chevrons(cx=32, cy=32, col="#ffce5c", up=True, n=3):
    b = []
    d = -1 if up else 1
    for i in range(n):
        y = cy + d * (i * 6 - 6)
        b.append(P(f"M{cx-9} {y+d*4} L{cx} {y-d*4} L{cx+9} {y+d*4}", "none",
                   stroke=col, stroke_width="2.6", stroke_linecap="round", stroke_linejoin="round"))
    return "".join(b)

def hourglass(cx=32, cy=32, col="#d8c08a"):
    b = [P(f"M{cx-8} {cy-13} L{cx+8} {cy-13} L{cx} {cy} L{cx+8} {cy+13} "
           f"L{cx-8} {cy+13} L{cx} {cy} Z", "none", stroke=col, stroke_width=2,
           stroke_linejoin="round")]
    b.append(P(f"M{cx-5} {cy-10} L{cx+5} {cy-10} L{cx} {cy-2} Z", "#ffe45c", opacity=".8"))
    b.append(P(f"M{cx} {cy+2} L{cx+5} {cy+10} L{cx-5} {cy+10} Z", "#ffe45c", opacity=".8"))
    return "".join(b)

def wisp(cx=32, cy=30, col="#bcb0ff"):
    b = [circle(cx, cy, 6, col, opacity=".5"),
         circle(cx, cy, 3.2, "#eae0ff")]
    for dx, dy, r in [(7, 6, 2), (-6, 8, 1.6), (9, -4, 1.4), (-8, -2, 1.3)]:
        b.append(circle(cx + dx, cy + dy, r, col, opacity=".7"))
    b.append(f'<path d="M{cx} {cy+5} Q{cx+4} {cy+12} {cx} {cy+16}" fill="none" '
             f'stroke="{col}" stroke-width="1.6" opacity=".6"/>')
    return "".join(b)

def fan_knives(cx=32, cy=34):
    import math
    b = []
    for ang in (-45, -20, 0, 20, 45):
        r = math.radians(ang - 90)
        tx, ty = cx + 17 * math.cos(r), cy + 17 * math.sin(r)
        b.append(g(poly([(cx, cy), (cx + 1.6, cy), (tx + 1.4, ty), (tx, ty - 1)], STEEL["fill"],
                        stroke="#3a4350", stroke_width=0.7),
                   transform=f"rotate({ang} {cx} {cy})"))
    b.append(circle(cx, cy, 2.4, GOLD["fill"], stroke=GOLD["line"], stroke_width=0.8))
    return "".join(b)

def weave(cx=32, cy=32, col="#b89bff"):
    b = []
    for i in range(-1, 2):
        off = i * 7
        b.append(f'<path d="M{cx-14} {cy+off} Q{cx} {cy+off-7} {cx+14} {cy+off}" '
                 f'fill="none" stroke="{col}" stroke-width="2.2" stroke-linecap="round" opacity=".9"/>')
        b.append(f'<path d="M{cx-14} {cy+off} Q{cx} {cy+off+7} {cx+14} {cy+off}" '
                 f'fill="none" stroke="#eae0ff" stroke-width="1" stroke-linecap="round" opacity=".5"/>')
    return "".join(b)

def well(cx=32, cy=34, col="#8aa6ff"):
    b = [P(f"M{cx-12} {cy} Q{cx} {cy-6} {cx+12} {cy} L{cx+9} {cy+8} "
           f"Q{cx} {cy+12} {cx-9} {cy+8} Z", col, stroke="#2a3a8a", stroke_width=1.2,
           opacity=".85")]
    b.append(drop(cx, cy - 9, ICE, .9))
    b.append(line(cx - 7, cy + 1, cx + 7, cy + 1, "#dfe8ff", 1, opacity=".5"))
    return "".join(b)

def lance_charge(cx=32, cy=32):
    # forward charge: blade + speed lines
    b = [blade(STEEL, ang=55)]
    for dy in (-9, 0, 9):
        b.append(line(cx - 18, cy + dy, cx - 8, cy + dy, "#ffce5c", 2, opacity=".8"))
    return "".join(b)

# ---------------------------------------------------------------- accents (corner badge)
def badge(kind, cx=47, cy=47):
    base = circle(cx, cy, 8.5, "#11151c", opacity=".55") + circle(cx, cy, 8.5, "none",
                  stroke="#ffffff", stroke_width="0.6", opacity=".25")
    inner = {
        "blood": drop(cx, cy, BLOOD, .85),
        "poison": drop(cx, cy, POISON, .85),
        "fire": flame(cx, cy, FIRE, .5),
        "ice": snowflake(cx, cy, "#bfeeff", .42),
        "bolt": bolt(cx, cy, BOLT),
        "up": P(f"M{cx-5} {cy+3} L{cx} {cy-4} L{cx+5} {cy+3}", "none", stroke="#7CFC9A",
                stroke_width="2.2", stroke_linecap="round", stroke_linejoin="round"),
        "shield": shield(STEEL, cx, cy, .42),
        "star": star(cx, cy, 6, GOLD["fill"]),
        "skull": skull(cx, cy + 1, "#eef1f5"),
        "eye": eye(cx, cy, "#37d0ff"),
        "plus": line(cx - 5, cy, cx + 5, cy, "#7CFC9A", 2.4) + line(cx, cy - 5, cx, cy + 5, "#7CFC9A", 2.4),
    }.get(kind, "")
    if kind == "bolt":
        inner = g(inner, transform=f"scale(.5) translate({cx},{cy})")
        # simpler: redo bolt small
        inner = P(f"M{cx+2} {cy-6} L{cx-3} {cy+1} L{cx} {cy+1} L{cx-2} {cy+6} "
                  f"L{cx+3} {cy-1} L{cx} {cy-1} Z", BOLT["fill"], stroke=BOLT["line"], stroke_width=0.6)
    return base + inner

# ---------------------------------------------------------------- frame
def frame(theme):
    t = THEMES[theme]
    return f'''<defs>
<linearGradient id="metal" x1="0" y1="0" x2="1" y2="1">
 <stop offset="0" stop-color="#9aa3ad"/><stop offset=".45" stop-color="#5b636d"/>
 <stop offset=".55" stop-color="#454c55"/><stop offset="1" stop-color="#1d2127"/>
</linearGradient>
<radialGradient id="bg" cx=".42" cy=".36" r=".75">
 <stop offset="0" stop-color="{t['bg1']}"/><stop offset="1" stop-color="{t['bg2']}"/>
</radialGradient>
<radialGradient id="glow" cx=".5" cy=".42" r=".55">
 <stop offset="0" stop-color="{t['glow']}" stop-opacity=".55"/>
 <stop offset="1" stop-color="{t['glow']}" stop-opacity="0"/>
</radialGradient>
<filter id="sh" x="-30%" y="-30%" width="160%" height="160%">
 <feDropShadow dx="0" dy="1.2" stdDeviation="1" flood-color="#000" flood-opacity=".55"/>
</filter>
</defs>
<rect x="1.5" y="1.5" width="61" height="61" rx="11" fill="url(#metal)" stroke="#10131a" stroke-width="1.5"/>
<rect x="5.5" y="5.5" width="53" height="53" rx="8" fill="url(#bg)" stroke="{t['ring']}" stroke-width="1.4"/>
<rect x="5.5" y="5.5" width="53" height="53" rx="8" fill="url(#glow)"/>
<rect x="6.5" y="6.5" width="51" height="51" rx="7" fill="none" stroke="#ffffff" stroke-width="0.7" opacity="0.10"/>'''

def make_svg(theme, glyph, accent=None):
    body = frame(theme)
    body += g(glyph, filter="url(#sh)")
    if accent:
        body += badge(accent)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64" '
            'shape-rendering="geometricPrecision">' + body + "</svg>")

# ---------------------------------------------------------------- ability -> glyph map
# value: lambda producing glyph string, optional accent key
M = {
# ---- SWORD ----
"Aggression":            (lambda: blade(STEEL) + chevrons(32, 14, "#ff7a66", up=True, n=2), "up"),
"Banner of the Vanguard":(lambda: banner(), "star"),
"Battle-Hardened":       (lambda: shield(STEEL) + line(26,28,38,28,"#9aa3ad",1)+line(26,34,38,34,"#9aa3ad",1), "plus"),
"Bloodthirst":           (lambda: blade(STEEL, ang=18) + drop(44, 40, BLOOD), "blood"),
"Bulwark Stance":        (lambda: shield(STEEL, s=1.12), "shield"),
"Charge!":               (lambda: lance_charge(), None),
"Crescent Cleave":       (lambda: crescent() , None),
"Earthsplitter":         (lambda: blade(STEEL, ang=180, cy=24) + ground_crack(32,46), None),
"Hardened Frame":        (lambda: shield(STEEL) + P("M26 26 L38 26 L38 38 L26 38 Z","none",stroke="#9aa3ad",stroke_width=1.4), "shield"),
"Hemorrhage":            (lambda: slash(32,30,-25,"#ff5a4a") + drop(40,44,BLOOD,.8)+drop(26,44,BLOOD,.7), "blood"),
"Iron Riposte":          (lambda: blade(STEEL,ang=-35)+blade(STEEL,ang=35)+burst(32,24,"#fff2c0"), None),
"Last Stand":            (lambda: shield(STEEL)+blade(STEEL,ang=42,cx=40,cy=30,ln=15,w=3), "plus"),
"Vanguard's Onslaught":  (lambda: slash(32,32,-30,"#fff2e0",n=3), None),
"Second Wind":           (lambda: windswirl(32,30)+badge("plus",32,46), "plus"),
"Sentinel's Mark":       (lambda: crosshair(32,32,"#ff7a66"), None),
"Steel Flurry":          (lambda: slash(32,32,-30,"#dfe6ef",n=3), None),
"Sundering Blow":        (lambda: blade(STEEL,ang=180,cy=26)+crack(32,44,"#ffb347"), None),
"Vanguard's Resolve":    (lambda: shield(STEEL)+star(32,30,6,GOLD["fill"]), "star"),
"Vault Strike":          (lambda: blade(STEEL,ang=130,cx=34,cy=30)+(lambda: "".join([line(18,42,24,36,"#ffce5c",2,opacity=".7")]))(), None),
"Vow of the Vanguard":   (lambda: blade(STEEL)+circle(32,16,4,"none",stroke=GOLD["fill"],stroke_width="2"), "star"),
# ---- BOW ----
"Barbed Shot":           (lambda: arrow(STEEL,ang=135)+poly([(38,26),(42,24),(40,28)],BLOOD["fill"]), "blood"),
"Caltrops":              (lambda: caltrop(), None),
"Disengage":             (lambda: arrow(STEEL,ang=225)+windswirl(40,40,"#bfe9b0"), None),
"Eagle Eye":             (lambda: eye(32,32,"#9ff58a"), None),
"Execution":             (lambda: skull(32,28)+arrow(STEEL,ang=135,cy=40,ln=14), "skull"),
"Hailstorm":             (lambda: "".join(arrow(ICE,ang=160,cx=22+i*10,cy=22,ln=16) for i in range(3)), "ice"),
"Keen Eye":              (lambda: eye(32,32,"#9ff58a")+circle(32,32,15,"none",stroke="#bfe9b0",stroke_width=1,opacity=".5"), None),
"Lethality":             (lambda: arrow(STEEL,ang=135)+skull(44,44,"#eef1f5"), "skull"),
"Mark of the Hunt":      (lambda: crosshair(32,32,"#9ff58a"), "skull"),
"Marksman's Focus":      (lambda: crosshair(32,32,"#bfe9b0")+circle(32,32,2,"#fff"), None),
"Sky Volley":            (lambda: "".join(arrow(STEEL,ang=130-i*15,cx=24+i*8,cy=40,ln=18) for i in range(3)), None),
"Skyfall":               (lambda: "".join(arrow(STEEL,ang=200,cx=22+i*10,cy=20,ln=18) for i in range(3)), None),
"Snap Shot":             (lambda: arrow(STEEL,ang=90)+line(14,32,22,32,"#ffce5c",2)+line(15,27,22,29,"#ffce5c",1.5), None),
"Snipe":                 (lambda: arrow(STEEL,ang=90,ln=30)+crosshair(46,32,"#9ff58a"), None),
"Split Shot":            (lambda: arrow(STEEL,ang=70,cx=34)+arrow(STEEL,ang=90)+arrow(STEEL,ang=110,cx=30), None),
"Steady Aim":            (lambda: bow()+arrow(STEEL,ang=90,ln=22), None),
"Sundering Arrow":       (lambda: arrow(STEEL,ang=135)+crack(44,42,"#ffb347"), None),
"Surefoot":              (lambda: boot(), "up"),
"Tailwind":              (lambda: windswirl(30,30,"#bfe9b0")+arrow(STEEL,ang=70,cx=40,cy=40,ln=14), "up"),
"Wind Rider":            (lambda: windswirl(32,32,"#bfe9b0"), "up"),
# ---- STAFF ----
"Aether Ward":           (lambda: shield(STEEL)+rings(32,31,"#8aa6ff"), "shield"),
"Arcane Familiar":       (lambda: wisp(), None),
"Arcane Bolt":           (lambda: orb(32,32,"#8aa6ff"), None),
"Arcane Lance":          (lambda: beam(32,32,"#b89bff"), None),
"Arcane Resonance":      (lambda: rings(32,32,"#b89bff"), None),
"Communion":             (lambda: orb(32,30,"#bcb0ff","#fff")+chevrons(32,48,"#bcb0ff",up=True,n=1), "plus"),
"Deep Wellspring":       (lambda: well(), "plus"),
"Elemental Affinity":    (lambda: flame(24,34,FIRE,.55)+snowflake(40,34,"#bfeeff",.5)+bolt(32,24,BOLT), None),
"Frost Patch":           (lambda: snowflake(32,30)+line(18,44,46,44,"#bfeeff",2,opacity=".7"), "ice"),
"Glacial Spike":         (lambda: ice_spike(), "ice"),
"Immolate":              (lambda: flame(32,32,FIRE,1.05), "fire"),
"Killing Spree":         (lambda: burst(32,32,"#ffd27a")+skull(32,32,"#eef1f5"), "skull"),
"Mana Surge":            (lambda: orb(32,36,"#8aa6ff")+chevrons(32,18,"#8aa6ff",up=True,n=2), "up"),
"Mana Flow":             (lambda: weave(32,32,"#8aa6ff"), None),
"Overload":              (lambda: bolt(32,32,BOLT)+burst(32,32,"#fff6c0"), "bolt"),
"Phase Step":            (lambda: portal(), None),
"Pyre Burst":            (lambda: flame(32,32,FIRE)+burst(32,32,"#ffd27a"), "fire"),
"Spell Ward":            (lambda: rings(32,32,"#bcb0ff")+star(32,32,5,GOLD["fill"]), "shield"),
"Spellweave":            (lambda: weave(32,32,"#b89bff"), None),
"Stormcall":             (lambda: bolt(30,34,BOLT)+P("M20 22 q-6 2 -2 7 q-6 0 0 6 l24 0 q6 -4 0 -8 q2 -8 -8 -8 q-6 -2 -14 3 z",
                                                      "#9aa6b4",opacity=".55"), "bolt"),
# ---- DAGGER ----
"Backstab":              (lambda: dagger(STEEL,ang=200)+crosshair(40,40,"#5ff0d0"), None),
"Bloodlust":             (lambda: dagger(STEEL,ang=20)+drop(44,40,BLOOD), "blood"),
"Composure":             (lambda: dagger(STEEL)+circle(32,32,15,"none",stroke="#5ff0d0",stroke_width=1,opacity=".5"), None),
"Cripple":               (lambda: chevrons(32,36,"#5ff0d0",up=False,n=2)+crack(32,24,"#5ff0d0"), None),
"Cutthroat":             (lambda: dagger(STEEL,ang=70)+slash(32,30,-15,"#ff5a4a",n=1), "blood"),
"Death Mark":            (lambda: crosshair(32,32,"#b08bff")+skull(32,32,"#eef1f5"), "skull"),
"Envenom":               (lambda: dagger(STEEL,ang=18)+drop(44,40,POISON), "poison"),
"Evasion":               (lambda: dagger(STEEL,ang=25)+windswirl(26,38,"#5ff0d0"), None),
"Eviscerate":            (lambda: slash(32,32,-30,"#fff2e0")+slash(32,32,30,"#fff2e0"), "blood"),
"Fan of Knives":         (lambda: fan_knives(), None),
"Killer Instinct":       (lambda: eye(32,30,"#b08bff")+dagger(STEEL,ang=0,cy=44), "eye"),
"Killing Edge":          (lambda: dagger(STEEL,ang=25)+P("M40 22 l4 -4 M42 26 l5 -2","none",stroke="#fff6c0",stroke_width=1.5,stroke_linecap="round"), None),
"Opportunist":           (lambda: dagger(STEEL,ang=30)+hourglass(44,44), None),
"Predator's Patience":   (lambda: eye(32,30,"#5ff0d0")+hourglass(44,46), "eye"),
"Shadow Partner":        (lambda: dagger(SHADOW,ang=-18,cx=28)+dagger(STEEL,ang=18,cx=36), None),
"Shadowstep":            (lambda: portal(32,32,"#7d6fb0")+footprint(32,32,"#cdd6e2"), None),
"Smoke Bomb":            (lambda: smoke(), None),
"Toxicology":            (lambda: vial(32,32,POISON), "poison"),
"Twin Fang":             (lambda: dagger(STEEL,ang=-20,cx=27)+dagger(STEEL,ang=20,cx=37), "poison"),
"Vendetta":              (lambda: dagger(STEEL,ang=15)+crosshair(40,42,"#b08bff"), "blood"),
}

def fallback(name):
    return lambda: star(32, 32, 13, GOLD["fill"])

# ---------------------------------------------------------------- driver
def main():
    rows = []
    made = 0
    for w in WEAPONS:
        os.makedirs(os.path.join(OUT, w), exist_ok=True)
        for tres in sorted(glob.glob(os.path.join(ABIL, w, "*.tres"))):
            txt = open(tres, encoding="utf-8").read()
            m = re.search(r'ability_name\s*=\s*"([^"]+)"', txt)
            if not m:
                continue
            name = m.group(1)
            spec = M.get(name)
            if spec is None:
                glyph_fn, accent = fallback(name), None
            else:
                glyph_fn, accent = spec
            svg = make_svg(w, glyph_fn(), accent)
            base = os.path.splitext(os.path.basename(tres))[0]
            with open(os.path.join(OUT, w, base + ".svg"), "w", encoding="utf-8") as f:
                f.write(svg)
            made += 1
            rows.append((w, name, base, svg, spec is not None))
    # contact sheet
    cells = ""
    by_w = {}
    for w, name, base, svg, ok in rows:
        by_w.setdefault(w, []).append((name, svg, ok))
    for w in WEAPONS:
        t = THEMES[w]
        cells += f'<h2 style="color:{t["glow"]}">{w} &mdash; {len(by_w.get(w,[]))}</h2><div class="grid">'
        for name, svg, ok in by_w.get(w, []):
            flag = "" if ok else ' style="outline:2px solid #f33"'
            cells += f'<figure{flag}>{svg}<figcaption>{html.escape(name)}</figcaption></figure>'
        cells += "</div>"
    page = f'''<!doctype html><meta charset=utf-8><title>Ability icons</title>
<style>body{{background:#15171c;color:#cdd6e2;font:14px system-ui;margin:24px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,124px);gap:16px;margin:0 0 28px}}
figure{{margin:0;text-align:center}}figure svg{{width:112px;height:112px;display:block;margin:0 auto}}
figcaption{{font-size:11px;margin-top:4px;color:#9aa6b4;line-height:1.15}}
h2{{border-bottom:1px solid #333;padding-bottom:4px}}</style>
<h1>Ability icons &mdash; {made} generated</h1>{cells}'''
    with open(os.path.join(OUT, "index.html"), "w", encoding="utf-8") as f:
        f.write(page)
    print(f"Generated {made} SVG icons -> {OUT}")
    print(f"Contact sheet: {os.path.join(OUT, 'index.html')}")

if __name__ == "__main__":
    main()
