#!/usr/bin/env python3
"""
v1 ability upgrade .tres generator.

For each new v1 ability (defined in gen_v1_abilities.SPECS) produces:
  - 1 T1 (1pt fixed-always-owned) small flat improvement
  - 1 T2 (1pt fixed-always-owned) medium flat improvement
  - 3 T3 (2pt mutually-exclusive variants) shape-changing upgrades

Total: 5 upgrades per ability × 22 abilities = 110 upgrade .tres files.

Also patches each parent A_*.tres to reference its new upgrades in the
`upgrades = Array[...]([...])` field. Idempotent — overwrites in place.

Run:  python tools/gen_v1_upgrades.py
Out:  resources/Abilities/<weapon>/Upgrades/U_<prefix>_<name>.tres

The exact balance numbers are starter values; tune in the resource editor
after playtest. Each T3 variant is mechanically distinct (per the locked
"+1 hit beats +90% damage" rule — variants change how the ability plays,
not just numbers).
"""

import os
import re
import hashlib
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gen_v1_abilities import SPECS, gen_uid, UID_UPGRADE_DATA  # type: ignore

UID_AB_UPGRADE_DATA = UID_UPGRADE_DATA  # alias for clarity


# ─────────────────────────────────────────────────────────────────────────────
# Per-ability upgrade specs.
#   prefix     : 2-4 letter upgrade-id prefix (matches existing convention)
#   t1_name    : tier-1 upgrade display name
#   t1_desc    : T1 description (uses smart-placeholder pattern from existing trees)
#   t1_key     : T1 effect_key (bonus_damage_mult / cooldown_flat_reduction / etc.)
#   t1_mag     : T1 magnitude
#   t2_*       : same fields for T2
#   t3a/b/c    : tuples of (name, desc, effect_key, magnitude) for the 3 T3 variants
#
# All T3 variants share the same `variant_group` (formed from the prefix) —
# the ability's owned-upgrades guard enforces mutual exclusivity at runtime.
# ─────────────────────────────────────────────────────────────────────────────

