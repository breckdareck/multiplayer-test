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
ATTR_SOFT_CAP_KNEE  = 300   # diminishing returns on allocation above this (stats.gd)
ATTR_SOFT_CAP_SLOPE = 0.4

def soft_cap(raw):
    return raw if raw <= ATTR_SOFT_CAP_KNEE else ATTR_SOFT_CAP_KNEE + int((raw - ATTR_SOFT_CAP_KNEE) * ATTR_SOFT_CAP_SLOPE)
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

# Enemy stat curves (sampled from assets/curves/monster_*_curve.tres, 2026-05-29).
# All enemy HP/defense is curve-driven off monster_level — these .tres ARE the
# single balance lever for enemy difficulty. Even-level values at the tiers:
# Rebalanced 2026-05-29: HP keeps the ≤L58 shape then grows quadratically (was
# cubic — killed the L100 runaway); defense clamped at 260 so def_mult >= ~0.66.
ENEMY_HP   = {1: 15,  30: 1800, 60: 10485, 100: 29132}
ENEMY_WDEF = {1: 0,   30: 75,   60: 225,   100: 260}   # weapon defense (melee/bow/dagger)
ENEMY_MDEF = {1: 0,   30: 110,  60: 240,   100: 260}   # magic defense (staff)

# Ability-point economy (ability.gd): 6 pts / mastery level, cap 20 = 120/discipline.
PTS_PER_MASTERY = 6
PTS_BUDGET = PTS_PER_MASTERY * MASTERY_CAP   # 120
COST_ACTIVE_MAX = 20    # level 1→20 (starter 19)
COST_PASSIVE_MAX = 10   # level 1→10 (starter 9)
COST_FULL_UPGRADES = 4  # T1(1)+T2(1)+one T3(2)
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

# ─────────────────────────────────────────────────────────────────────────────
# UPGRADE TREES  (source: resources/Abilities/*/Upgrades/U_*.tres, 2026-05-29)
# Per damage ability: fixed (always-owned tier-1+2) damage upgrades, then the
# tier-3 VARIANT group (mutually exclusive — own exactly ONE). Only the four
# damage-relevant effect_keys are modelled here (bonus_damage_mult / bonus_hits /
# bonus_targets / cooldown_flat_reduction). DoT-potency, combo-override and
# passive-stat upgrades are noted in the analysis, not folded into direct damage.
#   fixed = (sum_dmg_mult, add_hits, add_targets, cd_reduction)
#   variants = list of (dmg_mult, add_hits, add_targets, cd_reduction)  [pick best]
UPG = {
 # Sword
 "Crescent Cleave (starter)": {"fixed": (0.25,0,0,1.0), "variants": [(0,0,0,0)], "extra":"+Razor Wind combo override (not modelled)"},
 "Steel Flurry":              {"fixed": (0.20,0,1,0.0), "variants": [(0,1,0,0),(0.50,0,0,0)]},
 "Sundering Blow":            {"fixed": (0.30,0,0,1.0), "variants": [(0,0,1,0),(0.70,0,0,0)], "extra":"+Executioner combo override"},
 "Hemorrhage":                {"fixed": (0.25,0,0,0.0), "variants": [(0,0,1,0)], "extra":"+bleed potency/duration upgrades boost the DoT"},
 "Vault Strike":              {"fixed": (0.25,0,1,0.0), "variants": [(0.60,0,0,0),(0,0,2,0),(0,1,0,0)]},
 # Bow
 "Split Shot":                {"fixed": (0,0,1,0.5),    "variants": [(0.45,0,0,0),(0,1,0,0),(0,0,2,0)]},
 "Hailstorm":                 {"fixed": (0,1,1,0.0),    "variants": [(0,3,0,0),(0.40,0,0,0),(0,0,2,0)]},
 "Skyfall":                   {"fixed": (0.25,0,2,0.0), "variants": [(0,0,4,0),(0.60,0,0,0),(0,1,0,0)]},
 "Barbed Shot":               {"fixed": (0.25,0,0,0.0), "variants": [(0,0,1,0)], "extra":"+bleed potency/duration boost the DoT"},
 "Disengage":                 {"fixed": (0.30,0,0,1.0), "variants": [(0.70,0,0,0),(0,0,2,0),(0,0,0,2.0)]},
 "Snipe":                     {"fixed": (0.30,0,0,1.0), "variants": [(0.90,0,0,0),(0,0,1,0),(0,1,0,0)]},
 # Staff
 "Arcane Bolt (starter)":     {"fixed": (0,0,1,0.4),    "variants": [(0.45,0,0,0),(0,0,3,0),(0,1,0,0)]},
 "Glacial Spike":             {"fixed": (0.25,0,0,1.0), "variants": [(0.70,0,0,0),(0,1,0,0),(0,0,2,0)]},
 "Immolate":                  {"fixed": (0.25,0,0,0.0), "variants": [(0,0,1,0)], "extra":"+burn potency/duration boost the DoT; Fire stance ~doubles it"},
 "Pyre Burst":                {"fixed": (0.25,0,2,0.0), "variants": [(0,0,4,0),(0.60,0,0,0),(0,1,0,0)]},
 "Arcane Lance":              {"fixed": (0,1,1,0.0),    "variants": [(0.40,0,0,0),(0,3,0,0),(0,0,2,0)]},
 # Dagger
 "Twin Fang (starter)":       {"fixed": (0.25,0,0,0.5), "variants": [(0,1,0,0),(0.65,0,0,0),(0,0,1,0)]},
 "Fan of Knives":             {"fixed": (0.30,0,0,1.0), "variants": [(0,0,2,0),(0,3,0,0),(0.70,0,0,0)]},
 "Envenom":                   {"fixed": (0.25,0,0,0.0), "variants": [(0,0,0,0)], "extra":"+poison potency/stacks/duration boost the DoT"},
 "Cripple":                   {"fixed": (0.30,0,0,2.0), "variants": [(0,0,0,4.0),(0.75,0,0,0),(0,0,2,0)]},
 "Shadowstep":                {"fixed": (0.25,0,0,1.0), "variants": [(0.65,0,0,0),(0,0,2,0),(0,1,0,0)]},
 "Eviscerate":                {"fixed": (0.30,0,0,1.0), "variants": [(0.90,0,0,0),(0,1,0,0),(0,0,1,0)]},
}

