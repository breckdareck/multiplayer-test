#!/usr/bin/env python3
"""
Ability damage / balance report generator (weapon-identity overhaul).

Implements the VERIFIED in-game damage formula (combat.gd + stats.gd, read
2026-05-29) and models every active ability's damage + DPS across character
levels and attribute-allocation archetypes, then renders a standalone HTML
report with a cross-weapon balance analysis.

Run:  python tools/ability_balance_report.py
Out:  docs/ability_balance_report.html

NOTHING here touches the game; it's a pure offline model. All formula constants
are mirrored from source and labelled with their origin so they can be re-synced
when the tunables change.
"""

import os

# ─────────────────────────────────────────────────────────────────────────────
# VERIFIED FORMULA CONSTANTS  (source: combat.gd / stats.gd, 2026-05-29)
# ─────────────────────────────────────────────────────────────────────────────
WEAPON_MULTIPLIER = 1.2     # CombatComponent.weapon_multiplier (@export default)
MASTERY_FLOOR     = 0.2     # CombatComponent.mastery — min-roll fraction (NOT weapon mastery)
BASE_ATTR         = 4       # StatData base for STR/DEX/INT/LUCK/CON
BASE_CRITCHANCE   = 5.0     # %  (stats.gd)
BASE_CRITDAMAGE   = 0.0     # %  (stats.gd) — the "crit trap": no gear source yet
ATTR_PTS_PER_LEVEL = 5      # stats.gd ATTRIBUTE_POINTS_PER_LEVEL
MASTERY_CAP       = 20      # WeaponMasteryComponent cap
LUCK_TO_CRIT      = 0.1     # % crit per LUCK point (stats.gd)
CRIT_MULT_AVG     = (1.2 + 1.5) / 2.0   # randf_range(1.2,1.5) average, + CRITDAMAGE/100

# Discipline primary / secondary stat (resource_manager.get_primary/secondary_stat)
#   and per-mastery-level stat_bonuses (discipline .tres).  stat keys: STR DEX INT LUCK
DISCIPLINES = {
    "Sword":  {"primary": "STR", "secondary": "DEX", "attack": "WEAPONATTACK",
               "mastery_bonus": {"STR": 3, "DEX": 2}},
    "Bow":    {"primary": "DEX", "secondary": "STR", "attack": "WEAPONATTACK",
               "mastery_bonus": {"STR": 2, "DEX": 3}},
    "Staff":  {"primary": "INT", "secondary": "LUCK", "attack": "MAGICATTACK",
               "mastery_bonus": {"INT": 3, "LUCK": 2}},
    "Dagger": {"primary": "LUCK", "secondary": "DEX", "attack": "WEAPONATTACK",
               "mastery_bonus": {"DEX": 2, "LUCK": 3}},
}

# Gear-driven attack power (WEAPONATTACK / MAGICATTACK are base 0 — gear only).
# Anchored to REAL gear at both ends: starter weapons give ~9 attack at L1
# (Wooden Sword +10 / Bronze Dagger +9 / Worn Warbow +7 / Wooden Staff +10 MATK),
# and the verified L100 benchmark (Eternal Dirk ≈ 197 WEAPONATTACK). Linear
# interpolation between. ABSOLUTE damage scales with this curve; the RELATIVE
# ability balance is gear-independent. NOTE: because base stats are only 4 and
# the pool/mastery are 0 at L1, early damage is almost entirely weapon-gated.
def gear_attack_power(level: int) -> int:
    return max(2, round(9.0 + (197.0 - 9.0) * (level - 1) / 99.0))

# Levels modelled.  (mastery assumption per tier: you can't out-level mastery cap.)
LEVEL_TIERS = [1, 30, 60, 100]
def mastery_at(level: int) -> int:
    # Reasonable assumption: mastery tracks early play then caps. L1 newbie=0,
    # L30≈10, L60≈18, L100=20 (capped). Mastery is kill-earned, cap 20.
    return min(MASTERY_CAP, round(level * 0.22))

