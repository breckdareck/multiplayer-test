#!/usr/bin/env python3
"""Render side-by-side MOCKUPS of two proposed outer-world topologies (with levels),
so we can compare before changing the game. Pure visualization — touches no game data.
  tools/_mockup_opt1_wheel.png  = Fix the wheel (symmetric rim + branches + spokes)
  tools/_mockup_opt2_tree.png   = Hub-and-spoke tree (fan from start, no loop)
"""
import math, os
from PIL import Image, ImageDraw, ImageFont
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 1780, 940
try:
    F = ImageFont.truetype("arial.ttf", 15); FT = ImageFont.truetype("arialbd.ttf", 22)
    FL = ImageFont.truetype("arial.ttf", 14)
except Exception:
    F = ImageFont.load_default(); FT = F; FL = F

COL_TOWN = (255, 209, 77); COL_FIELD = (128, 199, 140); COL_BRANCH = (110, 196, 196)
COL_HUB = (245, 170, 70); COL_GATE = (165, 120, 220); COL_EDGE = (150, 138, 96)
COL_BRANCH_EDGE = (90, 150, 150); COL_LVL = (120, 196, 255); COL_NAME = (230, 230, 235)

def render(nodes, edges, branch_edges, fname, title, subtitle):
    img = Image.new("RGB", (W, H), (8, 10, 18)); d = ImageDraw.Draw(img)
    def px(n): return (nodes[n]["pos"][0] * W, nodes[n]["pos"][1] * H)
    for a, b in edges:
        d.line([px(a), px(b)], fill=COL_EDGE, width=3)
    for a, b in branch_edges:
        d.line([px(a), px(b)], fill=COL_BRANCH_EDGE, width=3)
    for n, nd in nodes.items():
        x, y = px(n); k = nd["kind"]
        col = {"town": COL_TOWN, "field": COL_FIELD, "branch": COL_BRANCH,
               "hub": COL_HUB, "gate": COL_GATE}[k]
        R = 17 if k in ("town", "hub", "gate") else (11 if k == "branch" else 14)
        if k in ("town", "hub"):
            d.rectangle([x - R, y - R, x + R, y + R], fill=col, outline=(20, 20, 20))
        else:
            d.ellipse([x - R, y - R, x + R, y + R], fill=col, outline=(20, 20, 20))
        lbl = nd.get("label", "")
        if lbl:
            tb = d.textbbox((0, 0), lbl, font=F); d.text((x - (tb[2] - tb[0]) / 2, y + R + 2), lbl, fill=COL_NAME, font=F)
        lv = nd.get("lv")
        if lv is not None:
            s = "TOWN" if lv == 0 and k == "town" else ("Lv %s" % lv)
            tb = d.textbbox((0, 0), s, font=FL)
            d.text((x - (tb[2] - tb[0]) / 2, y + R + 19), s, fill=COL_TOWN if s == "TOWN" else COL_LVL, font=FL)
    d.text((24, 18), title, fill=(255, 220, 150), font=FT)
    d.text((24, 50), subtitle, fill=(150, 150, 165), font=F)
    # legend
    lx, ly = 24, H - 70
    for i, (c, t) in enumerate([(COL_TOWN, "Town / hub"), (COL_FIELD, "Field map"), (COL_BRANCH, "Branch (grinding pocket)"), (COL_GATE, "Core gateway")]):
        d.ellipse([lx, ly + i * 18, lx + 12, ly + i * 18 + 12], fill=c)
        d.text((lx + 18, ly + i * 18 - 2), t, fill=(180, 180, 190), font=FL)
    img.save(os.path.join(ROOT, fname))

