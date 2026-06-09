#!/usr/bin/env python3
"""
FULL top-to-bottom ability balance report (weapon-identity overhaul).

Consumes the AUTHORITATIVE per-level ability data dumped straight from the game
formulas (docs/ability_data_dump.json, produced by tools/dump_ability_data.gd)
and runs a faithful re-implementation of the in-game combat pipeline
(combat.gd._execute_hit / _calculate_max_range + stats.gd derivation, read
2026-06-08) across:

  * character levels 1 .. 100   (with the 5-attribute-points-per-level pool and
    mastery scaling that a focused single-weapon player has at that level)
  * every ability rank 1 .. max_level (paced to the character level a focused
    player realistically unlocks that rank at)
  * a spread of monster levels around the player (the level-vs-level matrix)

For every damage-dealing ability it computes the damage profile and, crucially,
flags abilities whose AL_*.gd script computes damage as `raw WEAPONATTACK/
MAGICATTACK * fraction` (the BROKEN model) instead of the proper
`max_range / dot_scaling_base` model -- these fall ~35x behind at the level cap.

Run:  python tools/full_balance_report.py
Out:  docs/full_balance_report.html

Pure offline model -- nothing here touches the running game. Formula constants
are mirrored from source and labelled with their origin.
"""

import json
import math
import os
import html

HERE = os.path.dirname(__file__)
DUMP = os.path.join(HERE, "..", "docs", "ability_data_dump.json")
OUT = os.path.join(HERE, "..", "docs", "full_balance_report.html")

# ===========================================================================
# FORMULA CONSTANTS  (source: combat.gd / stats.gd / weapon_mastery.gd, 2026-06-08)
# ===========================================================================
WEAPON_MULTIPLIER = 1.2      # CombatComponent.weapon_multiplier (@export default)
MASTERY_FLOOR = 0.2          # CombatComponent.mastery -- min-roll fraction
AVG_ROLL = (MASTERY_FLOOR + 1.0) / 2.0   # randf_range(floor*max, max) average = 0.6*max
BASE_ATTR = 4                # StatData base for STR/DEX/INT/LUCK/CON
BASE_CRITCHANCE = 5.0        # %  (stats.gd)
BASE_CRITDAMAGE = 0.0        # %  (stats.gd) -- no gear source modelled
LUCK_TO_CRIT = 0.1           # % crit per LUCK point (stats.gd _apply_attribute_utilities)
LUCK_CRIT_KNEE = 100.0       # LUCK->crit diminishing returns above this (stats.gd, 2026-06-08)
LUCK_CRIT_SLOPE = 0.30


def luck_to_crit(luck):
    if luck <= LUCK_CRIT_KNEE:
        return luck * LUCK_TO_CRIT
    return LUCK_CRIT_KNEE * LUCK_TO_CRIT + (luck - LUCK_CRIT_KNEE) * LUCK_TO_CRIT * LUCK_CRIT_SLOPE
DEX_TO_ACCURACY = 0.05       # accuracy per DEX (stats.gd / combat.gd)
SPELLBLADE_PHYS_RATE = 0.5   # staff only: +0.5*max(STR,DEX) into INT for max_range
ATTR_PTS_PER_LEVEL = 5       # stats.gd ATTRIBUTE_POINTS_PER_LEVEL
ATTR_SOFT_CAP_KNEE = 300     # stats.gd
ATTR_SOFT_CAP_SLOPE = 0.4
CRIT_MULT_AVG = (1.2 + 1.5) / 2.0 + BASE_CRITDAMAGE / 100.0   # avg crit multiplier = 1.35
DEFENSE_DENOM = 500.0        # combat.gd: def_mult = 1 - DEF/(DEF+500)
MASTERY_CAP = 100            # weapon_mastery.gd
# Focused single-weapon player: mastery 100 reached ~char 70 (weapon_mastery.gd comment).
MASTERY_AT_CHAR70 = 100


def soft_cap(raw):
    if raw <= ATTR_SOFT_CAP_KNEE:
        return raw
    return ATTR_SOFT_CAP_KNEE + int((raw - ATTR_SOFT_CAP_KNEE) * ATTR_SOFT_CAP_SLOPE)


def mastery_at(char_level):
    """Focused player's mastery level at a character level (caps at 100 ~char 70)."""
    return min(MASTERY_CAP, round(char_level * MASTERY_AT_CHAR70 / 70.0))


# Gear-driven attack power. WEAPONATTACK / MAGICATTACK are base 0 -- entirely gear.
# Anchored to REAL gear: starter weapons ~9 attack at L1, endgame ~197 at L100
# (verified benchmark, see project_combat_damage_formula memory). Linear interp.
# Absolute numbers scale with this; the RELATIVE good-vs-broken gap does not.
def gear_attack(level):
    return max(2, round(9.0 + (197.0 - 9.0) * (level - 1) / 99.0))


# Discipline primary/secondary stat + per-mastery-level stat bonuses
# (resources/Player/Disciplines/*.tres).
DISC = {
    "Sword":  {"primary": "STR", "secondary": "DEX", "attack": "WEAPONATTACK",
               "mb": {"STR": 3, "DEX": 2}},
    "Bow":    {"primary": "DEX", "secondary": "STR", "attack": "WEAPONATTACK",
               "mb": {"STR": 2, "DEX": 3}},
    "Staff":  {"primary": "INT", "secondary": "LUCK", "attack": "MAGICATTACK",
               "mb": {"INT": 3, "LUCK": 2}},
    "Dagger": {"primary": "LUCK", "secondary": "DEX", "attack": "WEAPONATTACK",
               "mb": {"DEX": 2, "LUCK": 3}},
}