# ─────────────────────────────────────────────────────────────────────────────
# ABILITY DATA  (source: resources/Abilities/*/A_*.tres, extracted 2026-05-29)
#   dmg = base + per_level*(lvl-1);  hits/targets similar.  magic=True → MAGICATTACK
# ─────────────────────────────────────────────────────────────────────────────
# fields: name, max_lvl, dmg_base, dmg_per, hits, hits_per, targets, mana_base,
#         mana_per, cd_base, cd_per, magic(bool), note
ABILITIES = {
"Sword": [
    ("Crescent Cleave (starter)", 20, 150, 8, 1, 0, 6, 2, 0.2, 4, 0, False, "AoE 6; combo builder"),
    ("Steel Flurry",              20,  80, 3, 2, 0, 2, 5, 0.3, 1, 0, False, "2 hits; combo builder; 1.0s CD"),
    ("Sundering Blow",            20, 114, 6, 1, 0, 1, 6, 0.3, 3, 0, False, "combo finisher"),
    ("Hemorrhage",                20, 130, 5, 1, 0, 1, 4, 0.3, 2, 0, False, "+ bleed DoT"),
    ("Vault Strike",              20, 120, 5, 1, 0, 2, 6, 0.4, 3, 0, False, "gap-closer dash"),
    ("Iron Riposte",              20,  12, 2, 1, 0, 1, 18,1.0, 25,0, False, "BUFF (reflect); dmg negligible"),
],
"Bow": [
    ("Snap Shot (basic)",          1, 100, 0, 1, 0, 1, 0, 0,   0,  0, False, "basic attack; builds Momentum"),
    ("Split Shot",                20,  77, 3, 2, 0, 1, 4, 0.2, 1.5,0, False, "2 hits"),
    ("Hailstorm",                 20,  40, 2, 3, 0.4,3,18,0.6, 4,  0, False, "multi-hit AoE; +2 Momentum/cast"),
    ("Skyfall",                   20,  60, 3, 1, 0, 6, 20,1.0, 5,  0, False, "AoE 6; +2 Momentum/cast"),
    ("Barbed Shot",               20, 110, 4, 1, 0, 1, 5, 0.3, 3,  0, False, "+ bleed DoT"),
    ("Disengage",                 20, 110, 5, 1, 0, 1, 6, 0.3, 6,  0, False, "kite dash + i-frames"),
    ("Snipe",                     20, 200,10, 1, 0, 1, 10,0.4, 6,  0, False, "Momentum SPENDER (+12%/stack)"),
],
"Staff": [
    ("Arcane Bolt (starter)",     20, 100, 5, 1, 0, 1, 4, 0.2, 1.2,0, True,  "spammable; 1.2s CD"),
    ("Glacial Spike",             20,  90, 5, 1, 0, 1, 16,0.6, 6,  0, True,  "+Ice stance = freeze"),
    ("Immolate",                  20, 100, 4, 1, 0, 1, 8, 0.3, 3,  0, True,  "+Fire stance = big burn + splash"),
    ("Pyre Burst",                20,  60, 3, 1, 0, 6, 18,0.8, 5,  0, True,  "AoE 6; +Fire = burn"),
    ("Arcane Lance",              20,  50, 2, 3, 0.4,3,18,0.6, 4,  0, True,  "channel; +Lightning = chain"),
],
"Dagger": [
    ("Twin Fang (starter)",       20,  73, 3, 2, 0, 1, 3, 0.1, 1,  0, False, "2 hits; 1.0s CD"),
    ("Fan of Knives",             20,  24, 1, 7, 0, 3, 10,0.4, 3,  0, False, "7 hits x3 targets"),
    ("Envenom",                   20,  90, 4, 1, 0, 1, 6, 0.3, 4,  0, False, "+ poison DoT"),
    ("Cripple",                   20,  70, 3, 1, 0, 1, 12,0.4, 10, 0, False, "+ def/atk debuff"),
    ("Shadowstep",                20, 100, 5, 1, 0, 1, 7, 0.3, 5,  0, False, "dash + i-frames"),
    ("Eviscerate",                20, 190,10, 1, 0, 1, 10,0.4, 6,  0, False, "finisher; stealth = execute <35% HP"),
],
}

