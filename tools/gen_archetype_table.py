#!/usr/bin/env python3
# Generates docs/archetype_stats.html — a reference of the resulting monster
# stats (curve x archetype) per level, plus the physical/magic damage-landed
# split (the rock-paper-scissors feel). Re-run after retuning the curves or
# archetype presets:  python tools/gen_archetype_table.py
#
# NOTE: the formulas + presets below MUST mirror tools/gen_monster_curves.py and
# EnemyData._ARCHETYPE_PRESETS. Update both if you change one.
import os

# --- monster curve formulas (mirror gen_monster_curves.py) -------------------
def c_att(L):  return max(2, round(L ** 1.5))
def c_def(L):  return round(1.8 * L ** 1.2)
def c_hp(L):   return max(15, round(0.7 * L ** 2.3))

# --- archetype presets (mirror EnemyData._ARCHETYPE_PRESETS): def, mdef, hp, atk
PRESETS = {
    "NONE":       (1.0, 1.0, 1.0, 1.0),
    "OOZE":       (1.5, 0.4, 1.0, 0.8),
    "ARMORED":    (1.7, 0.7, 1.2, 1.0),
    "SPECTRAL":   (0.5, 1.7, 0.85, 1.0),
    "BRUTE":      (1.0, 0.6, 1.6, 1.4),
    "GLASS":      (0.5, 0.5, 0.6, 1.5),
    "JUGGERNAUT": (1.5, 1.5, 2.2, 1.2),
}
FEEL = {
    "NONE": "curve baseline", "OOZE": "phys wall, melts to magic",
    "ARMORED": "tanky, decent magic resist", "SPECTRAL": "magic wall, melts to physical",
    "BRUTE": "big HP, hits hard, weak to magic", "GLASS": "fragile, high damage",
    "JUGGERNAUT": "elite — tanky both, huge HP",
}
LEVELS = [10, 30, 50, 70, 100]

def stat(L, arch, which):
    d, m, h, a = PRESETS[arch]
    if which == "atk":  return round(c_att(L) * a)
    if which == "def":  return round(c_def(L) * d)
    if which == "mdef": return round(c_def(L) * m)
    if which == "hp":   return round(c_hp(L) * h)

def landed(def_val):  # % of YOUR damage that lands vs this defense: 500/(def+500)
    return round(100.0 * 500.0 / (def_val + 500.0))

def stat_table(title, which):
    rows = ""
    for arch in PRESETS:
        cells = "".join("<td>%d</td>" % stat(L, arch, which) for L in LEVELS)
        rows += '<tr><th class="a">%s</th>%s</tr>' % (arch, cells)
    head = "".join("<th>L%d</th>" % L for L in LEVELS)
    return ('<h2>%s</h2><table><tr><th>Archetype</th>%s</tr>%s</table>'
            % (title, head, rows))

def feel_table():
    rows = ""
    for arch in PRESETS:
        d, m, h, a = PRESETS[arch]
        dfn, mdf = stat(50, arch, "def"), stat(50, arch, "mdef")
        rows += ('<tr><th class="a">%s</th><td>%.2g/%.2g/%.2g/%.2g</td>'
                 '<td class="%s">%d%%</td><td class="%s">%d%%</td><td class="feel">%s</td></tr>'
                 % (arch, d, m, h, a,
                    "lo" if landed(dfn) < 60 else "hi", landed(dfn),
                    "lo" if landed(mdf) < 60 else "hi", landed(mdf), FEEL[arch]))
    return ('<h2>The feel @ L50 &mdash; how much of YOUR damage lands</h2>'
            '<p class="note">Profile = def/mdef/hp/atk multipliers. A lower number means '
            'that damage type is resisted (bring the other one).</p>'
            '<table><tr><th>Archetype</th><th>Profile</th><th>Physical lands</th>'
            '<th>Magic lands</th><th>Feel</th></tr>%s</table>' % rows)

html = """<!doctype html><meta charset=utf-8><title>Monster Archetype Stats</title>
<style>
 body{background:#15171c;color:#d7dbe2;font:14px/1.5 system-ui,sans-serif;margin:24px auto;max-width:900px}
 h1{color:#e6c95c} h2{color:#7ec2ff;margin-top:28px;border-bottom:1px solid #333;padding-bottom:4px}
 table{border-collapse:collapse;width:100%;margin:8px 0}
 th,td{border:1px solid #2c3038;padding:6px 10px;text-align:right}
 tr th:first-child,th.a{text-align:left;color:#cfd5df;background:#1c1f26}
 tr:nth-child(even) td{background:#191c22}
 td.feel{text-align:left;color:#9aa3af} td.lo{color:#ff8f8f} td.hi{color:#8fe39a}
 .note{color:#8a92a0;font-size:13px} .sub{color:#8a92a0}
</style>
<h1>Monster Archetype Stats</h1>
<p class="sub">Resulting stats = level curve &times; archetype preset. Per-enemy
fine-tune multipliers (default 1.0) stack on top. Curves: ATK=L^1.5, DEF/MDEF=1.8&middot;L^1.2, HP=0.7&middot;L^2.3.</p>
"""
html += feel_table()
html += stat_table("DEFENSE (physical)", "def")
html += stat_table("MAGIC DEFENSE", "mdef")
html += stat_table("HP", "hp")
html += stat_table("ATTACK", "atk")

out = os.path.join(os.path.dirname(__file__), "..", "docs", "archetype_stats.html")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    f.write(html)
print("Wrote", os.path.normpath(out))
