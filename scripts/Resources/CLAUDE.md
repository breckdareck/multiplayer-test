# Data resource classes

GDScript class definitions for the game's data-driven content. The **classes** live
here; the **data instances** (`.tres` files) live under `resources/`.

## Subfolders

| Folder | Classes |
|---|---|
| `AbilitySystem/` | `AbilityData`, `AbilityLevelData`, `AbilityScalingData`, `AbilityScalingFormula`, `ActiveBehaviorData`, `ProcEffectData`, `StatBonusFormula` |
| `BuffSystem/` | `BuffData` (with the `StackBehavior` enum) |
| `ClassSystem/` | `ClassData` |
| `ItemSystem/` | `ItemData` → `EquipmentData` → `ArmorData` / `WeaponData`; `ConsumableData`; `ItemDrop.gd` (class `ItemDropResource`); `DroppedItem`; `Effects/` |
| `StatSystem/` | `StatData` |
| `QuestSystem/` | `QuestData` |
| (root) | `EnemyData.gd` |

## ResourceManager loads most of this for free

`ResourceManager` recursively scans these folders on startup and indexes every
`.tres` / `.res` it finds — **no manual registration**:

- `resources/Abilities/` → `AbilityData`, keyed by `ability_id` and `ability_name`
- `resources/Buffs/` → `BuffData`, keyed by `buff_id` and `buff_name`
- `resources/Items/` → `ItemData`, keyed by `item_id` and `name`
- `resources/Player/Classes/` → `ClassData`, keyed by `class_type`

Look content up with `ResourceManager.get_ability_data(id_or_name)`,
`get_item_by_name(name)`, etc. — never `load()` content `.tres` at runtime.

**Exception — enemies are NOT auto-loaded.** `EnemyData` (`resources/Enemies/`) is
referenced directly by an exported `enemy_data` on each enemy scene, not via
`ResourceManager`.

**Exception — quests are NOT data-driven.** `QuestData` carries `@export` fields
for future `.tres` authoring, but the live quest list is registered in code by
`_define_quests()` on `QuestManager`. There is no `resources/Quests/` folder.
`KILL` objectives match exactly on `EnemyData.monster_name`, so the target
string must be the same one set on the enemy `.tres` — past bugs shipped
quests targeting non-existent enemy names that silently never completed.

`QuestData.npc_only` (bool, default false): set true to hide a quest from the
Q-window's Available tab so it can ONLY be obtained through a `QuestGiverNPC`
whose `offered_quest_ids` includes it. Use for NPC-locked chains (e.g. the
Village Elder's Endless Hunt 15/50/99/999) where the journal shouldn't
spoil quests that are meant to be discovered through dialogue. After accept,
the quest behaves normally — it appears in the Active / Completed tabs and
in the Quest Tracker HUD like any other.

## Conventions

- `AbilityData`, `BuffData`, and `ItemData` carry an **auto-generated UUID** id
  (`ability_id` / `buff_id` / `item_id`). Leave the id blank in the editor — a
  fresh UUID is generated in the setter / `_init()`. Lookups also work by
  human-readable name, which is how most code references content.
- Most resource classes are marked `@tool` so they preview live in the editor and
  in the `addons/resource_editor/` dock.
- **Stats** are `StatData`: `base_value` + `flat_bonus_value` + `percent_bonus_value`,
  with `total_value` as the derived sum. Equipment and buff bonuses use
  `flat_bonus_value` / `percent_bonus_value`; leave `base_value` to the character.
- Items persist **slim** — only instance data (canonical path, id, stack count, and
  `variant` rolls). All static fields are re-derived from the canonical `.tres` on
  load. Don't add a field expecting it to round-trip per-instance unless you also
  extend the variant serialization (`_append_variant_data` / `_apply_variant_data`).
- `ClassData.starter_ability` is the ability auto-granted at **level 1** to a
  brand-new character of that class. New class `.tres` files should set it so the
  player has a castable skill from spawn — otherwise classes whose basic attack
  is weak (Mage's staff has only +3 WEAPONATTACK) feel unplayable before earning
  their first ability point. Returning characters keep their saved levels;
  the auto-grant only matters on first creation.

## Creating content

Use the matching skill — each walks the full recipe and field list: `add-ability`,
`add-buff`, `add-item`, `add-enemy`.