# Allocation archetypes (how the 5/level pool is spent).
#   "default" = discipline ratio (un-respecced).  "pure" = all into primary.
#   "tank"    = half primary / half CON.
ARCHETYPES = ["default", "pure", "tank"]

def linear(base, per, lvl):
    return base + per * (lvl - 1)

# ─────────────────────────────────────────────────────────────────────────────
# STAT MODEL
# ─────────────────────────────────────────────────────────────────────────────
def build_stats(disc_name, level, archetype):
    """Returns dict of final STR/DEX/INT/LUCK/CON + crit% for a build."""
    d = DISCIPLINES[disc_name]
    pool = ATTR_PTS_PER_LEVEL * max(0, level - 1)
    mast = mastery_at(level)
    attrs = {k: BASE_ATTR for k in ("STR", "DEX", "INT", "LUCK", "CON")}

    # 1) allocate the pool
    if archetype == "default":
        # discipline ratio = its mastery_bonus ratio (sums to 5/level)
        ratio = d["mastery_bonus"]
        tot = sum(ratio.values())
        for k, w in ratio.items():
            attrs[k] += round(pool * w / tot)
    elif archetype == "pure":
        attrs[d["primary"]] += pool
    elif archetype == "tank":
        attrs[d["primary"]] += pool // 2
        attrs["CON"] += pool - pool // 2

    # 2) mastery scaling (auto, on the wielded discipline)
    for k, per in d["mastery_bonus"].items():
        attrs[k] += per * mast

    crit = BASE_CRITCHANCE + attrs["LUCK"] * LUCK_TO_CRIT
    return attrs, crit, pool, mast

def max_range(disc_name, attrs, attack_power):
    d = DISCIPLINES[disc_name]
    primary = attrs[d["primary"]]
    secondary = attrs[d["secondary"]]
    stat_mult = primary * 4 + secondary
    return round(WEAPON_MULTIPLIER * stat_mult * attack_power / 100.0)

def ability_numbers(ab, disc_name, level, archetype):
    """Compute per-hit + per-cast + DPS for an ability at character `level`."""
    (name, max_lvl, dmg_base, dmg_per, hits, hits_per, targets,
     mana_base, mana_per, cd_base, cd_per, magic, note) = ab
    if dmg_base <= 0:
        return None  # non-damage (buff/passive/mobility)

    ab_lvl = min(max_lvl, level)  # ability level capped by its own max (and char level)
    dmg_pct = linear(dmg_base, dmg_per, ab_lvl)
    n_hits = round(linear(hits, hits_per, ab_lvl))
    cd = max(0.1, linear(cd_base, cd_per, ab_lvl))

    attrs, crit, pool, mast = build_stats(disc_name, level, archetype)
    ap = gear_attack_power(level)
    mr = max_range(disc_name, attrs, ap)

    hit_max = mr * dmg_pct / 100.0                  # top of the roll, one hit
    hit_min = hit_max * MASTERY_FLOOR               # bottom of the roll
    hit_avg = (hit_min + hit_max) / 2.0
    # crit expectation (same-level even fight, no defense): CRITDAMAGE=0 → ×~1.35
    crit_mult = CRIT_MULT_AVG + BASE_CRITDAMAGE / 100.0
    eff_avg = hit_avg * (1.0 + (crit / 100.0) * (crit_mult - 1.0))

    per_cast_avg = eff_avg * n_hits                 # single target, all hits
    dps_single = per_cast_avg / cd
    dps_aoe = dps_single * targets                  # full-AoE potential
    return {
        "name": name, "ab_lvl": ab_lvl, "dmg_pct": round(dmg_pct, 1),
        "hits": n_hits, "targets": targets, "cd": round(cd, 2),
        "max_range": mr, "hit_max": round(hit_max), "hit_min": round(hit_min),
        "hit_avg": round(hit_avg), "eff_avg": round(eff_avg),
        "per_cast": round(per_cast_avg), "dps": round(dps_single),
        "dps_aoe": round(dps_aoe), "mana": round(linear(mana_base, mana_per, ab_lvl), 1),
        "dmg_per_mana": round(per_cast_avg / max(1, linear(mana_base, mana_per, ab_lvl)), 1),
        "crit": round(crit, 1), "note": note,
    }