# Generic upgrade catalogue per ability spec id. Where balance is sensitive
# (combo spenders, channels), the T3 variants are tailored.
UPGRADES = {
    # ── SWORD ────────────────────────────────────────────────────────────────
    "charge_v1": {
        "prefix": "CHG",
        "t1": ("Swift Foot", "Charge!'s cooldown is reduced by 1 second.", "cooldown_flat_reduction", 1.0),
        "t2": ("Wider Cleave", "Charge! deals +25% damage.", "bonus_damage_mult", 0.25),
        "t3": [
            ("Trampling Charge", "Charge! pierces +2 additional enemies in its path.", "bonus_targets", 2),
            ("Crushing Charge", "Charge! deals +70% damage.", "bonus_damage_mult", 0.70),
            ("Battlecry", "Each enemy pierced builds +1 extra combo point.", "bonus_combo_per_hit", 1),
        ],
    },
    "earthsplitter_v1": {
        "prefix": "EAR",
        "t1": ("Wider Crack", "Earthsplitter's zone radius is increased.", "bonus_zone_radius", 20.0),
        "t2": ("Lingering Tremors", "Earthsplitter's zone duration is increased by 1.5 seconds.", "bonus_zone_duration", 1.5),
        "t3": [
            ("Fissure Network", "Earthsplitter splits into 2 smaller zones at impact (one ahead, one behind).", "bonus_zone_split", 1),
            ("Aftershock", "1.5 seconds after impact, a second pulse hits everything in zone for +50% damage.", "bonus_aftershock_mult", 0.5),
            ("Cataclysm", "Consumes the zone duration into a single big impact (+200% damage, no ticks).", "bonus_burst_mult", 2.0),
        ],
    },
    "onslaught_v1": {
        "prefix": "OSL",
        "t1": ("Swift Wind-up", "Vanguard's Onslaught's max channel time is reduced by 0.5 seconds.", "channel_time_reduction", 0.5),
        "t2": ("Strong Arm", "Vanguard's Onslaught deals +25% damage.", "bonus_damage_mult", 0.25),
        "t3": [
            ("Earthshaker", "Vanguard's Onslaught pierces +3 additional enemies.", "bonus_targets", 3),
            ("Devastator", "Vanguard's Onslaught deals +60% damage at max charge.", "bonus_damage_mult", 0.60),
            ("Unstoppable", "Vanguard's Onslaught grants +1 combo per pierced enemy (in addition to the base).", "bonus_combo_per_hit", 1),
        ],
    },
    "banner_v1": {
        "prefix": "BNR",
        "t1": ("Wider Banner", "Banner of the Vanguard's aura radius is increased.", "bonus_zone_radius", 30.0),
        "t2": ("Lasting Banner", "Banner of the Vanguard's duration is increased by 3 seconds.", "bonus_zone_duration", 3.0),
        "t3": [
            ("Inspiring Banner", "Banner also grants allies +10% damage while inside.", "bonus_aura_damage", 0.10),
            ("Healing Banner", "Banner's HP regen tick is doubled.", "bonus_heal_mult", 1.0),
            ("Bulwark Banner", "Banner reduces incoming damage by 15% for allies inside.", "bonus_damage_reduction", 0.15),
        ],
    },
    "sentinels_mark_v1": {
        "prefix": "SNM",
        "t1": ("Extended Mark", "Sentinel's Mark lasts 3 seconds longer.", "bonus_mark_duration", 3.0),
        "t2": ("Sharper Mark", "Damage to marked enemies is increased by +10%.", "bonus_mark_damage", 0.10),
        "t3": [
            ("Generous Mark", "Combo-refund chance against marked is increased to 50%.", "bonus_refund_chance", 0.25),
            ("Punishing Mark", "Damage to marked enemies is increased by +30%.", "bonus_mark_damage", 0.30),
            ("Echoing Mark", "When the marked target dies, the mark spreads to a nearby enemy.", "bonus_mark_spread", 1),
        ],
    },
    "vanguards_resolve_v1": {
        "prefix": "VRS",
        "t1": ("Stalwart Resolve", "Vanguard's Resolve grants an additional -2% damage reduction per combo.", "bonus_passive_potency", 0.02),
        "t2": ("Iron Resolve", "Vanguard's Resolve grants an additional -3% damage reduction per combo.", "bonus_passive_potency", 0.03),
        "t3": [
            ("Eternal Resolve", "Vanguard's Resolve continues for 2 seconds after combo is spent.", "bonus_resolve_carryover", 2.0),
            ("Combat Resolve", "Vanguard's Resolve also grants +Defense while at full combo.", "bonus_defense_at_full", 50),
            ("Tenacious Resolve", "Vanguard's Resolve cap is increased to 4 combo (effective -20%).", "bonus_resolve_cap", 1),
        ],
    },
    # ── BOW ──────────────────────────────────────────────────────────────────
    "caltrops_v1": {
        "prefix": "CAL",
        "t1": ("Sharper Spikes", "Caltrops' tick damage is increased by +25%.", "bonus_damage_mult", 0.25),
        "t2": ("Wider Field", "Caltrops' radius is increased.", "bonus_zone_radius", 20.0),
        "t3": [
            ("Lingering Field", "Caltrops' duration is increased to 7 seconds.", "bonus_zone_duration", 2.0),
            ("Piercing Spikes", "Caltrops' slow is increased to 50%.", "bonus_slow_pct", 0.20),
            ("Poisoned Spikes", "Caltrops applies a stacking Bleed to enemies inside.", "bonus_bleed_applies", 1),
        ],
    },
    "sky_volley_v1": {
        "prefix": "SKV",
        "t1": ("Sustained Volley", "Sky Volley's max channel is increased by 1 second.", "channel_time_extension", 1.0),
        "t2": ("Heavy Volley", "Sky Volley's per-tick damage is increased by +20%.", "bonus_damage_mult", 0.20),
        "t3": [
            ("Wide Volley", "Sky Volley's radius is increased significantly.", "bonus_zone_radius", 40.0),
            ("Rapid Volley", "Sky Volley's tick interval is halved (faster damage).", "bonus_tick_rate", 0.5),
            ("Marking Volley", "Sky Volley applies Mark of the Hunt to enemies inside.", "bonus_marks_applied", 1),
        ],
    },
    "mark_of_the_hunt_v1": {
        "prefix": "MOH",
        "t1": ("Lasting Mark", "Mark of the Hunt's duration is increased by 4 seconds.", "bonus_mark_duration", 4.0),
        "t2": ("Quick Mark", "Mark of the Hunt's cooldown is reduced by 2 seconds.", "cooldown_flat_reduction", 2.0),
        "t3": [
            ("Double Mark", "Mark of the Hunt applies to 2 enemies simultaneously.", "bonus_mark_targets", 1),
            ("Sundering Mark", "The auto-crit consume also pierces nearby enemies.", "bonus_pierce_on_crit", 1),
            ("Bleeding Mark", "Marked targets also bleed for 5% Weapon Attack per second.", "bonus_bleed_dot", 0.05),
        ],
    },
    "sundering_arrow_v1": {
        "prefix": "SDR",
        "t1": ("Swift Sundering", "Sundering Arrow's cooldown is reduced by 1 second.", "cooldown_flat_reduction", 1.0),
        "t2": ("Heavy Sundering", "Sundering Arrow deals +30% damage.", "bonus_damage_mult", 0.30),
        "t3": [
            ("Far Sundering", "Sundering Arrow pierces +3 additional enemies.", "bonus_targets", 3),
            ("Crushing Sundering", "Sundering Arrow deals +70% damage.", "bonus_damage_mult", 0.70),
            ("Refunding Sundering", "Sundering Arrow refunds 4 Momentum if it kills any enemy.", "bonus_momentum_refund", 4),
        ],
    },
    "wind_rider_v1": {
        "prefix": "WND",
        "t1": ("Soaring Wind", "Wind Rider's per-stack speed reduction is increased.", "bonus_passive_potency", 0.005),
        "t2": ("Howling Wind", "Wind Rider's max reduction is increased to -35%.", "bonus_passive_cap", 0.10),
        "t3": [
            ("Twin Wind", "Wind Rider also reduces ability cooldowns by half its current bonus.", "bonus_cd_carryover", 0.5),
            ("Steady Wind", "Wind Rider's reduction is doubled at full Momentum.", "bonus_at_full_mult", 1.0),
            ("Driving Wind", "Wind Rider grants +10% damage at full Momentum (on top of Tailwind).", "bonus_dmg_at_full", 0.10),
        ],
    },
    # ── DAGGER ───────────────────────────────────────────────────────────────
    "backstab_v1": {
        "prefix": "BKS",
        "t1": ("Sharper Backstab", "Backstab's bonus damage is increased by +10%.", "bonus_positional_dmg", 0.10),
        "t2": ("Quick Backstab", "Backstab's cooldown is reduced by 1 second.", "cooldown_flat_reduction", 1.0),
        "t3": [
            ("Twin Backstab", "Backstab hits 2 times instead of 1.", "bonus_hits", 1),
            ("Crippling Backstab", "Backstab also slows the target by 30% for 2 seconds.", "bonus_slow_apply", 0.30),
            ("Lethal Backstab", "Backstab's bonus damage is doubled at full health.", "bonus_at_full_hp", 0.50),
        ],
    },
    "death_mark_v1": {
        "prefix": "DMK",
        "t1": ("Lingering Mark", "Death Mark's duration is increased by 4 seconds.", "bonus_mark_duration", 4.0),
        "t2": ("Killing Mark", "Death Mark's crit chance bonus is increased by +10%.", "bonus_mark_potency", 10.0),
        "t3": [
            ("Spreading Mark", "When a marked target dies, the mark spreads to 1 nearby enemy.", "bonus_mark_spread", 1),
            ("Bleeding Mark", "Marked targets also bleed for 10% Weapon Attack per second.", "bonus_bleed_dot", 0.10),
            ("Double Mark", "Death Mark applies to 2 enemies simultaneously.", "bonus_mark_targets", 1),
        ],
    },
    "vendetta_v1": {
        "prefix": "VEN",
        "t1": ("Sharp Vendetta", "Vendetta's per-stack burst damage is increased by +10%.", "bonus_damage_mult", 0.10),
        "t2": ("Quick Vendetta", "Vendetta's cooldown is reduced by 1 second.", "cooldown_flat_reduction", 1.0),
        "t3": [
            ("Spreading Vendetta", "Vendetta also strikes 1 nearby enemy for half damage.", "bonus_targets", 1),
            ("Lethal Vendetta", "Vendetta's burst deals +100% damage if it kills the target.", "bonus_execute_mult", 1.0),
            ("Regenerative Vendetta", "Vendetta heals you for 25% of damage dealt.", "bonus_lifesteal", 0.25),
        ],
    },
    "smoke_bomb_v1": {
        "prefix": "SMK",
        "t1": ("Lasting Smoke", "Smoke Bomb's duration is increased by 2 seconds.", "bonus_zone_duration", 2.0),
        "t2": ("Wider Smoke", "Smoke Bomb's radius is increased.", "bonus_zone_radius", 30.0),
        "t3": [
            ("Choking Smoke", "Enemies inside Smoke Bomb deal 30% less damage for 2s after leaving.", "bonus_enemy_damage_debuff", 0.30),
            ("Restorative Smoke", "Allies inside Smoke Bomb regenerate HP every second.", "bonus_ally_heal", 8.0),
            ("Shadow Smoke", "Allies inside Smoke Bomb enter stealth briefly when leaving.", "bonus_exit_stealth", 1.0),
        ],
    },
    "predators_patience_v1": {
        "prefix": "PRD",
        "t1": ("Sharper Patience", "Predator's Patience's per-stack bonus is increased.", "bonus_passive_potency", 0.005),
        "t2": ("Greater Patience", "Predator's Patience's max stacks is increased to 12.", "bonus_passive_cap", 2),
        "t3": [
            ("Eternal Patience", "Predator's Patience's bonus persists for 2 seconds after the ambush.", "bonus_carryover", 2.0),
            ("Killer Patience", "Each Patience stack also grants +1% critical hit chance.", "bonus_crit_per_stack", 0.01),
            ("Lifesteal Patience", "Ambush hits with full Patience heal you for 30% damage dealt.", "bonus_lifesteal_at_max", 0.30),
        ],
    },
    # ── STAFF ────────────────────────────────────────────────────────────────
    "frost_patch_v1": {
        "prefix": "FPT",
        "t1": ("Wider Frost", "Frost Patch's radius is increased.", "bonus_zone_radius", 20.0),
        "t2": ("Deep Frost", "Frost Patch's tick damage is increased by +25%.", "bonus_damage_mult", 0.25),
        "t3": [
            ("Glacial Frost", "Frost Patch enemies are also frozen briefly when entering.", "bonus_freeze_on_enter", 0.5),
            ("Lingering Frost", "Frost Patch's duration is increased to 6 seconds.", "bonus_zone_duration", 2.0),
            ("Shattering Frost", "Frost Patch's slow is increased to 70%.", "bonus_slow_pct", 0.20),
        ],
    },
    "arcane_familiar_v1": {
        "prefix": "AFM",
        "t1": ("Lasting Familiar", "Arcane Familiar's duration is increased by 4 seconds.", "bonus_summon_duration", 4.0),
        "t2": ("Quick Familiar", "Arcane Familiar's fire-rate is increased by +25%.", "bonus_fire_rate", 0.25),
        "t3": [
            ("Heavy Familiar", "Arcane Familiar's bolt damage is increased by +40%.", "bonus_damage_mult", 0.40),
            ("Chaining Familiar", "Arcane Familiar's bolts chain to 1 nearby enemy.", "bonus_chain_targets", 1),
            ("Twin Familiar", "Summons 2 familiars instead of 1.", "bonus_summon_count", 1),
        ],
    },
    "spellweave_v1": {
        "prefix": "SPW",
        "t1": ("Swift Weave", "Spellweave's max channel is reduced by 0.5 seconds.", "channel_time_reduction", 0.5),
        "t2": ("Heavy Weave", "Spellweave's released effect is amplified by +30%.", "bonus_damage_mult", 0.30),
        "t3": [
            ("Doubled Weave", "Spellweave's release happens twice (second after a 0.5s delay).", "bonus_double_release", 1),
            ("Wide Weave", "Spellweave's affected area is increased by 50%.", "bonus_zone_radius", 50.0),
            ("Echoing Weave", "Spellweave refunds 50% MP on cast if it hits any enemy.", "bonus_mp_refund", 0.50),
        ],
    },
    "mana_surge_v1": {
        "prefix": "MNS",
        "t1": ("Lingering Surge", "Mana Surge's mark duration is increased by 4 seconds.", "bonus_mark_duration", 4.0),
        "t2": ("Surging Refund", "Mana Surge's MP refund is increased to 65%.", "bonus_refund_pct", 0.15),
        "t3": [
            ("Multiplying Surge", "Mana Surge applies to 2 enemies.", "bonus_mark_targets", 1),
            ("Heavy Surge", "Mana Surge's damage bonus is increased to +75%.", "bonus_damage_bonus", 0.25),
            ("Cascading Surge", "When consumed, Mana Surge spreads to 1 nearby enemy.", "bonus_mark_spread", 1),
        ],
    },
    "stormcall_v1": {
        "prefix": "STC",
        "t1": ("Sustained Storm", "Stormcall's channel duration is increased by 1 second.", "channel_time_extension", 1.0),
        "t2": ("Heavy Storm", "Stormcall's per-tick damage is increased by +25%.", "bonus_damage_mult", 0.25),
        "t3": [
            ("Wide Storm", "Stormcall's radius is increased significantly.", "bonus_zone_radius", 40.0),
            ("Rapid Storm", "Stormcall's tick interval is halved (faster damage).", "bonus_tick_rate", 0.5),
            ("Chaining Storm", "Stormcall's strikes chain to 1 nearby enemy.", "bonus_chain_targets", 1),
        ],
    },
    "elemental_affinity_v1": {
        "prefix": "ELA",
        "t1": ("Greater Affinity", "Elemental Affinity's bonus is increased by +3%.", "bonus_passive_potency", 0.03),
        "t2": ("Mastery Affinity", "Elemental Affinity's bonus is increased by +5%.", "bonus_passive_potency", 0.05),
        "t3": [
            ("Crossover Affinity", "Elemental Affinity also grants +6% to spells of the previous-cycle element.", "bonus_carryover", 0.06),
            ("Mighty Affinity", "Elemental Affinity's bonus is doubled when at full mana.", "bonus_at_full_mp", 1.0),
            ("Sustained Affinity", "Elemental Affinity also reduces MP cost of matched spells by 10%.", "bonus_mp_reduction", 0.10),
        ],
    },
}


