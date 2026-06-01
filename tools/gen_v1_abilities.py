#!/usr/bin/env python3
"""
v1 weapon-identity ability .tres generator.

Authors 22 new ability resources (18 actives + 4 passives across the four
weapon disciplines) by templating the existing A_VaultStrike / A_Aggression
.tres formats. The corresponding AL_*.gd logic scripts are already in
scripts/Abilities/; this tool wires them into AbilityData resources Godot's
ResourceManager can auto-load.

Run:  python tools/gen_v1_abilities.py
Out:  resources/Abilities/<Sword|Bow|Dagger|Staff>/A_<Name>.tres

Re-runnable: overwrites existing files in place. The UIDs are deterministic
(derived from the ability_id slug) so a re-run produces byte-identical output.

After running, also update the discipline .tres files
(resources/Player/Disciplines/<weapon>.tres) to add the new abilities to
each discipline's `skills` array — see the gen_discipline_register section
of this file (TODO marker).
"""

import os
import hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ─────────────────────────────────────────────────────────────────────────────
# Stable script UIDs — these are the existing project UIDs for the shared
# AbilityData / ActiveBehaviorData / AbilityScalingData / etc. scripts.
# Read from existing .tres files. Do not change.
# ─────────────────────────────────────────────────────────────────────────────
UID_ABILITY_DATA = "uid://b8y62rc8nb40j"          # AbilityData.gd
UID_ACTIVE_BEHAVIOR_DATA = "uid://1raaatfhww5y"   # ActiveBehaviorData.gd
UID_SCALING_DATA = "uid://csg6jvyvm5q1n"          # AbilityScalingData.gd
UID_SCALING_FORMULA = "uid://dnsex6fyou07d"       # AbilityScalingFormula.gd
UID_STAT_BONUS_FORMULA = "uid://bx4thfjsjclbw"    # StatBonusFormula.gd
UID_UPGRADE_DATA = "uid://baupgr1sword3"          # AbilityUpgradeData.gd


# ─────────────────────────────────────────────────────────────────────────────
# Class type constants (from scripts/Core/Enums/constants.gd ClassType enum)
# ─────────────────────────────────────────────────────────────────────────────
CLASS_SWORD = 0
CLASS_BOW = 1
CLASS_STAFF = 2
CLASS_DAGGER = 3

# Weapon types (from Constants.WeaponType — same ordering)
WPN_SWORD = 0
WPN_BOW = 1
WPN_STAFF = 2
WPN_DAGGER = 3

# Ability type
AB_TYPE_ACTIVE = 0
AB_TYPE_PASSIVE = 1


