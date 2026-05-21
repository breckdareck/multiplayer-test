---
name: add-buff
description: >-
  Use when creating or editing a buff or debuff for this Godot RPG — a timed
  stat modifier or a reactive effect (damage-over-time, on-hit reactions).
  Covers the BuffData .tres and custom BL_ logic scripts.
paths: resources/Buffs/**, scripts/Buffs/**
---

# Adding a buff

Buffs are data-driven `BuffData` resources. `ResourceManager` auto-loads
everything under `resources/Buffs/` on startup — **no manual registration**.
`BuffComponent` (`scripts/Components/buff.gd`) applies, stacks, ticks, and expires
them; all of that runs server-side.

## Steps

1. **Create the resource.** Add a `BuffData` `.tres` under `resources/Buffs/`.
   Leave `buff_id` blank — a UUID is generated automatically.

2. **Core fields.**
   - `buff_name`, `description`, `buff_icon`
   - `duration` — seconds; **`0` = permanent** until removed explicitly
   - `is_debuff` — beneficial vs. harmful
   - `stack_behavior` — `REFRESH` (reset duration), `STACK` (add a stack, up to
     `max_stacks`), or `IGNORE` (keep the existing buff)
   - `max_stacks` — only used when `stack_behavior = STACK`

3. **Stat modifiers.** Fill `stat_modifiers` (`Dictionary[StatType, StatData]`).
   Use `flat_bonus_value` / `percent_bonus_value` on each `StatData`; bonuses are
   multiplied by the current stack count. `StatsComponent` picks them up
   automatically — do not also write a logic script just to change stats.

4. **Custom / reactive logic** (optional). For effects beyond static stats
   (damage-over-time, on-hit reactions, invisibility), write
   `scripts/Buffs/BL_<Name>.gd` and assign it to `logic_script`. Contract —
   `extends Node`, with any of these optional methods:
   ```gdscript
   func on_apply(owner, active_buff) -> void:
   func on_remove(owner, active_buff) -> void:
   func on_tick(owner, active_buff, delta) -> void:      # every server frame
   func on_damaged(owner, active_buff, amount, source) -> void:  # owner took damage
   ```
   `owner` is the character. Ticking and `on_damaged` only fire on the server.
   See `scripts/Buffs/BL_Haste.gd` for the simplest example.

5. **Apply it.** From code: `buff_component.apply_buff(buff_id_or_name, source,
   optional_duration)`. From an ability: set the ability's `applies_buff` or
   `applies_target_debuff` (see the `add-ability` skill).

6. **Test.** Trigger the buff in-game and confirm the icon, duration, stacking,
   and stat changes behave as intended.
