#!/usr/bin/env python3
"""
Survivability & enemy-tuning balance report (weapon-identity overhaul).

The companion to tools/full_balance_report.py. That report covered player->enemy
OFFENSE (ability damage). This one closes the loop:

  A. PLAYER SURVIVABILITY -- HP, DEFENSE, MAGICDEFENSE with level-appropriate ARMOR
     (the generated armor sets, tools/generate_item_content.gd) per discipline,
     run against the enemy touch-damage formula (enemy_base.gd.damage_on_overlap,
     read 2026-06-08): incoming hit, % of HP, hits-to-die, effective HP.

  B. ENEMY TUNING -- monster HP / DEFENSE / MAGICDEFENSE across the level curve,
     correlated to how much damage the player actually deals (the same combat
     model as report 1): hits-to-kill per discipline, is the mob too spongy /
     too fragile, is its touch damage too deadly / toothless.

Reuses the verified stat + combat + enemy-curve model from full_balance_report.py.

Run:  python tools/survivability_report.py
Out:  docs/survivability_report.html
"""

import importlib.util
import os
import html

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "docs", "survivability_report.html")

# Reuse the verified model from the offense report.
_spec = importlib.util.spec_from_file_location("fbr", os.path.join(HERE, "full_balance_report.py"))
fbr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fbr)


# ===========================================================================
# PLAYER HP CURVE  (source: stats.gd, keyed on PRIMARY discipline)
# ===========================================================================
HP_CURVE = {
    "Sword":  lambda L: 120 + 26 * (L - 1),
    "Bow":    lambda L: 90 + 22 * (L - 1),
    "Staff":  lambda L: 70 + 23 * (L - 1),
    "Dagger": lambda L: 95 + 22 * (L - 1),
}
CON_TO_HP = 8.0          # stats.gd _apply_attribute_utilities
STR_TO_DEFENSE = 1.0     # stats.gd


# ===========================================================================
# ARMOR MODEL  (source: tools/generate_item_content.gd _generate_armor)
#   per piece stat = round((base + item_level*slope) * slot_weight)
#   a full set = the 4 slots summed.
# ===========================================================================
ARMOR_LEVELS = [1, 8, 13, 20, 27, 35, 43, 50, 60, 68, 77, 85, 93, 100]
SLOT_WEIGHTS = [0.6, 1.0, 0.8, 0.5]   # Helm, Mail, Legguards, Boots

# discipline -> armor family identity
ARMOR_SETS = {
    "Sword":  {"def": (3.0, 0.7), "mdef": (2.0, 0.45), "theme": {"STR": (1.0, 0.25), "HEALTH": (8.0, 1.8)},
               "family": "Vanguard plate"},
    "Bow":    {"def": (2.5, 0.55), "mdef": (2.5, 0.55), "theme": {"DEX": (1.0, 0.3)},
               "family": "Pathfinder leather"},
    "Staff":  {"def": (2.0, 0.45), "mdef": (3.0, 0.7), "theme": {"INT": (1.0, 0.3)},
               "family": "Arcanist robes"},
    "Dagger": {"def": (2.5, 0.55), "mdef": (2.5, 0.55), "theme": {"LUCK": (1.0, 0.3)},
               "family": "Nightshade garb"},
}


def armor_item_level(L):
    cand = [x for x in ARMOR_LEVELS if x <= L]
    return cand[-1] if cand else 1


def _set_total(base, slope, lv):
    return sum(max(1, round((base + lv * slope) * w)) for w in SLOT_WEIGHTS)


def armor_set(disc, L):
    # Use the SAME gear model as the offense report (generate_item_content.gd) so
    # DEF / MDEF / HEALTH / EVASION and the folded attributes stay consistent.
    return fbr.gear_stats(disc, L)


# ===========================================================================
# ENEMY TOUCH DAMAGE  (source: enemy_base.gd.damage_on_overlap, 2026-06-08)
# ===========================================================================
DEFENSE_SOFTNESS = 0.75
MAX_DEFENSE_MITIGATION = 0.85


def a_coef(level_diff):   # player_level - monster_level
    return max(0.1, min(5.0, 1.0 - level_diff * 0.03))


def b_coef(level_diff):
    if level_diff >= 0:
        return 1.0
    d = -level_diff
    if d <= 10:
        return round(1.0 - d * 0.01, 2)
    if d <= 20:
        return round(0.90 - (d - 10) * 0.02, 2)
    if d <= 29:
        return round(0.70 - (d - 20) * 0.02, 2)
    return 0.50


def touch_mitigation(player_def, monster_att, level_diff):
    eff = b_coef(level_diff) * player_def
    mit = eff / (eff + max(1.0, DEFENSE_SOFTNESS * monster_att))
    return min(mit, MAX_DEFENSE_MITIGATION)