# ---------------- Option 1: FIX THE WHEEL (symmetric rim) ----------------
def opt1():
    CX, CY, RX, RY = 0.5, 0.43, 0.44, 0.36
    def P(ang, rf=1.0):
        a = math.radians(ang); return (CX + RX * rf * math.cos(a), CY - RY * rf * math.sin(a))
    nodes, edges, bedges = {}, [], []
    # rim: 12 nodes, 30deg apart, clockwise from top. Symmetric levels around the start.
    rim = [("lr", "Lantern's Rest", "town", 0), ("r1", "", "field", 2), ("r2", "", "field", 5),
           ("r3", "", "field", 8), ("wk", "Wickmoor", "town", 0), ("f1", "", "field", 13),
           ("pk", "", "field", 16), ("f2", "", "field", 13), ("hm", "Hollowmere", "town", 0),
           ("l3", "", "field", 8), ("l2", "", "field", 5), ("l1", "", "field", 2)]
    for i, (nid, lbl, kind, lv) in enumerate(rim):
        nodes[nid] = {"pos": P(90 - 30 * i), "kind": kind, "label": lbl, "lv": lv}
    for i in range(12):
        edges.append((rim[i][0], rim[(i + 1) % 12][0]))
    # branch grinding-pockets hanging OUTWARD off a few rim fields
    for src, ang, lv in [("r2", 30, 6), ("pk", -90, 17), ("l2", 150, 6)]:
        bid = "b_" + src
        nodes[bid] = {"pos": P(ang, 1.28), "kind": "branch", "label": "", "lv": lv}
        bedges.append((src, bid))
    # Emberwatch hub + 3 inward spokes (4 maps each) + Core gate
    nodes["emb"] = {"pos": (CX, CY), "kind": "hub", "label": "Emberwatch", "lv": 0}
    spokes = {"lr": [20, 28, 36, 43], "wk": [20, 28, 36, 43], "hm": [20, 28, 36, 43]}
    for town, lvls in spokes.items():
        tp = nodes[town]["pos"]; prev = town
        for j, lv in enumerate(lvls):
            t = (j + 1) / (len(lvls) + 1)
            sid = "s_%s_%d" % (town, j)
            nodes[sid] = {"pos": (tp[0] + (CX - tp[0]) * t, tp[1] + (CY - tp[1]) * t), "kind": "field", "label": "", "lv": lv}
            edges.append((prev, sid)); prev = sid
        edges.append((prev, "emb"))
    nodes["core"] = {"pos": (CX, CY + 0.30), "kind": "gate", "label": "The Core  ↓", "lv": "48-100"}
    edges.append(("emb", "core"))
    render(nodes, edges, bedges, "tools/_mockup_opt1_wheel.png",
           "OPTION 1 — Fix the wheel (symmetric rim)",
           "Closed rim loop: both sides of Lantern's Rest start Lv2 and climb to a Lv16 peak on the FAR side. Branch pockets + 3 inward spokes to Emberwatch, then the Core.")

# ---------------- Option 2: HUB-AND-SPOKE TREE (no loop) ----------------
def opt2():
    nodes, edges, bedges = {}, [], []
    def add(nid, x, y, kind, lv, lbl=""):
        nodes[nid] = {"pos": (x, y), "kind": kind, "label": lbl, "lv": lv}
    add("lr", 0.5, 0.06, "town", 0, "Lantern's Rest")
    # dead-end starter grinding pocket
    add("sp", 0.30, 0.10, "branch", 2); bedges.append(("lr", "sp"))
    # left branch -> Hollowmere
    L = [("L1", 0.34, 0.20, 3), ("L2", 0.23, 0.31, 6), ("L3", 0.16, 0.43, 9),
         ("hm", 0.15, 0.57, 0), ("L4", 0.27, 0.55, 16), ("L5", 0.39, 0.55, 20)]
    # right branch -> Wickmoor (mirror)
    Rr = [("R1", 0.66, 0.20, 3), ("R2", 0.77, 0.31, 6), ("R3", 0.84, 0.43, 9),
          ("wk", 0.85, 0.57, 0), ("R4", 0.73, 0.55, 16), ("R5", 0.61, 0.55, 20)]
    # center branch
    C = [("C1", 0.5, 0.20, 4), ("C2", 0.5, 0.33, 8), ("C3", 0.5, 0.45, 12), ("C4", 0.5, 0.56, 18)]
    for seq, town_idx in [(L, 3), (Rr, 3)]:
        for i, (nid, x, y, lv) in enumerate(seq):
            kind = "town" if i == town_idx else "field"
            add(nid, x, y, kind, lv, "Hollowmere" if nid == "hm" else ("Wickmoor" if nid == "wk" else ""))
        edges.append(("lr", seq[0][0]))
        for i in range(len(seq) - 1):
            edges.append((seq[i][0], seq[i + 1][0]))
    for nid, x, y, lv in C:
        add(nid, x, y, "field", lv)
    edges.append(("lr", "C1"))
    for i in range(len(C) - 1):
        edges.append((C[i][0], C[i + 1][0]))
    add("emb", 0.5, 0.68, "hub", 0, "Emberwatch")
    for last in ["L5", "R5", "C4"]:
        edges.append((last, "emb"))
    add("core", 0.5, 0.86, "gate", "48-100", "The Core  ↓"); edges.append(("emb", "core"))
    render(nodes, edges, bedges, "tools/_mockup_opt2_tree.png",
           "OPTION 2 — Hub-and-spoke tree (no loop)",
           "Lantern's Rest fans into 3+ branches (all start Lv2-4), each a clean climb through a town and inward; they only meet at Emberwatch. No closed perimeter.")