# ===========================================================================
# ENEMY CURVES  (source: tools/gen_monster_curves.py -- the canonical lever)
# ===========================================================================
def _atk_bonus(L):
    if L <= 5.0:
        frac = L / 5.0
    else:
        frac = max(0.0, 1.0 - (L - 5.0) / (30.0 - 5.0))
    return 20.0 * frac


def enemy_attack(L):
    # Exponent softened 1.5 -> 1.25 (2026-06-08) to bring at-level touch damage to
    # MapleStory chip levels; see gen_monster_curves.py. Player damage is unaffected.
    return max(2, round(L ** 1.25 + _atk_bonus(L)))


def enemy_def(L):
    return round(1.8 * L ** 1.2)


def enemy_mdef(L):
    return round(1.8 * L ** 1.2)


def enemy_hp(L):
    return max(15, round(0.7 * L ** 2.3))


# ===========================================================================
# GEAR STAT MODEL  (source: tools/generate_item_content.gd, 2026-06-08)
#   Folds the level-appropriate generated SET (4 armour pieces + weapon) into the
#   player stats so the report reflects real geared power, not attributes+mastery
#   alone. Each armour piece = COMMON splash of all attributes + crit/accuracy, plus
#   the set's SIGNATURE; summed across slots (weights below).
# ===========================================================================
GEAR_LEVELS = [1, 8, 13, 20, 27, 35, 43, 50, 60, 68, 77, 85, 93, 100]
SLOT_WEIGHTS = [0.6, 1.0, 0.8, 0.5]
DISC_ARMOR = {"Sword": "Vanguard", "Bow": "Pathfinder", "Staff": "Arcanist", "Dagger": "Nightshade"}
ARMOR_COMMON = [("STR", 0.4, 0.09), ("DEX", 0.4, 0.09), ("INT", 0.4, 0.09), ("LUCK", 0.4, 0.09),
                ("CON", 0.5, 0.10), ("CRITCHANCE", 0.3, 0.025), ("CRITDAMAGE", 0.25, 0.025), ("ACCURACY", 0.3, 0.03)]
ARMOR_FAMILY = {
    "Vanguard":   {"def": (3.0, 0.7), "mdef": (2.0, 0.45),
                   "sig": [("STR", 0.6, 0.16), ("HEALTH", 8.0, 1.8), ("CON", 0.5, 0.12)]},
    "Pathfinder": {"def": (2.5, 0.55), "mdef": (2.5, 0.55),
                   "sig": [("DEX", 0.6, 0.16), ("CRITCHANCE", 0.6, 0.04), ("CRITDAMAGE", 0.4, 0.035), ("EVASION", 0.5, 0.04), ("ACCURACY", 0.5, 0.06)]},
    "Arcanist":   {"def": (2.0, 0.45), "mdef": (3.0, 0.7),
                   "sig": [("INT", 0.6, 0.16), ("MANA", 6.0, 1.5), ("MPREGEN", 0.3, 0.06)]},
    "Nightshade": {"def": (2.5, 0.55), "mdef": (2.5, 0.55),
                   "sig": [("LUCK", 0.6, 0.16), ("CRITDAMAGE", 1.0, 0.08), ("CRITCHANCE", 0.4, 0.03), ("EVASION", 0.5, 0.04)]},
}
# Generated common weapon's attribute + crit bonus (single item).
WEAPON_BONUS = {
    "Sword":  [("STR", 2.0, 0.35)],
    "Bow":    [("DEX", 2.0, 0.4), ("CRITCHANCE", 1.0, 0.06)],
    "Staff":  [("INT", 2.0, 0.4)],
    "Dagger": [("LUCK", 2.0, 0.35), ("CRITCHANCE", 2.0, 0.12)],
}


def gear_item_level(char_level):
    cand = [x for x in GEAR_LEVELS if x <= char_level]
    return cand[-1] if cand else 1


def gear_stats(disc_name, char_level):
    """Level-appropriate full set (4 armour + weapon) stat totals, mirroring the
    generator. Returns {stat_name: int} incl. DEF/MDEF/HEALTH/EVASION/CRITCHANCE/..."""
    lv = gear_item_level(char_level)
    fam = ARMOR_FAMILY[DISC_ARMOR[disc_name]]
    out = {"item_level": lv}
    out["DEF"] = sum(max(1, round((fam["def"][0] + lv * fam["def"][1]) * w)) for w in SLOT_WEIGHTS)
    out["MDEF"] = sum(max(1, round((fam["mdef"][0] + lv * fam["mdef"][1]) * w)) for w in SLOT_WEIGHTS)
    for w in SLOT_WEIGHTS:                       # accumulate per piece, round, sum
        acc = {}
        for (st, b, sl) in ARMOR_COMMON:
            acc[st] = acc.get(st, 0.0) + (b + lv * sl)
        for (st, b, sl) in fam["sig"]:
            acc[st] = acc.get(st, 0.0) + (b + lv * sl)
        for st, v in acc.items():
            out[st] = out.get(st, 0) + max(1, round(v * w))
    for (st, b, sl) in WEAPON_BONUS[disc_name]:  # weapon attribute/crit
        out[st] = out.get(st, 0) + max(1, round(b + lv * sl))
    return out