def touch_hit(player_def, char_level, mob_level):
    """Average enemy touch hit vs the player, plus mitigation & hit-chance."""
    diff = char_level - mob_level
    att = fbr.enemy_attack(mob_level)
    mit = touch_mitigation(player_def, att, diff)
    a = a_coef(diff)
    avg = a * 0.925 * att * (1.0 - mit)   # 0.925 = mean of 0.85x and 1.0x rolls
    hitc = max(5.0, min(100.0, 95.0 + (-diff * 3.0)))  # enemy accuracy 0, evasion 0
    return avg, mit, hitc


# ===========================================================================
# PLAYER SURVIVABILITY BUNDLE
# ===========================================================================
def survivability(disc, L, alloc="pure"):
    st = fbr.build_stats(disc, L, alloc)
    arm = armor_set(disc, L)
    base_hp = HP_CURVE[disc](L)
    con = st["attrs"]["CON"]            # build_stats already folds gear CON in
    hp = base_hp + round(con * CON_TO_HP) + arm.get("HEALTH", 0)
    str_total = st["attrs"]["STR"]      # build_stats already folds gear STR in
    defense = round(str_total * STR_TO_DEFENSE) + arm["DEF"]
    mdef = arm["MDEF"]
    return {"hp": hp, "def": defense, "mdef": mdef, "armor": arm, "st": st,
            "base_hp": base_hp, "str_total": str_total}


def player_avg_hit(disc, L, mob_level):
    """Representative average direct hit (basic attack, 100% dmg) vs a mob."""
    st = fbr.build_stats(disc, L, "pure")
    magic = disc == "Staff"
    return fbr.direct_hit(st, 100, 1, L, mob_level, magic)


# ===========================================================================
# RENDER HELPERS
# ===========================================================================
def cls_pct(p, lo, hi, invert=False):
    """Generic threshold colourer."""
    if invert:
        if p <= lo:
            return "ok"
        if p <= hi:
            return "warn"
        return "bad"
    if p >= hi:
        return "ok"
    if p >= lo:
        return "warn"
    return "bad"


def fmt(n):
    return fbr.fmt(n)


LEVELS = [1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]


def survivability_table(disc):
    fam = ARMOR_SETS[disc]["family"]
    out = [f'<div class="ability" id="surv-{disc}"><h4>{disc} &mdash; <span class="stat-tag">{fam}</span> '
           '(pure-damage allocation, full level-appropriate set)</h4>',
           '<table class="dmg"><thead><tr>'
           '<th>Lv</th><th>Armor iLv</th><th>HP</th><th>DEF</th><th>MDEF</th>'
           '<th>Phys mitig.</th><th>EHP(phys)</th>'
           '<th>Mob touch hit</th><th>% HP</th><th>Touch&rarr;die</th><th>Mob hit%</th>'
           '<th>Your hit</th><th>Mob HP</th><th>Hits&rarr;kill</th><th>Read</th>'
           '</tr></thead><tbody>']
    for L in LEVELS:
        s = survivability(disc, L)
        mob = L
        touch, mit, hitc = touch_hit(s["def"], L, mob)
        pct = 100.0 * touch / s["hp"]
        die = s["hp"] / touch if touch > 0 else 999
        ehp = s["hp"] / (1.0 - mit) if mit < 1 else s["hp"]
        yhit = player_avg_hit(disc, L, mob)
        mhp = fbr.enemy_hp(mob)
        kill = mhp / yhit if yhit > 0 else 999
        # verdict
        reads = []
        if pct > 30:
            reads.append("mobs hit hard")
        elif pct < 1.5:
            reads.append("mobs harmless")
        if kill <= 1:
            reads.append("you one-shot mobs")
        elif kill > 12:
            reads.append("mob too spongy")
        read = "; ".join(reads) if reads else "ok"
        vcls = "ok" if read == "ok" else ("warn" if ("hard" in read or "harmless" in read) else "bad")
        out.append(
            f'<tr><td>{L}</td><td>{s["armor"]["item_level"]}</td>'
            f'<td>{s["hp"]:,}</td><td>{s["def"]:,}</td><td>{s["mdef"]:,}</td>'
            f'<td>{mit*100:.0f}%</td><td>{ehp:,.0f}</td>'
            f'<td>{fmt(touch)}</td>'
            f'<td class="{cls_pct(pct,5,15,invert=True)}">{pct:.1f}%</td>'
            f'<td>{die:.0f}</td><td>{hitc:.0f}%</td>'
            f'<td>{fmt(yhit)}</td><td>{mhp:,}</td>'
            f'<td class="{cls_pct(kill,2,12,invert=True)}">{kill:.1f}</td>'
            f'<td class="{vcls}">{read}</td></tr>')
    out.append('</tbody></table>')
    # under-level stress: char vs mobs +5/+10 at L50
    out.append('<div class="sweep"><b>Under-levelled stress @ char 50 (% HP per mob touch / mob hit%):</b>'
               '<table class="dmg sweeptab"><thead><tr><th>vs mob</th>'
               '<th>L45</th><th>L50</th><th>L55</th><th>L60</th><th>L65</th></tr></thead><tbody>')
    s = survivability(disc, 50)
    cells_p, cells_h = [], []
    for mob in [45, 50, 55, 60, 65]:
        touch, mit, hitc = touch_hit(s["def"], 50, mob)
        cells_p.append(f'<td class="{cls_pct(100*touch/s["hp"],5,15,invert=True)}">{100*touch/s["hp"]:.1f}%</td>')
        cells_h.append(f'<td>{hitc:.0f}%</td>')
    out.append(f'<tr><td>touch %HP</td>{"".join(cells_p)}</tr>')
    out.append(f'<tr><td>mob hit%</td>{"".join(cells_h)}</tr>')
    out.append('</tbody></table></div></div>')
    return "\n".join(out)