# ---------------- Option 3: EMBERWATCH CROSSROADS (chosen direction) ----------------
# No ring. Emberwatch is the central hub: town<->Emberwatch<->town (travel between
# towns ALWAYS routes through the middle). Each town's OUTER end fans into branch
# maps (MapleStory hunting-grounds). Towns are ascending tiers; only Lantern's Rest
# is the start. Core descends from Emberwatch.
def opt3():
    nodes, edges, bedges = {}, [], []
    def add(nid, x, y, kind, lv, lbl=""):
        nodes[nid] = {"pos": (x, y), "kind": kind, "label": lbl, "lv": lv}
    add("emb", 0.5, 0.5, "hub", 0, "Emberwatch")
    # --- UP arm: Lantern's Rest region (START, Lv1-24) ---
    add("lr", 0.5, 0.28, "town", 0, "Lantern's Rest")
    add("lr_r1", 0.5, 0.37, "field", 18); add("lr_r2", 0.5, 0.44, "field", 24)
    edges += [("lr", "lr_r1"), ("lr_r1", "lr_r2"), ("lr_r2", "emb")]
    # outer fan above the start town (the early hunting grounds)
    add("lr_f0", 0.5, 0.19, "field", 4)
    add("lr_f1", 0.37, 0.11, "branch", 2); add("lr_f2", 0.50, 0.09, "branch", 6); add("lr_f3", 0.63, 0.11, "branch", 8)
    edges += [("lr", "lr_f0")]; bedges += [("lr_f0", "lr_f1"), ("lr_f0", "lr_f2"), ("lr_f0", "lr_f3")]
    # --- RIGHT arm: Wickmoor region (Lv28-50) ---
    add("wk_r1", 0.59, 0.5, "field", 30); add("wk_r2", 0.66, 0.5, "field", 40)
    add("wk", 0.74, 0.5, "town", 0, "Wickmoor")
    edges += [("emb", "wk_r1"), ("wk_r1", "wk_r2"), ("wk_r2", "wk")]
    add("wk_f1", 0.85, 0.40, "branch", 46); add("wk_f2", 0.89, 0.5, "branch", 48); add("wk_f3", 0.85, 0.60, "branch", 50)
    bedges += [("wk", "wk_f1"), ("wk", "wk_f2"), ("wk", "wk_f3")]
    # --- LEFT arm: Hollowmere region (Lv54-75) ---
    add("hm_r1", 0.41, 0.5, "field", 56); add("hm_r2", 0.34, 0.5, "field", 66)
    add("hm", 0.26, 0.5, "town", 0, "Hollowmere")
    edges += [("emb", "hm_r1"), ("hm_r1", "hm_r2"), ("hm_r2", "hm")]
    add("hm_f1", 0.15, 0.40, "branch", 70); add("hm_f2", 0.11, 0.5, "branch", 72); add("hm_f3", 0.15, 0.60, "branch", 75)
    bedges += [("hm", "hm_f1"), ("hm", "hm_f2"), ("hm", "hm_f3")]
    # --- DOWN arm: the Core descent (Lv78-100) ---
    add("c1", 0.5, 0.62, "field", 80); add("c2", 0.5, 0.72, "field", 88); add("c3", 0.5, 0.82, "field", 94)
    add("warlord", 0.5, 0.92, "gate", 100, "Warlord")
    edges += [("emb", "c1"), ("c1", "c2"), ("c2", "c3"), ("c3", "warlord")]
    render(nodes, edges, bedges, "tools/_mockup_opt3_crossroads.png",
           "OPTION 3 — Emberwatch crossroads (no ring)",
           "Town<->Emberwatch<->town: travel between towns ALWAYS routes through the middle. Each town's OUTER end fans into branch maps (MapleStory). Towns are ascending tiers; only Lantern's Rest is the start.")