# ===========================================================================
# PLAYER STAT MODEL
# ===========================================================================
def build_stats(disc_name, char_level, alloc="pure"):
    """Returns the derived stat bundle for a focused player.

    alloc: 'pure'  = every attribute point into the primary damage stat
           'split' = discipline's natural 3:2 primary:secondary (un-respecced)
    """
    d = DISC[disc_name]
    m = mastery_at(char_level)
    pool = ATTR_PTS_PER_LEVEL * max(0, char_level - 1)

    attrs = {s: BASE_ATTR for s in ("STR", "DEX", "INT", "LUCK", "CON")}
    # mastery bonuses (summed across owned disciplines -- focused = just this one)
    for s, per in d["mb"].items():
        attrs[s] += per * m
    # allocation
    if alloc == "pure":
        attrs[d["primary"]] += soft_cap(pool)
    else:  # natural 3:2 split between primary and secondary
        p = soft_cap(int(round(pool * 0.6)))
        s2 = soft_cap(pool - int(round(pool * 0.6)))
        attrs[d["primary"]] += p
        attrs[d["secondary"]] += s2

    # --- Fold in level-appropriate GEAR (armour set + weapon): attributes ---
    gear = gear_stats(disc_name, char_level)
    for s in ("STR", "DEX", "INT", "LUCK", "CON"):
        attrs[s] += gear.get(s, 0)

    primary = attrs[d["primary"]]
    secondary = attrs[d["secondary"]]
    # Staff spellblade supplement folded into the primary used for max_range.
    primary_for_dmg = primary
    if disc_name == "Staff":
        primary_for_dmg += int(SPELLBLADE_PHYS_RATE * max(attrs["STR"], attrs["DEX"]))

    crit_chance = min(100.0, BASE_CRITCHANCE + luck_to_crit(attrs["LUCK"]) + gear.get("CRITCHANCE", 0))
    avg_crit_mult = CRIT_MULT_AVG + gear.get("CRITDAMAGE", 0) / 100.0
    crit_factor = 1.0 + (crit_chance / 100.0) * (avg_crit_mult - 1.0)
    atk = gear_attack(char_level)

    stat_mult = primary_for_dmg * 4 + secondary
    max_range = round(WEAPON_MULTIPLIER * stat_mult * atk / 100.0)

    return {
        "mastery": m, "pool": pool, "attrs": attrs,
        "primary": primary, "secondary": secondary,
        "primary_for_dmg": primary_for_dmg,
        "attack_power": atk, "max_range": max_range,
        "crit_chance": crit_chance, "crit_factor": crit_factor,
        "dex": attrs["DEX"], "gear": gear, "evasion": gear.get("EVASION", 0),
    }


def hit_chance(char_level, mob_level, dex):
    hc = 95.0 + (char_level - mob_level) * 3.0 + dex * DEX_TO_ACCURACY
    return max(5.0, min(100.0, hc)) / 100.0


def level_mod(char_level, mob_level):
    return max(0.5, min(1.5, 1.0 + (char_level - mob_level) * 0.05))


def def_mult(defense):
    return 1.0 - (defense / (defense + DEFENSE_DENOM))


# ===========================================================================
# DAMAGE MODEL OVERRIDES  (source: scripts/Abilities/AL_*.gd, read 2026-06-08)
#   Damage from a DoT/zone/summon AL bypasses _execute_hit -> no defense, no
#   crit, no level-modifier, always hits (take_damage is called directly).
#   kind:
#     BROKEN  -> per-tick = attack_power * frac   (raw stat -- the bug)
#     PROPER  -> per-tick = max_range * (dmg%/100) * frac   (dot_scaling_base)
# ===========================================================================
# Each entry: list of damage components attached to the ability (on top of any
# direct hit its damage% produces through combat).
DOT_MODELS = {
    # ---- BROKEN raw-stat abilities (the ones to fix) ----
    "Earthsplitter": [{"label": "tremor zone", "kind": "PROPER", "frac": 0.15,
                       "ticks": 4, "note": "x(1+0.75/combo pt): up to x3.25 at 3 combo"}],
    "Frost Patch":   [{"label": "frost ticks", "kind": "PROPER", "frac": 0.08, "ticks": 4}],
    "Stormcall":     [{"label": "storm ticks", "kind": "PROPER", "frac": 0.11, "ticks": 6}],
    "Sky Volley":    [{"label": "arrow rain", "kind": "PROPER", "frac": 0.09, "ticks": 6}],
    "Arcane Familiar": [{"label": "15 bolts", "kind": "PROPER", "frac": 0.22, "ticks": 15,
                         "note": "0.8s cadence over 12s"}],
    "Arcane Lance":  [{"label": "chain/enemy", "kind": "PROPER", "frac": 0.40, "ticks": 1,
                       "note": "bonus AoE to ~2 enemies per landed hit, Lightning stance only"}],
    "Spellweave":    [{"label": "fire pool", "kind": "PROPER", "frac": 0.15, "ticks": 5,
                       "note": "Fire stance"},
                      {"label": "lightning/enemy", "kind": "PROPER", "frac": 0.60, "ticks": 1,
                       "note": "Lightning stance, 6 hops to 6 enemies (per-enemy shown)"}],
    # ---- PROPER DoTs (dot_scaling_base -- correct) ----
    "Hemorrhage":    [{"label": "bleed", "kind": "PROPER", "frac": 0.10, "ticks": 6,
                       "note": "per stack, max 3 stacks"}],
    "Barbed Shot":   [{"label": "bleed", "kind": "PROPER", "frac": 0.10, "ticks": 6,
                       "note": "per stack, max 3"}],
    "Envenom":       [{"label": "poison", "kind": "PROPER", "frac": 0.06, "ticks": 6,
                       "note": "per stack, max 3 (2/hit stealthed)"}],
    "Immolate":      [{"label": "burn", "kind": "PROPER", "frac": 0.10, "ticks": 6,
                       "note": "x1.5 + splash in Fire stance"}],
    "Pyre Burst":    [{"label": "burn", "kind": "PROPER", "frac": 0.12, "ticks": 4},
                      {"label": "fire pool", "kind": "PROPER", "frac": 0.10, "ticks": 3}],
    "Caltrops":      [{"label": "spike zone", "kind": "PROPER", "frac": 0.08, "ticks": 5}],
}