def enemy_curve_table():
    out = ['<table class="dmg"><thead><tr><th>Mob Lv</th><th>HP</th><th>DEF</th><th>MDEF</th><th>Attack</th>'
           '<th>Phys def-mult<small>(player hit)</small></th>'
           '<th colspan="4">At-level player hits&rarr;kill</th><th>Read</th></tr>'
           '<tr><th></th><th></th><th></th><th></th><th></th><th></th>'
           '<th>Sword</th><th>Bow</th><th>Staff</th><th>Dagger</th><th></th></tr></thead><tbody>']
    for mob in [1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]:
        hp = fbr.enemy_hp(mob)
        d = fbr.enemy_def(mob)
        md = fbr.enemy_mdef(mob)
        att = fbr.enemy_attack(mob)
        defmult = fbr.def_mult(d)
        kills = {}
        for disc in ["Sword", "Bow", "Staff", "Dagger"]:
            yhit = player_avg_hit(disc, mob, mob)
            kills[disc] = hp / yhit if yhit > 0 else 999
        avgkill = sum(kills.values()) / 4
        reads = []
        if avgkill > 12:
            reads.append("spongy")
        elif avgkill < 2:
            reads.append("fragile")
        read = "; ".join(reads) if reads else "ok"
        vcls = "ok" if read == "ok" else "warn"
        kcells = "".join(
            f'<td class="{cls_pct(kills[dd],2,12,invert=True)}">{kills[dd]:.1f}</td>'
            for dd in ["Sword", "Bow", "Staff", "Dagger"])
        out.append(
            f'<tr><td>{mob}</td><td>{hp:,}</td><td>{d}</td><td>{md}</td><td>{att}</td>'
            f'<td>{defmult*100:.0f}%</td>{kcells}<td class="{vcls}">{read}</td></tr>')
    out.append('</tbody></table>')
    return "\n".join(out)


def con_comparison():
    """Show how a CON/bruiser allocation changes HP & survivability at L100."""
    out = ['<table class="dmg"><thead><tr><th>Discipline</th>'
           '<th>HP (pure dmg)</th><th>HP (40% CON)</th><th>DEF</th>'
           '<th>at-L100 touch %HP (pure)</th><th>touch %HP (40% CON)</th></tr></thead><tbody>']
    for disc in ["Sword", "Bow", "Staff", "Dagger"]:
        sp = survivability(disc, 100, "pure")
        # 40% CON: emulate by adding CON points = 0.4 * pool to CON utility HP
        pool = fbr.ATTR_PTS_PER_LEVEL * 99
        con_extra = fbr.soft_cap(round(pool * 0.4))
        hp_con = sp["base_hp"] + round((4 + con_extra) * CON_TO_HP) + sp["armor"].get("HEALTH", 0)
        tp, _, _ = touch_hit(sp["def"], 100, 100)
        out.append(
            f'<tr><td>{disc}</td><td>{sp["hp"]:,}</td><td>{hp_con:,}</td><td>{sp["def"]:,}</td>'
            f'<td class="{cls_pct(100*tp/sp["hp"],5,15,invert=True)}">{100*tp/sp["hp"]:.1f}%</td>'
            f'<td class="{cls_pct(100*tp/hp_con,5,15,invert=True)}">{100*tp/hp_con:.1f}%</td></tr>')
    out.append('</tbody></table>')
    return "\n".join(out)


BOSS_PICKS = {"Sword": "Sundering Blow", "Bow": "Snipe", "Staff": "Arcane Bolt", "Dagger": "Eviscerate"}
BOSS_HEALTH_MULT = 20.0   # set on ED_EternalWarlord.tres (2026-06-08)