# ---------------- Option 4: VICTORIA-ISLAND STYLE (Emberwatch crossway) ----------------
# Like MapleStory's Six Path Crossway: a central junction (Emberwatch) that all town
# roads pass through. Organic winding roads with field maps strung along them; each town
# fans into dead-end hunting-ground BRANCHES; the Core dungeon descends DEEP from the
# centre (Sleepywood/Ant-Tunnel analog). Lantern's Rest (SW edge) is the low start;
# difficulty rises around the crossway and plunges into the Core.
def opt4():
    nodes, edges, bedges = {}, [], []
    def add(nid, x, y, kind, lv, lbl=""):
        nodes[nid] = {"pos": (x, y), "kind": kind, "label": lbl, "lv": lv}
    add("emb", 0.50, 0.45, "hub", 0, "Emberwatch  (crossway)")
    # --- Lantern's Rest: START region, SW edge (Lv1-17) ---
    add("lr", 0.18, 0.72, "town", 0, "Lantern's Rest")
    for nid, x, y, lv in [("lf1", 0.07, 0.59, 2), ("lf2", 0.06, 0.73, 4), ("lf3", 0.11, 0.86, 6), ("lf4", 0.28, 0.85, 8)]:
        add(nid, x, y, "branch", lv); bedges.append(("lr", nid))
    for a, b in [("lr", "lr1"), ("lr1", "lr2"), ("lr2", "lr3"), ("lr3", "emb")]:
        edges.append((a, b))
    add("lr1", 0.29, 0.63, "field", 11); add("lr2", 0.38, 0.56, "field", 14); add("lr3", 0.45, 0.50, "field", 17)
    # --- Wickmoor: mid region, NORTH (Lv22-42) ---
    add("wr1", 0.49, 0.32, "field", 22); add("wr2", 0.50, 0.22, "field", 28)
    add("wk", 0.51, 0.11, "town", 0, "Wickmoor")
    for a, b in [("emb", "wr1"), ("wr1", "wr2"), ("wr2", "wk")]:
        edges.append((a, b))
    for nid, x, y, lv in [("wf1", 0.40, 0.05, 34), ("wf2", 0.54, 0.04, 38), ("wf3", 0.65, 0.08, 42)]:
        add(nid, x, y, "branch", lv); bedges.append(("wk", nid))
    # --- Hollowmere: mid-high region, EAST (Lv46-64) ---
    add("hr1", 0.61, 0.41, "field", 46); add("hr2", 0.71, 0.38, "field", 52)
    add("hm", 0.84, 0.35, "town", 0, "Hollowmere")
    for a, b in [("emb", "hr1"), ("hr1", "hr2"), ("hr2", "hm")]:
        edges.append((a, b))
    for nid, x, y, lv in [("hf1", 0.92, 0.27, 56), ("hf2", 0.95, 0.37, 60), ("hf3", 0.92, 0.47, 64)]:
        add(nid, x, y, "branch", lv); bedges.append(("hm", nid))
    # --- Core: deep dungeon descent from the centre (Lv70-100), winding ---
    add("cr1", 0.55, 0.58, "field", 70); add("cr2", 0.44, 0.67, "field", 78)
    add("av", 0.35, 0.78, "town", 0, "Ashvigil")
    add("cr3", 0.50, 0.80, "field", 88); add("cr4", 0.56, 0.90, "field", 95)
    add("warlord", 0.46, 0.96, "gate", 100, "Warlord")
    for a, b in [("emb", "cr1"), ("cr1", "cr2"), ("cr2", "av"), ("av", "cr3"), ("cr3", "cr4"), ("cr4", "warlord")]:
        edges.append((a, b))
    render(nodes, edges, bedges, "tools/_mockup_opt4_victoria.png",
           "OPTION 4 — Victoria-Island style (Emberwatch crossway)",
           "Central crossway routes ALL town travel. Organic roads with field maps; towns fan into branch hunting-grounds; the Core dungeon descends deep from the centre. Lantern's Rest (SW) = low start; difficulty rises around the crossway into the Core.")

