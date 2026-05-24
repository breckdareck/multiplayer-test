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

**`QuestData` follows the same pattern, but owned by `QuestManager`** —
`QuestManager._load_quests_from_resources()` recursively scans
`resources/Quests/` on `_ready()` and keys each loaded `QuestData` by its
`quest_id` string. Look quests up with `QuestManager.get_quest_data(id)`.
Quests live in chain-themed subfolders (`Beginner/`, `Early/`, `Mid/`,
`Advancement/`, `EndlessHunt/`, `SlimeThreat/`) so they're discoverable by
narrative role rather than alphabetic dump. To add a quest, drop a new
`.tres` under the right subfolder — no code change required.

**Exception — enemies are NOT auto-loaded.** `EnemyData` (`resources/Enemies/`) is
referenced directly by an exported `enemy_data` on each enemy scene, not via
`ResourceManager`.

### QuestData author notes

- **`quest_id` is a hand-authored stable string, not a UUID.** Player save data
  persists references to it (`_active_quests`, `_completed_quests`,
  `_tracked_quests`) and scene files bake it into NPC `offered_quest_ids` arrays
  in `town.tscn` / `game.tscn`. Renaming a `quest_id` is a breaking change —
  existing characters lose progress on the renamed quest.
- **`KILL` objective `target` strings match exactly on `EnemyData.monster_name`** —
  past bugs shipped quests targeting non-existent enemy names that silently
  never completed.
- **`reward_items` are item NAMES** (e.g. `"Health Potion"`), resolved by
  `ResourceManager.get_item_by_name` at completion time. Mismatches `push_warning`
  but silently skip the reward.
- **`sort_order: int`** controls display order in the Q-window's Available tab
  and `QuestGiverDialog` rows. Lower values appear first; use ~10-unit spacing
  (10, 20, 30, ...) so new quests can slot in between existing ones without
  renumbering. Without it, `ResourceLoader.list_directory` returns filesystem
  (alphabetical) order, which scrambles narrative flow.
- **`npc_only: bool`** (default false): hide a quest from the Q-window's
  Available tab so it can ONLY be obtained through a `QuestGiverNPC` whose
  `offered_quest_ids` includes it. Use for NPC-locked chains (e.g. the
  Village Elder's Endless Hunt 15/50/99/999) where the journal shouldn't
  spoil quests meant to be discovered through dialogue. Once accepted the
  quest behaves normally — it appears in the Active / Completed tabs and in
  the Quest Tracker HUD like any other.
- **`objectives: Array[Dictionary]`** is the per-objective list. Each dict is
  `{"type": int, "target": String, "amount": int}` where `type` is the int
  value of `QuestData.ObjectiveType` (`KILL = 0`, `COLLECT = 1`,
  `REACH_LEVEL = 2`). The generic inspector renders this as expandable
  dictionaries — workable but clunky; you author the keys by hand. A future
  improvement is wrapping each objective in a typed `QuestObjective` Resource
  subclass for dropdowns/validation, but it would require updating every
  `obj.get("type", ...)` read site in `quest_manager.gd`.

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