# ─────────────────────────────────────────────────────────────────────────────
# HTML RENDERING
# ─────────────────────────────────────────────────────────────────────────────
def esc(s): return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def heat(val, lo, hi):
    """0..1 → color for a cell (green good/low → red high)."""
    if hi <= lo: return ""
    t = max(0.0, min(1.0, (val - lo) / (hi - lo)))
    r = int(40 + t * 180); g = int(160 - t * 110); b = 70
    return f"background:rgba({r},{g},{b},0.35);"

def render():
    parts = []
    parts.append(HEAD)
    parts.append('<div class="wrap">')
    parts.append(f'<h1>Ability Damage &amp; Balance Report</h1>')
    parts.append('<p class="sub">Weapon-identity overhaul · branch <code>pr-7-attributes-class-removal</code> · '
                 'model mirrors the verified <code>combat.gd</code> / <code>stats.gd</code> formula (2026-05-29)</p>')

    # Formula card
    parts.append('<div class="card"><h2>The damage formula (verified)</h2>'
        '<pre>'
        'max_range = 1.2 × (primary×4 + secondary) × ATTACK_POWER / 100\n'
        'roll      = rand(max_range × 0.2 , max_range)        # 20%–100% of max\n'
        'ability   = roll × (damage_percent / 100)            # per hit\n'
        'per hit   ×= level_modifier(0.5–1.5) × defense_mult(1 − def/(def+500))\n'
        'if crit (rand% < CRITCHANCE):  × ( rand(1.2,1.5) + CRITDAMAGE/100 )'
        '</pre>'
        '<ul class="notes">'
        '<li><b>ATTACK_POWER</b> = WEAPONATTACK (melee/bow) or MAGICATTACK (staff). Base <b>0</b> — '
        '<b>100% gear-driven</b>; it is the single biggest damage lever. Model assumes ≈ 2×level '
        '(anchored to the L100 benchmark ≈197).</li>'
        '<li><b>primary/secondary</b> = base 4 + allocated attributes (5/level pool) + mastery '
        '(discipline bonus × mastery level). <b>No per-level auto scaling</b> — it is all manual now.</li>'
        '<li><b>CRITDAMAGE base 0</b> with no gear source → a crit is only ×1.2–1.5. Crit rate is a near-dead stat.</li>'
        '<li>Tables below are <b>raw, same-level, zero-defense</b> single-target to isolate ability balance '
        '(defense &amp; level-gap are flat multipliers that hit every ability equally).</li>'
        '<li><b>Why Level 1 damage is tiny:</b> at L1 the attribute pool is 0 (5×(level−1)) and mastery is 0, '
        'so primary/secondary are just their base 4 → stat term = 4×4+4 = 20. With a starter weapon (~9 attack) '
        'that is 1.2×20×9/100 ≈ <b>2</b> per basic hit. Early damage is almost entirely <b>weapon-gated</b>; it '
        'climbs fast as the pool, mastery, and gear all grow together.</li>'
        '</ul></div>')

    # Allocation archetype explainer
    parts.append('<div class="card"><h2>Attribute allocation archetypes</h2>'
        '<p>The 5-points/level pool (= 5×(level−1); <b>495 at L100</b>) is spent manually. '
        'Three builds modelled:</p><ul class="notes">'
        '<li><b>default</b> — discipline ratio (what an un-respecced character auto-gets; e.g. Sword 3 STR : 2 DEX). Reproduces the old baseline.</li>'
        '<li><b>pure</b> — every point into the primary stat. The damage-max build.</li>'
        '<li><b>tank</b> — half primary, half CON (survivability at a damage cost).</li>'
        '</ul></div>')

    # Per-weapon, per-level tables (default archetype headline) + pure/default spread
    for disc in DISCIPLINES:
        parts.append(f'<h2 class="weap">{disc}</h2>')
        for lvl in LEVEL_TIERS:
            attrs, crit, pool, mast = build_stats(disc, lvl, "default")
            ap = gear_attack_power(lvl)
            d = DISCIPLINES[disc]
            rows = []
            for ab in ABILITIES[disc]:
                r = ability_numbers(ab, disc, lvl, "default")
                if r: rows.append(r)
            if not rows:
                continue
            dps_vals = [r["dps"] for r in rows]
            lo, hi = min(dps_vals), max(dps_vals)
            parts.append(f'<h3>Level {lvl} '
                f'<span class="meta">· {d["primary"]} {attrs[d["primary"]]} / {d["secondary"]} {attrs[d["secondary"]]} '
                f'· {d["attack"]} {ap} · mastery {mast} · crit {crit:.0f}% · pool {pool}</span></h3>')
            parts.append('<table><thead><tr>'
                '<th>Ability</th><th>dmg%</th><th>hits</th><th>tgts</th><th>CD</th>'
                '<th>hit (min–max)</th><th>eff/hit</th><th>per cast</th>'
                '<th>DPS (1T)</th><th>DPS (AoE)</th><th>mana</th><th>dmg/mana</th><th>note</th>'
                '</tr></thead><tbody>')
            for r in rows:
                parts.append('<tr>'
                    f'<td class="ab">{esc(r["name"])}</td>'
                    f'<td>{r["dmg_pct"]:.0f}%</td><td>{r["hits"]}</td><td>{r["targets"]}</td><td>{r["cd"]:.1f}s</td>'
                    f'<td>{r["hit_min"]:,}–{r["hit_max"]:,}</td>'
                    f'<td>{r["eff_avg"]:,}</td><td>{r["per_cast"]:,}</td>'
                    f'<td style="{heat(r["dps"],lo,hi)}"><b>{r["dps"]:,}</b></td>'
                    f'<td>{r["dps_aoe"]:,}</td>'
                    f'<td>{r["mana"]:g}</td><td>{r["dmg_per_mana"]:,}</td>'
                    f'<td class="note">{esc(r["note"])}</td>'
                    '</tr>')
            parts.append('</tbody></table>')

        # default vs pure spread at L100
        spread = []
        for ab in ABILITIES[disc]:
            rd = ability_numbers(ab, disc, 100, "default")
            rp = ability_numbers(ab, disc, 100, "pure")
            if rd and rp:
                spread.append((rd["name"], rd["dps"], rp["dps"]))
        if spread:
            avg_gain = sum((p / d - 1) for _, d, p in spread) / len(spread) * 100
            parts.append(f'<p class="spread"><b>Pure-primary vs default at L100:</b> '
                f'+{avg_gain:.0f}% DPS on average from re-speccing all points into the primary stat. '
                f'This is the "damage ceiling" lever (ADR 0002 Open #1).</p>')

    parts.append(ANALYSIS)
    parts.append('</div>')  # wrap
    parts.append('</body></html>')
    return "\n".join(parts)

