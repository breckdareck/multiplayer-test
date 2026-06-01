#!/usr/bin/env python3
# Regenerates the monster stat curves (assets/curves/*.tres) with smooth,
# monotonically-ACCELERATING power-law ramps so difficulty genuinely climbs each
# band (no flat plateaus, no L30 HP wall). Run from project root:
#     python tools/gen_monster_curves.py
#
# Design intent (per design call): later monsters must be tougher, and GEAR is
# the lever a player pulls to keep up — a lucky weapon/armour drop is what lets
# you out-pace the curve, not just levelling. So monster ATTACK and HP ramp
# super-linearly, enemy DEFENSE keeps rising (old curves hard-capped at 260 from
# ~L70, freezing endgame), and player mitigation is intended to gently DECLINE
# toward endgame (harder) unless the player stacks defensive gear.
#
# Tune the exponents/coefficients below to reshape difficulty; re-run; done.
import os

BASE = os.path.join(os.path.dirname(__file__), "..", "assets", "curves")
LEVELS = [1] + list(range(5, 101, 5))   # 1, 5, 10, ... 100 (linear interp between)

# (filename, uid, value_fn) -- uids preserved so enemy .tscn refs don't break.
CURVES = [
    # Attack ramps L^1.5: clear accelerating steps (L10~32, L30~164, L100=1000).
    ("monster_wep_att_curve.tres",   "uid://c20efdba57fc", lambda L: max(2, round(L ** 1.5))),
    # Magic attack mirrors physical; magic already hits harder (player MAGICDEFENSE
    # is gear-only) so no extra multiplier here.
    ("monster_magic_att_curve.tres", "uid://cf67a4a36687", lambda L: max(2, round(L ** 1.5))),
    # Enemy defense L^1.2 to ~452 at L100 (was hard-capped 260) so player attack /
    # better weapons stay meaningful at endgame and high mobs are real walls.
    ("monster_wep_def_curve.tres",   "uid://e847666d08f4", lambda L: round(1.8 * L ** 1.2)),
    ("monster_magic_def_curve.tres", "uid://1b70eda8f0b1", lambda L: round(1.8 * L ** 1.2)),
    # HP L^2.3 to ~28k at L100, smooth through L30 (~1750) — kills the old
    # 720->1800 spike while keeping fights longer at high level.
    ("monster_hp_curve.tres",        "uid://q6qc5kgdbmyv", lambda L: max(15, round(0.7 * L ** 2.3))),
]


def emit(fname, uid, fn):
    pts = [(L, int(fn(L))) for L in LEVELS]
    ymax = float(max(v for _, v in pts))
    # _data point format: Vector2(x,y), left_tan, right_tan, left_mode, right_mode.
    # mode 1 = LINEAR (predictable straight-line interpolation between points).
    data = ", ".join("Vector2(%d, %d), 0.0, 0.0, 1, 1" % (L, v) for L, v in pts)
    txt = (
        '[gd_resource type="Curve" format=3 uid="%s"]\n\n'
        '[resource]\n'
        '_limits = [0.0, %g, 0.0, 100.0]\n'
        '_data = [%s]\n'
        'point_count = %d\n'
    ) % (uid, ymax, data, len(pts))
    with open(os.path.join(BASE, fname), "w") as f:
        f.write(txt)
    print("%-28s L1=%-4d L30=%-6d L50=%-7d L100=%d" %
          (fname, fn(1), fn(30), fn(50), pts[-1][1]))


for fname, uid, fn in CURVES:
    emit(fname, uid, fn)
print("Done. Monster curves regenerated.")
