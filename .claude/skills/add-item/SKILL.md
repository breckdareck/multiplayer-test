---
name: add-item
description: >-
  Use when creating or editing an item for this Godot RPG — a weapon, a piece
  of armor, a consumable/potion, or a crafting material. Covers the item .tres,
  stat bonuses, consumable effect scripts, and making it droppable.
paths: resources/Items/**, scripts/Resources/ItemSystem/**
---

# Adding an item

Items are data-driven resources. `ResourceManager` auto-loads everything under
`resources/Items/` on startup — **no manual registration**. Most code references
items by `name`. Class definitions are in `scripts/Resources/ItemSystem/`.

## Choose the type

| Item | Class | Folder |
|---|---|---|
| Weapon | `WeaponData` | `resources/Items/Weapons/` |
| Armor | `ArmorData` | `resources/Items/Armor/` |
| Consumable / potion | `ConsumableData` | `resources/Items/Consumables/` |
| Material / other | `ItemData` | `resources/Items/` |

`WeaponData` and `ArmorData` extend `EquipmentData` extend `ItemData`.

## Steps

1. **Create the `.tres`** with the class above. Leave `item_id` blank — a UUID is
   generated automatically.

2. **Common fields:** `name`, `rarity` (`Constants.ItemRarity`), `icon`,
   `description`, `item_level`. `item_type` is `EQUIPMENT` for weapons/armor (set
   it and stacking auto-disables), `CONSUMABLE` (forced by `ConsumableData`), or
   `MATERIAL`. `base_value` is derived from `item_level` via a curve — only set
   `custom_item_value` for `item_level < 0`.

3. **Type-specific fields:**
   - **Weapon:** `equipment_type = WEAPON`, `weapon_type`
     (`SWORD`/`BOW`/`STAFF`/`DAGGER`), `weapon_attack_speed` (1–10, default 4).
   - **Armor:** `equipment_type = ARMOR`, `armor_type`
     (`HEAD`/`CHEST`/`LEGS`/`FEET`).
   - **Consumable:** `effect_script` + `effect_properties`.

4. **Equipment bonuses.** Fill `bonus_stats` (`Dictionary[StatType, StatData]`) —
   use `flat_bonus_value` / `percent_bonus_value` on each `StatData`.

5. **Consumable effects.** `effect_script` must extend `BaseItemEffect`
   (`scripts/Resources/ItemSystem/Effects/`), override `execute()`, and read
   `user` / `source_item`. `effect_properties` is a tuning dict, e.g.
   `{"heal_amount": 50}`. Existing effects: `Effect_RestoreHealth`,
   `Effect_RestoreMana`, `Effect_GrantExperience`, `Effect_TownPotion`.
   **Bot note:** bots auto-use a potion only if `effect_properties` has a
   `heal_amount` (health) or `regain_amount` (mana) key.

6. **Make it droppable** (optional). Add an `ItemDropResource` entry to an
   enemy's `EnemyData.item_drops`, referencing the item by `item_name`. See the
   `add-enemy` skill.

7. **Test.** Spawn or equip the item; for equipment verify the stat changes, for
   consumables verify the effect fires.