# ─────────────────────────────────────────────────────────────────────────────
# FULL ROSTER  (every ability incl. passives/buffs/non-damage actives, tagged
# by SHAPE for distribution analysis. The ABILITIES dict above only models
# damage-dealing actives — this dict covers everything currently on disk.)
# Source: A_*.tres descriptions, 2026-05-31.
# fields: name, kind (active/passive), shape, description
# ─────────────────────────────────────────────────────────────────────────────
ROSTER = {
"Sword": [
    # Combo MESH (sword's resource gauge — fully wired)
    ("Steel Flurry",         "active",  "combo-builder",              "2 thrusts on 2 enemies; each hit builds 1 combo point (cap 3)."),
    ("Vault Strike",         "active",  "combo-builder + gap-closer", "Dash forward, strike up to 2 enemies; +2 combo per enemy hit."),
    ("Crescent Cleave",      "active",  "combo-spender (AoE)",        "Consumes all combo to amplify AoE dmg +100%/point (max +300%)."),
    ("Sundering Blow",       "active",  "combo-spender (ST)",         "Consumes all combo to amplify single-target +200%/point (max +600%)."),
    # Other actives
    ("Hemorrhage",           "active",  "dot-applier (bleed)",        "Cuts deeply + stacks Bleed (max 3, 20% WATK/s for 6s)."),
    ("Iron Riposte",         "active",  "self-buff (reflect)",        "Reflects a % of damage taken back to attackers for buff duration."),
    ("Bulwark Stance",       "active",  "self-buff (defense)",        "+250 Defense; drains 2 MP/s, auto-cancels at 0 MP."),
    ("Vow of the Vanguard",  "active",  "self-buff (all stats)",      "+X% all stats for buff duration."),
    # Passives — pure stats
    ("Battle-Hardened",      "passive", "stat (Defense)",             "+Defense, permanent."),
    ("Hardened Frame",       "passive", "stat (Max HP %)",            "+Max HP%, permanent."),
    ("Second Wind",          "passive", "stat (HP regen)",            "+HP regen, permanent."),
    # Passives — conditional %
    ("Aggression",           "passive", "conditional (>90% HP)",      "+30% dmg to enemies above 90% HP."),
    ("Last Stand",           "passive", "conditional (<35% HP)",      "+35% dmg while below 35% HP."),
    ("Bloodthirst",          "passive", "conditional (on kill)",      "Restore X% of Max HP on kill."),
],
"Bow": [
    # Momentum MESH (bow's resource gauge — fully wired)
    ("Snap Shot",            "active",  "momentum-builder (basic)",   "Basic attack; builds Momentum."),
    ("Hailstorm",            "active",  "momentum-builder (AoE)",     "3 arrows on 3 enemies; +2 Momentum/cast."),
    ("Skyfall",              "active",  "momentum-builder (AoE)",     "Arrow rain on up to 6 enemies; +2 Momentum/cast."),
    ("Snipe",                "active",  "momentum-spender (ST)",      "Single devastating shot; +12% dmg per Momentum stack."),
    # Other actives
    ("Split Shot",           "active",  "cooldown-damage",            "2 arrows on 1 enemy."),
    ("Barbed Shot",          "active",  "dot-applier (bleed)",        "Stacking Bleed (max 3, 20% WATK/s for 6s)."),
    ("Disengage",            "active",  "kite-escape",                "Hop back + i-frames; shoots on the way out."),
    ("Steady Aim",           "active",  "self-buff (offensive)",      "+weapon atk, +crit chance for buff duration."),
    ("Eagle Eye",            "active",  "party-buff",                 "+crit chance/dmg to whole party for buff duration."),
    # Passives — pure stats
    ("Marksman's Focus",     "passive", "stat (Accuracy %)",          "+Accuracy%, permanent."),
    ("Lethality",            "passive", "stat (Crit Damage %)",       "+Crit Damage%, permanent."),
    ("Keen Eye",             "passive", "stat (Crit Chance %)",       "+Crit Chance%, permanent."),
    ("Surefoot",             "passive", "stat (knockback resist)",    "+knockback resist, permanent."),
    # Passives — conditional %
    ("Execution",            "passive", "conditional (<30% HP)",      "+45% dmg vs enemies below 30% HP."),
    ("Tailwind",             "passive", "conditional (full Momentum)","+30% dmg at full Momentum — engages the gauge."),
],
"Dagger": [
    # Actives — no resource gauge wired
    ("Twin Fang",            "active",  "cooldown-damage (basic)",    "Quick 2-hit on 1 enemy; low CD spammable."),
    ("Fan of Knives",        "active",  "cooldown-damage (AoE)",      "7 throwing blades on 3 enemies."),
    ("Envenom",              "active",  "dot-applier (poison)",       "Stacking Poison (max 3) — feeds Toxicology synergy."),
    ("Cripple",              "active",  "utility-debuff",             "-def/atk to one enemy."),
    ("Shadowstep",           "active",  "gap-closer",                 "Blink + strike + brief i-frames."),
    ("Eviscerate",           "active",  "ST burst (execute?)",        "Heavy single-target finisher. Modeled as 'stealth = execute <35% HP' but the .tres has no stealth gate."),
    ("Killing Edge",         "active",  "self-buff (offensive)",      "+crit chance/dmg for a short window."),
    ("Bloodlust",            "active",  "party-buff",                 "+crit chance/dmg to whole party for buff duration."),
    ("Shadow Partner",       "active",  "summon (echo)",              "Shadow clone mimics attacks at X% dmg for buff duration."),
    # Passives — pure stats
    ("Killer Instinct",      "passive", "stat (Crit Chance %)",       "+Crit Chance%, permanent."),
    ("Cutthroat",            "passive", "stat (Crit Damage %)",       "+Crit Damage%, permanent."),
    ("Evasion",              "passive", "stat (Evasion %)",           "+Evasion%, permanent."),
    # Passives — conditional %
    ("Composure",            "passive", "conditional (>80% HP)",      "+25% dmg above 80% HP."),
    ("Opportunist",          "passive", "conditional (stealth)",      "+35% dmg in stealth — but NO ability enters stealth."),
    ("Toxicology",           "passive", "conditional (synergy)",      "+30% dmg vs Poisoned enemies (consumes Envenom mark)."),
],
"Staff": [
    # Actives — no resource gauge wired
    ("Arcane Bolt",          "active",  "cooldown-damage (basic)",    "Spammable single-target magic; low CD floor."),
    ("Arcane Lance",         "active",  "cooldown-damage (channel)",  "Channel — multi-pulse line across enemies."),
    ("Glacial Spike",        "active",  "cooldown-damage",            "Heavy ice strike. Notes claim 'Ice stance = freeze' — NO stance state on disk."),
    ("Pyre Burst",           "active",  "cooldown-damage (AoE)",      "Fireball AoE. Notes claim 'Fire stance = burn splash' — NO stance state on disk."),
    ("Immolate",             "active",  "dot-applier (burn)",         "Stacking Burn (max 3, 18% MATK/s for 6s)."),
    ("Aether Ward",          "active",  "utility-defensive (shield)", "MP-drains-to-absorb-HP shield until MP runs out."),
    ("Phase Step",           "active",  "gap-closer / escape",        "Blink in facing direction (or up/down); brief i-frames."),
    ("Communion",            "active",  "party-buff",                 "+MP regen, +Magic Attack to whole party for buff duration."),
    # Passives — pure stats
    ("Mana Flow",            "passive", "stat (MP regen)",            "+MP regen, permanent."),
    ("Deep Wellspring",      "passive", "stat (Max MP %)",            "+Max Mana%, permanent."),
    ("Spell Ward",           "passive", "stat (Magic Defense)",       "+Magic Defense, permanent."),
    ("Arcane Resonance",     "passive", "stat (Magic Attack %)",      "+Magic Attack%, permanent."),
    # Passives — conditional %
    ("Killing Spree",        "passive", "conditional (after kill 4s)","+30% dmg for 4s after a kill."),
    ("Overload",             "passive", "conditional (>50% MP)",      "+25% dmg above 50% MP."),
],
}