# ---------------- Option 5: REFINED — crossway + 2-direction arms ----------------
# Each town sits on a LINE: one road OUTWARD (frontier), one road INWARD to Emberwatch.
# Field maps along the spine can BRANCH OFF to side-pockets. Maps near a town share a
# level and rise outward. Lantern's Rest = Lv1 start (low frontier out; climb in ~Lv30).
# Wickmoor + Hollowmere = parallel mid arms (Lv33-48). Core UNCHANGED (descends centre).
def opt5():
    nodes, edges, bedges = {}, [], []
    def add(nid, x, y, kind, lv, lbl=""): nodes[nid] = {"pos": (x, y), "kind": kind, "label": lbl, "lv": lv}
    add("emb", 0.50, 0.44, "hub", 30, "Emberwatch (crossway)")
    # --- Lantern's Rest arm (START, SW): town near outer end ---
    add("lr", 0.21, 0.64, "town", 0, "Lantern's Rest")
    add("lo1", 0.12, 0.58, "field", 2); add("lo2", 0.07, 0.69, "field", 5); add("lo3", 0.13, 0.81, "field", 8)
    edges += [("lr", "lo1"), ("lo1", "lo2"), ("lo2", "lo3")]
    add("lb1", 0.02, 0.83, "branch", 15); bedges += [("lo2", "lb1")]          # side spike off the Lv5 map
    add("li1", 0.31, 0.60, "field", 8); add("li2", 0.38, 0.55, "field", 16); add("li3", 0.44, 0.50, "field", 24); add("li4", 0.49, 0.47, "field", 30)
    edges += [("lr", "li1"), ("li1", "li2"), ("li2", "li3"), ("li3", "li4"), ("li4", "emb")]
    add("lib", 0.34, 0.47, "branch", 20); bedges += [("li1", "lib")]
    # --- Wickmoor arm (N, parallel mid Lv33-48): low side toward Emberwatch, climb outward ---
    add("wi1", 0.52, 0.34, "field", 33); add("wi2", 0.51, 0.25, "field", 38)
    add("wk", 0.51, 0.15, "town", 0, "Wickmoor")
    add("wo1", 0.51, 0.07, "field", 44); add("wo2", 0.59, 0.03, "field", 48)
    edges += [("emb", "wi1"), ("wi1", "wi2"), ("wi2", "wk"), ("wk", "wo1"), ("wo1", "wo2")]
    add("wb1", 0.42, 0.03, "branch", 50); bedges += [("wo1", "wb1")]
    # --- Hollowmere arm (E, parallel mid Lv33-48) ---
    add("hi1", 0.60, 0.42, "field", 33); add("hi2", 0.70, 0.39, "field", 38)
    add("hm", 0.81, 0.36, "town", 0, "Hollowmere")
    add("ho1", 0.90, 0.30, "field", 44); add("ho2", 0.96, 0.22, "field", 48)
    edges += [("emb", "hi1"), ("hi1", "hi2"), ("hi2", "hm"), ("hm", "ho1"), ("ho1", "ho2")]
    add("hb1", 0.96, 0.38, "branch", 50); bedges += [("ho1", "hb1")]
    # --- Core (UNCHANGED, Lv48-100) descends from the centre ---
    add("c1", 0.50, 0.56, "field", 55); add("c2", 0.43, 0.66, "field", 68)
    add("av", 0.34, 0.76, "town", 0, "Ashvigil")
    add("c3", 0.49, 0.79, "field", 82); add("c4", 0.56, 0.88, "field", 94); add("warlord", 0.47, 0.95, "gate", 100, "Warlord")
    edges += [("emb", "c1"), ("c1", "c2"), ("c2", "av"), ("av", "c3"), ("c3", "c4"), ("c4", "warlord")]
    render(nodes, edges, bedges, "tools/_mockup_opt5_arms.png",
           "OPTION 5 — Crossway + 2-direction arms (REFINED)",
           "Each town is on a LINE: OUTWARD frontier + INWARD road to Emberwatch; field maps branch off to side-pockets. Near a town maps share a level, rising outward. Lantern's Rest = Lv1 start. Wickmoor/Hollowmere = parallel mid arms. Core UNCHANGED.")