def render_upgrade_tres(prefix: str, tier_num: int, suffix: str, name: str, desc: str, point_cost: int, effect_key: str, magnitude: float, variant_group: str) -> str:
    upgrade_id = f"{prefix.lower()}_t{tier_num}_{suffix}"
    file_uid = gen_uid(upgrade_id, "upgrade")
    parts = []
    parts.append(f'[gd_resource type="Resource" script_class="AbilityUpgradeData" load_steps=2 format=3 uid="{file_uid}"]')
    parts.append('')
    parts.append(f'[ext_resource type="Script" uid="{UID_AB_UPGRADE_DATA}" path="res://scripts/Resources/AbilitySystem/AbilityUpgradeData.gd" id="1_aud"]')
    parts.append('')
    parts.append('[resource]')
    parts.append('script = ExtResource("1_aud")')
    parts.append(f'upgrade_id = "{upgrade_id}"')
    parts.append(f'upgrade_name = "{name}"')
    parts.append(f'description = "{desc}"')
    parts.append(f'point_cost = {point_cost}')
    parts.append(f'tier = {tier_num}')
    parts.append(f'variant_group = "{variant_group}"')
    parts.append(f'effect_key = "{effect_key}"')
    parts.append(f'magnitude = {magnitude}')
    return "\n".join(parts) + "\n"