# Grouping of shapes into families, for the cross-weapon distribution view.
SHAPE_FAMILIES = [
    ("Pure damage button (cooldown-gated)", [
        "cooldown-damage", "cooldown-damage (basic)", "cooldown-damage (AoE)", "cooldown-damage (channel)",
    ]),
    ("Resource mesh — BUILDER", [
        "combo-builder", "combo-builder + gap-closer",
        "momentum-builder (basic)", "momentum-builder (AoE)",
    ]),
    ("Resource mesh — SPENDER", [
        "combo-spender (AoE)", "combo-spender (ST)", "momentum-spender (ST)",
    ]),
    ("DoT applier (sets a mark)", [
        "dot-applier (bleed)", "dot-applier (poison)", "dot-applier (burn)",
    ]),
    ("Mobility / position", [
        "gap-closer", "gap-closer / escape", "kite-escape", "combo-builder + gap-closer",
    ]),
    ("Self-buff (offensive/defensive)", [
        "self-buff (reflect)", "self-buff (defense)", "self-buff (all stats)",
        "self-buff (offensive)",
    ]),
    ("Party-buff / summon / shield / debuff", [
        "party-buff", "summon (echo)", "utility-defensive (shield)", "utility-debuff",
    ]),
    ("Conditional damage (execute / opener / synergy)", [
        "ST burst (execute?)",
        "conditional (>90% HP)", "conditional (<35% HP)", "conditional (on kill)",
        "conditional (<30% HP)", "conditional (full Momentum)", "conditional (>80% HP)",
        "conditional (stealth)", "conditional (synergy)",
        "conditional (after kill 4s)", "conditional (>50% MP)",
    ]),
    ("Pure stat passive", [
        "stat (Defense)", "stat (Max HP %)", "stat (HP regen)",
        "stat (Accuracy %)", "stat (Crit Damage %)", "stat (Crit Chance %)", "stat (knockback resist)",
        "stat (Evasion %)", "stat (MP regen)", "stat (Max MP %)", "stat (Magic Defense)",
        "stat (Magic Attack %)",
    ]),
]

# Per-weapon resource/gauge state: designed (per the class-widget convention) vs built.
GAUGES = {
    "Sword":  {"gauge": "Combo (max 3)",
               "built": True,
               "builders": ["Steel Flurry", "Vault Strike"],
               "spenders": ["Crescent Cleave", "Sundering Blow"],
               "diagnosis": "MESH WIRED. Two builders feed two spenders (1 AoE / 1 ST). Distinct identity in play."},
    "Bow":    {"gauge": "Momentum",
               "built": True,
               "builders": ["Snap Shot", "Hailstorm", "Skyfall"],
               "spenders": ["Snipe"],
               "diagnosis": "MESH WIRED. Three builders, one big spender, plus Tailwind passive engages the gauge. Identity present."},
    "Dagger": {"gauge": "Stealth",
               "built": False,
               "builders": [],
               "spenders": ["Eviscerate (?)", "Opportunist (passive)"],
               "diagnosis": "HALF-BUILT. Opportunist passive grants +35% dmg in stealth; Eviscerate is modeled as a stealth execute. But NO ability enters stealth — the gauge has payoffs with no setup. Dagger plays as cooldown-button + DoT mark + crit-stack passives, no signature 'in stealth' moment."},
    "Staff":  {"gauge": "Elemental Stance (Fire / Ice / Lightning)",
               "built": False,
               "builders": [],
               "spenders": [],
               "diagnosis": "NOT BUILT. No stance ability, no stance state. Glacial Spike / Pyre Burst / Arcane Lance are modeled with 'Ice freeze / Fire burn splash / Lightning chain' notes but the .tres files have none of it. ALL four damage actives behave the same: cast → hit → damage on cooldown. Worst shape-samey offender."},
}


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

    # apply the soft-cap to the ALLOCATED portion (per stat), before mastery/base
    for k in attrs:
        alloc = attrs[k] - BASE_ATTR
        if alloc > 0:
            attrs[k] = BASE_ATTR + soft_cap(alloc)

    # 2) mastery scaling (auto, on the wielded discipline) — not soft-capped
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