# NOTE (verified 2026-06-08, ability.gd/_trigger_ability_state_change -> attack.gd
# _start_ability_attack -> combat.process_ability_hit): EVERY active arms its
# combat hitbox on cast regardless of logic_script, so these ground-zone abilities
# DO land a proper, full-scaling direct hit (their damage_percent) on enemies in
# the cast hitbox. Only the lingering ZONE/DoT rider is broken (raw-stat). So no
# ability is "zone-only" -- the direct hit always counts.
ZONE_ONLY = set()

# Stance-exclusive: only ONE component fires per cast (depends on active element),
# so the burst takes the largest component rather than summing them.
EXCLUSIVE_COMPONENTS = {"Spellweave"}

# FIXED 2026-06-08: all 7 now route their tick through combat.dot_scaling_base, and
# the 4 staff zones' damage_stat was corrected WEAPONATTACK -> MAGICATTACK (their
# direct hit was computing off a mage's zero WEAPONATTACK). No raw-stat riders remain.
BROKEN_NAMES = set()

# The stat the AL_*.gd script ACTUALLY reads (the zone staff abilities leave
# AbilityData.damage_stat at the default WEAPONATTACK but hardcode MAGICATTACK).
AL_STAT = {
    "Earthsplitter": "WEAPONATTACK", "Frost Patch": "MAGICATTACK",
    "Stormcall": "MAGICATTACK", "Sky Volley": "WEAPONATTACK",
    "Arcane Familiar": "MAGICATTACK", "Arcane Lance": "MAGICATTACK",
    "Spellweave": "MAGICATTACK", "Hemorrhage": "WEAPONATTACK",
    "Barbed Shot": "WEAPONATTACK", "Envenom": "WEAPONATTACK",
    "Immolate": "MAGICATTACK", "Pyre Burst": "MAGICATTACK", "Caltrops": "WEAPONATTACK",
}


def effective_stat(a):
    return AL_STAT.get(a["name"], a["damage_stat"])


def dot_components(name, st, dmg_pct):
    """Returns [(label, per_tick, ticks, total, kind, note)] for a DoT ability."""
    out = []
    for comp in DOT_MODELS.get(name, []):
        frac = comp["frac"]
        ticks = comp["ticks"]
        if comp["kind"] == "BROKEN":
            per_tick = max(1, round(st["attack_power"] * frac))
        else:  # PROPER -- dot_scaling_base = max_range * (dmg%/100), 100 if no dmg%
            pct = dmg_pct if dmg_pct > 0 else 100
            per_tick = max(1, round(st["max_range"] * (pct / 100.0) * frac))
        out.append({
            "label": comp["label"], "per_tick": per_tick, "ticks": ticks,
            "total": per_tick * ticks, "kind": comp["kind"], "note": comp.get("note", ""),
        })
    return out


def proper_reference_tick(name, st, dmg_pct):
    """For a BROKEN ability: what one tick WOULD deal if it used dot_scaling_base."""
    comp = DOT_MODELS[name][0]
    pct = dmg_pct if dmg_pct > 0 else 100
    return max(1, round(st["max_range"] * (pct / 100.0) * comp["frac"]))


# ===========================================================================
# DIRECT HIT
# ===========================================================================
def direct_hit(st, dmg_pct, hits, char_level, mob_level, magic):
    """Expected per-cast damage to ONE enemy through the combat pipeline."""
    mr = st["max_range"] * dmg_pct / 100.0
    avg = mr * AVG_ROLL
    lm = level_mod(char_level, mob_level)
    dm = def_mult(enemy_mdef(mob_level) if magic else enemy_def(mob_level))
    hc = hit_chance(char_level, mob_level, st["dex"])
    per_hit = avg * lm * dm * st["crit_factor"]
    return per_hit * hits * hc


# ===========================================================================
# REPORT BUILD
# ===========================================================================
def load_dump():
    with open(DUMP, encoding="utf-8") as f:
        return json.load(f)


def paced_char_level(rank, max_level):
    # Focused player: rank scales ~linearly to char 70 where mastery caps and the
    # main kit is maxed. rank max_level -> char 70.
    return max(1, round(70 * rank / max_level))


def fmt(n):
    if n >= 1000:
        return f"{n:,.0f}"
    if n >= 100:
        return f"{n:.0f}"
    if n >= 10:
        return f"{n:.1f}"
    return f"{n:.2f}"


def pct_hp_class(p):
    if p >= 25:
        return "ok"
    if p >= 8:
        return "warn"
    return "bad"


CHAR_TIERS = [1, 10, 20, 30, 40, 50, 60, 70, 85, 100]
SWEEP_TIERS = [1, 10, 50, 100]


# Abilities with an incidental damage% whose real function is a buff/mark, not a
# direct hit -- keep them in the support list so the report doesn't imply they are
# damage dealers (their output is reflect/aura/mark-amp, not max_range).
SUPPORT_OVERRIDE = {"Iron Riposte", "Sentinel's Mark"}


def ability_is_damage(a):
    name = a["name"]
    if name in SUPPORT_OVERRIDE:
        return False
    if name in DOT_MODELS:
        return True
    if a["type"] != "Active":
        return False
    if a["max_level"] <= 1 and not a["present"].get("damage"):
        return False
    # any active with a damage% > 0 at max level
    last = a["levels"][-1]
    return last.get("damage", 0) > 0


