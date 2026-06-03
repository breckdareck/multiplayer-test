#!/usr/bin/env python3
"""Render all 80 abilities as 32x32 framed pixel-art PNGs.

Beveled frame tinted per discipline (Sword/Bow/Staff/Dagger) + a pixel glyph
mapped to each ability name (mirrors the SVG generator's motif map).

Output: assets/sprites/Abilities/generated_px/<Weapon>/<A_*>.png  (+ index.html)
Run from project root:  python tools/gen_ability_icons_px.py
"""
import os, re, glob, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixelart import Canvas, hexc

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ABIL = os.path.join(ROOT, "resources", "Abilities")
OUT = os.path.join(ROOT, "assets", "sprites", "Abilities", "generated_px")
WEAPONS = ["Sword", "Bow", "Staff", "Dagger"]

# colors
STEEL = hexc("#cdd6e2"); STEELH = hexc("#f2f6fb"); STEELD = hexc("#5a626c")
GRIP = hexc("#6e4a28"); GOLD = hexc("#ffce5c"); GOLDD = hexc("#7a5600")
RED = hexc("#e8413f"); REDH = hexc("#ff9a8a")
POISON = hexc("#86e34a"); ICE = hexc("#9fe6ff"); FIRE = hexc("#ff8a3c"); FIREH = hexc("#ffd27a")
BOLT = hexc("#ffe45c"); GREEN = hexc("#9ff58a"); TEAL = hexc("#5ff0d0")
PURP = hexc("#b89bff"); PURPH = hexc("#dcc0ff"); SHADOW = hexc("#7d6fb0")
WHITE = hexc("#ffffff"); BLOOD = hexc("#e8413f")

THEME = {"Sword": hexc("#5d1717"), "Bow": hexc("#184a23"),
         "Staff": hexc("#222d63"), "Dagger": hexc("#163f3c")}
THEME_HI = {"Sword": hexc("#7a2222"), "Bow": hexc("#246b34"),
            "Staff": hexc("#33408f"), "Dagger": hexc("#1f5b56")}
RING = {"Sword": hexc("#c0392b"), "Bow": hexc("#27ae60"),
        "Staff": hexc("#5b6dd6"), "Dagger": hexc("#16a085")}

def frame(disc):
    cv = Canvas(32, 32)
    cv.rect(0, 0, 31, 31, hexc("#10131a"), fill=hexc("#454c55"))
    cv.rect(1, 1, 30, 30, hexc("#9aa3ad"))
    cv.rect(3, 3, 28, 28, RING[disc], fill=THEME[disc])
    cv.hline(4, 27, 4, THEME_HI[disc]); cv.vline(4, 4, 27, THEME_HI[disc])
    return cv

# ---------------------------------------------------------------- motifs (center ~16,16)
def m_blade(cv, col=STEEL, cx=16, cy=15, up=True):
    cv.poly([(cx,cy-8),(cx+2,cy-5),(cx+2,cy+6),(cx-2,cy+6),(cx-2,cy-5)], col)
    cv.vline(cx, cy-6, cy+5, STEELH)
    cv.hline(cx-4, cx+4, cy+7, GOLD)
    cv.vline(cx, cy+8, cy+11, GRIP); cv.px(cx, cy+12, GOLD)

def m_blade_down(cv, col=STEEL, cx=16, cy=17):
    cv.poly([(cx,cy+8),(cx+2,cy+5),(cx+2,cy-6),(cx-2,cy-6),(cx-2,cy+5)], col)
    cv.vline(cx, cy-5, cy+6, STEELH)
    cv.hline(cx-4, cx+4, cy-7, GOLD); cv.vline(cx, cy-10, cy-8, GRIP)

def m_blade_diag(cv, col=STEEL, cx=16, cy=16):
    cv.poly([(cx-7,cy+8),(cx-5,cy+8),(cx+8,cy-6),(cx+6,cy-6)], col)
    cv.line(cx+7,cy-6,cx-6,cy+7, STEELH)
    cv.line(cx-9,cy+4,cx-3,cy+10, GOLD); cv.line(cx-7,cy+9,cx-9,cy+11, GRIP)

def m_dagger(cv, col=STEEL, cx=16, cy=15):
    cv.poly([(cx,cy-7),(cx+2,cy-4),(cx+1,cy+5),(cx-1,cy+5),(cx-2,cy-4)], col)
    cv.vline(cx, cy-5, cy+4, STEELH)
    cv.hline(cx-3, cx+3, cy+6, GOLD); cv.vline(cx, cy+7, cy+10, GRIP)

