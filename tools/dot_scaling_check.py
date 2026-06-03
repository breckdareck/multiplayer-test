#!/usr/bin/env python3
"""
DoT scaling check — verifies how bleed/poison/burn per-tick damage scales across
character level, weapon mastery, ability level, and gear, under the CURRENT model
(% of raw attack stat) vs. the PROPOSED model (% of the applying hit).

Mirrors the verified combat math (combat.gd _calculate_max_range / stats.gd):
  max_range = weapon_mult * (primary*4 + secondary) * attack_power / 100
  ability_hit = max_range * damage_percent/100        (max roll)
All constants are read from source (2026-06-02). Pure offline model; touches nothing.
"""

WEAPON_MULT = 1.2
BASE_ATTR = 4
AP_PER_LEVEL = 5            # stats.gd ATTRIBUTE_POINTS_PER_LEVEL
SOFT_KNEE, SOFT_SLOPE = 300, 0.4
MASTERY_CAP = 100
MASTERY_AT_CHAR70 = 100     # design: mastery 100 ≈ char 70

# Per-discipline mastery stat_bonuses (discipline .tres)
MASTERY_BONUS = {"sword": {"pri": 3, "sec": 2}, "staff": {"pri": 3, "sec": 2}}

def soft_cap(raw):
    return raw if raw <= SOFT_KNEE else SOFT_KNEE + (raw - SOFT_KNEE) * SOFT_SLOPE

def mastery_at(level):
    return min(MASTERY_CAP, round(level * MASTERY_CAP / MASTERY_AT_CHAR70))

def ability_level_at(level):
    # abilities leveled with mastery points (1/mastery lvl); assume this DoT
    # ability keeps pace — caps at its max_level 10.
    return max(1, min(10, round(mastery_at(level) / 10)))

def gear_attack(level):
    # WEAPONATTACK/MAGICATTACK are gear-only (base 0). Anchored: ~9 at L1
    # (starter weapon), ~197 at L100 (verified Eternal Dirk). Linear.
    return 9.0 + (197.0 - 9.0) * (level - 1) / 99.0

# Enemy HP at matched level (sampled from monster_hp_curve anchors, interpolated)
ENEMY_HP = {1: 15, 10: 250, 30: 1800, 50: 5500, 70: 12000, 100: 29132}

def primary_secondary(level, disc):
    m = mastery_at(level)
    pool = AP_PER_LEVEL * (level - 1)          # all-in on primary (DPS build)
    primary = BASE_ATTR + m * MASTERY_BONUS[disc]["pri"] + soft_cap(pool)
    secondary = BASE_ATTR + m * MASTERY_BONUS[disc]["sec"]
    return primary, secondary

def max_range(level, disc):
    p, s = primary_secondary(level, disc)
    return WEAPON_MULT * (p * 4 + s) * gear_attack(level) / 100.0

def ability_hit(level, disc, dmg_base, dmg_per):
    al = ability_level_at(level)
    dmg_pct = dmg_base + (al - 1) * dmg_per
    return max_range(level, disc) * dmg_pct / 100.0

LEVELS = [1, 10, 30, 50, 70, 100]


def report(title, disc, dmg_base, dmg_per, attack_pct_old, new_pct, stacks, ticks):
    print(f"\n=== {title} ===")
    print(f"  old: per_tick = {attack_pct_old:.0%} x attack_stat (gear only)")
    print(f"  new: per_tick = {new_pct:.0%} x applying_hit   |  {stacks} stacks x {ticks} ticks")
    hdr = f"  {'char':>4} {'mast':>4} {'abilL':>5} {'maxRange':>9} {'hit':>8} | {'OLD/tk':>7} {'OLDtot':>8} {'OLD/hit':>7} {'OLD/HP':>7} | {'NEW/tk':>7} {'NEWtot':>8} {'NEW/hit':>7} {'NEW/HP':>7}"
    print(hdr)
    for L in LEVELS:
        m = mastery_at(L); al = ability_level_at(L)
        mr = max_range(L, disc); hit = ability_hit(L, disc, dmg_base, dmg_per)
        ap = gear_attack(L)
        old_tk = max(1, round(ap * attack_pct_old)) * stacks
        old_tot = old_tk * ticks
        new_tk = max(1, round(hit * new_pct)) * stacks
        new_tot = new_tk * ticks
        hp = ENEMY_HP[L]
        print(f"  {L:>4} {m:>4} {al:>5} {mr:>9.0f} {hit:>8.0f} | "
              f"{old_tk:>7} {old_tot:>8} {old_tot/hit:>6.2f}x {old_tot/hp:>6.1%} | "
              f"{new_tk:>7} {new_tot:>8} {new_tot/hit:>6.2f}x {new_tot/hp:>6.1%}")


# Sword bleed (Hemorrhage): dmg% 130 +10/lvl, old 20% WEAPONATTACK, 3 stacks/5 ticks
report("Sword BLEED — Hemorrhage", "sword", 130, 10, 0.20, 0.10, 3, 5)
# Dagger poison (Envenom): dmg% 90 +8/lvl (uses WEAPONATTACK like sword), 5 stacks/8 ticks
report("Dagger POISON — Envenom", "sword", 90, 8, 0.20, 0.08, 5, 8)
# Staff fire pool (Pyre Burst): dmg% 60 +6/lvl, old 12% MAGICATTACK, 3 stacks/4 ticks
report("Staff FIRE POOL — Pyre Burst", "staff", 60, 6, 0.12, 0.12, 3, 4)

print("\nKEY: OLD/hit and NEW/hit = full DoT damage as a multiple of ONE applying hit.")
print("A well-scaled DoT keeps that multiple ~constant across levels. OLD collapses; NEW holds.")