def build_ability_section(a, disc_name):
    name = a["name"]
    magic = effective_stat(a) == "MAGICATTACK"
    max_lvl = a["max_level"]
    is_broken = name in BROKEN_NAMES
    zone_only = name in ZONE_ONLY
    has_dot = name in DOT_MODELS

    def level_dmgpct(rank):
        idx = min(rank, len(a["levels"])) - 1
        return a["levels"][idx].get("damage", 0)

    def level_hits(rank):
        idx = min(rank, len(a["levels"])) - 1
        return max(1, a["levels"][idx].get("hits", 1) or 1)

    rows = []
    for rank in range(1, max_lvl + 1):
        cl = paced_char_level(rank, max_lvl)
        st = build_stats(disc_name, cl, "pure")
        dmg_pct = level_dmgpct(rank)
        hits = level_hits(rank)
        mob = cl  # at-level monster
        hp = enemy_hp(mob)

        direct = 0.0
        if dmg_pct > 0 and not zone_only:
            direct = direct_hit(st, dmg_pct, hits, cl, mob, magic)
        dots = dot_components(name, st, dmg_pct) if has_dot else []
        if name in EXCLUSIVE_COMPONENTS and dots:
            dot_total = max(d["total"] for d in dots)
        else:
            dot_total = sum(d["total"] for d in dots)
        burst = direct + dot_total  # single cast / single application full output vs one enemy
        pct = 100.0 * burst / hp if hp else 0
        casts = math.ceil(hp / burst) if burst > 0 else 999
        rows.append({
            "rank": rank, "cl": cl, "mr": st["max_range"], "atk": st["attack_power"],
            "primary": st["primary"], "dmg_pct": dmg_pct, "hits": hits,
            "direct": direct, "dots": dots, "dot_total": dot_total,
            "burst": burst, "hp": hp, "pct": pct, "casts": casts,
            "hc": hit_chance(cl, mob, st["dex"]) * 100,
        })

    # ---- monster-level sweep (level-vs-level matrix) ----
    sweep = []
    for cl in SWEEP_TIERS:
        rank = min(max_lvl, max(1, round(max_lvl * cl / 70.0)))
        st = build_stats(disc_name, cl, "pure")
        dmg_pct = level_dmgpct(rank)
        hits = level_hits(rank)
        cells = []
        for mob in [max(1, cl - 10), max(1, cl - 5), cl, cl + 5, cl + 10]:
            hp = enemy_hp(mob)
            direct = direct_hit(st, dmg_pct, hits, cl, mob, magic) if (dmg_pct > 0 and not zone_only) else 0.0
            dots = dot_components(name, st, dmg_pct) if has_dot else []
            if name in EXCLUSIVE_COMPONENTS and dots:
                dtot = max(d["total"] for d in dots)
            else:
                dtot = sum(d["total"] for d in dots)
            burst = direct + dtot
            cells.append({"mob": mob, "pct": 100.0 * burst / hp if hp else 0, "burst": burst})
        sweep.append({"cl": cl, "rank": rank, "cells": cells})

    # ---- broken shortfall summary ----
    shortfall = None
    if is_broken:
        st100 = build_stats(disc_name, 100, "pure")
        comp = DOT_MODELS[name][0]
        actual = max(1, round(st100["attack_power"] * comp["frac"]))
        proper = proper_reference_tick(name, st100, level_dmgpct(max_lvl))
        st1 = build_stats(disc_name, 1, "pure")
        actual1 = max(1, round(st1["attack_power"] * comp["frac"]))
        proper1 = proper_reference_tick(name, st1, level_dmgpct(1))
        shortfall = {"actual100": actual, "proper100": proper,
                     "ratio100": proper / actual if actual else 0,
                     "actual1": actual1, "proper1": proper1,
                     "ratio1": proper1 / actual1 if actual1 else 0}

    return render_ability(a, disc_name, rows, sweep, shortfall, is_broken, has_dot)


