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

# Early-game attack bump (added 2026-06-02). The bare L^1.5 ramp makes low-level
# monster ATTACK tiny (L6~15), and because defense mitigation is attack-scaled
# (def/(def+0.75*att) in enemy_base.damage_on_overlap), a small attack is heavily
# mitigated AND further cut by the level-gap modifier — so a near-level low-level
# mob felt toothless (a L6 Boar hit a L10 player for ~4). This adds a TENT-shaped
# bonus that fades IN from L1, peaks at LOW_ATK_PEAK_LEVEL (so the very-first-mob
# newbie experience stays gentle), then fades OUT to 0 by LOW_ATK_FADE_END — the
# early "real combat" band hits meaningfully harder while L1-3 stay soft and L30+
# endgame is untouched (the L100=1000 benchmark is preserved). Tune LOW_ATK_BONUS
# up for more early-game lethality, down for less; re-run; done.
LOW_ATK_BONUS = 20.0
LOW_ATK_PEAK_LEVEL = 5.0
LOW_ATK_FADE_END = 30.0


def _atk_bonus(L):
    if L <= LOW_ATK_PEAK_LEVEL:
        frac = L / LOW_ATK_PEAK_LEVEL
    else:
        frac = max(0.0, 1.0 - (L - LOW_ATK_PEAK_LEVEL) / (LOW_ATK_FADE_END - LOW_ATK_PEAK_LEVEL))
    return LOW_ATK_BONUS * frac


# Attack exponent SOFTENED 1.5 -> 1.25 (2026-06-08). The L^1.5 ramp made endgame
# touch damage brutal: a same-level, same-gear non-Sword character took ~30% of its
# HP per contact hit (died in 3-4 touches), forcing potion-spam every couple of
# seconds — far harsher than the MapleStory model this game targets (touch damage is
# chip you out-heal while farming; death at-level comes from boss/elite skills, not
# walking into a normal mob). L^1.25 keeps a super-linear climb (gear still matters)
# but brings at-level touch to ~5-8% of HP for squishies / ~2% for the Sword tank,
# and ARMOR matters MORE per point (mitigation = def/(def+0.75*att) rises as att falls).
# It also defangs the boss's flat special from a one-shot to a survivable telegraph.
# Player->enemy damage is unaffected (that uses the separate DEFENSE curve).
def _attack(L):
    return max(2, round(L ** 1.25 + _atk_bonus(L)))


# (filename, uid, value_fn) -- uids preserved so enemy .tscn refs don't break.
CURVES = [
    # Attack: L^1.25 ramp + early-game tent bump (see _attack). L6~29, L30~70, L100~316.
    ("monster_wep_att_curve.tres",   "uid://c20efdba57fc", _attack),
    # Magic attack mirrors physical; magic already hits harder (player MAGICDEFENSE
    # is gear-only) so no extra multiplier here.
    ("monster_magic_att_curve.tres", "uid://cf67a4a36687", _attack),
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