# ─────────────────────────────────────────────────────────────────────────────
# Ability specs — every new v1 ability defined here. Existing icons reused
# to avoid blocking on art (the icons can be swapped in the resource editor).
# ─────────────────────────────────────────────────────────────────────────────
# Fields:
#   id           : snake_case ability_id string (lookup key)
#   name         : display name
#   weapon       : "Sword" | "Bow" | "Dagger" | "Staff"
#   filename     : A_<name>.tres stem
#   al_script    : path to AL_*.gd in scripts/Abilities/
#   icon_path    : reuse existing sprite (the editor can replace)
#   description  : tooltip text (supports $[damage_percent] etc.)
#   kind         : "active" | "passive"
#   max_level    : 10 for actives, 5 for passives (v1 economy default)
#   damage_pct   : base + per_level for damage % formula (None if no damage)
#   mana         : (base, per_level) for mana cost
#   cooldown     : (base, per_level)
#   hits         : (base, per_level)
#   targets      : (base, per_level)
#   hitbox_size  : (width, height) for melee hitbox; None for utility/passive
#   hitbox_pos   : (x, y)
#   tree_path    : 0 or 1
#   tree_depth   : skill tree row
# ─────────────────────────────────────────────────────────────────────────────
SPECS = [
    # ─── SWORD ───────────────────────────────────────────────────────────────
    dict(id="charge_v1", name="Charge!", weapon="Sword", filename="A_Charge",
         al_script="res://scripts/Abilities/AL_Charge.gd",
         icon_path="res://assets/sprites/Abilities/Brandish.png",
         description="Rush forward in your facing direction, striking up to $[target_count] enemies for $[damage_percent] damage. [color=#e6c95c]+1 combo per enemy hit.[/color]",
         kind="active", max_level=10,
         damage_pct=(100.0, 4), mana=(5.0, 0.4), cooldown=(4.0, 0),
         hits=(1.0, 0), targets=(3.0, 0),
         hitbox_size=(110, 24), hitbox_pos=(55, -12),
         tree_path=0, tree_depth=4),

    dict(id="earthsplitter_v1", name="Earthsplitter", weapon="Sword", filename="A_Earthsplitter",
         al_script="res://scripts/Abilities/AL_Earthsplitter.gd",
         icon_path="res://assets/sprites/Abilities/power_strike.png",
         description="A heavy slam consumes ALL combo points to leave a tremor zone at your feet for 4s. Each combo point spent amplifies the per-tick damage by +75%. [color=#e6c95c]Ground-zone deals $[damage_percent] per tick.[/color]",
         kind="active", max_level=10,
         damage_pct=(80.0, 4), mana=(10.0, 0.5), cooldown=(8.0, 0),
         hits=(1.0, 0), targets=(8.0, 0),
         hitbox_size=(100, 30), hitbox_pos=(0, -15),
         tree_path=0, tree_depth=5),

    dict(id="onslaught_v1", name="Vanguard's Onslaught", weapon="Sword", filename="A_Onslaught",
         al_script="res://scripts/Abilities/AL_Onslaught.gd",
         icon_path="res://assets/sprites/Abilities/Brandish.png",
         description="Channel for up to 2 seconds. Release a forward thrust that PIERCES every enemy in a line, dealing $[damage_percent] damage. [color=#e6c95c]+1 combo per enemy pierced.[/color]",
         kind="active", max_level=10,
         damage_pct=(180.0, 8), mana=(8.0, 0.4), cooldown=(8.0, 0),
         hits=(1.0, 0), targets=(6.0, 0),
         hitbox_size=(180, 24), hitbox_pos=(90, -12),
         tree_path=1, tree_depth=5),

    dict(id="banner_v1", name="Banner of the Vanguard", weapon="Sword", filename="A_Banner",
         al_script="res://scripts/Abilities/AL_Banner.gd",
         icon_path="res://assets/sprites/Abilities/HP_Boost.png",
         description="Plant a banner at your feet for 8 seconds. Allies inside gain +Defense and HP regen each second. The vanguard's resolve.",
         kind="active", max_level=10,
         damage_pct=None, mana=(15.0, 0.6), cooldown=(20.0, 0),
         hits=None, targets=None,
         hitbox_size=None, hitbox_pos=None,
         tree_path=1, tree_depth=4),

    dict(id="sentinels_mark_v1", name="Sentinel's Mark", weapon="Sword", filename="A_SentinelsMark",
         al_script="res://scripts/Abilities/AL_SentinelsMark.gd",
         icon_path="res://assets/sprites/Abilities/power_strike.png",
         description="Mark one enemy for 8 seconds. While marked, sword hits on this target deal +30% damage and have a 25% chance to refund 1 combo point.",
         kind="active", max_level=10,
         damage_pct=(60.0, 2), mana=(4.0, 0.2), cooldown=(6.0, 0),
         hits=(1.0, 0), targets=(1.0, 0),
         hitbox_size=(30, 20), hitbox_pos=(15, -10),
         tree_path=0, tree_depth=3),

    dict(id="vanguards_resolve_v1", name="Vanguard's Resolve", weapon="Sword", filename="A_VanguardsResolve",
         al_script="res://scripts/Abilities/AL_VanguardsResolve.gd",
         icon_path="res://assets/sprites/Abilities/HP_Boost.png",
         description="While you carry 1 or more combo points, take $[stat_bonus] reduced damage (scales with combo: 1/2/3 combo = -8/-12/-16% at max level).",
         kind="passive", max_level=5,
         damage_pct=None, mana=None, cooldown=None,
         hits=None, targets=None,
         hitbox_size=None, hitbox_pos=None,
         tree_path=0, tree_depth=5),

    # ─── BOW ─────────────────────────────────────────────────────────────────
    dict(id="caltrops_v1", name="Caltrops", weapon="Bow", filename="A_Caltrops",
         al_script="res://scripts/Abilities/AL_Caltrops.gd",
         icon_path="res://assets/sprites/Abilities/strafe.png",
         description="Drop a patch of caltrops at your feet for 5 seconds. Enemies inside take $[damage_percent] damage per tick and are slowed by 30%.",
         kind="active", max_level=10,
         damage_pct=(50.0, 2), mana=(6.0, 0.3), cooldown=(10.0, 0),
         hits=None, targets=(6.0, 0),
         hitbox_size=None, hitbox_pos=None,
         tree_path=1, tree_depth=4),

    dict(id="sky_volley_v1", name="Sky Volley", weapon="Bow", filename="A_SkyVolley",
         al_script="res://scripts/Abilities/AL_SkyVolley.gd",
         icon_path="res://assets/sprites/Abilities/strafe.png",
         description="Channel for up to 3 seconds. Arrows rain in a wide area ahead of you, dealing $[damage_percent] damage every half-second. [color=#e6c95c]+1 Momentum per second held.[/color]",
         kind="active", max_level=10,
         damage_pct=(45.0, 2), mana=(12.0, 0.6), cooldown=(8.0, 0),
         hits=None, targets=(6.0, 0),
         hitbox_size=None, hitbox_pos=None,
         tree_path=0, tree_depth=4),

    dict(id="mark_of_the_hunt_v1", name="Mark of the Hunt", weapon="Bow", filename="A_MarkOfTheHunt",
         al_script="res://scripts/Abilities/AL_MarkOfTheHunt.gd",
         icon_path="res://assets/sprites/Abilities/double_shot.webp",
         description="Mark one enemy with a Hunter's Mark for 8 seconds. The next momentum-spender cast against this target is an AUTO-CRIT.",
         kind="active", max_level=10,
         damage_pct=None, mana=(5.0, 0.2), cooldown=(12.0, 0),
         hits=(1.0, 0), targets=(1.0, 0),
         hitbox_size=(160, 46), hitbox_pos=(80, -10),
         tree_path=1, tree_depth=3),

    dict(id="sundering_arrow_v1", name="Sundering Arrow", weapon="Bow", filename="A_SunderingArrow",
         al_script="res://scripts/Abilities/AL_SunderingArrow.gd",
         icon_path="res://assets/sprites/Abilities/double_shot.webp",
         description="Consumes all current Momentum to fire a heavy arrow that PIERCES every enemy in a line for $[damage_percent] damage each.",
         kind="active", max_level=10,
         damage_pct=(170.0, 8), mana=(10.0, 0.5), cooldown=(7.0, 0),
         hits=(1.0, 0), targets=(6.0, 0),
         hitbox_size=(220, 36), hitbox_pos=(110, -18),
         tree_path=0, tree_depth=5),

    dict(id="wind_rider_v1", name="Wind Rider", weapon="Bow", filename="A_WindRider",
         al_script="res://scripts/Abilities/AL_WindRider.gd",
         icon_path="res://assets/sprites/Abilities/strafe.png",
         description="Each Momentum stack reduces basic-attack delay by $[stat_bonus]%. The faster you build, the faster you fire.",
         kind="passive", max_level=5,
         damage_pct=None, mana=None, cooldown=None,
         hits=None, targets=None,
         hitbox_size=None, hitbox_pos=None,
         tree_path=1, tree_depth=5),

    # ─── DAGGER ──────────────────────────────────────────────────────────────
    dict(id="backstab_v1", name="Backstab", weapon="Dagger", filename="A_Backstab",
         al_script="res://scripts/Abilities/AL_Backstab.gd",
         icon_path="res://assets/sprites/Abilities/disorder.webp",
         description="A precise strike from the side opposite your target's facing. Deals normal damage PLUS +50% Weapon Attack as bonus damage when struck from behind.",
         kind="active", max_level=10,
         damage_pct=(80.0, 4), mana=(4.0, 0.2), cooldown=(5.0, 0),
         hits=(1.0, 0), targets=(1.0, 0),
         hitbox_size=(34, 22), hitbox_pos=(17, -10),
         tree_path=0, tree_depth=3),

    dict(id="death_mark_v1", name="Death Mark", weapon="Dagger", filename="A_DeathMark",
         al_script="res://scripts/Abilities/AL_DeathMark.gd",
         icon_path="res://assets/sprites/Abilities/disorder.webp",
         description="Mark one enemy for 8 seconds. Every dagger hit on the marked target has +25% critical hit chance.",
         kind="active", max_level=10,
         damage_pct=None, mana=(6.0, 0.2), cooldown=(10.0, 0),
         hits=(1.0, 0), targets=(1.0, 0),
         hitbox_size=(34, 22), hitbox_pos=(17, -10),
         tree_path=1, tree_depth=3),

    dict(id="vendetta_v1", name="Vendetta", weapon="Dagger", filename="A_Vendetta",
         al_script="res://scripts/Abilities/AL_Vendetta.gd",
         icon_path="res://assets/sprites/Abilities/disorder.webp",
         description="Consumes ALL Envenom poison stacks on the target for a burst of damage: $[damage_percent] base + 60% Weapon Attack per stack consumed.",
         kind="active", max_level=10,
         damage_pct=(120.0, 6), mana=(8.0, 0.4), cooldown=(6.0, 0),
         hits=(1.0, 0), targets=(1.0, 0),
         hitbox_size=(34, 22), hitbox_pos=(17, -10),
         tree_path=0, tree_depth=5),

    dict(id="smoke_bomb_v1", name="Smoke Bomb", weapon="Dagger", filename="A_SmokeBomb",
         al_script="res://scripts/Abilities/AL_SmokeBomb.gd",
         icon_path="res://assets/sprites/Abilities/disorder.webp",
         description="Drops a smoke cloud at your feet for 4 seconds. Allies inside gain +Evasion; enemies inside lose targeting on you (aggro drops briefly).",
         kind="active", max_level=10,
         damage_pct=None, mana=(10.0, 0.4), cooldown=(15.0, 0),
         hits=None, targets=None,
         hitbox_size=None, hitbox_pos=None,
         tree_path=1, tree_depth=4),

    dict(id="predators_patience_v1", name="Predator's Patience", weapon="Dagger", filename="A_PredatorsPatience",
         al_script="res://scripts/Abilities/AL_PredatorsPatience.gd",
         icon_path="res://assets/sprites/Abilities/disorder.webp",
         description="Each second out of stealth since your last ambush builds a Patience stack (max 10). Your next ambush gains +$[stat_bonus]% damage per stack.",
         kind="passive", max_level=5,
         damage_pct=None, mana=None, cooldown=None,
         hits=None, targets=None,
         hitbox_size=None, hitbox_pos=None,
         tree_path=0, tree_depth=5),

    # ─── STAFF ───────────────────────────────────────────────────────────────
    dict(id="frost_patch_v1", name="Frost Patch", weapon="Staff", filename="A_FrostPatch",
         al_script="res://scripts/Abilities/AL_FrostPatch.gd",
         icon_path="res://assets/sprites/Abilities/ice_strike.png",
         description="Cast a patch of frost at your feet for 4 seconds. Enemies inside take $[damage_percent] magic damage per tick and are chilled for 50% slow.",
         kind="active", max_level=10,
         damage_pct=(45.0, 2), mana=(10.0, 0.4), cooldown=(8.0, 0),
         hits=None, targets=(6.0, 0),
         hitbox_size=None, hitbox_pos=None,
         tree_path=0, tree_depth=4),

    dict(id="arcane_familiar_v1", name="Arcane Familiar", weapon="Staff", filename="A_ArcaneFamiliar",
         al_script="res://scripts/Abilities/AL_ArcaneFamiliar.gd",
         icon_path="res://assets/sprites/Abilities/magic_bolt.png",
         description="Summons a mini arcane wisp for 12 seconds. The familiar auto-casts an Arcane Bolt at nearby enemies for $[damage_percent] magic damage.",
         kind="active", max_level=10,
         damage_pct=(60.0, 3), mana=(20.0, 0.8), cooldown=(20.0, 0),
         hits=None, targets=None,
         hitbox_size=None, hitbox_pos=None,
         tree_path=1, tree_depth=4),

    dict(id="spellweave_v1", name="Spellweave", weapon="Staff", filename="A_Spellweave",
         al_script="res://scripts/Abilities/AL_Spellweave.gd",
         icon_path="res://assets/sprites/Abilities/magic_bolt.png",
         description="Channel for up to 2 seconds. Release an AMPLIFIED version of your current stance's signature: FIRE = larger pool, ICE = area freeze, LIGHTNING = +3 chain hops.",
         kind="active", max_level=10,
         damage_pct=(110.0, 5), mana=(18.0, 0.7), cooldown=(10.0, 0),
         hits=None, targets=(4.0, 0),
         hitbox_size=None, hitbox_pos=None,
         tree_path=0, tree_depth=5),

    dict(id="mana_surge_v1", name="Mana Surge", weapon="Staff", filename="A_ManaSurge",
         al_script="res://scripts/Abilities/AL_ManaSurge.gd",
         icon_path="res://assets/sprites/Abilities/magic_bolt.png",
         description="Mark one enemy with Mana Resonance for 8 seconds. Your next staff spell vs this target deals +50% damage AND refunds 50% of its MP cost.",
         kind="active", max_level=10,
         damage_pct=None, mana=(8.0, 0.3), cooldown=(12.0, 0),
         hits=(1.0, 0), targets=(1.0, 0),
         hitbox_size=(40, 30), hitbox_pos=(20, -15),
         tree_path=1, tree_depth=3),

    dict(id="stormcall_v1", name="Stormcall", weapon="Staff", filename="A_Stormcall",
         al_script="res://scripts/Abilities/AL_Stormcall.gd",
         icon_path="res://assets/sprites/Abilities/magic_bolt.png",
         description="Channel for 3 seconds. Lightning randomly strikes nearby enemies every half-second for $[damage_percent] magic damage. The staff's heaviest sustain.",
         kind="active", max_level=10,
         damage_pct=(55.0, 3), mana=(16.0, 0.7), cooldown=(12.0, 0),
         hits=None, targets=(5.0, 0),
         hitbox_size=None, hitbox_pos=None,
         tree_path=1, tree_depth=5),

    dict(id="elemental_affinity_v1", name="Elemental Affinity", weapon="Staff", filename="A_ElementalAffinity",
         al_script="res://scripts/Abilities/AL_ElementalAffinity.gd",
         icon_path="res://assets/sprites/Abilities/magic_bolt.png",
         description="While in a stance, spells whose element matches gain +$[stat_bonus]% damage. Commit to a stance, reap the payoff.",
         kind="passive", max_level=5,
         damage_pct=None, mana=None, cooldown=None,
         hits=None, targets=None,
         hitbox_size=None, hitbox_pos=None,
         tree_path=0, tree_depth=5),
]