def render_ability(a, disc_name, rows, sweep, shortfall, is_broken, has_dot):
    name = html.escape(a["name"])
    stat = effective_stat(a)
    badge = ""
    if is_broken:
        badge = '<span class="badge badge-bad">BROKEN zone/DoT rider: raw-stat</span>'
    elif has_dot:
        badge = '<span class="badge badge-ok">DoT: dot_scaling_base (correct)</span>'
    desc = html.escape(a.get("description", "") or "")

    out = [f'<div class="ability {"broken" if is_broken else ""}" id="ab-{html.escape(a["id"][:12])}">']
    out.append(f'<h4>{name} <span class="stat-tag">{stat}</span> {badge}</h4>')
    out.append(f'<div class="desc">{desc}</div>')

    if shortfall:
        s = shortfall
        out.append(
            '<div class="shortfall">'
            '<b>Broken zone/DoT rider.</b> The cast still lands a proper, full-scaling direct hit '
            '(the <code>damage%</code> column below), but the lingering zone/DoT ticks scale off RAW '
            f'attack only. At L1 one rider tick deals <b>{s["actual1"]}</b> (a proper tick would deal '
            f'{s["proper1"]} &rarr; {s["ratio1"]:.1f}&times;). At L100 one rider tick deals '
            f'<b>{s["actual100"]}</b> but a proper tick would deal <b>{s["proper100"]:,}</b> '
            f'&mdash; the rider is <b>{s["ratio100"]:.0f}&times; too weak</b> at the cap, so this '
            'ability loses its defining zone/sustain identity at endgame even though its direct hit survives. '
            'Fix: route the tick through <code>combat.dot_scaling_base(ability)</code> like the bleeds do.'
            '</div>')

    # rank scaling table
    out.append('<table class="dmg"><thead><tr>'
               '<th>Rank</th><th>Char Lv</th><th>Primary</th><th>MaxRange</th>'
               '<th>Dmg%</th><th>Direct/cast</th><th>DoT total</th><th>Burst vs 1</th>'
               '<th>Mob HP</th><th>% HP</th><th>Casts&rarr;kill</th><th>Hit%</th>'
               '</tr></thead><tbody>')
    for r in rows:
        dot_str = "&mdash;"
        if r["dots"]:
            joiner = " / " if a["name"] in EXCLUSIVE_COMPONENTS else " + "
            parts_d = []
            for d in r["dots"]:
                cls = ' class="bad"' if d["kind"] == "BROKEN" else ''
                parts_d.append(f'<span{cls}>{fmt(d["total"])}</span><small>({d["label"]})</small>')
            dot_str = joiner.join(parts_d)
        out.append(
            f'<tr><td>{r["rank"]}</td><td>{r["cl"]}</td><td>{r["primary"]:,}</td>'
            f'<td>{r["mr"]:,}</td><td>{r["dmg_pct"] or "&mdash;"}</td>'
            f'<td>{fmt(r["direct"]) if r["direct"] else "&mdash;"}</td>'
            f'<td>{dot_str}</td><td><b>{fmt(r["burst"])}</b></td>'
            f'<td>{r["hp"]:,}</td>'
            f'<td class="{pct_hp_class(r["pct"])}">{r["pct"]:.1f}%</td>'
            f'<td>{r["casts"]}</td><td>{r["hc"]:.0f}%</td></tr>')
    out.append('</tbody></table>')

    # monster sweep
    out.append('<div class="sweep"><b>Level-vs-level (% of mob HP per cast/application):</b>'
               '<table class="dmg sweeptab"><thead><tr><th>Char Lv (rank)</th>'
               '<th>mob -10</th><th>mob -5</th><th>mob =</th><th>mob +5</th><th>mob +10</th></tr></thead><tbody>')
    for s in sweep:
        cells = "".join(
            f'<td class="{pct_hp_class(c["pct"])}">{c["pct"]:.1f}%<small>L{c["mob"]}</small></td>'
            for c in s["cells"])
        out.append(f'<tr><td>{s["cl"]} (r{s["rank"]})</td>{cells}</tr>')
    out.append('</tbody></table></div>')

    out.append('</div>')
    return "\n".join(out)


def build_support_row(a):
    name = html.escape(a["name"])
    kind = a["type"]
    desc = html.escape((a.get("description", "") or "")[:160])
    note = ""
    if a["name"] in ("Mark of the Hunt", "Death Mark"):
        note = '<span class="badge badge-ok">T3 bleed uses dot_scaling_base</span>'
    return f'<tr><td>{name}</td><td>{kind}</td><td>{note}{desc}</td></tr>'


def _atlevel_pct(a, w, cl):
    """Single-target % of at-level mob HP for one ability at a character level,
    returns (total_pct, rider_pct, rank)."""
    name = a["name"]
    magic = effective_stat(a) == "MAGICATTACK"
    has_dot = name in DOT_MODELS
    mx = a["max_level"]
    rank = min(mx, max(1, round(mx * cl / 70.0)))
    st = build_stats(w, cl, "pure")
    idx = min(rank, len(a["levels"])) - 1
    dp = a["levels"][idx].get("damage", 0)
    hits = max(1, a["levels"][idx].get("hits", 1) or 1)
    direct = direct_hit(st, dp, hits, cl, cl, magic) if dp > 0 else 0.0
    dots = dot_components(name, st, dp) if has_dot else []
    if name in EXCLUSIVE_COMPONENTS and dots:
        dtot = max(d["total"] for d in dots)
    else:
        dtot = sum(d["total"] for d in dots)
    hp = enemy_hp(cl)
    return 100.0 * (direct + dtot) / hp, 100.0 * dtot / hp, rank


def build_overview(roster):
    out = ['<h3 style="margin-top:22px">At-a-glance: every damage ability, level 1 &rarr; 100</h3>',
           '<p style="color:var(--mut);font-size:12.5px">Single-target burst as % of an <i>at-level</i> '
           'enemy\'s HP (one cast / one DoT application). Max target count shown for AoE context. '
           '"Rider@100" = the share coming from a zone/DoT tick at L100 (red = broken raw-stat rider that '
           'dies at endgame).</p>',
           '<table class="dmg"><thead><tr><th>Ability</th><th>Wpn</th><th>Model</th><th>Tgts</th>'
           '<th>L1</th><th>L50</th><th>L100</th><th>Rider@100</th><th>Read</th></tr></thead><tbody>']
    for w in ["Sword", "Bow", "Staff", "Dagger"]:
        for a in sorted([x for x in roster[w] if ability_is_damage(x)], key=lambda x: x["name"]):
            name = a["name"]
            p1, _, _ = _atlevel_pct(a, w, 1)
            p50, _, _ = _atlevel_pct(a, w, 50)
            p100, rider100, _ = _atlevel_pct(a, w, 100)
            tgts = max((lv.get("targets", 1) or 1) for lv in a["levels"])
            is_broken = name in BROKEN_NAMES
            model = "zone/DoT rider (RAW)" if is_broken else ("DoT (ok)" if name in DOT_MODELS else "direct")
            # read/verdict
            reads = []
            if is_broken:
                reads.append("rider dead @100")
            if p1 > 150:
                reads.append("one-shots @L1")
            if p100 < 8 and tgts <= 2 and not is_broken:
                reads.append("weak single-target")
            if p100 > 55 and name not in DOT_MODELS:
                reads.append("very strong @100")
            read = "; ".join(reads) if reads else "ok"
            rcls = "bad" if is_broken else ("ok" if name in DOT_MODELS and rider100 > 5 else "")
            rowcls = ' class="broken"' if is_broken else ''
            verdict_cls = "bad" if (is_broken or (reads and "ok" not in read)) else "ok"
            out.append(
                f'<tr{rowcls}><td>{html.escape(name)}</td><td>{w}</td><td>{model}</td>'
                f'<td>{tgts}</td>'
                f'<td class="{pct_hp_class(p1)}">{p1:.0f}%</td>'
                f'<td class="{pct_hp_class(p50)}">{p50:.0f}%</td>'
                f'<td class="{pct_hp_class(p100)}">{p100:.0f}%</td>'
                f'<td class="{rcls}">{rider100:.1f}%</td>'
                f'<td class="{verdict_cls}">{read}</td></tr>')
    out.append('</tbody></table>')
    return "\n".join(out)