HEAD = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ability Balance Report</title>
<style>
:root{--bg:#0f1117;--card:#171a23;--ink:#e7e9ee;--mut:#9aa3b2;--line:#262b38;--acc:#6db1ff;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif}
.wrap{max-width:1180px;margin:0 auto;padding:32px 22px 80px}
h1{font-size:30px;margin:0 0 4px}
.sub{color:var(--mut);margin:0 0 24px}
h2.weap{margin:38px 0 6px;font-size:24px;color:var(--acc);border-bottom:2px solid var(--line);padding-bottom:6px}
h2{font-size:20px;margin:0 0 12px}
h3{font-size:15px;margin:20px 0 8px;font-weight:600}
h3 .meta{color:var(--mut);font-weight:400;font-size:12.5px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:18px 20px;margin:14px 0}
pre{background:#0b0d13;border:1px solid var(--line);border-radius:8px;padding:14px;overflow:auto;color:#cdd6e4;font-size:12.5px}
ul.notes{margin:10px 0 0;padding-left:18px;color:var(--mut)}
ul.notes li{margin:4px 0}
ul.notes b{color:var(--ink)}
table{width:100%;border-collapse:collapse;margin:4px 0 8px;font-size:12.5px}
th,td{padding:6px 8px;text-align:right;border-bottom:1px solid var(--line);white-space:nowrap}
th{color:var(--mut);font-weight:600;text-align:right;position:sticky;top:0;background:var(--bg)}
td.ab,th:first-child,td.note{text-align:left}
td.ab{font-weight:600;color:#fff}
td.note{color:var(--mut);white-space:normal;min-width:160px}
.spread{background:#1c2230;border-left:3px solid var(--acc);padding:10px 14px;border-radius:6px;margin:6px 0 10px;color:#cdd6e4}
.find{background:var(--card);border:1px solid var(--line);border-left:4px solid #e0a800;border-radius:8px;padding:12px 16px;margin:10px 0}
.find.good{border-left-color:#3fb950}.find.bad{border-left-color:#f85149}
.find h4{margin:0 0 4px;font-size:14.5px}
.find p{margin:0;color:var(--mut)}
code{background:#0b0d13;padding:1px 5px;border-radius:4px;color:#cdd6e4}
</style></head><body>"""

ANALYSIS = """
<h2 class="weap">Balance findings &amp; recommendations</h2>

<div class="find bad"><h4>1 · Crit is a dead stat (CRITDAMAGE base 0, no gear source)</h4>
<p>A crit only multiplies ×1.2–1.5. LUCK→crit-rate (Dagger primary, +0.1%/pt) therefore barely
moves DPS, and the Dagger's Shadowmeld <b>guaranteed crit</b> is worth far less than it sounds.
<b>Fix B6:</b> add CRITDAMAGE rolls to high-tier gear so crit builds (and the guaranteed-crit
ambush) actually pay off. Until then Dagger's LUCK-primary identity is mostly a non-lever.</p></div>

<div class="find"><h4>2 · Pure-primary allocation ≈ +40% damage over default</h4>
<p>Re-speccing all points into the primary stat is a large, always-correct DPS gain with no
opportunity cost but survivability. Either soft-cap primary scaling, give the secondary stat a
real damage role, or make CON/utility compelling enough to tempt points away. (ADR 0002 Open #1.)</p></div>

<div class="find good"><h4>3 · Finishers read correctly as finishers</h4>
<p>Snipe (Bow, 200%+10/lvl, consumes Momentum), Eviscerate (Dagger, 190%+10/lvl, stealth execute)
and Sundering Blow (Sword, combo spender) top their kits' single-hit damage, gated behind
cooldown / a resource. Good shape — the payoff abilities hit hardest.</p></div>

<div class="find"><h4>4 · DoT abilities under-represented in raw tables</h4>
<p>Hemorrhage / Barbed Shot / Envenom / Immolate show only their <i>direct</i> hit here; their
bleed/poison/burn DoT adds 20%-of-stat/sec ×stacks on top (and Immolate under Fire stance roughly
doubles + splashes). Their effective DPS is higher than the table — keep that in mind before
buffing their base %.</p></div>

<div class="find"><h4>5 · Spammable starters are low-CD DPS floors — watch mana</h4>
<p>Arcane Bolt (1.2s), Twin Fang (1.0s), Steel Flurry (1.0s) and Split Shot (1.5s) deliver high
sustained DPS at trivial mana. They set each kit's floor; the cooldown abilities must clear that
floor (per-cast) to be worth a button. Most do; verify Cripple (10s CD, 70% dmg) earns its slot
beyond the debuff utility.</p></div>

<div class="find"><h4>6 · Cross-weapon parity holds at the starter level, diverges by build</h4>
<p>At default allocation the four kits land within a reasonable band. Staff scales on MAGICATTACK
(separate gear pool) and leans on its element stance for effective output; Bow's Momentum ramp
(+35% dmg / +30% fire-rate at cap) and Dagger's ambush ×2 are multiplicative on top of these raw
numbers, so signature uptime — not base % — is where real divergence will come from in play.</p></div>

<div class="find"><h4>7 · Tune targets, not just numbers</h4>
<p>Key starting-value knobs flagged this session: Immolate Fire splash %, Glacial Spike freeze
duration, lightning chain hops, Snipe's +12%/stack, Eviscerate's 35% execute threshold, Momentum
per-stack ramp. All are isolated constants — cheap to adjust from playtest feel.</p></div>
"""

if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "docs", "ability_balance_report.html")
    out = os.path.abspath(out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(render())
    print("wrote", out)