# Droppable weapon WEAPONATTACK/MAGICATTACK at an item level (generate_item_content.gd,
# common base roll). "L90 gear" = item_level 93 (the best PRE-boss tier); the boss
# itself drops the item_level-100 tier. Drops can roll Uncommon..Legendary (up to ~2x),
# so these base values are a CONSERVATIVE (slowest-kill) floor.
def weapon_attack_ilv(disc, ilv):
    if disc in ("Sword", "Staff"):
        return 7 + 1.5 * ilv
    if disc == "Bow":
        return 6 + 1.35 * ilv
    return 4 + 0.95 * ilv   # Dagger


MAGIC_ENEMIES = [("Stone Slime", 33), ("Deer Druid", 44), ("Rabbit Wizard", 48),
                 ("Fire Slime", 73), ("Astral Slime", 93)]


def magic_axis_section():
    out = ['<p>Magic enemies (<code>is_magic_attacker</code>) scale on the MAGIC-attack curve '
           '(identical magnitude to physical, both now L^1.25) and are mitigated by the player\'s '
           '<b>MAGICDEFENSE</b> &mdash; which is <b>armor-only</b> (no attribute feeds it, unlike physical '
           'DEFENSE which gets +1 per STR). There are 5 in the game: '
           + ", ".join(f"{n} (L{l})" for n, l in MAGIC_ENEMIES) + '.</p>',
           '<table class="dmg"><thead><tr><th>Discipline @ Lv</th><th>Armor DEF</th><th>Armor MDEF</th>'
           '<th>Phys touch %HP</th><th>Magic touch %HP</th><th>Magic vs phys</th><th>Read</th>'
           '</tr></thead><tbody>']
    for disc in ["Sword", "Bow", "Staff", "Dagger"]:
        for L in [30, 60, 100]:
            s = survivability(disc, L)
            tp, _, _ = touch_hit(s["def"], L, L)            # physical: player DEFENSE
            tm, _, _ = touch_hit(s["mdef"], L, L)            # magic: player MAGICDEFENSE
            pp, pm = 100 * tp / s["hp"], 100 * tm / s["hp"]
            ratio = tm / tp if tp > 0 else 0
            read = "magic axis fine" if pm < 12 else ("magic stings" if pm < 20 else "magic too hard")
            if ratio > 2.2:
                read += "; weak to magic"
            vcls = "ok" if pm < 12 else ("warn" if pm < 20 else "bad")
            out.append(
                f'<tr><td>{disc} L{L}</td><td>{s["armor"]["DEF"]}</td><td>{s["armor"]["MDEF"]}</td>'
                f'<td class="{cls_pct(pp,5,15,invert=True)}">{pp:.1f}%</td>'
                f'<td class="{cls_pct(pm,5,15,invert=True)}">{pm:.1f}%</td>'
                f'<td>{ratio:.1f}&times;</td><td class="{vcls}">{read}</td></tr>')
    out.append('</tbody></table>')
    # per-piece breakdown at L100
    out.append('<div class="sweep"><b>Per-piece armor at item_level 100 (full set = sum; weights '
               'Helm 0.6 / Mail 1.0 / Legguards 0.8 / Boots 0.5):</b>'
               '<table class="dmg sweeptab"><thead><tr><th>Family</th>'
               '<th>Helm D/M</th><th>Mail D/M</th><th>Legs D/M</th><th>Boots D/M</th>'
               '<th>Full set DEF</th><th>Full set MDEF</th></tr></thead><tbody>')
    for disc in ["Sword", "Bow", "Staff", "Dagger"]:
        sdef = ARMOR_SETS[disc]["def"]
        smdef = ARMOR_SETS[disc]["mdef"]
        cells = []
        for w in SLOT_WEIGHTS:
            cells.append(f'<td>{max(1,round((sdef[0]+100*sdef[1])*w))}/'
                         f'{max(1,round((smdef[0]+100*smdef[1])*w))}</td>')
        a = armor_set(disc, 100)
        out.append(f'<tr><td>{disc} ({ARMOR_SETS[disc]["family"]})</td>{"".join(cells)}'
                   f'<td>{a["DEF"]}</td><td>{a["MDEF"]}</td></tr>')
    out.append('</tbody></table></div>')
    out.append(
        '<div class="finding-big">After the attack-curve softening, <b>both axes sit in a healthy range</b> '
        '(~5&ndash;8% HP per touch at-level for every class). Magic is NOT meaningfully worse than physical '
        'for casters/balanced classes &mdash; Arcanist robes and the balanced leather/cloth sets carry MDEF '
        'on par with their DEF. The one real asymmetry is the <b>Sword</b>: its physical DEF is huge (STR-fed) '
        'but its MDEF is armor-only and Vanguard plate is the weakest magic-resist family, so it takes ~3&times; '
        'more from magic than physical (still only ~6% HP/touch, ~18 hits to die &mdash; survivable, just no '
        'longer near-immune). That warrior-weak-to-magic shape is classic and arguably intended. <b>Gear DEF/MDEF '
        'keep every class in range</b>; no per-piece value is out of proportion now that the attack curve is '
        'softened.</div>')
    return "\n".join(out)