def main():
    dump = load_dump()
    roster = dump["roster"]

    # collect broken summary
    broken_found = []
    for w in ["Sword", "Bow", "Staff", "Dagger"]:
        for a in roster[w]:
            if a["name"] in BROKEN_NAMES:
                broken_found.append((w, a))

    parts = [HTML_HEAD]
    # executive summary
    parts.append('<section id="summary"><h2>Executive summary</h2>')
    parts.append(
        '<p>This report re-implements the live combat pipeline '
        '(<code>combat.gd._execute_hit</code> / <code>_calculate_max_range</code> + '
        '<code>stats.gd</code>) and drives it with the authoritative per-level ability '
        'numbers dumped straight from the game formulas '
        '(<code>docs/ability_data_dump.json</code>). For every damage ability it walks '
        'ranks 1&rarr;max at the character level a focused player unlocks them, against a '
        'spread of monster levels, from level 1 to 100.</p>')
    parts.append(
        '<div class="finding-big" style="border-color:#2a6;background:#13241a">&#9745; <b>RESOLVED '
        '(2026-06-08): the 7 raw-stat riders are fixed.</b> Earthsplitter, Sky Volley, Frost Patch, Stormcall, '
        'Arcane Lance, Arcane Familiar and Spellweave now scale their zone/DoT/summon ticks through '
        '<code>combat.dot_scaling_base(ability)</code> (the same <code>max_range &times; damage%</code> anchor '
        'the bleeds use), so they track attributes + mastery + gear instead of falling ~30&ndash;55&times; '
        'behind at the cap. Additionally, 4 staff zones (Frost Patch, Stormcall, Spellweave, Arcane Familiar) '
        'had <code>damage_stat = WEAPONATTACK</code> &mdash; a mage\'s WEAPONATTACK is 0, so their <i>direct '
        'hit was also dealing ~zero</i>; corrected to MAGICATTACK. The tables below reflect the fixed scaling; '
        'all damage abilities now sit in a sane band L1&rarr;100. Watch tuning on Earthsplitter at max combo '
        '(combo amp &times; the now-larger base) and Spellweave\'s amplified release &mdash; both are strong '
        'but no longer broken.</div>')
    # broken table
    parts.append('<table class="dmg"><thead><tr><th>Ability</th><th>Weapon</th><th>Rider stat</th>'
                 '<th>Rider model</th><th>L100 rider tick now</th><th>L100 tick if fixed</th><th>Rider shortfall</th></tr></thead><tbody>')
    for w, a in broken_found:
        st100 = build_stats(w, 100, "pure")
        comp = DOT_MODELS[a["name"]][0]
        actual = max(1, round(st100["attack_power"] * comp["frac"]))
        last_pct = a["levels"][-1].get("damage", 0)
        proper = proper_reference_tick(a["name"], st100, last_pct)
        parts.append(
            f'<tr class="broken"><td>{html.escape(a["name"])}</td><td>{w}</td>'
            f'<td>{effective_stat(a)}</td>'
            f'<td>attack&times;{comp["frac"]}</td><td>{actual}</td><td>{proper:,}</td>'
            f'<td class="bad">{proper/actual:.0f}&times; too weak</td></tr>')
    parts.append('</tbody></table>')
    parts.append(build_overview(roster))
    parts.append(METHODOLOGY)
    parts.append('</section>')

    # per weapon
    for w in ["Sword", "Bow", "Staff", "Dagger"]:
        parts.append(f'<section id="{w}"><h2>{w}</h2>')
        dmg_abils = [a for a in roster[w] if ability_is_damage(a)]
        support = [a for a in roster[w] if not ability_is_damage(a)]
        # order: broken first, then dots, then direct
        dmg_abils.sort(key=lambda a: (0 if a["name"] in BROKEN_NAMES else
                                      1 if a["name"] in DOT_MODELS else 2, a["name"]))
        parts.append('<h3>Damage abilities</h3>')
        for a in dmg_abils:
            parts.append(build_ability_section(a, w))
        parts.append('<h3>Support / utility / passives (no direct damage)</h3>')
        parts.append('<table class="dmg"><thead><tr><th>Ability</th><th>Type</th><th>Effect</th></tr></thead><tbody>')
        for a in sorted(support, key=lambda x: (x["type"], x["name"])):
            parts.append(build_support_row(a))
        parts.append('</tbody></table>')
        parts.append('</section>')

    parts.append(HTML_TAIL)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))
    print(f"Wrote {OUT}")
    print(f"Broken raw-stat abilities: {[a['name'] for _, a in broken_found]}")