def write_upgrades():
    upgrade_index = {}  # ability_id -> list of (filename, file_uid, ext_id_suffix)
    written = 0
    for spec in SPECS:
        ab_id = spec["id"]
        if ab_id not in UPGRADES:
            continue
        cfg = UPGRADES[ab_id]
        prefix = cfg["prefix"]
        weapon = spec["weapon"]
        upgrades_dir = os.path.join(ROOT, "resources", "Abilities", weapon, "Upgrades")
        os.makedirs(upgrades_dir, exist_ok=True)
        ab_upgrades = []
        # T1
        t1_name, t1_desc, t1_key, t1_mag = cfg["t1"]
        t1_slug = "_".join(t1_name.lower().split())
        t1_path = os.path.join(upgrades_dir, f"U_{prefix}_{t1_slug}.tres")
        with open(t1_path, "w", encoding="utf-8") as f:
            f.write(render_upgrade_tres(prefix, 1, t1_slug, t1_name, t1_desc, 1, t1_key, t1_mag, f"{prefix.lower()}_t1"))
        ab_upgrades.append((t1_path, gen_uid(f"{prefix.lower()}_t1_{t1_slug}", "upgrade")))
        written += 1
        # T2
        t2_name, t2_desc, t2_key, t2_mag = cfg["t2"]
        t2_slug = "_".join(t2_name.lower().split())
        t2_path = os.path.join(upgrades_dir, f"U_{prefix}_{t2_slug}.tres")
        with open(t2_path, "w", encoding="utf-8") as f:
            f.write(render_upgrade_tres(prefix, 2, t2_slug, t2_name, t2_desc, 1, t2_key, t2_mag, f"{prefix.lower()}_t2"))
        ab_upgrades.append((t2_path, gen_uid(f"{prefix.lower()}_t2_{t2_slug}", "upgrade")))
        written += 1
        # T3 variants
        for v_name, v_desc, v_key, v_mag in cfg["t3"]:
            v_slug = "_".join(v_name.lower().split())
            v_path = os.path.join(upgrades_dir, f"U_{prefix}_{v_slug}.tres")
            with open(v_path, "w", encoding="utf-8") as f:
                f.write(render_upgrade_tres(prefix, 3, v_slug, v_name, v_desc, 2, v_key, v_mag, f"{prefix.lower()}_t3_variant"))
            ab_upgrades.append((v_path, gen_uid(f"{prefix.lower()}_t3_{v_slug}", "upgrade")))
            written += 1
        upgrade_index[ab_id] = ab_upgrades
    print(f"Wrote {written} upgrade .tres files across {len(upgrade_index)} abilities.")
    return upgrade_index