# ---------------- Option 6: THREE IDENTICAL ARMS, Emberwatch = halfway ----------------
# All 3 towns behave the SAME (like Lantern's): a Lv1 town with a single OUTWARD frontier
# line (+ side-pockets) and a single INWARD climb to Emberwatch. The arms are parallel
# first-half regions (Lv1->~48). Reaching Emberwatch = the midpoint; the Core is the
# whole second half (Lv52-100, UNCHANGED). Levels here are representative (real build is
# much denser - more maps, finer steps). Travel between towns routes through Emberwatch.
def opt6():
    nodes, edges, bedges = {}, [], []
    def add(nid, x, y, kind, lv, lbl=""): nodes[nid] = {"pos": (x, y), "kind": kind, "label": lbl, "lv": lv}
    add("emb", 0.50, 0.42, "hub", 50, "Emberwatch (crossway)")
    # one identical arm builder: town at the tip, frontier OUT, climb IN to Emberwatch
    def arm(pfx, town_name, town_xy, frontier, pocket_xy, climb):
        add(pfx + "t", town_xy[0], town_xy[1], "town", 0, town_name)
        # frontier (single outward line + one side-pocket off the first frontier map)
        prev = pfx + "t"
        for i, (x, y, lv) in enumerate(frontier):
            nid = "%sf%d" % (pfx, i); add(nid, x, y, "field", lv); edges.append((prev, nid)); prev = nid
        add(pfx + "p", pocket_xy[0], pocket_xy[1], "branch", 16); bedges.append((pfx + "f0", pfx + "p"))
        # inward climb (single line) to Emberwatch
        prev = pfx + "t"
        for i, (x, y, lv) in enumerate(climb):
            nid = "%sc%d" % (pfx, i); add(nid, x, y, "field", lv); edges.append((prev, nid)); prev = nid
        edges.append((prev, "emb"))
    arm("L", "Lantern's Rest", (0.13, 0.54), [(0.07, 0.62, 3), (0.05, 0.74, 9)], (0.02, 0.53),
        [(0.20, 0.50, 14), (0.28, 0.47, 26), (0.37, 0.45, 38), (0.44, 0.43, 48)])
    arm("W", "Wickmoor", (0.50, 0.07), [(0.42, 0.03, 3), (0.30, 0.03, 9)], (0.46, 0.005) if False else (0.22, 0.06),
        [(0.50, 0.15, 14), (0.50, 0.22, 26), (0.50, 0.30, 38), (0.50, 0.37, 48)])
    arm("H", "Hollowmere", (0.87, 0.54), [(0.93, 0.62, 3), (0.95, 0.74, 9)], (0.98, 0.53),
        [(0.80, 0.50, 14), (0.72, 0.47, 26), (0.64, 0.45, 38), (0.57, 0.43, 48)])
    # Core (UNCHANGED) descends from Emberwatch = the whole second half
    add("cc1", 0.50, 0.52, "field", 55); add("cc2", 0.43, 0.62, "field", 68)
    add("av", 0.35, 0.72, "town", 0, "Ashvigil")
    add("cc3", 0.50, 0.74, "field", 82); add("cc4", 0.57, 0.84, "field", 94); add("warlord", 0.48, 0.93, "gate", 100, "Warlord")
    edges += [("emb", "cc1"), ("cc1", "cc2"), ("cc2", "av"), ("av", "cc3"), ("cc3", "cc4"), ("cc4", "warlord")]
    render(nodes, edges, bedges, "tools/_mockup_opt6_threearms.png",
           "OPTION 6 — Three identical arms, Emberwatch = halfway",
           "All 3 towns are the SAME: Lv1 town, one OUTWARD frontier line (+pocket), one INWARD climb to Emberwatch (~Lv48). Parallel first-half regions; reaching Emberwatch = midpoint. Core = whole second half (Lv52-100, UNCHANGED). Levels representative; real build is much denser.")