# ─────────────────────────────────────────────────────────────────────────────
# UID generation — deterministic 16-char base32-ish per ability_id so a
# re-run produces byte-identical output but each ability has a unique uid.
# Godot's uid format is "uid://" + 13-char-ish base32 string.
# ─────────────────────────────────────────────────────────────────────────────
_BASE32 = "abcdefghijklmnopqrstuvwxyz234567"

def gen_uid(label: str, salt: str = "") -> str:
    h = hashlib.sha256((label + ":" + salt).encode()).digest()
    chars = []
    for i in range(13):
        chars.append(_BASE32[h[i] & 0x1f])
    return "uid://" + "".join(chars)


# ─────────────────────────────────────────────────────────────────────────────
# CLASS_TYPE / WPN_TYPE mapping
# ─────────────────────────────────────────────────────────────────────────────
WEAPON_TO_CLASS = {"Sword": CLASS_SWORD, "Bow": CLASS_BOW, "Staff": CLASS_STAFF, "Dagger": CLASS_DAGGER}
WEAPON_TO_WPN = {"Sword": WPN_SWORD, "Bow": WPN_BOW, "Staff": WPN_STAFF, "Dagger": WPN_DAGGER}


# ─────────────────────────────────────────────────────────────────────────────
# Render an A_*.tres file from a spec.
# ─────────────────────────────────────────────────────────────────────────────
def render_active_tres(spec: dict) -> str:
    """Active ability tres — needs hitbox, scaling formulas for damage/mana/CD/hits/targets."""
    file_uid = gen_uid(spec["id"], "file")
    icon_uid = gen_uid(spec["id"], "icon")
    al_uid = gen_uid(spec["id"], "al")

    needs_hitbox = spec.get("hitbox_size") is not None
    has_damage = spec.get("damage_pct") is not None

    parts = []
    parts.append(f'[gd_resource type="Resource" script_class="AbilityData" load_steps=20 format=3 uid="{file_uid}"]')
    parts.append('')
    # ext_resources
    parts.append(f'[ext_resource type="Texture2D" path="{spec["icon_path"]}" id="1_icon"]')
    parts.append(f'[ext_resource type="Script" uid="{UID_ACTIVE_BEHAVIOR_DATA}" path="res://scripts/Resources/AbilitySystem/ActiveBehaviorData.gd" id="2_abd"]')
    parts.append(f'[ext_resource type="Script" path="{spec["al_script"]}" id="3_al"]')
    parts.append(f'[ext_resource type="Script" uid="{UID_ABILITY_DATA}" path="res://scripts/Resources/AbilitySystem/AbilityData.gd" id="4_ad"]')
    parts.append(f'[ext_resource type="Script" uid="{UID_SCALING_FORMULA}" path="res://scripts/Resources/AbilitySystem/AbilityScalingFormula.gd" id="5_asf"]')
    parts.append(f'[ext_resource type="Script" uid="{UID_SCALING_DATA}" path="res://scripts/Resources/AbilitySystem/AbilityScalingData.gd" id="7_asd"]')
    parts.append(f'[ext_resource type="Script" uid="{UID_STAT_BONUS_FORMULA}" path="res://scripts/Resources/AbilitySystem/StatBonusFormula.gd" id="8_sbf"]')
    parts.append('')

    # sub_resources
    if needs_hitbox:
        w, h = spec["hitbox_size"]
        parts.append(f'[sub_resource type="RectangleShape2D" id="RectangleShape2D_hit"]')
        parts.append(f'size = Vector2({w}, {h})')
        parts.append('')

    # active_behavior
    parts.append('[sub_resource type="Resource" id="Resource_active"]')
    parts.append('script = ExtResource("2_abd")')
    parts.append('target_type = 1')
    if needs_hitbox:
        parts.append('hit_box_shape_data = SubResource("RectangleShape2D_hit")')
        x, y = spec["hitbox_pos"]
        parts.append(f'hit_box_position_data = Vector2({x}, {y})')
    parts.append('animation_name = "attack_1"')
    parts.append('sfx_path = "res://assets/sounds/tap.wav"')
    parts.append('logic_script = ExtResource("3_al")')
    parts.append('')

    # scaling formulas
    def emit_formula(sub_id: str, base: float, per: float):
        parts.append(f'[sub_resource type="Resource" id="{sub_id}"]')
        parts.append('script = ExtResource("5_asf")')
        parts.append(f'base_value = {base}')
        if per != 0:
            parts.append(f'per_level = {per}')
        parts.append('')

    emit_formula("Resource_cast", 0.0, 0)
    cd_b, cd_p = spec.get("cooldown", (0.0, 0)) or (0.0, 0)
    emit_formula("Resource_cd", cd_b, cd_p)
    if has_damage:
        d_b, d_p = spec["damage_pct"]
        emit_formula("Resource_dmg", d_b, d_p)
    m_b, m_p = spec.get("mana", (0.0, 0)) or (0.0, 0)
    emit_formula("Resource_mana", m_b, m_p)
    if spec.get("hits"):
        h_b, h_p = spec["hits"]
        emit_formula("Resource_hits", h_b, h_p)
    if spec.get("targets"):
        t_b, t_p = spec["targets"]
        emit_formula("Resource_tgts", t_b, t_p)

    # scaling_data
    parts.append('[sub_resource type="Resource" id="Resource_scaling"]')
    parts.append('script = ExtResource("7_asd")')
    parts.append('mana_cost_formula = SubResource("Resource_mana")')
    parts.append('cooldown_formula = SubResource("Resource_cd")')
    if has_damage:
        parts.append('damage_percent_formula = SubResource("Resource_dmg")')
    if spec.get("targets"):
        parts.append('max_targets_formula = SubResource("Resource_tgts")')
    if spec.get("hits"):
        parts.append('max_hits_formula = SubResource("Resource_hits")')
    parts.append('cast_time_formula = SubResource("Resource_cast")')
    parts.append('')

    # [resource]
    parts.append('[resource]')
    parts.append('script = ExtResource("4_ad")')
    parts.append(f'ability_id = "{spec["id"]}"')
    parts.append(f'ability_name = "{spec["name"]}"')
    parts.append(f'description = "{spec["description"]}"')
    parts.append('ability_icon = ExtResource("1_icon")')
    parts.append(f'max_level = {spec["max_level"]}')
    parts.append('ability_type = 0')  # ACTIVE
    parts.append(f'required_class = Array[int]([{WEAPON_TO_CLASS[spec["weapon"]]}])')
    parts.append(f'required_weapon_types = Array[int]([{WEAPON_TO_WPN[spec["weapon"]]}])')
    parts.append(f'tree_path = {spec["tree_path"]}')
    parts.append(f'tree_depth = {spec["tree_depth"]}')
    parts.append('active_behavior = SubResource("Resource_active")')
    parts.append('scaling_data = SubResource("Resource_scaling")')

    return "\n".join(parts) + "\n"