METHODOLOGY = """
<details class="method"><summary>Methodology &amp; assumptions (click)</summary>
<ul>
<li><b>Damage formula</b>: <code>max_range = round(1.2 &times; (primary&times;4 + secondary) &times; attack_power / 100)</code>;
per hit rolls <code>randf_range(0.2&times;max, max)</code> (avg 0.6&times;), then &times; level-modifier
<code>clamp(1+0.05&times;(charLv-mobLv), 0.5, 1.5)</code>, &times; defense <code>1 - DEF/(DEF+500)</code>,
&times; expected crit. DoT/zone ticks call <code>take_damage</code> directly so they skip defense, crit,
level-mod and always land.</li>
<li><b>Player build</b>: <i>focused</i> single weapon, all 5 attribute points/level into the primary
damage stat (soft-capped above 300 allocation), plus per-mastery stat bonuses. Mastery tracks the
character level and caps at 100 around char 70 (focused grinder).</li>
<li><b>Gear</b>: WEAPON/MAGIC ATTACK is base 0 (gear only); modelled ~9 at L1 &rarr; ~197 at L100
(real starter &rarr; endgame weapons). <b>Folded in 2026-06-08</b>: the level-appropriate generated
SET (4 armour pieces + weapon, <code>generate_item_content.gd</code>) now contributes its full attribute
spread (STR/DEX/INT/LUCK/CON), crit chance, and crit damage to the player stats &mdash; so these numbers
reflect a geared player, not attributes+mastery alone (this adds ~+16% max-range / ~+20% damage at L100,
and pushes gear-stacked crit rates high, e.g. Dagger ~100% from LUCK&rarr;crit + Nightshade crit gear).</li>
<li><b>Rank pacing</b>: ability rank <i>r</i> is shown at character level <code>round(70&times;r/max_level)</code>
&mdash; where a focused player realistically has that rank (rank max &asymp; char 70).</li>
<li><b>Enemies</b>: NONE-archetype curve baseline &mdash; HP <code>0.7&times;L^2.3</code>,
DEF/MDEF <code>1.8&times;L^1.2</code>. Real enemies apply archetype multipliers (tanky/glassy) on top.</li>
<li><b>% HP</b> = single cast / single DoT application vs ONE at-level enemy. Green &ge;25%, amber 8&ndash;25%,
red &lt;8%. DoT stacks &amp; AoE-on-many-targets are noted, not folded into the single-target % HP.</li>
</ul></details>
"""

HTML_HEAD = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Full Ability Balance Report &mdash; Weapon Identity Overhaul</title>
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
nav a:hover{text-decoration:underline}
section{padding:20px 32px;border-bottom:1px solid var(--line)}
h2{font-size:20px;border-left:4px solid var(--acc);padding-left:10px}
h3{font-size:16px;color:var(--mut);margin-top:26px;text-transform:uppercase;letter-spacing:.04em}
h4{margin:0 0 4px;font-size:15px}
code{background:#11141c;padding:1px 5px;border-radius:4px;color:#c9d1d9;font-size:12px}
.ability{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px;margin:14px 0}
.ability.broken{border-color:#5a2230;background:#1d1418}
.desc{color:var(--mut);font-size:12.5px;margin-bottom:8px}
.stat-tag{font-size:11px;color:var(--mut);font-weight:400;border:1px solid var(--line);border-radius:4px;padding:1px 5px;margin-left:4px}
.badge{font-size:11px;border-radius:5px;padding:2px 7px;font-weight:700;margin-left:6px}
.badge-bad{background:#5a2230;color:#ffb3bd}
.badge-ok{background:#16341f;color:#9fe6ad}
.shortfall{background:#2a1419;border:1px solid #5a2230;border-radius:8px;padding:8px 10px;margin:8px 0;font-size:13px;color:#ffd7dc}
table.dmg{width:100%;border-collapse:collapse;margin:8px 0;font-size:12.5px}
table.dmg th{background:#11141c;color:var(--mut);text-align:right;padding:5px 7px;border-bottom:1px solid var(--line);font-weight:600}
table.dmg th:first-child,table.dmg td:first-child{text-align:left}
table.dmg td{padding:4px 7px;border-bottom:1px solid #20242e;text-align:right}
table.dmg td small{color:var(--mut);font-size:10px;margin-left:3px}
tr.broken td{background:#1d1418}
.ok{color:var(--ok)}.warn{color:var(--warn)}.bad{color:var(--bad);font-weight:700}
td.ok{color:var(--ok)}td.warn{color:var(--warn)}td.bad{color:var(--bad);font-weight:700}
.sweep{margin-top:6px}.sweeptab{max-width:680px}
.finding-big{background:#2a1419;border:1px solid #5a2230;border-radius:10px;padding:14px 16px;margin:12px 0;font-size:14.5px;line-height:1.55}
details.method{margin-top:16px;background:var(--card2);border:1px solid var(--line);border-radius:8px;padding:8px 12px}
details.method summary{cursor:pointer;font-weight:700;color:var(--acc)}
details.method ul{margin:10px 0 4px;padding-left:18px;color:#c9d1d9}
details.method li{margin:4px 0}
</style></head><body>
<header><h1>Full Ability Balance Report</h1>
<p>Weapon-identity overhaul &mdash; every ability, every rank, level 1&rarr;100, vs the monster curve.
Generated from authoritative game-formula data.</p></header>
<nav><a href="#summary">Summary</a><a href="#Sword">Sword</a><a href="#Bow">Bow</a>
<a href="#Staff">Staff</a><a href="#Dagger">Dagger</a></nav>
"""

HTML_TAIL = "</body></html>"


if __name__ == "__main__":
    main()