# ---------------- Option 7: ONE TOWN REGION IN DETAIL (all 3 built like this) ----------------
# A rich, branchy LOW area (>=10 maps, Lv1-15) fanning off the town as dead-end grinding
# pockets, plus the single INWARD climb to Emberwatch (Lv10->48). All 3 town regions are
# identical. The Core keeps its OWN separate world-map view (spiral) opened via the gateway.
def opt7():
    nodes, edges, bedges = {}, [], []
    def add(nid, x, y, kind, lv, lbl=""): nodes[nid] = {"pos": (x, y), "kind": kind, "label": lbl, "lv": lv}
    add("T", 0.30, 0.50, "town", 0, "Lantern's Rest")
    # --- rich branchy LOW frontier (west): 4-map spine + 4 dead-end pockets (x2) = 12 low maps ---
    spine = [("A1", 0.24, 0.50, 2), ("A2", 0.18, 0.50, 4), ("A3", 0.12, 0.50, 6), ("A4", 0.06, 0.50, 8)]
    prev = "T"
    for nid, x, y, lv in spine:
        add(nid, x, y, "field", lv); edges.append((prev, nid)); prev = nid
    pockets = [
        ("A1", ("P1a", 0.25, 0.37, 3), ("P1b", 0.21, 0.27, 5)),
        ("A2", ("P2a", 0.17, 0.63, 6), ("P2b", 0.13, 0.73, 9)),
        ("A3", ("P3a", 0.10, 0.37, 10), ("P3b", 0.05, 0.27, 13)),
        ("A4", ("P4a", 0.04, 0.63, 12), ("P4b", 0.07, 0.74, 15)),
    ]
    for anchor, p1, p2 in pockets:
        add(p1[0], p1[1], p1[2], "branch", p1[3]); add(p2[0], p2[1], p2[2], "branch", p2[3])
        bedges.append((anchor, p1[0])); edges.append((p1[0], p2[0]))
    # --- single INWARD climb (east) to Emberwatch ---
    climb = [("K1", 0.42, 0.50, 10), ("K2", 0.52, 0.50, 18), ("K3", 0.62, 0.50, 26),
             ("K4", 0.72, 0.50, 34), ("K5", 0.81, 0.50, 42), ("K6", 0.89, 0.50, 48)]
    prev = "T"
    for nid, x, y, lv in climb:
        add(nid, x, y, "field", lv); edges.append((prev, nid)); prev = nid
    add("KP", 0.52, 0.63, "branch", 22); bedges.append(("K2", "KP"))
    add("emb", 0.96, 0.50, "hub", 50, "Emberwatch")
    edges.append(("K6", "emb"))
    add("core", 0.96, 0.66, "gate", "50-100", "Core (own map)"); edges.append(("emb", "core"))
    render(nodes, edges, bedges, "tools/_mockup_opt7_region_detail.png",
           "ONE TOWN REGION (detail) — all 3 towns built like this",
           "Rich branchy LOW area (>=10 maps, Lv1-15) of dead-end grinding pockets off the town, + one INWARD climb to Emberwatch (~Lv48). World view = 3 of these arms around Emberwatch; the Core keeps its OWN separate spiral view via the gateway.")