def render_passive_tres(spec: dict) -> str:
    """Passive — no hitbox, no scaling formulas typically; just active_behavior wrapping the logic script."""
    file_uid = gen_uid(spec["id"], "file")
    parts = []
    parts.append(f'[gd_resource type="Resource" script_class="AbilityData" load_steps=8 format=3 uid="{file_uid}"]')
    parts.append('')
    parts.append(f'[ext_resource type="Texture2D" path="{spec["icon_path"]}" id="1_icon"]')
    parts.append(f'[ext_resource type="Script" uid="{UID_ACTIVE_BEHAVIOR_DATA}" path="res://scripts/Resources/AbilitySystem/ActiveBehaviorData.gd" id="2_abd"]')
    parts.append(f'[ext_resource type="Script" uid="{UID_SCALING_DATA}" path="res://scripts/Resources/AbilitySystem/AbilityScalingData.gd" id="3_asd"]')
    parts.append(f'[ext_resource type="Script" uid="{UID_STAT_BONUS_FORMULA}" path="res://scripts/Resources/AbilitySystem/StatBonusFormula.gd" id="4_sbf"]')
    parts.append(f'[ext_resource type="Script" uid="{UID_ABILITY_DATA}" path="res://scripts/Resources/AbilitySystem/AbilityData.gd" id="6_ad"]')
    parts.append(f'[ext_resource type="Script" path="{spec["al_script"]}" id="11_al"]')
    parts.append('')

    parts.append('[sub_resource type="Resource" id="Resource_active"]')
    parts.append('resource_local_to_scene = true')
    parts.append('script = ExtResource("2_abd")')
    parts.append('logic_script = ExtResource("11_al")')
    parts.append('')

    parts.append('[sub_resource type="Resource" id="Resource_scaling"]')
    parts.append('script = ExtResource("3_asd")')
    parts.append('')

    parts.append('[resource]')
    parts.append('script = ExtResource("6_ad")')
    parts.append(f'ability_id = "{spec["id"]}"')
    parts.append(f'ability_name = "{spec["name"]}"')
    parts.append(f'description = "{spec["description"]}"')
    parts.append('ability_icon = ExtResource("1_icon")')
    parts.append(f'max_level = {spec["max_level"]}')
    parts.append('ability_type = 1')  # PASSIVE
    parts.append(f'required_class = Array[int]([{WEAPON_TO_CLASS[spec["weapon"]]}])')
    parts.append(f'required_weapon_types = Array[int]([{WEAPON_TO_WPN[spec["weapon"]]}])')
    parts.append(f'tree_path = {spec["tree_path"]}')
    parts.append(f'tree_depth = {spec["tree_depth"]}')
    parts.append('active_behavior = SubResource("Resource_active")')
    parts.append('scaling_data = SubResource("Resource_scaling")')

    return "\n".join(parts) + "\n"


