# Ability field reference

Companion to the `add-ability` skill. Class definitions live in
`scripts/Resources/AbilitySystem/`.

## AbilityData

| Field | Type | Notes |
|---|---|---|
| `ability_id` | String | Leave blank — auto-generated UUID |
| `ability_name` | String | Human-readable; most code looks abilities up by this |
| `description` | String (multiline) | |
| `ability_icon` | Texture2D | |
| `max_level` | int | |
| `ability_type` | `Constants.AbilityType` | `ACTIVE` or `PASSIVE` |
| `damage_stat` | `Constants.StatType` | Defaults to `WEAPONATTACK` |
| `required_class` | Array[ClassType] | |
| `required_weapon_types` | Array[WeaponType] | |
| `prerequisite_abilities` | Dictionary[AbilityData, int] | ability → required level |
| `active_behavior` | `ActiveBehaviorData` | Active abilities only |
| `applies_buff` | `BuffData` | Buff applied to caster/allies |
| `buff_duration_formula` | `AbilityScalingFormula` | |
| `applies_target_debuff` | `BuffData` | Debuff applied to each enemy hit |
| `debuff_duration_formula` | `AbilityScalingFormula` | |
| `use_scaling_formulas` | bool | `true` (default) → use `scaling_data` |
| `scaling_data` | `AbilityScalingData` | Per-level formulas |
| `level_data` | Array[AbilityLevelData] | Only used when `use_scaling_formulas = false` |

`get_level_stats(level)` returns an `AbilityLevelData` — generated from
`scaling_data` and cached, or read from `level_data` when formulas are off.

## ActiveBehaviorData

`target_type` (`TargetType`), `hit_box_shape_data` (`Shape2D`),
`hit_box_position_data` (`Vector2`), `animation_name`, `sfx_path`,
`logic_script` (`Script` — the `AL_` script), `is_projectile`,
`projectile_scene` (`PackedScene`), `projectile_speed`.

## AbilityScalingFormula

`scaling_type`: `FLAT` (`base_value + (level-1) * per_level`),
`MULTIPLICATIVE` (`base_value * multiplier^(level-1)`), `STEPPED`
(`step_values` breakpoints), `CUSTOM` (`custom_formula` expression with
variables `level`, `base_value`). `calculate(level)` evaluates it.

## AbilityScalingData

Formulas: `mana_cost_formula`, `cooldown_formula`, `damage_percent_formula`,
`max_targets_formula`, `max_hits_formula`, `cast_time_formula`,
`status_effect_chance_formula`, `status_effect_duration_formula`,
`range_multiplier_formula`, `knockback_force_formula`, plus aura and proc
formulas. `stat_bonus_formulas: Array[StatBonusFormula]` drives **passive** stat
bonuses. `generate_level_data(level)` builds the `AbilityLevelData`.

## AL_ logic script contract

Assigned to `active_behavior.logic_script`. `AbilityComponent` does
`logic_script.new()` then `execute(owner, ability, level_stats)` on every cast,
on the server, after the attack state transition.

```gdscript
extends Node

func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData):
    if not owner_node.multiplayer.is_server():
        return
    # owner_node = the casting character node.
    # Components: owner_node.get_node_or_null("Components/Buff"), ".../Health", etc.
    # Buffs: buff_component.apply_buff(buff_id_or_name, owner_node, duration)
```

See `scripts/Abilities/AL_Haste.gd` for a worked party-buff example.

## Passive logic

A passive may instead use `AbilityLevelData.passive_logic_script` with
`on_passive_acquired(owner, level_data)`, `on_passive_removed(owner, level_data)`,
and `process(owner, level_data, delta)`. Simple passive stat bonuses need no
script — just `scaling_data.stat_bonus_formulas`.
