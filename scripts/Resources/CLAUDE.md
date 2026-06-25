# Data resource classes

GDScript class definitions for the game's data-driven content. The **classes** live
here; the **data instances** (`.tres` files) live under `resources/`.

## Subfolders

| Folder | Classes |
|---|---|
| `AbilitySystem/` | `AbilityData`, `AbilityLevelData`, `AbilityScalingData`, `AbilityScalingFormula`, `ActiveBehaviorData`, `ProcEffectData`, `StatBonusFormula` |
| `BuffSystem/` | `BuffData` (with the `StackBehavior` enum) |
| `DisciplineSystem/` | `WeaponDisciplineData` (the starting weapon family and its passive scaling — previously `ClassData`) |
| `ItemSystem/` | `ItemData` → `EquipmentData` → `ArmorData` / `WeaponData`; `ConsumableData` → `PetFoodData` / `PetSkillBookData`; `ItemDrop.gd` (class `ItemDropResource`); `DroppedItem`; `Effects/` |
| `PetSystem/` | `PetData` (the static pet variety definition — sprite, walk speed, leash radius, autoloot radius, hunger curve) |
| `StatSystem/` | `StatData` |
| `QuestSystem/` | `QuestData` |
| (root) | `EnemyData.gd`, `BossAttackData.gd` |

## ResourceManager loads most of this for free

`ResourceManager` recursively scans these folders on startup and indexes every
`.tres` / `.res` it finds — **no manual registration**:

- `resources/Abilities/` → `AbilityData`, keyed by `ability_id` and `ability_name`
- `resources/Buffs/` → `BuffData`, keyed by `buff_id` and `buff_name`
- `resources/Items/` → `ItemData`, keyed by `item_id` and `name`
- `resources/Player/Disciplines/` → `WeaponDisciplineData`, keyed by `class_type` (the `ClassType` enum still names the field; semantically it's a weapon discipline now)

Look content up with `ResourceManager.get_ability_data(id_or_name)`,
`get_item_by_name(name)`, etc. — never `load()` content `.tres` at runtime.

**Loading is split for startup speed.** Disciplines + buffs load synchronously in
`_ready()` (they have early consumers — the character-select portrait, combat
buffs). The heavy categories — **abilities + items (~800 `.tres`)** — load on a
**background thread**, because nothing needs them until a player spawns into a
map; this keeps the login screen from blocking on a disk scan it never reads. The
`get_ability_data` / `get_item_*` getters call `ResourceManager.ensure_loaded()`
internally, so normal callers see no difference (an early caller transparently
blocks until the scan finishes). **If you read `ability_data` / `item_data`
directly instead of through a getter** (e.g. iterating `.values()`), call
`ResourceManager.ensure_loaded()` first — the dict may still be filling. Connect
to the `content_ready` signal (or poll `is_content_ready()`) to react to
completion without blocking.

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

**`PetData` follows the quest pattern, but owned by `PetManager`** —
`PetManager._load_pet_data_registry()` scans `resources/PetSystem/Pets/` on
`_ready()` and keys each `PetData` by its `pet_id` (a hand-authored stable
string, e.g. `"basic_bird"`). Look pets up with `PetManager.get_pet_data(id)`.
Per-character pet state (hunger, learned commands, pet inventory) lives in
the player save under `pets: []`, not as `.tres`. See
[docs/adr/0001-pet-system-architecture.md](../../docs/adr/0001-pet-system-architecture.md).

### Item-system pet subclasses (`ItemSystem/`)

- **`PetFoodData extends ConsumableData`** — fed to a summoned pet via the
  Pet UI's Feed button, NOT via the normal "Use Item" pipeline. Author with
  no `effect_script` so accidental Use becomes a silent no-op; the only
  field beyond `ConsumableData` is `fullness_restore: float`.
- **`PetSkillBookData extends ConsumableData`** — teaches a pet a single
  command. Author with `effect_script = Effect_TeachPetCommand` and
  `effect_properties = {"command_id": "..."}` matching one of
  `PetManager.CMD_AUTO_POT` / `CMD_ITEM_POUCH` / `CMD_MESO_MAGNET` /
  `CMD_AUTOBUFF`. The effect refunds the book on failure (no pet summoned,
  already learned).

### Item-effects (`ItemSystem/Effects/`)

- **`Effect_HatchPet`** — used by Pet Egg consumables; reads
  `{"pet_data_id": "...", "default_name": "..."}` from `effect_properties`
  and calls `PetManager.hatch_pet_server`.
- **`Effect_TeachPetCommand`** — used by Pet Skill Book consumables; reads
  `{"command_id": "..."}` and appends to the summoned pet's
  `learned_commands`. Refunds the book if no pet is summoned.

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
- `WeaponDisciplineData` no longer has a `starter_ability` field (PR 8 removed it).
  New characters spawn with **1 ability point** in their chosen discipline's pool —
  bootstrapped to mastery 1 at first login (see `AbilityComponent.bootstrap_fresh_character_if_needed`).
  Players pick where that first point goes through the regular Ability Window.

## Creating content

Use the matching skill — each walks the full recipe and field list: `add-ability`,
`add-buff`, `add-item`, `add-enemy`.