def write_all() -> None:
    counts = {"Sword": 0, "Bow": 0, "Dagger": 0, "Staff": 0}
    written = []
    for spec in SPECS:
        weapon_dir = os.path.join(ROOT, "resources", "Abilities", spec["weapon"])
        os.makedirs(weapon_dir, exist_ok=True)
        out_path = os.path.join(weapon_dir, spec["filename"] + ".tres")
        if spec["kind"] == "passive":
            content = render_passive_tres(spec)
        else:
            content = render_active_tres(spec)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(content)
        counts[spec["weapon"]] += 1
        written.append(out_path)
    print(f"Wrote {len(written)} ability resources:")
    for w, c in counts.items():
        print(f"  {w}: {c}")
    return written


# ─────────────────────────────────────────────────────────────────────────────
# Discipline .tres registration — adds the new abilities to the per-weapon
# `skills` array so Godot picks them up at game start.
#
# Discipline file format:
#   - ext_resource lines with id="N_yyy" referencing each ability .tres
#   - `skills = Array[ExtResource(...)]([ExtResource("..."), ...])` line that
#     lists every ability the discipline grants.
#
# We append our new ext_resources after the existing ones (with a unique id
# prefix per ability) and append the same ids to the skills array.
# ─────────────────────────────────────────────────────────────────────────────
import re

