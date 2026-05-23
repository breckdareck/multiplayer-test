---
name: add-ability
description: >-
  Use when creating or editing a player ability/skill — active attacks, buffs,
  or passives — for this Godot RPG. Covers the AbilityData .tres, scaling
  formulas, custom AL_ logic scripts, and registering the ability to a class.
paths: resources/Abilities/**, scripts/Abilities/**
---

# Adding an ability

Abilities are data-driven `AbilityData` resources. `ResourceManager` auto-loads
everything under `resources/Abilities/` on startup — there is **no manual
registration step**. Full field/formula reference:
[references/ability-fields.md](references/ability-fields.md).

The `addons/resource_editor/` editor dock has a dedicated ability editor (formula
and level editor, hitbox visualizer) — prefer it over the raw inspector.

## Steps

1. **Create the resource.** Add an `AbilityData` `.tres` under the class folder in
   `resources/Abilities/<Class>/` (`Warrior/`, `Archer/`, `Mage/`, `Rogue/`).
   Leave `ability_id` blank — a UUID is generated automatically.

2. **Core fields.** Set `ability_name`, `description`, `ability_icon`,
   `max_level`, `ability_type` (`ACTIVE` or `PASSIVE`), `required_class`, and
   `required_weapon_types`.

3. **Active behavior** (active abilities). Set `active_behavior`
   (`ActiveBehaviorData`): `target_type`, `hit_box_shape_data`,
   `hit_box_position_data`, `animation_name`, `sfx_path`. For a projectile, set
   `is_projectile`, `projectile_scene`, and `projectile_speed`.

4. **Scaling.** Fill `scaling_data` (`AbilityScalingData`) — one
   `AbilityScalingFormula` per stat (`mana_cost_formula`, `cooldown_formula`,
   `damage_percent_formula`, …). A `FLAT` formula is
   `base_value + (level - 1) * per_level`. Abilities are formula-only; there
   is no manual level-data array.

5. **Custom logic** (optional). If the ability does anything beyond a hitbox or
   projectile, write `scripts/Abilities/AL_<Name>.gd` and assign it to
   `active_behavior.logic_script`. Contract — `extends Node`, and:
   ```gdscript
   func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData):
       if not owner_node.multiplayer.is_server():
           return
       # owner_node is the casting character; reach components via
       # owner_node.get_node_or_null("Components/Buff") etc.
   ```

6. **Buffs / debuffs** (optional). To buff the caster or allies set `applies_buff`
   (+ `buff_duration_formula`); to debuff enemies hit set `applies_target_debuff`
   (+ `debuff_duration_formula`). Create the buff with the `add-buff` skill.

7. **Passives.** Set `ability_type = PASSIVE`; put stat bonuses in
   `scaling_data.stat_bonus_formulas`, or proc effects in the `proc_*` fields.

8. **Register to a class.** Open the class `.tres` in
   `resources/Player/Classes/` and add the new `AbilityData` to its `skills`
   array. Gate the unlock with the ability's `prerequisite_abilities`.

9. **Test.** Run the game, create or load a character of the class, spend points
   to learn/level the ability, and cast it from the hotbar.