def patch_ability_upgrades(upgrade_index):
    """For each parent A_*.tres, add the upgrade ext_resources + upgrades array field."""
    for spec in SPECS:
        ab_id = spec["id"]
        if ab_id not in upgrade_index:
            continue
        weapon = spec["weapon"]
        ab_path = os.path.join(ROOT, "resources", "Abilities", weapon, spec["filename"] + ".tres")
        if not os.path.exists(ab_path):
            print(f"  SKIP: {ab_path} not found")
            continue
        with open(ab_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Find existing max ext_resource id number (e.g. "8_sbf" → 8)
        ids = re.findall(r'id="(\d+)_[a-z0-9_]+"', content)
        next_id_num = (max(int(i) for i in ids) + 1) if ids else 100

        # Build new ext_resource lines for the upgrades + ext-id list for the array
        new_lines = []
        new_ext_ids = []
        for upg_path, upg_uid in upgrade_index[ab_id]:
            rel_path = "res://" + upg_path.replace("\\", "/").split("multiplayer-test-overhaul/")[-1]
            short_id = f"{next_id_num}_upg"
            new_lines.append(
                f'[ext_resource type="Resource" uid="{upg_uid}" path="{rel_path}" id="{short_id}"]'
            )
            new_ext_ids.append(short_id)
            next_id_num += 1

        # Also need the AbilityUpgradeData script ext_resource (so the
        # `Array[ExtResource("X_aud")]` typing works). Reuse from the gen
        # template — the existing tres files declare this script.
        aud_id = f"{next_id_num}_aud"
        new_lines.append(
            f'[ext_resource type="Script" uid="{UID_AB_UPGRADE_DATA}" path="res://scripts/Resources/AbilitySystem/AbilityUpgradeData.gd" id="{aud_id}"]'
        )
        next_id_num += 1

        # Insert after the last existing ext_resource line.
        ext_re = re.compile(r'^\[ext_resource[^\n]*\n', re.MULTILINE)
        last_match = None
        for m in ext_re.finditer(content):
            last_match = m
        if last_match is None:
            continue
        insertion_point = last_match.end()
        ext_block = "\n".join(new_lines) + "\n"
        content = content[:insertion_point] + ext_block + content[insertion_point:]

        # Now add the `upgrades = Array[ExtResource("X_aud")]([ExtResource("Y_upg"), ...])`
        # field to the [resource] section. Insert before `active_behavior =` if present,
        # or just before the last line.
        upgrades_field = f'upgrades = Array[ExtResource("{aud_id}")]([' + \
                         ", ".join(f'ExtResource("{eid}")' for eid in new_ext_ids) + \
                         '])\n'

        # Replace existing `upgrades = ...` line if any, else insert before active_behavior.
        if re.search(r'^upgrades = ', content, re.MULTILINE):
            content = re.sub(r'^upgrades = .*\n', upgrades_field, content, count=1, flags=re.MULTILINE)
        else:
            # Insert before active_behavior =
            ab_match = re.search(r'^active_behavior = ', content, re.MULTILINE)
            if ab_match:
                content = content[:ab_match.start()] + upgrades_field + content[ab_match.start():]
            else:
                # append at end
                content = content.rstrip() + "\n" + upgrades_field

        with open(ab_path, "w", encoding="utf-8") as f:
            f.write(content)
    print("Patched parent A_*.tres files with upgrade references.")


if __name__ == "__main__":
    upgrade_index = write_upgrades()
    patch_ability_upgrades(upgrade_index)
    print("\nDone. Re-open the project in Godot so it re-imports the new upgrade resources.")