SPELLBLADE_PHYS_RATE = 0.5  # staff INT supplemented by this × best physical stat (combat.gd)

def staff_spellblade_bonus(disc_name, attrs):
    """Spellblade: a wielded STAFF adds SPELLBLADE_PHYS_RATE × best physical stat
    to its INT primary (so a physical main's off-hand staff isn't dead)."""
    if disc_name != "Staff":
        return 0
    return int(SPELLBLADE_PHYS_RATE * max(attrs["STR"], attrs["DEX"]))

def maxhit_for_alloc(disc_name, level, alloc):
    """Basic-attack max-hit for an EXPLICIT raw-point allocation dict
    ({STR/DEX/INT/LUCK/CON: pts}). Applies the soft-cap + mastery + gear like
    build_stats, but with a custom split — used for the 2-weapon loadout analysis
    where the allocation must serve two weapons' primary/secondary stats."""
    d = DISCIPLINES[disc_name]
    mast = mastery_at(level)
    attrs = {k: BASE_ATTR for k in ("STR", "DEX", "INT", "LUCK", "CON")}
    for k, pts in alloc.items():
        attrs[k] += soft_cap(int(pts))
    for k, per in d["mastery_bonus"].items():
        attrs[k] += per * mast
    # spellblade: staff borrows from physical stats
    sb = staff_spellblade_bonus(disc_name, attrs)
    attrs = dict(attrs)
    attrs[d["primary"]] += sb
    return max_range(disc_name, attrs, gear_attack_power(level))

def best_upgrade_config(name, base_hits, base_cd):
    """Pick the tier-3 variant that maximises single-target DPS, combined with the
    always-owned fixed upgrades. Returns (dmg_mult_add, hits_add, targets_add,
    cd_reduction, label) or None if the ability has no modelled damage upgrades."""
    u = UPG.get(name)
    if not u:
        return None
    fd, fh, ft, fc = u["fixed"]
    best = None
    for (vd, vh, vt, vc) in u["variants"]:
        dmg_mult = fd + vd
        hits_add = fh + vh
        cd_red = fc + vc
        eff_cd = max(0.1, base_cd - cd_red)
        # single-target DPS proxy: (1+dmg) × (hits+add)/hits ÷ cd
        st = (1.0 + dmg_mult) * ((base_hits + hits_add) / base_hits) / eff_cd
        if best is None or st > best[0]:
            best = (st, dmg_mult, hits_add, ft + vt, cd_red)
    _, dmg_mult, hits_add, tgt_add, cd_red = best
    return dmg_mult, hits_add, tgt_add, cd_red, u.get("extra", "")