def register_disciplines() -> None:
    by_weapon = {"Sword": [], "Bow": [], "Dagger": [], "Staff": []}
    for spec in SPECS:
        by_weapon[spec["weapon"]].append(spec)

    for weapon, specs in by_weapon.items():
        if not specs:
            continue
        disc_path = os.path.join(ROOT, "resources", "Player", "Disciplines", weapon.lower() + ".tres")
        if not os.path.exists(disc_path):
            print(f"  SKIP: {disc_path} not found")
            continue

        with open(disc_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Find the highest existing ext_resource id number ("18_bh" -> 18)
        ids = re.findall(r'id="(\d+)_[a-z0-9_]+"', content)
        next_id_num = (max(int(i) for i in ids) + 1) if ids else 1

        # Build new ext_resource block (one line per new ability)
        new_ext_lines = []
        new_ext_refs = []  # for the skills array append
        for spec in specs:
            file_uid = gen_uid(spec["id"], "file")
            rel_path = f"res://resources/Abilities/{weapon}/{spec['filename']}.tres"
            short_id = f"{next_id_num}_{spec['id'][:6]}"
            new_ext_lines.append(
                f'[ext_resource type="Resource" uid="{file_uid}" path="{rel_path}" id="{short_id}"]'
            )
            new_ext_refs.append(short_id)
            next_id_num += 1

        # Insert new ext_resource lines after the LAST existing ext_resource line.
        # Find all ext_resource lines and grab the last one's position.
        ext_re = re.compile(r'^\[ext_resource[^\n]*\n', re.MULTILINE)
        last_match = None
        for m in ext_re.finditer(content):
            last_match = m
        if last_match is None:
            print(f"  ERROR: no ext_resource lines found in {disc_path}")
            continue

        insertion_point = last_match.end()
        ext_block = "\n".join(new_ext_lines) + "\n"
        content = content[:insertion_point] + ext_block + content[insertion_point:]

        # Append new IDs to the `skills` array. The line looks like:
        #   skills = Array[ExtResource("3_lkye1")]([ExtResource("6_kdifu"), ...])
        skills_re = re.compile(r'(skills = Array\[ExtResource\("[^"]+"\)\]\(\[)([^\]]*)(\]\))')
        m = skills_re.search(content)
        if not m:
            print(f"  ERROR: could not find skills array in {disc_path}")
            continue
        prefix, body, suffix = m.group(1), m.group(2), m.group(3)
        # Append our new refs
        if body.strip() and not body.rstrip().endswith(","):
            body = body.rstrip() + ", "
        new_refs_str = ", ".join(f'ExtResource("{rid}")' for rid in new_ext_refs)
        new_skills_line = prefix + body + new_refs_str + suffix
        content = content[:m.start()] + new_skills_line + content[m.end():]

        with open(disc_path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"  Registered {len(specs)} new abilities in {weapon.lower()}.tres")


if __name__ == "__main__":
    write_all()
    print("\nRegistering new abilities in discipline files...")
    register_disciplines()
    print("\nDone. Re-open the project in Godot so it re-imports the new resources.")