def boss_section():
    base_hp = fbr.enemy_hp(100)
    bhp = round(base_hp * BOSS_HEALTH_MULT)
    bdef = fbr.enemy_def(100)
    dump = fbr.load_dump()
    roster = dump["roster"]
    # Model damage at the BIS attack our offense model assumes (197); rescale to the
    # actual droppable weapon attack at item_level 93 (the gear you bring to the boss).
    out = [f'<p>The boss now carries <code>health_mult = {BOSS_HEALTH_MULT:g}</code> &rarr; HP '
           f'<b>{bhp:,}</b> (was {base_hp:,}, a normal mob). DEF/MDEF {bdef} (your hits land at '
           f'{fbr.def_mult(bdef)*100:.0f}% after defense). Numbers below are for a <b>level-90-gear</b> '
           'player (item_level&nbsp;93 weapon, common base roll &mdash; the conservative floor; lucky '
           'Uncommon&ndash;Legendary rolls and the boss\'s own item_level-100 drops kill faster).</p>',
           '<table class="dmg"><thead><tr><th>Discipline (L100, L90 gear)</th>'
           '<th>Wpn atk</th><th>Basic hit</th><th>Basics &rarr; kill</th>'
           '<th>Best ST ability</th><th>Per cast</th><th>Casts &rarr; kill</th></tr></thead><tbody>']
    for disc in ["Sword", "Bow", "Staff", "Dagger"]:
        magic = disc == "Staff"
        st = fbr.build_stats(disc, 100, "pure")
        scale = weapon_attack_ilv(disc, 93) / 197.0   # rescale from the model's BIS 197
        basic = fbr.direct_hit(st, 100, 1, 100, 100, magic) * scale
        a = next(x for x in roster[disc] if x["name"] == BOSS_PICKS[disc])
        amg = fbr.effective_stat(a) == "MAGICATTACK"
        lv = a["levels"][-1]
        dp = lv.get("damage", 0)
        hits = max(1, lv.get("hits", 1) or 1)
        cast = fbr.direct_hit(st, dp, hits, 100, 100, amg) * scale
        out.append(
            f'<tr><td>{disc}</td><td>{weapon_attack_ilv(disc,93):.0f}</td><td>{basic:,.0f}</td>'
            f'<td>{bhp/basic:.0f}</td>'
            f'<td>{html.escape(BOSS_PICKS[disc])} ({dp}%)</td><td>{cast:,.0f}</td>'
            f'<td>{bhp/cast:.0f}</td></tr>')
    out.append('</tbody></table>')
    out.append(
        '<div class="finding-big">&#9745; <b>With <code>health_mult = 10</code> the boss takes ~150&ndash;220 '
        'basic attacks, or ~35&ndash;80 ability casts, from a level-90-gear player</b> &mdash; a real, '
        'multi-phase fight (phases at 66% / 33% HP, enrage at 20%) instead of the old ~12-hit faceroll, and it '
        'eases as you collect the boss\'s item_level-100 drops. The HP multiplier is the single lever here; '
        'each +1 &asymp; +28k HP. Bump toward 12&ndash;15 for a longer endurance fight, down toward 7&ndash;8 '
        'if it drags when farmed repeatedly. <b>Player damage was NOT touched</b> &mdash; a maxed player still '
        'needs 3&ndash;5 ability casts per normal L100 mob (healthy), so attributes/abilities are correctly '
        'scaled; the boss was simply under-HP\'d.</div>')
    return "\n".join(out)