# ---------------- Town splines: all 3 regions, DISTINCT archetypes/roles ----------------
def town_splines():
    W2, H2 = 1880, 1720
    img = Image.new("RGB", (W2, H2), (8, 10, 18)); d = ImageDraw.Draw(img)
    try:
        FBIG = ImageFont.truetype("arialbd.ttf", 24); FN = ImageFont.truetype("arial.ttf", 14); FLG = ImageFont.truetype("arial.ttf", 15)
    except Exception:
        FBIG = ImageFont.load_default(); FN = FBIG; FLG = FBIG
    AC = {"town": (255, 209, 77), "open": (150, 214, 150), "field": (104, 176, 116),
          "cave": (176, 140, 96), "cliffs": (122, 150, 184), "tower": (172, 130, 202)}
    LEV = {"spine": [2, 4, 6, 8], "climb": [11, 17, 24, 32, 40, 47], "kp": 21}

    def build(cy, town, spine, pockets, climb, kp_arch):
        N, E, B = {}, [], []
        def add(i, x, y, arch, lv, role, name=""): N[i] = {"pos": (x, y), "arch": arch, "lv": lv, "role": role, "name": name}
        add("T", 0.26, cy, "town", 0, "town", town)
        sx = [0.215, 0.170, 0.125, 0.080]; prev = "T"
        for j in range(4):
            nid = "S%d" % j; add(nid, sx[j], cy, spine[j], LEV["spine"][j], "field"); E.append((prev, nid)); prev = nid
        for j in range(4):
            chain = pockets[j]; anchor = "S%d" % j; up = (j % 2 == 0); prev = anchor
            for k, (lv, arch) in enumerate(chain):
                dy = (0.05 + 0.052 * k) * (-1 if up else 1)
                nid = "P%d_%d" % (j, k); add(nid, sx[j] - 0.016 - 0.011 * k, cy + dy, arch, lv, "dead" if k == len(chain) - 1 else "mid")
                (B if k == 0 else E).append((prev, nid)); prev = nid
        kx = [0.36, 0.45, 0.54, 0.63, 0.72, 0.81]; prev = "T"
        for j in range(6):
            nid = "K%d" % j; add(nid, kx[j], cy, climb[j], LEV["climb"][j], "field"); E.append((prev, nid)); prev = nid
        add("KP", 0.45, cy + 0.06, kp_arch, LEV["kp"], "dead"); B.append(("K1", "KP"))
        add("EMB", 0.90, cy, "town", 0, "hub", "→ Emberwatch"); E.append(("K5", "EMB"))
        return N, E, B

    regions = [
        (0.15, "Lantern's Rest  (meadows — open/field)",
         build(0.15, "Lantern's Rest", ["open", "field", "open", "field"],
               [[(4, "cave"), (6, "cave")], [(7, "open"), (9, "cliffs")], [(10, "cliffs"), (13, "cave")], [(12, "tower"), (15, "tower")]],
               ["field", "open", "cliffs", "field", "tower", "cliffs"], "cave")),
        (0.47, "Wickmoor  (bog/moor — cave-heavy, one deep 3-map warren, no towers)",
         build(0.47, "Wickmoor", ["open", "cave", "open", "cave"],
               [[(3, "cave"), (5, "cave"), (7, "cave")], [(8, "cliffs"), (10, "open")], [(11, "cave"), (14, "cave")], [(13, "cliffs"), (16, "cliffs")]],
               ["cave", "cliffs", "cave", "cliffs", "cave", "cliffs"], "open")),
        (0.79, "Hollowmere  (drowned spires — tower/cliff-heavy, vertical)",
         build(0.79, "Hollowmere", ["cliffs", "tower", "cliffs", "tower"],
               [[(4, "cave"), (6, "cave")], [(7, "tower"), (9, "tower")], [(11, "cliffs"), (14, "tower")], [(12, "cave"), (15, "cliffs")]],
               ["cliffs", "tower", "cliffs", "tower", "cliffs", "tower"], "tower")),
    ]
    for _, title, (N, E, B) in regions:
        def px(i): return (N[i]["pos"][0] * W2, N[i]["pos"][1] * H2)
        for a, b in E: d.line([px(a), px(b)], fill=(150, 138, 96), width=3)
        for a, b in B: d.line([px(a), px(b)], fill=(96, 150, 150), width=3)
        for i, nd in N.items():
            x, y = px(i); arch = nd["arch"]; col = AC.get(arch, (150, 150, 150))
            R = 19 if arch == "town" else 13
            if arch == "town":
                d.rectangle([x - R, y - R, x + R, y + R], fill=col, outline=(20, 20, 20))
            else:
                d.ellipse([x - R, y - R, x + R, y + R], fill=col, outline=(20, 20, 20))
                if nd["role"] == "dead":
                    d.ellipse([x - R - 4, y - R - 4, x + R + 4, y + R + 4], outline=(110, 110, 110))
            if nd.get("name"):
                tb = d.textbbox((0, 0), nd["name"], font=FN); d.text((x - (tb[2] - tb[0]) / 2, y + R + 2), nd["name"], fill=(232, 232, 235), font=FN)
            if nd["lv"]:
                s = "Lv%d" % nd["lv"]; tb = d.textbbox((0, 0), s, font=FN); d.text((x - (tb[2] - tb[0]) / 2, y - R - 18), s, fill=(120, 196, 255), font=FN)
    for i, (cy, title, _) in enumerate(regions):
        d.text((24, cy * H2 - 215), title, fill=(255, 220, 150), font=FBIG)
    # legend
    lx, ly = 24, H2 - 80
    d.text((lx, ly - 26), "Archetype:", fill=(200, 200, 210), font=FLG)
    for i, (arch, c) in enumerate([("open", AC["open"]), ("field", AC["field"]), ("cave", AC["cave"]), ("cliffs", AC["cliffs"]), ("tower", AC["tower"]), ("town", AC["town"])]):
        d.ellipse([lx + i * 150, ly, lx + i * 150 + 16, ly + 16], fill=c); d.text((lx + i * 150 + 22, ly - 1), arch, fill=(190, 190, 200), font=FLG)
    d.text((lx, ly + 26), "ring = dead-end grind pocket   ·   left of town = frontier (Lv2-16)   ·   right = climb to Emberwatch (Lv11-47)", fill=(150, 150, 160), font=FLG)
    img.save(os.path.join(ROOT, "tools/_mockup_town_splines.png"))

town_splines()
print("rendered town_splines")