def m_dagger_diag(cv, col=STEEL, cx=16, cy=16, flip=False):
    sx = -1 if flip else 1
    cv.poly([(cx-6*sx,cy+7),(cx-4*sx,cy+7),(cx+7*sx,cy-6),(cx+5*sx,cy-6)], col)
    cv.line(cx-5*sx,cy+8,cx-8*sx,cy+11, GRIP)

def m_arrow(cv, col=STEEL, cx=16, cy=16, ln=11, vert=True):
    if vert:
        cv.vline(cx, cy-ln//2, cy+ln//2, GRIP)
        cv.poly([(cx,cy-ln//2-1),(cx-3,cy-ln//2+4),(cx+3,cy-ln//2+4)], col)
        cv.line(cx-3,cy+ln//2,cx,cy+ln//2-3, col); cv.line(cx+3,cy+ln//2,cx,cy+ln//2-3, col)
    else:
        cv.hline(cx-ln//2, cx+ln//2, cy, GRIP)
        cv.poly([(cx+ln//2+1,cy),(cx+ln//2-4,cy-3),(cx+ln//2-4,cy+3)], col)

def m_bow(cv, cx=15, cy=16):
    for t in range(0,17):
        yy=cy-8+t; xx=cx+6-int(6*(1-((t-8)/8.0)**2))
        cv.px(xx,yy,GRIP)
    cv.line(cx+6,cy-8,cx+6,cy+8, hexc("#d8d8d8"))

def m_shield(cv, col=STEEL, cx=16, cy=16, s=1.0):
    w=int(7*s)
    cv.poly([(cx-w,cy-7),(cx+w,cy-7),(cx+w,cy+2),(cx,cy+8),(cx-w,cy+2)], col)
    cv.vline(cx, cy-6, cy+6, STEELH)

def m_banner(cv, cx=16, cy=16, col=None):
    col = col or RING["Sword"]
    cv.vline(cx-4, cy-9, cy+9, GRIP)
    cv.poly([(cx-4,cy-8),(cx+7,cy-8),(cx+4,cy-4),(cx+7,cy),(cx-4,cy)], col)
    cv.px(cx+1,cy-4,GOLD)

def m_slash(cv, col=WHITE, cx=16, cy=16, off=0):
    pts=[]
    for i in range(13):
        x=cx-8+i; y=cy+5-int(round(0.12*(x-cx)**2))
        pts.append((x,y))
    for i in range(len(pts)-1):
        cv.line(pts[i][0],pts[i][1],pts[i+1][0],pts[i+1][1],col)
        cv.px(pts[i][0],pts[i][1]-1,col)
    cv.px(pts[-1][0],pts[-1][1]-1,col)

def m_crescent(cv, col=hexc("#dff0ff"), cx=16, cy=16):
    cv.disc(cx,cy,8,col); cv.disc(cx+4,cy-2,8,THEME["Sword"])

def m_crack(cv, col=hexc("#ffb347"), cx=16, cy=16):
    cv.line(cx,cy-6,cx-2,cy,col); cv.line(cx-2,cy,cx+1,cy+2,col); cv.line(cx+1,cy+2,cx-1,cy+7,col)

def m_groundcrack(cv, cx=16, cy=24):
    cv.hline(cx-8,cx+8,cy,hexc("#6e4326"))
    m_crack(cv, hexc("#ffb347"), cx, cy-3)

def m_drops(cv, cx=16, cy=16, col=BLOOD, n=3):
    pts=[(cx,cy),(cx+4,cy+3),(cx-4,cy+3)][:n]
    for x,y in pts:
        cv.disc(x,y+1,1.6,col); cv.px(x,y-1,col)

def m_eye(cv, iris=hexc("#37d0ff"), cx=16, cy=16):
    cv.ellipse(cx,cy,7,4,STEELH); cv.disc(cx,cy,3,iris); cv.disc(cx,cy,1.4,hexc("#0a1620"))
    cv.px(cx-1,cy-1,WHITE)

def m_crosshair(cv, col=BOLT, cx=16, cy=16):
    cv.ring(cx,cy,6,col); cv.ring(cx,cy,2,col)
    cv.vline(cx,cy-8,cy-6,col); cv.vline(cx,cy+6,cy+8,col)
    cv.hline(cx-8,cx-6,cy,col); cv.hline(cx+6,cx+8,cy,col)

def m_skull(cv, cx=16, cy=15, col=hexc("#eef1f5")):
    cv.disc(cx,cy,5,col); cv.rect(cx-3,cy+3,cx+3,cy+7,None,fill=col)
    cv.disc(cx-2,cy,1.4,hexc("#222b36")); cv.disc(cx+2,cy,1.4,hexc("#222b36"))
    cv.px(cx,cy+3,hexc("#222b36")); cv.vline(cx-1,cy+5,cy+7,col); cv.vline(cx+1,cy+5,cy+7,col)

def m_flame(cv, cx=16, cy=16):
    cv.poly([(cx,cy-8),(cx+5,cy+1),(cx+3,cy+7),(cx-3,cy+7),(cx-5,cy)], FIRE)
    cv.poly([(cx,cy-2),(cx+2,cy+3),(cx,cy+6),(cx-2,cy+3)], FIREH)

def m_snowflake(cv, cx=16, cy=16, col=ICE):
    cv.vline(cx,cy-7,cy+7,col); cv.hline(cx-7,cx+7,cy,col)
    cv.line(cx-5,cy-5,cx+5,cy+5,col); cv.line(cx-5,cy+5,cx+5,cy-5,col)
    cv.disc(cx,cy,1.4,WHITE)

def m_icespike(cv, cx=16, cy=16):
    cv.poly([(cx,cy-8),(cx+3,cy+2),(cx+1,cy+7),(cx-1,cy+7),(cx-3,cy+2)], ICE)
    cv.vline(cx,cy-6,cy+5,WHITE)

def m_bolt(cv, cx=16, cy=16, col=BOLT):
    cv.poly([(cx+2,cy-8),(cx-4,cy+1),(cx,cy+1),(cx-2,cy+8),(cx+5,cy-2),(cx+1,cy-2)], col)

def m_wind(cv, cx=16, cy=16, col=hexc("#d8f5e6")):
    cv.line(cx-7,cy-3,cx+5,cy-3,col); cv.line(cx+5,cy-3,cx+3,cy-1,col)
    cv.line(cx-7,cy+1,cx+7,cy+1,col); cv.line(cx+7,cy+1,cx+5,cy+3,col)
    cv.line(cx-6,cy+5,cx+3,cy+5,col)

def m_smoke(cv, cx=16, cy=17):
    for (x,y,r) in [(cx-3,cy+1,4),(cx+3,cy,4),(cx,cy-3,4),(cx+5,cy+3,3),(cx-5,cy+2,3)]:
        cv.disc(x,y,r,hexc("#9aa6b4"))
    cv.disc(cx-1,cy-2,2,hexc("#c3cdd8"))

def m_orb(cv, cx=16, cy=16, col=hexc("#8aa6ff")):
    cv.disc(cx,cy,6,col); cv.disc(cx-2,cy-2,2,WHITE); cv.ring(cx,cy,7,STEELD)

def m_beam(cv, cx=16, cy=16, col=PURP):
    cv.poly([(cx-8,cy+3),(cx+7,cy-4),(cx+8,cy-2),(cx-7,cy+5)], col)
    cv.poly([(cx+7,cy-4),(cx+10,cy-3),(cx+8,cy-1)], WHITE)

def m_rings(cv, cx=16, cy=16, col=hexc("#8aa6ff")):
    cv.ring(cx,cy,7,col); cv.ring(cx,cy,4,col); cv.disc(cx,cy,1.4,col)

def m_star(cv, cx=16, cy=16, col=GOLD, r=4):
    cv.vline(cx,cy-r,cy+r,col); cv.hline(cx-r,cx+r,cy,col)
    cv.px(cx-1,cy-1,col); cv.px(cx+1,cy-1,col); cv.px(cx-1,cy+1,col); cv.px(cx+1,cy+1,col)

def m_burst(cv, cx=16, cy=16, col=hexc("#ffd27a")):
    for dx,dy in [(0,-7),(0,7),(-7,0),(7,0),(5,5),(-5,5),(5,-5),(-5,-5)]:
        cv.line(cx+dx//3,cy+dy//3,cx+dx,cy+dy,col)
    cv.disc(cx,cy,2,WHITE)

def m_boot(cv, cx=16, cy=16):
    cv.poly([(cx-4,cy-7),(cx,cy-7),(cx,cy+3),(cx+6,cy+3),(cx+6,cy+8),(cx-4,cy+8)], hexc("#d8c08a"))

def m_footprint(cv, cx=18, cy=16):
    cv.ellipse(cx,cy+3,2,4,hexc("#cdd6e2"))
    for dx in (-2,0,2): cv.px(cx+dx,cy-3,hexc("#cdd6e2"))

def m_vial(cv, cx=16, cy=16, col=POISON):
    cv.poly([(cx-3,cy-7),(cx+3,cy-7),(cx+4,cy+5),(cx,cy+8),(cx-4,cy+5)], hexc("#dfe8ef"))
    cv.poly([(cx-3,cy),(cx+3,cy),(cx+3,cy+5),(cx,cy+7),(cx-3,cy+5)], col)
    cv.rect(cx-2,cy-9,cx+2,cy-7,hexc("#7a4a22"))

def m_caltrop(cv, cx=16, cy=16):
    cv.line(cx,cy,cx,cy-7,STEEL); cv.line(cx,cy,cx+6,cy+4,STEEL); cv.line(cx,cy,cx-6,cy+4,STEEL)
    cv.disc(cx,cy,2,STEELH)

def m_portal(cv, cx=16, cy=16, col=PURP):
    cv.ellipse(cx,cy,5,8,col); cv.ellipse(cx,cy,2,5,THEME["Staff"])

def m_chevrons(cv, cx=16, cy=14, col=GOLD, up=True, n=2):
    d=-1 if up else 1
    for i in range(n):
        y=cy+d*i*4
        cv.line(cx-5,y+d*3,cx,y-d*1,col); cv.line(cx,y-d*1,cx+5,y+d*3,col)

def m_hourglass(cv, cx=18, cy=18, col=hexc("#d8c08a")):
    cv.hline(cx-4,cx+4,cy-6,col); cv.hline(cx-4,cx+4,cy+6,col)
    cv.line(cx-4,cy-6,cx,cy,col); cv.line(cx+4,cy-6,cx,cy,col)
    cv.line(cx-4,cy+6,cx,cy,col); cv.line(cx+4,cy+6,cx,cy,col)

def m_wisp(cv, cx=16, cy=15, col=PURPH):
    cv.disc(cx,cy,4,col); cv.disc(cx,cy,2,WHITE)
    for (x,y) in [(cx+5,cy+4),(cx-4,cy+5),(cx+6,cy-2)]: cv.px(x,y,col)

def m_fan(cv, cx=16, cy=18):
    for ang,dx in [(-6,-6),(-3,0),(0,6)]:
        cv.line(cx,cy,cx+dx,cy-9,STEEL)
    cv.disc(cx,cy,2,GOLD)

def m_weave(cv, cx=16, cy=16, col=PURP):
    for off in (-5,0,5):
        pts=[(cx-7+i, cy+off+int(round(2.0*math.sin(i*0.85)))) for i in range(15)]
        for i in range(len(pts)-1):
            cv.line(pts[i][0],pts[i][1],pts[i+1][0],pts[i+1][1],col)

def m_well(cv, cx=16, cy=18, col=hexc("#8aa6ff")):
    cv.poly([(cx-7,cy-2),(cx+7,cy-2),(cx+5,cy+5),(cx-5,cy+5)], col)
    cv.disc(cx,cy-6,2,ICE)

def m_lancecharge(cv, cx=16, cy=16):
    m_blade_diag(cv, STEEL, cx+2, cy)
    for dy in (-5,0,5): cv.hline(cx-11,cx-5,cy+dy,GOLD)

# ---------------------------------------------------------------- ability -> draw
def DR(*fns):
    def run(cv):
        for f in fns: f(cv)
    return run

PX = {
 # SWORD
 "Aggression": DR(lambda c: m_blade(c), lambda c: m_chevrons(c, 16, 7, REDH, True, 2)),
 "Banner of the Vanguard": DR(lambda c: m_banner(c), lambda c: m_star(c, 17, 13, GOLD, 2)),
 "Battle-Hardened": DR(lambda c: m_shield(c), lambda c: (c.hline(12,20,14,STEELD), c.hline(12,20,18,STEELD))),
 "Bloodthirst": DR(lambda c: m_blade_diag(c), lambda c: m_drops(c, 22, 20, BLOOD, 2)),
 "Bulwark Stance": DR(lambda c: m_shield(c, STEEL, 16, 16, 1.2)),
 "Charge!": DR(lambda c: m_lancecharge(c)),
 "Crescent Cleave": DR(lambda c: m_crescent(c)),
 "Earthsplitter": DR(lambda c: m_blade_down(c, STEEL, 16, 12), lambda c: m_groundcrack(c, 16, 25)),
 "Hardened Frame": DR(lambda c: m_shield(c), lambda c: c.rect(13,13,19,19,STEELD)),
 "Hemorrhage": DR(lambda c: m_slash(c, REDH), lambda c: m_drops(c, 16, 21, BLOOD, 2)),
 "Iron Riposte": DR(lambda c: m_blade_diag(c, STEEL, 13, 16), lambda c: m_dagger_diag(c, STEEL, 19, 16, True), lambda c: m_star(c, 16, 9, GOLD, 2)),
 "Last Stand": DR(lambda c: m_shield(c, STEEL, 13, 17), lambda c: m_dagger_diag(c, STEEL, 21, 14)),
 "Vanguard's Onslaught": DR(lambda c: m_slash(c, WHITE, 16, 13), lambda c: m_slash(c, WHITE, 16, 18)),
 "Second Wind": DR(lambda c: m_wind(c, 16, 14), lambda c: m_star(c, 16, 23, GREEN, 3)),
 "Sentinel's Mark": DR(lambda c: m_crosshair(c, REDH)),
 "Steel Flurry": DR(lambda c: m_slash(c, STEELH, 16, 11), lambda c: m_slash(c, STEELH, 16, 16), lambda c: m_slash(c, STEELH, 16, 21)),
 "Sundering Blow": DR(lambda c: m_blade_down(c, STEEL, 16, 13), lambda c: m_crack(c, hexc("#ffb347"), 16, 24)),
 "Vanguard's Resolve": DR(lambda c: m_shield(c), lambda c: m_star(c, 16, 15, GOLD, 3)),
 "Vault Strike": DR(lambda c: m_blade_diag(c), lambda c: (c.line(8,24,13,19,GOLD))),
 "Vow of the Vanguard": DR(lambda c: m_blade(c), lambda c: c.ring(16, 8, 3, GOLD)),
 # BOW
 "Barbed Shot": DR(lambda c: m_arrow(c, STEEL, 16, 16, 13, False), lambda c: m_drops(c, 22, 11, BLOOD, 1)),
 "Caltrops": DR(lambda c: m_caltrop(c)),
 "Disengage": DR(lambda c: m_arrow(c, STEEL, 18, 16, 11, False), lambda c: m_wind(c, 11, 16, GREEN)),
 "Eagle Eye": DR(lambda c: m_eye(c, GREEN)),
 "Execution": DR(lambda c: m_skull(c, 16, 13), lambda c: m_arrow(c, STEEL, 16, 23, 8)),
 "Hailstorm": DR(lambda c: m_arrow(c, ICE, 11, 16, 10), lambda c: m_arrow(c, ICE, 16, 16, 10), lambda c: m_arrow(c, ICE, 21, 16, 10)),
 "Keen Eye": DR(lambda c: m_eye(c, GREEN), lambda c: c.ring(16, 16, 8, hexc("#bfe9b0"))),
 "Lethality": DR(lambda c: m_arrow(c, STEEL, 13, 14, 11), lambda c: m_skull(c, 22, 21)),
 "Mark of the Hunt": DR(lambda c: m_crosshair(c, GREEN), lambda c: m_skull(c, 16, 16)),
 "Marksman's Focus": DR(lambda c: m_crosshair(c, hexc("#bfe9b0")), lambda c: c.disc(16,16,1.4,WHITE)),
 "Sky Volley": DR(lambda c: m_arrow(c, STEEL, 11, 18, 12), lambda c: m_arrow(c, STEEL, 16, 16, 12), lambda c: m_arrow(c, STEEL, 21, 18, 12)),
 "Skyfall": DR(lambda c: (m_arrow(c, STEEL, 11, 16, 12), m_arrow(c, STEEL, 16, 16, 12), m_arrow(c, STEEL, 21, 16, 12))),
 "Snap Shot": DR(lambda c: m_arrow(c, STEEL, 16, 16, 14, False), lambda c: (c.hline(6,10,13,GOLD), c.hline(6,10,19,GOLD))),
 "Snipe": DR(lambda c: m_arrow(c, STEEL, 12, 16, 16, False), lambda c: m_crosshair(c, GREEN, 23, 16)),
 "Split Shot": DR(lambda c: m_arrow(c, STEEL, 16, 16, 12, False), lambda c: (m_arrow(c, STEEL, 16, 11, 9, False), m_arrow(c, STEEL, 16, 21, 9, False))),
 "Steady Aim": DR(lambda c: m_bow(c), lambda c: m_arrow(c, STEEL, 16, 16, 13, False)),
 "Sundering Arrow": DR(lambda c: m_arrow(c, STEEL, 14, 16, 12, False), lambda c: m_crack(c, hexc("#ffb347"), 23, 16)),
 "Surefoot": DR(lambda c: m_boot(c), lambda c: m_chevrons(c, 16, 6, GREEN, True, 1)),
 "Tailwind": DR(lambda c: m_wind(c, 16, 13, GREEN), lambda c: m_arrow(c, STEEL, 20, 22, 8)),
 "Wind Rider": DR(lambda c: m_wind(c, 16, 16, GREEN)),
 # STAFF
 "Aether Ward": DR(lambda c: m_shield(c), lambda c: m_rings(c, 16, 15)),
 "Arcane Familiar": DR(lambda c: m_wisp(c)),
 "Arcane Bolt": DR(lambda c: m_orb(c)),
 "Arcane Lance": DR(lambda c: m_beam(c)),
 "Arcane Resonance": DR(lambda c: m_rings(c, 16, 16, PURP)),
 "Communion": DR(lambda c: m_orb(c, 16, 14, PURPH), lambda c: m_chevrons(c, 16, 24, PURPH, True, 1)),
 "Deep Wellspring": DR(lambda c: m_well(c)),
 "Elemental Affinity": DR(lambda c: m_flame_small(c, 11, 18), lambda c: m_snowflake(c, 21, 18, ICE), lambda c: m_bolt(c, 16, 12)),
 "Frost Patch": DR(lambda c: m_snowflake(c, 16, 14), lambda c: c.hline(8,24,23,ICE)),
 "Glacial Spike": DR(lambda c: m_icespike(c)),
 "Immolate": DR(lambda c: m_flame(c)),
 "Killing Spree": DR(lambda c: m_burst(c), lambda c: m_skull(c, 16, 16)),
 "Mana Surge": DR(lambda c: m_orb(c, 16, 19), lambda c: m_chevrons(c, 16, 8, hexc("#8aa6ff"), True, 2)),
 "Mana Flow": DR(lambda c: m_weave(c, 16, 16, hexc("#8aa6ff"))),
 "Overload": DR(lambda c: m_burst(c, 16, 16, BOLT), lambda c: m_bolt(c)),
 "Phase Step": DR(lambda c: m_portal(c)),
 "Pyre Burst": DR(lambda c: m_burst(c, 16, 16, FIREH), lambda c: m_flame(c)),
 "Spell Ward": DR(lambda c: m_rings(c, 16, 16, PURP), lambda c: m_star(c, 16, 16, GOLD, 2)),
 "Spellweave": DR(lambda c: m_weave(c, 16, 16, PURP)),
 "Stormcall": DR(lambda c: (c.disc(13,12,4,hexc("#9aa6b4")), c.disc(19,12,4,hexc("#9aa6b4")), c.disc(16,11,5,hexc("#9aa6b4"))), lambda c: m_bolt(c, 16, 20, BOLT)),
 # DAGGER
 "Backstab": DR(lambda c: m_dagger_diag(c, STEEL, 13, 14), lambda c: m_crosshair(c, TEAL, 21, 21)),
 "Bloodlust": DR(lambda c: m_dagger_diag(c), lambda c: m_drops(c, 22, 20, BLOOD, 2)),
 "Composure": DR(lambda c: m_dagger(c), lambda c: c.ring(16, 16, 8, TEAL)),
 "Cripple": DR(lambda c: m_chevrons(c, 16, 20, TEAL, False, 2), lambda c: m_crack(c, TEAL, 16, 11)),
 "Cutthroat": DR(lambda c: m_dagger_diag(c), lambda c: m_slash(c, REDH, 16, 14)),
 "Death Mark": DR(lambda c: m_crosshair(c, PURP), lambda c: m_skull(c, 16, 16)),
 "Envenom": DR(lambda c: m_dagger_diag(c), lambda c: m_drops(c, 22, 20, POISON, 2)),
 "Evasion": DR(lambda c: m_dagger_diag(c, STEEL, 18, 14), lambda c: m_wind(c, 11, 20, TEAL)),
 "Eviscerate": DR(lambda c: (c.line(8,9,24,23,WHITE), c.line(8,10,24,24,WHITE)), lambda c: (c.line(24,9,8,23,WHITE), c.line(24,10,8,24,WHITE))),
 "Fan of Knives": DR(lambda c: m_fan(c)),
 "Killer Instinct": DR(lambda c: m_eye(c, PURP, 16, 13), lambda c: m_dagger(c, STEEL, 16, 20)),
 "Killing Edge": DR(lambda c: m_dagger_diag(c), lambda c: (c.px(22,9,WHITE), c.px(24,8,WHITE), c.px(23,11,WHITE))),
 "Opportunist": DR(lambda c: m_dagger_diag(c, STEEL, 13, 14), lambda c: m_hourglass(c, 22, 21)),
 "Predator's Patience": DR(lambda c: m_eye(c, TEAL, 14, 13), lambda c: m_hourglass(c, 22, 22)),
 "Shadow Partner": DR(lambda c: m_dagger_diag(c, SHADOW, 12, 16, True), lambda c: m_dagger_diag(c, STEEL, 20, 16)),
 "Shadowstep": DR(lambda c: m_portal(c, 16, 15, SHADOW), lambda c: m_footprint(c, 16, 22)),
 "Smoke Bomb": DR(lambda c: m_smoke(c)),
 "Toxicology": DR(lambda c: m_vial(c, 16, 16, POISON)),
 "Twin Fang": DR(lambda c: m_dagger_diag(c, STEEL, 12, 16, True), lambda c: m_dagger_diag(c, STEEL, 20, 16)),
 "Vendetta": DR(lambda c: m_dagger_diag(c), lambda c: m_crosshair(c, PURP, 21, 21)),
}

def m_flame_small(cv, cx, cy):
    cv.poly([(cx,cy-5),(cx+3,cy+1),(cx+2,cy+4),(cx-2,cy+4),(cx-3,cy)], FIRE)

def fallback(cv):
    m_star(cv, 16, 16, GOLD, 6)

def main():
    rows = []
    for w in WEAPONS:
        for tres in sorted(glob.glob(os.path.join(ABIL, w, "*.tres"))):
            txt = open(tres, encoding="utf-8").read()
            mm = re.search(r'ability_name\s*=\s*"([^"]+)"', txt)
            if not mm:
                continue
            name = mm.group(1)
            cv = frame(w)
            (PX.get(name) or fallback)(cv)
            base = os.path.splitext(os.path.basename(tres))[0]
            outp = os.path.join(OUT, w, base + ".png")
            os.makedirs(os.path.dirname(outp), exist_ok=True)
            cv.to_png(outp)
            rows.append((w, name, f"{w}/{base}.png", name in PX))
    by = {}
    for w, name, rel, ok in rows:
        by.setdefault(w, []).append((name, rel, ok))
    cells = ""
    for w in WEAPONS:
        cells += f'<h2>{w} &mdash; {len(by.get(w,[]))}</h2><div class="grid">'
        for name, rel, ok in by.get(w, []):
            flag = "" if ok else ' style="outline:2px solid #f33"'
            cells += f'<figure{flag}><img src="{rel}"><figcaption>{name}</figcaption></figure>'
        cells += "</div>"
    html = f'''<!doctype html><meta charset=utf-8><title>Ability pixel icons</title>
<style>body{{background:#15171c;color:#cdd6e2;font:12px system-ui;margin:18px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,84px);gap:8px;margin-bottom:18px}}
figure{{margin:0;text-align:center}}img{{width:64px;height:64px;image-rendering:pixelated}}
figcaption{{font-size:9px;color:#9aa6b4;line-height:1.05}}h2{{border-bottom:1px solid #333}}</style>
<h1>Ability pixel icons &mdash; {len(rows)}</h1>{cells}'''
    open(os.path.join(OUT, "index.html"), "w", encoding="utf-8").write(html)
    print(f"Generated {len(rows)} ability pixel icons -> {OUT}")

if __name__ == "__main__":
    main()