def ability_numbers(ab, disc_name, level, archetype, upgraded=False):
    """Compute per-hit + per-cast + DPS for an ability at character `level`.
    If upgraded=True, fold in the best single-target upgrade config."""
    (name, max_lvl, dmg_base, dmg_per, hits, hits_per, targets,
     mana_base, mana_per, cd_base, cd_per, magic, note) = ab
    if dmg_base <= 0:
        return None  # non-damage (buff/passive/mobility)

    ab_lvl = min(max_lvl, level)  # ability level capped by its own max (and char level)
    dmg_pct = linear(dmg_base, dmg_per, ab_lvl)
    n_hits = round(linear(hits, hits_per, ab_lvl))
    cd = max(0.1, linear(cd_base, cd_per, ab_lvl))
    dmg_mult_up = 1.0
    upg_label = ""
    if upgraded:
        cfg = best_upgrade_config(name, max(1, n_hits), cd)
        if cfg:
            dmg_add, hits_add, tgt_add, cd_red, extra = cfg
            dmg_mult_up = 1.0 + dmg_add
            n_hits += hits_add
            targets += tgt_add
            cd = max(0.1, cd - cd_red)
            upg_label = f"+{dmg_add*100:.0f}% dmg" + (f", +{hits_add}h" if hits_add else "") + \
                        (f", +{tgt_add}t" if tgt_add else "") + (f", -{cd_red:g}s CD" if cd_red else "")

    attrs, crit, pool, mast = build_stats(disc_name, level, archetype)
    ap = gear_attack_power(level)
    mr = max_range(disc_name, attrs, ap)

    hit_max = mr * dmg_pct / 100.0 * dmg_mult_up    # top of the roll, one hit
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
        "crit": round(crit, 1), "note": note, "upg_label": upg_label,
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
        '<li><b>Ability level &amp; upgrades:</b> each ability scales with character level capped at its own max '
        '(so the L100 tables show abilities at <b>max level 20</b>). The per-level tables are <b>base — no '
        'upgrades</b>. The <a href="#ceil">Fully-Upgraded Ceilings</a> section below adds the PR6 upgrade trees '
        '(best single-target tier-3 variant per ability) to show each ability\'s true endgame ceiling.</li>'
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

    # ── FULL ROSTER ────────────────────────────────────────────────────────
    parts.append('<h2 class="weap" id="roster">Roster — every ability per weapon</h2>')
    parts.append('<div class="card"><p>Every ability per weapon, including non-damage actives, '
        'self-buffs, party-buffs, and passives that the damage tables below don\'t model. The '
        '<b>shape</b> column tags each one by mechanical category — scan it to see how the '
        'distribution of shapes inside a weapon does (and doesn\'t) vary.</p></div>')
    for disc in DISCIPLINES:
        parts.append(f'<h3>{disc} <span class="meta">· {len(ROSTER[disc])} abilities</span></h3>')
        parts.append('<table><thead><tr>'
            '<th>Name</th><th>kind</th><th>shape</th><th>what it does</th>'
            '</tr></thead><tbody>')
        for name, kind, shape, desc in ROSTER[disc]:
            kind_color = "#7ec2ff" if kind == "active" else "#c79bff"
            parts.append('<tr>'
                f'<td class="ab">{esc(name)}</td>'
                f'<td><span style="color:{kind_color};font-weight:600">{kind}</span></td>'
                f'<td>{esc(shape)}</td>'
                f'<td class="note">{esc(desc)}</td>'
                '</tr>')
        parts.append('</tbody></table>')

    # ── SHAPE DISTRIBUTION ─────────────────────────────────────────────────
    parts.append('<h2 class="weap" id="shape-dist">Shape distribution — where the samey-ness lives</h2>')
    parts.append('<div class="card"><p>How many abilities each weapon has in each <b>shape family</b>. '
        'If a row is overwhelmingly "Pure damage button" or "Pure stat passive," that\'s the '
        'shape-samey diagnosis showing up visually. Green cells = ≥2 abilities cover the family; '
        'yellow = exactly 1 (single point of failure); red = 0 (gap).</p></div>')
    parts.append('<table><thead><tr><th>Shape family</th>')
    for d in DISCIPLINES:
        parts.append(f'<th>{d}</th>')
    parts.append('</tr></thead><tbody>')
    for family, shapes in SHAPE_FAMILIES:
        parts.append(f'<tr><td class="ab">{esc(family)}</td>')
        for d in DISCIPLINES:
            count = sum(1 for _, _, sh, _ in ROSTER[d] if sh in shapes)
            if count >= 2:
                bg = "background:rgba(63,185,80,0.28);"
            elif count == 1:
                bg = "background:rgba(224,168,0,0.25);"
            else:
                bg = "background:rgba(248,81,73,0.22);"
            parts.append(f'<td style="{bg}text-align:center"><b>{count}</b></td>')
        parts.append('</tr>')
    parts.append('</tbody></table>')

    # ── MESH DIAGNOSIS (the gauge / resource shape per weapon) ─────────────
    parts.append('<h2 class="weap" id="mesh">Mesh diagnosis — class gauges &amp; what feeds them</h2>')
    parts.append('<div class="card"><p>The weapon-identity overhaul committed to four <b>class gauges</b> '
        '(class-widget convention — each weapon\'s signature resource gets its own anchored UI). For '
        'each weapon: is the gauge actually wired up in the .tres roster, and which abilities '
        'feed (build) or consume (spend) it?</p></div>')
    parts.append('<table><thead><tr><th>Weapon</th><th>Gauge</th><th>Built?</th>'
        '<th>Builders</th><th>Spenders</th><th>Diagnosis</th></tr></thead><tbody>')
    for d in DISCIPLINES:
        g = GAUGES[d]
        built_label = "yes" if g["built"] else "NO"
        built_style = ("color:#3fb950;font-weight:700;" if g["built"]
                       else "color:#f85149;font-weight:700;")
        builders = ", ".join(g["builders"]) if g["builders"] else "—"
        spenders = ", ".join(g["spenders"]) if g["spenders"] else "—"
        parts.append('<tr>'
            f'<td class="ab">{d}</td>'
            f'<td>{esc(g["gauge"])}</td>'
            f'<td style="{built_style}">{built_label}</td>'
            f'<td>{esc(builders)}</td>'
            f'<td>{esc(spenders)}</td>'
            f'<td class="note">{esc(g["diagnosis"])}</td>'
            '</tr>')
    parts.append('</tbody></table>')

    parts.append('<div class="find bad"><h4>Mesh finding · 2 of 4 weapons have no resource shape — everything is a cooldown button</h4>'
        '<p>Sword (Combo) and Bow (Momentum) have a full <b>builder → spender</b> mesh and a clear '
        'signature moment ("burn 3 combo for the AoE finisher" / "spend Momentum on a Snipe"). '
        '<b>Dagger</b> has Stealth payoffs (Opportunist passive +35% dmg, Eviscerate execute) but '
        'NO ability enters stealth — the gauge is a payoff with no setup. <b>Staff</b> has no '
        'stance / mode / resource at all: Arcane Bolt, Arcane Lance, Glacial Spike, Pyre Burst all '
        'behave identically (cast → damage on cooldown). The "+Ice freeze / Fire splash / Lightning '
        'chain" tags in the existing model\'s notes describe an unbuilt design, not the current '
        '.tres state. <b>This is where the shape-samey complaint actually lives.</b> Fix Dagger '
        'and Staff\'s resource mesh BEFORE adding new abilities — or those new abilities will '
        'inherit the same flatness.</p></div>')

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

    # ── Fully-upgraded ceilings (L100, pure-primary) ────────────────────────
    parts.append('<h2 class="weap" id="ceil">Fully-Upgraded Ceilings — L100, pure-primary</h2>')
    parts.append('<div class="card"><p>Each damage ability at <b>max level 20 + its best single-target upgrade '
        'path</b> (PR6 trees: the always-owned tier-1/2 upgrades plus the tier-3 variant that maximises '
        'single-target DPS — variants are mutually exclusive). Compare <b>base</b> (no upgrades) vs <b>upgraded</b> '
        'DPS. DoT-potency, combo-override and passive-stat upgrades are <i>not</i> in these numbers (noted per row), '
        'so true ceilings for DoT abilities are higher still.</p></div>')
    for disc in DISCIPLINES:
        rows = []
        for ab in ABILITIES[disc]:
            base = ability_numbers(ab, disc, 100, "pure", upgraded=False)
            up = ability_numbers(ab, disc, 100, "pure", upgraded=True)
            if base and up:
                rows.append((base, up))
        if not rows:
            continue
        parts.append(f'<h3>{disc} <span class="meta">· L100 pure-primary · ability lvl 20</span></h3>')
        parts.append('<table><thead><tr>'
            '<th>Ability</th><th>base hit (max)</th><th>upg hit (max)</th>'
            '<th>base DPS</th><th>upg DPS</th><th>gain</th><th>upg AoE DPS</th>'
            '<th>upgrade path</th></tr></thead><tbody>')
        for base, up in rows:
            gain = up["dps"] / base["dps"] if base["dps"] else 1.0
            extra = up.get("upg_label", "")
            note_extra = ""
            u = UPG.get(base["name"], {})
            if u.get("extra"):
                note_extra = f' <span class="dim">· {esc(u["extra"])}</span>'
            parts.append('<tr>'
                f'<td class="ab">{esc(base["name"])}</td>'
                f'<td>{base["hit_max"]:,}</td><td>{up["hit_max"]:,}</td>'
                f'<td>{base["dps"]:,}</td><td><b>{up["dps"]:,}</b></td>'
                f'<td style="{heat(gain,1.0,2.2)}"><b>{gain:.2f}×</b></td>'
                f'<td>{up["dps_aoe"]:,}</td>'
                f'<td class="note">{esc(extra)}{note_extra}</td>'
                '</tr>')
        parts.append('</tbody></table>')

    # ── Player damage vs enemy curve (time-to-kill) ─────────────────────────
    parts.append('<h2 class="weap" id="ttk">Player damage vs the enemy curve — Time-to-Kill</h2>')
    parts.append('<div class="card"><p>For each weapon at each level (pure-primary build, ability maxed + best '
        'single-target upgrades), this is the time to solo an <b>even-level enemy</b>: '
        '<code>TTK = enemy_HP ÷ (best_DPS × defense_mult)</code>, where '
        '<code>defense_mult = 1 − def/(def+500)</code> (weapon def for melee/bow/dagger, magic def for staff). '
        'Optimistic (ignores mana, misses, movement) but consistent across weapons/levels — so the <b>trend</b> is '
        'the signal. Enemy HP/def are curve-driven (assets/curves/monster_*_curve.tres).</p></div>')
    parts.append('<table><thead><tr><th>Level</th><th>enemy HP</th><th>enemy def</th><th>def mult</th>'
        '<th>Sword TTK</th><th>Bow TTK</th><th>Staff TTK</th><th>Dagger TTK</th></tr></thead><tbody>')
    for lvl in LEVEL_TIERS:
        cells = []
        for disc in DISCIPLINES:
            best = 0
            for ab in ABILITIES[disc]:
                r = ability_numbers(ab, disc, lvl, "pure", upgraded=True)
                if r and r["dps"] > best:
                    best = r["dps"]
            mdef = ENEMY_MDEF[lvl] if disc == "Staff" else ENEMY_WDEF[lvl]
            dmult = 1.0 - mdef / (mdef + 500.0)
            ttk = ENEMY_HP[lvl] / (best * dmult) if best else 0
            cells.append(ttk)
        wdef = ENEMY_WDEF[lvl]
        dmult_w = 1.0 - wdef / (wdef + 500.0)
        ttklo, ttkhi = min(cells), max(cells)
        parts.append(f'<tr><td class="ab">L{lvl}</td><td>{ENEMY_HP[lvl]:,}</td>'
            f'<td>{wdef} / {ENEMY_MDEF[lvl]}m</td><td>{dmult_w:.2f}</td>' +
            "".join(f'<td style="{heat(c, ttklo, ttkhi*1.2)}">{c:.1f}s</td>' for c in cells) + '</tr>')
    parts.append('</tbody></table>')
    parts.append('<p class="spread"><b>Read the trend down each column.</b> If TTK climbs sharply with level, '
        'enemy HP/def out-scale player damage (enemies get spongier) — fix the curve before nerfing players. '
        'If it falls, players out-scale and content trivialises.</p>')

    # ── Build budget & what players take ────────────────────────────────────
    parts.append('<h2 class="weap" id="builds">Builds — budget &amp; the dominant picks</h2>')
    parts.append('<div class="card"><h2>The point budget</h2>'
        f'<p>Each discipline grants <b>{PTS_PER_MASTERY}/mastery level</b> → <b>{PTS_BUDGET} points</b> at '
        f'mastery cap ({MASTERY_CAP}). Costs: an active maxed (1→20) = <b>{COST_ACTIVE_MAX}</b>, a passive '
        f'(1→10) = <b>{COST_PASSIVE_MAX}</b>, full upgrades on any ability = <b>{COST_FULL_UPGRADES}</b> '
        '(T1+T2+one T3). So a maxed+upgraded active ≈ <b>24</b>, a maxed+upgraded passive ≈ <b>14</b>.</p>'
        '<p>A 120-pt build is therefore roughly <b>3 core actives (72) + 2 maxed passives (28) + ~20 spare</b> '
        '(a filler active or more upgrades). You <b>cannot</b> max a discipline — selective investment IS the '
        'build identity. Two weapon slots = two 120-pt pools, but mastery must be earned on each.</p>'
        '<ul class="notes">'
        '<li><b>Attribute meta:</b> pure-primary is +27–43% damage over default with no cost but survivability, '
        'so the dominant DPS build dumps all 5/level into the primary stat (STR sword / DEX bow / INT staff / '
        'LUCK dagger). CON only for tanky/PvP. Until this is reined in, "what players take" = pure primary.</li>'
        '<li><b>Core actives:</b> players take their highest-ceiling damage abilities — typically the spammable '
        'starter (DPS floor) + a DoT-setter + the finisher (Snipe/Eviscerate/Sundering Blow). The big-cooldown '
        'utility (dashes, buffs) competes for the 3rd slot.</li>'
        '<li><b>Passives:</b> the primary-stat % passive (Iron Sinews / Fleet Fingers / Arcane Mind / Larcenous '
        'Luck) is near-mandatory since it scales the whole kit; HP/defense passives fill the 2nd slot. The +6 '
        'passive count means ~3-of-6 is a real choice (good).</li>'
        '<li><b>Cross-weapon loadout:</b> Sword/Bow/Dagger all key off WEAPONATTACK + STR/DEX/LUCK, so a 2-melee '
        '/ melee+bow pair shares gear &amp; attribute investment. Staff is isolated (INT + MAGICATTACK, separate '
        'gear pool) — pairing a staff with a physical weapon splits your itemisation, a real cost. Expect '
        'physical/physical loadouts to dominate unless staff offers something they can\'t.</li>'
        '</ul></div>')

    # ── Level 1 → 100 progression ───────────────────────────────────────────
    parts.append('<h2 class="weap" id="prog">Level 1 → 100 progression — points &amp; damage</h2>')
    parts.append('<div class="card"><p>How a build grows: the attribute pool (5/level), ability points '
        '(6 × weapon mastery, cap 20 → 120/discipline), and the resulting basic-attack max-hit. Stats shown '
        'for a Sword default build (soft-capped); other weapons track the same shape. Mastery is assumed to '
        'climb with level (kill-earned) and cap at 20. Damage uses the model gear curve (≈2×level attack).</p></div>')
    parts.append('<table><thead><tr><th>Level</th><th>attr pool</th><th>spent/unspent (5/lvl)</th>'
        '<th>mastery</th><th>ability pts/disc</th><th>STR (primary)</th><th>gear ATK</th>'
        '<th>basic max-hit</th><th>even-lvl enemy HP</th></tr></thead><tbody>')
    for lvl in [1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]:
        attrs, crit, pool, mast = build_stats("Sword", lvl, "default")
        ap = gear_attack_power(lvl)
        mr = max_range("Sword", attrs, ap)
        ability_pts = PTS_PER_MASTERY * mast
        # nearest enemy-HP tier for context
        hp = ENEMY_HP[min(ENEMY_HP, key=lambda k: abs(k - lvl))]
        parts.append(f'<tr><td class="ab">L{lvl}</td><td>{pool}</td>'
            f'<td>{pool} / 0</td><td>{mast}/20</td><td>{ability_pts}</td>'
            f'<td>{attrs["STR"]}</td><td>{ap}</td><td>{mr:,}</td><td>{hp:,}</td></tr>')
    parts.append('</tbody></table>')
    parts.append('<p class="spread"><b>Point economy:</b> by L100 a build has <b>495 attribute points</b> '
        '(one full mono-stat is soft-capped) and <b>120 ability points per mastered discipline</b> — enough for '
        '~3 maxed+upgraded actives + 2 passives. Mastery is the gate: ability points only arrive as you master '
        'the weapon, so early levels are attribute-led and weapon-gear-led, with the kit filling in as mastery climbs.</p>')

    # ── 2-weapon loadout synergy ────────────────────────────────────────────
    parts.append('<h2 class="weap" id="loadouts">Endgame 2-weapon loadouts — how they mesh</h2>')
    parts.append('<div class="card"><p>You carry TWO weapons; passives from both apply, but only the ACTIVE '
        'weapon casts &amp; scales damage. <b>Damage now scales off the ACTIVE weapon\'s discipline</b> (fixed bug: '
        'it used your starting class), so a hybrid must either share attributes or split the pool (the soft-cap makes '
        'that viable). Each weapon brings its own attack stat (dagger=WEAPONATTACK, staff=MAGICATTACK). <b>Staff is '
        'the exception by design</b> — the SUPPORT off-hand: SPELLBLADE lets a physical main\'s STR/DEX fund staff '
        'damage (~59% of main), and its shield/blink/freeze/Communion buff are all INT-free, so it pairs with anything '
        'for survival + control + a group attack buff rather than raw DPS.</p></div>')
    PRIM = {d: DISCIPLINES[d]["primary"] for d in DISCIPLINES}
    SEC = {d: DISCIPLINES[d]["secondary"] for d in DISCIPLINES}
    pairs = [("Sword","Bow"),("Bow","Dagger"),("Sword","Dagger"),("Staff","Dagger"),("Sword","Staff"),("Bow","Staff")]
    notes = {
        ("Sword","Bow"): "BEST mesh — both use STR+DEX (just swapped primary/secondary) &amp; WEAPONATTACK. One STR/DEX allocation maxes both; shared gear. Bruiser-archer.",
        ("Bow","Dagger"): "THE crit build — share DEX; both WEAPONATTACK. Dagger brings crit-CHANCE passives, Bow brings crit-DAMAGE → multiplicative crit (esp. post-B6). Allocate DEX+LUCK.",
        ("Sword","Dagger"): "Share DEX; both WEAPONATTACK. STR(sword) vs LUCK(dagger) split. Survivable assassin — Sword's HP/heal + Dagger's evasion/crit. Allocate DEX + split STR/LUCK.",
        ("Staff","Dagger"): "★ Share LUCK — Dagger PRIMARY (×4) = Staff SECONDARY (×1), and Dagger's crit-chance passives boost Staff crits too. INT(staff primary) is the odd stat. Soft-cap makes a LUCK+INT split viable. See deep-dive below.",
        ("Sword","Staff"): "Disjoint stat lines (STR/DEX vs INT/LUCK), but Staff is the SUPPORT off-hand: SPELLBLADE lets your STR fund staff damage (~59% of main), and its shield/blink/freeze/Communion buff all work INT-free. You carry Staff for survival+control+group-buff, not raw DPS. A real pick now, not a tax.",
        ("Bow","Staff"): "Same as Sword/Staff — Staff as the utility/support off-hand (SPELLBLADE makes its damage viable off your DEX; shield/freeze/Communion are INT-free). Bow kites, Staff covers safety+control. Pick Staff for the toolkit, not DPS.",
    }
    parts.append('<table><thead><tr><th>Loadout</th><th>shared attribute(s)</th><th>attack stats</th>'
        '<th>mesh</th><th>how they combine</th></tr></thead><tbody>')
    for a, b in pairs:
        sa = set([PRIM[a], SEC[a]]) & set([PRIM[b], SEC[b]])
        shared = ", ".join(sorted(sa)) if sa else "—"
        atk_a = DISCIPLINES[a]["attack"].replace("ATTACK","")
        atk_b = DISCIPLINES[b]["attack"].replace("ATTACK","")
        atk = atk_a if atk_a == atk_b else f"{atk_a} / {atk_b}"
        rating = "●●●" if len(sa) >= 2 else ("●●" if len(sa) == 1 else "●")
        parts.append(f'<tr><td class="ab">{a} + {b}</td><td>{shared}</td><td>{atk}</td>'
            f'<td>{rating}</td><td class="note">{notes[(a,b)]}</td></tr>')
    parts.append('</tbody></table>')

    # Dagger/Staff numeric deep-dive
    parts.append('<h3>★ Dagger / Staff deep-dive (L100) — the LUCK-shared hybrid</h3>')
    parts.append('<div class="card"><p>Both weapons want LUCK (Dagger primary / Staff secondary &amp; crit), but Staff '
        'also wants INT (its primary). With 495 points, how you split LUCK vs INT trades the two weapons\' power. '
        'Basic-attack max-hit for each weapon under three allocations (each weapon uses its own attack stat, '
        '≈197 at L100):</p></div>')
    P = 495
    allocs = {
        "All LUCK (dagger-main)":        {"LUCK": P},
        "Balanced LUCK/INT":             {"LUCK": P // 2, "INT": P - P // 2},
        "All INT (staff-main)":          {"INT": P},
        "LUCK + INT + DEX (true hybrid)":{"LUCK": P // 3, "INT": P // 3, "DEX": P - 2 * (P // 3)},
    }
    parts.append('<table><thead><tr><th>Allocation</th><th>Dagger max-hit</th><th>Staff max-hit</th>'
        '<th>read</th></tr></thead><tbody>')
    reads = {
        "All LUCK (dagger-main)": "Dagger peaks; Staff usable (LUCK is its secondary) but no INT primary — Staff is a weak off-hand.",
        "Balanced LUCK/INT": "Both solid — the soft-cap means splitting costs little. The natural Dagger/Staff build.",
        "All INT (staff-main)": "Staff peaks; Dagger gutted (LUCK is its primary, now base 4) — Dagger is a dead off-hand.",
        "LUCK + INT + DEX (true hybrid)": "Spreads thin across 3 stats; both weapons fair but neither peaks. Over-diluted.",
    }
    for label, al in allocs.items():
        dag = maxhit_for_alloc("Dagger", 100, al)
        stf = maxhit_for_alloc("Staff", 100, al)
        parts.append(f'<tr><td class="ab">{esc(label)}</td><td>{dag:,}</td><td>{stf:,}</td>'
            f'<td class="note">{reads[label]}</td></tr>')
    parts.append('</tbody></table>')
    parts.append('<p class="spread"><b>Verdict:</b> Dagger/Staff works best as a <b>Balanced LUCK/INT</b> build — '
        'the soft-cap makes the split nearly free, LUCK double-dips (Dagger primary + Staff secondary + crit), and '
        'Dagger\'s crit-chance passives carry into Staff casts. INT is the only "wasted on Dagger" stat. It\'s a real '
        'hybrid, not a trap — though it can\'t out-DPS a focused single-attribute build (Sword/Bow). The crit-chance '
        'overlap is the glue; <b>B6 (CritDamage on gear) would make this pairing shine</b>.</p>')

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
.dim{color:#6b7280;font-size:11.5px}
a{color:var(--acc)}
</style></head><body>"""

ANALYSIS = """
<h2 class="weap">Balance findings &amp; recommendations</h2>

<div class="find bad"><h4>0 · FIX THE ENEMY CURVE FIRST — even-level TTK explodes at high level</h4>
<p>Even-level time-to-kill should be roughly <b>constant</b> across levels (an even fight should feel similar at
any level). Instead it swings 3.8s → 1.3s → 2.9s → <b>16.2s</b> (Sword) — enemies become massive sponges past
L60. Cause: player damage scales ~<b>quadratically</b> (primary stat × weapon attack, both ~linear in level)
while the enemy HP curve scales ~<b>cubically</b> (15 → 1,800 → 130,000), and the defense curve compounds it
(def_mult 0.87 → <b>0.49</b>, so L100 enemies also halve your damage). <b>Recommendation: re-shape the enemy
HP curve (and cap the defense curve) so even-level TTK lands ~2–4s at every level BEFORE touching ability
numbers.</b> The curves are single .tres files — one lever reshapes all difficulty; far cheaper and safer than
re-tuning 30+ abilities to chase a moving target. Early game (L1, 3.8–5s) is the secondary issue — weapon-gated
low damage; consider a small base-stat floor or stronger starter weapons.</p></div>

<div class="find"><h4>0b · Bow &amp; Dagger out-DPS Sword &amp; Staff ~2× (low-CD spammables)</h4>
<p>Across the TTK table, Bow/Dagger kill roughly twice as fast as Sword/Staff (L100: 8.0s/6.8s vs 16.2s/14.5s).
Their best sustained tools are near-zero-cooldown spammables (Snap Shot no CD, Twin Fang 0.5s upgraded) that the
model rates very high, while Sword/Staff lean on cooldown-gated hits. Some of this is the DPS-ignores-mana
caveat, but the gap is real — verify the spammables aren't free infinite DPS, and lift Sword/Staff sustained
floors (or gate Bow/Dagger spam behind mana/Momentum) in the ability pass.</p></div>

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

<div class="find bad"><h4>7 · Upgrades are a 2.5–3.8× power spike — the real endgame ceiling</h4>
<p>Fully upgraded, most damage abilities <b>2.5–3.8× their base DPS</b> (Twin Fang 3.80×, Cripple 3.25×,
Snipe/Eviscerate/Shadowstep ~3.1×). The trees stack three multipliers at once — bonus damage % ×
extra hits/targets × cooldown reduction — so the "fully invested" ceiling sits far above the per-level
tables. Balance the <i>ceiling</i>, not just the base %, or a maxed build trivialises content.</p></div>

<div class="find bad"><h4>8 · The "+1 hit" tier-3 variant usually beats the "+90% damage" one (single-target)</h4>
<p>On 1–2-hit abilities, adding a hit doubles per-cast damage, which beats even a +0.9 damage variant
(e.g. Snipe/Eviscerate pick <b>Double Tap/Overkill (+1 hit)</b> over Killshot/Assassinate (+90%)).
The flashy big-damage tier-3 variants are <b>traps</b> for single-target — they only win on already
multi-hit abilities (Fan of Knives, Twin Fang). Consider rebalancing so the choice is genuinely close.</p></div>

<div class="find"><h4>9 · Low-CD spammables dominate the raw DPS column — finishers are burst, not sustained</h4>
<p>Twin Fang (0.5s CD upgraded), Snap Shot (no CD) and Arcane Bolt out-DPS the cooldown finishers on
pure sustained single-target because DPS = per-cast ÷ cooldown ignores mana, animation lock, and the
fact that finishers are <i>woven</i> into auto-attacks for burst + their signature payoff (Snipe spends
Momentum, Eviscerate executes). Don't read the DPS column as "finishers are weak" — read it as "verify
the spammables aren't mana-free infinite DPS." Cripple shows the opposite: a 10s CD made it the floor
until CD-reduction upgrades (−6s) tripled it — long cooldowns are extremely upgrade-sensitive.</p></div>

<div class="find"><h4>10 · Tune targets, not just numbers</h4>
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