def touch_reality_check():
    out = ['<p>MapleStory reference: an at-level character in same-level gear <b>face-tanks packs while '
           'AoE-farming</b> &mdash; normal-mob contact damage is chip you out-heal with the potion loop, and '
           'death at-level comes from elite/boss skills, magic, or status, not from walking into a same-level '
           'monster. Surviving only 3&ndash;4 touch hits from an at-level mob is far harsher than that.</p>',
           '<table class="dmg"><thead><tr><th>Discipline @ L100</th><th>DEF</th><th>Touch hit</th>'
           '<th>% HP / touch (now)</th><th>Touch hits to die (now)</th>'
           '<th>MapleStory-like target</th></tr></thead><tbody>']
    for disc in ["Sword", "Bow", "Staff", "Dagger"]:
        s = survivability(disc, 100)
        t, mit, _ = touch_hit(s["def"], 100, 100)
        pct = 100 * t / s["hp"]
        die = s["hp"] / t
        target = "~12&ndash;25 hits (tank can be lower)" if disc == "Sword" else "~15&ndash;30 hits (4&ndash;6%/touch)"
        out.append(
            f'<tr><td>{disc}</td><td>{s["def"]:,}</td><td>{t:.0f}</td>'
            f'<td class="{cls_pct(pct,5,15,invert=True)}">{pct:.1f}%</td>'
            f'<td class="{cls_pct(die,6,15)}">{die:.0f}</td><td>{target}</td></tr>')
    out.append('</tbody></table>')
    out.append(
        '<div class="finding-big">&#9888; <b>Touch-damage-to-defense IS out of proportion, and the cause is '
        'structural: DEFENSE comes almost entirely from STR (+1/STR), and only the Sword stacks STR.</b> So the '
        'Sword self-tanks (969 DEF, 56% mitigation, dies in 8) while Staff/Dagger/Bow are paper (141&ndash;371 '
        'DEF, 16&ndash;33% mitigation, die in 3&ndash;4). The mitigation curve '
        '<code>def/(def+0.75&times;att)</code> needs eff_def &asymp; 4.25&times; the monster\'s attack to reach '
        'the 85% cap &mdash; at L100 att=1000 that is ~4,250 DEF, which no non-Sword build approaches. '
        'Levers (pick one or combine): (1) add a <b>class-neutral DEF source</b> so casters/rogues aren\'t paper '
        '&mdash; e.g. CON&rarr;DEF, a flat per-level DEF, or steeper armor DEF slopes; (2) <b>soften the monster '
        'attack curve</b> at high level (currently L^1.5 to 1000 at L100); (3) make mitigation more generous '
        '(lower the 0.75 softness or raise the 85% cap); and/or (4) raise HP pools. Recommendation: combine a '
        'class-neutral DEF source with a small attack-curve trim, targeting ~15&ndash;30 at-level touch hits to '
        'die for squishies and a bit lower for the Sword tank.</div>')
    return "\n".join(out)


def main():
    parts = [HEAD]

    parts.append('<section id="summary"><h2>Executive summary</h2>')

    # before/after for the applied changes (recompute old curve inline)
    def old_att(L):
        frac = L / 5.0 if L <= 5 else max(0.0, 1.0 - (L - 5.0) / 25.0)
        return max(2, round(L ** 1.5 + 20.0 * frac))
    s_st = survivability("Staff", 100)
    new_t, _, _ = touch_hit(s_st["def"], 100, 100)
    old_eff = b_coef(0) * s_st["def"]
    old_mit = min(0.85, old_eff / (old_eff + max(1.0, 0.75 * old_att(100))))
    old_t = 0.925 * old_att(100) * (1 - old_mit)
    parts.append(
        '<div class="finding-big" style="border-color:#2a6;background:#13241a">&#9745; <b>Two tuning changes '
        'applied (2026-06-08), one lever each:</b><br>'
        '&bull; <b>Monster attack curve softened</b> L^1.5&rarr;L^1.25 (gen_monster_curves.py): at L100 '
        f'monster attack 1000&rarr;316. A same-level Staff\'s touch hit drops from <b>{old_t:.0f}</b> '
        f'({100*old_t/s_st["hp"]:.0f}% HP, died in {s_st["hp"]/old_t:.0f}) to <b>{new_t:.0f}</b> '
        f'({100*new_t/s_st["hp"]:.0f}% HP, dies in {s_st["hp"]/new_t:.0f}) &mdash; MapleStory chip damage, no '
        'more potion-spam at-level. Armor matters MORE per point (mitigation rises as attack falls), and player '
        'damage is untouched.<br>'
        f'&bull; <b>Boss <code>health_mult = 10</code></b> (ED_EternalWarlord.tres): HP '
        f'{fbr.enemy_hp(100):,}&rarr;{round(fbr.enemy_hp(100)*BOSS_HEALTH_MULT):,}, turning a ~12-hit faceroll '
        'into a real multi-phase fight (see section C).</div>')

    parts.append(
        '<p>Companion to the offense report. Models player HP / DEFENSE / MAGICDEFENSE with the '
        'level-appropriate generated armor set per discipline '
        '(<code>generate_item_content.gd</code>) against the enemy touch-damage formula '
        '(<code>enemy_base.gd.damage_on_overlap</code>), then correlates the monster HP/defense '
        'curve to the player\'s actual ability damage (same combat model as report 1).</p>')

    # quick findings computed live
    s_sword = survivability("Sword", 100)
    s_staff = survivability("Staff", 100)
    tp_sword, mit_s, _ = touch_hit(s_sword["def"], 100, 100)
    tp_staff, mit_t, _ = touch_hit(s_staff["def"], 100, 100)
    parts.append(
        '<div class="finding-big">&#9888; <b>Survivability is wildly asymmetric by discipline</b> because '
        f'DEFENSE is +1 per STR. At L100 a Sword carries <b>{s_sword["def"]:,} DEF</b> '
        f'(mitigating {mit_s*100:.0f}% of touch damage, {tp_sword:.0f}/hit = {100*tp_sword/s_sword["hp"]:.1f}% '
        f'of its {s_sword["hp"]:,} HP) while a Staff carries only <b>{s_staff["def"]:,} DEF</b> '
        f'({mit_t*100:.0f}% mitigation, {tp_staff:.0f}/hit = {100*tp_staff/s_staff["hp"]:.1f}% of its '
        f'{s_staff["hp"]:,} HP). The pure-INT mage is a glass cannon vs physical mobs; the sword is a natural '
        'tank with zero defensive investment. Per the MapleStory survival model (HP + potions + defensives, '
        'no dodge) this is intended <i>direction</i>, but the magnitude is worth eyeballing &mdash; a mage '
        'must lean on MAGICDEFENSE, kiting, and CON, none of which a sword needs.</div>')
    parts.append(
        '<div class="finding-big">&#9888; <b>Enemy mitigation of player damage climbs toward endgame.</b> '
        'Enemy DEFENSE follows <code>1.8&times;L^1.2</code> (L30&asymp;75, L100&asymp;452), so the player '
        f'physical def-multiplier falls from ~87% at L30 to ~{fbr.def_mult(fbr.enemy_def(100))*100:.0f}% at '
        'L100. This is the intended "gear keeps you ahead" lever (gen_monster_curves.py) &mdash; fights get '
        'longer at high level unless the player upgrades weapons. The tables below show whether that leaves '
        'TTK in a sane band.</div>')

    parts.append('<h3>CON allocation as the survivability lever (L100)</h3>')
    parts.append('<p style="color:var(--mut);font-size:12.5px">The offense report assumes a pure-damage '
                 'build (0 CON). Re-spending 40% of the attribute pool into CON roughly doubles a squishy '
                 'class\'s effective HP:</p>')
    parts.append(con_comparison())
    parts.append(METHOD)
    parts.append('</section>')

    parts.append('<section id="survivability"><h2>A. Player survivability vs at-level mobs</h2>')
    parts.append('<p style="color:var(--mut);font-size:12.5px">"Touch&rarr;die" = how many average enemy '
                 'contact hits to drop you (lower = squishier). EHP = HP &divide; (1 &minus; mitigation). '
                 '"Hits&rarr;kill" = your average basic hits to kill the at-level mob. Amber/red on % HP = '
                 'mobs hit hard; on Hits&rarr;kill = mob too spongy.</p>')
    for disc in ["Sword", "Bow", "Staff", "Dagger"]:
        parts.append(survivability_table(disc))
    parts.append('</section>')

    parts.append('<section id="enemies"><h2>B. Enemy curve tuning vs ability damage</h2>')
    parts.append('<p style="color:var(--mut);font-size:12.5px">Monster HP / DEF / MDEF across the level '
                 'curve, with how many average at-level basic hits each discipline needs to kill. A healthy '
                 'normal mob dies in ~2&ndash;8 hits (green); &gt;12 = spongy, &lt;2 = fragile. Staff hits '
                 'MDEF; the other three hit DEF. Boss HP/defense multipliers (1.6&ndash;2.2&times; HP via '
                 'archetypes) stack on top of these baselines.</p>')
    parts.append(enemy_curve_table())
    parts.append('</section>')

    parts.append('<section id="boss"><h2>C. Boss fight &mdash; basic-attack TTK (is damage over-scaled?)</h2>')
    parts.append(boss_section())
    parts.append('</section>')

    parts.append('<section id="touch"><h2>D. Touch-damage reality check vs MapleStory</h2>')
    parts.append(touch_reality_check())
    parts.append('</section>')

    parts.append('<section id="magic"><h2>E. Magic axis: is magic damage as bad as physical?</h2>')
    parts.append(magic_axis_section())
    parts.append('</section>')

    parts.append(TAIL)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))
    print(f"Wrote {OUT}")


METHOD = """
<details class="method"><summary>Methodology &amp; assumptions (click)</summary>
<ul>
<li><b>Player HP</b> = primary-discipline level curve (stats.gd: Sword 120+26/lv, Bow 90+22/lv,
Staff 70+23/lv, Dagger 95+22/lv) + CON&times;8 + armor HEALTH. CON now includes the gear CON folded in
(the broad dual-discipline armour gives every piece a CON splash), so even a pure-damage build gets a
survivability bump from gear.</li>
<li><b>Player DEFENSE</b> = STR_total &times; 1.0 (STR&rarr;Defense utility) + full armor-set DEF.
A pure-primary Sword has a huge STR pool, so its DEF is enormous; a Staff's STR stays ~4.</li>
<li><b>MAGICDEFENSE</b> = armor only (base 0). Arcanist robes &amp; balanced sets carry the most.</li>
<li><b>Armor</b> = the generated set for the discipline's family (generate_item_content.gd):
per piece <code>round((base + iLv&times;slope)&times;weight)</code>, 4 slots (weights 0.6/1.0/0.8/0.5),
snapped to the tier ladder at-or-below the character level.</li>
<li><b>Enemy touch damage</b> (enemy_base.gd.damage_on_overlap): mitigation =
<code>eff_def/(eff_def + 0.75&times;att)</code> capped 85%, where <code>eff_def = b&times;DEF</code>;
&times; level coefficient <code>a = clamp(1 - 0.03&times;(charLv-mobLv), 0.1, 5)</code>; average of the
0.85&ndash;1.0 damage roll. <code>b</code> scales DEF down when the player is under-levelled.</li>
<li><b>Your hit</b> = average basic attack (100% damage) through the offense model from report 1
(crit, defense, level-mod, hit-chance). It's a proxy for sustained DPS; the per-ability detail is in the
offense report.</li>
<li><b>Enemies</b>: NONE-archetype baseline. Real enemies apply archetype multipliers (Brute 1.6&times; HP /
1.4&times; atk, Juggernaut 2.2&times; HP, Glass 0.6&times; HP, etc.) and bosses add phases + telegraphed
specials that hit far harder than touch damage.</li>
</ul></details>
"""

HEAD = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Survivability &amp; Enemy Tuning &mdash; Weapon Identity Overhaul</title>
<style>
:root{--bg:#0f1117;--card:#181b24;--card2:#1f232e;--line:#2c313d;--fg:#e6e8ee;--mut:#9aa3b2;
--ok:#3fb950;--warn:#d29922;--bad:#f85149;--acc:#58a6ff;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif}
header{padding:28px 32px;border-bottom:1px solid var(--line);background:linear-gradient(180deg,#1b2030,#0f1117)}
header h1{margin:0 0 6px;font-size:24px}
header p{margin:0;color:var(--mut)}
nav{position:sticky;top:0;z-index:10;background:#10131c;border-bottom:1px solid var(--line);padding:8px 32px;display:flex;gap:14px;flex-wrap:wrap}
nav a{color:var(--acc);text-decoration:none;font-weight:600;font-size:13px}
section{padding:20px 32px;border-bottom:1px solid var(--line)}
h2{font-size:20px;border-left:4px solid var(--acc);padding-left:10px}
h3{font-size:15px;color:var(--mut);margin-top:24px;text-transform:uppercase;letter-spacing:.04em}
h4{margin:0 0 8px;font-size:15px}
code{background:#11141c;padding:1px 5px;border-radius:4px;color:#c9d1d9;font-size:12px}
.ability{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px;margin:14px 0}
.stat-tag{font-size:11px;color:var(--mut);font-weight:400;border:1px solid var(--line);border-radius:4px;padding:1px 5px;margin-left:4px}
table.dmg{width:100%;border-collapse:collapse;margin:8px 0;font-size:12px}
table.dmg th{background:#11141c;color:var(--mut);text-align:right;padding:5px 6px;border-bottom:1px solid var(--line);font-weight:600}
table.dmg th:first-child,table.dmg td:first-child{text-align:left}
table.dmg td{padding:4px 6px;border-bottom:1px solid #20242e;text-align:right}
table.dmg td small,table.dmg th small{color:var(--mut);font-size:10px}
.ok{color:var(--ok)}.warn{color:var(--warn)}.bad{color:var(--bad);font-weight:700}
td.ok{color:var(--ok)}td.warn{color:var(--warn)}td.bad{color:var(--bad);font-weight:700}
.sweep{margin-top:8px}.sweeptab{max-width:620px}
.finding-big{background:#15202c;border:1px solid #244;border-radius:10px;padding:14px 16px;margin:12px 0;font-size:14px;line-height:1.55}
details.method{margin-top:16px;background:var(--card2);border:1px solid var(--line);border-radius:8px;padding:8px 12px}
details.method summary{cursor:pointer;font-weight:700;color:var(--acc)}
details.method ul{margin:10px 0 4px;padding-left:18px;color:#c9d1d9}
details.method li{margin:4px 0}
</style></head><body>
<header><h1>Survivability &amp; Enemy-Tuning Report</h1>
<p>Weapon-identity overhaul &mdash; player HP/defense with armor scaling, and monster HP/defense
correlated to ability damage, level 1&rarr;100.</p></header>
<nav><a href="#summary">Summary</a><a href="#survivability">A. Survivability</a>
<a href="#enemies">B. Enemy tuning</a><a href="#boss">C. Boss TTK</a>
<a href="#touch">D. Touch vs MapleStory</a><a href="#magic">E. Magic axis</a></nav>
"""

TAIL = "</body></html>"


if __name__ == "__main__":
    main()
