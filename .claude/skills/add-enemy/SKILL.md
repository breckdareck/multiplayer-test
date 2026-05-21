---
name: add-enemy
description: >-
  Use when creating or editing an enemy/monster for this Godot RPG. Covers the
  EnemyData .tres, the SpriteFrames, drop tables, and the enemy scene.
paths: resources/Enemies/**, scripts/Enemy/**, scenes/NPC/**
---

# Adding an enemy

Enemies are `EnemyData` resources attached to a scene whose root extends
`EnemyBase` (`scripts/Enemy/enemy_base.gd`).

**Important:** unlike abilities/items/buffs, enemies are **NOT** auto-loaded by
`ResourceManager`. An enemy exists only by being placed (or spawned) in a map with
its `enemy_data` assigned.

## Steps

1. **Create the folder** `resources/Enemies/<Name>/`.

2. **SpriteFrames** — make `SF_<Name>.tres` with animations `idle`, `walk`,
   `attack`, `hit`, and `death`. The death animation **must be named `death`** —
   `enemy_base.gd` keys death/pooling off that exact name.

3. **EnemyData** — make `ED_<Name>.tres`:
   - `monster_name`, `monster_level`, `movement_speed`
   - `sprite_frames` → the `SF_` resource
   - `character_collision_shape`, `body_hitbox_shape`, `attack_hitbox_shape`
     (`Shape2D` each)
   - `item_drops` → `Array[ItemDropResource]`

4. **Drops.** Each `item_drops` entry is an `ItemDropResource`: `item_name`
   (an existing item's `name`), `drop_chance` (0.0–1.0), `min_amount`/`max_amount`,
   and `randomize_stats` for rolled equipment. A `Coin` drop is auto-added from a
   curve if you don't define one. New items come from the `add-item` skill.

5. **Scene.** The simplest reliable path is to **duplicate an existing enemy
   scene** under `scenes/NPC/` and point its exported `enemy_data` at your new
   `ED_` resource. A from-scratch scene needs a root extending `EnemyBase` with
   children `AnimatedSprite2D`, `StateMachine`, `AttackHitbox` (+ shape),
   `BodyHitbox` (+ `EnemyBody` shape), `CollisionShape2D`, `MultiplayerSynchronizer`,
   a name `Label`, and the stat curves (`health_curve`, `experience_curve`,
   `wep_att_curve`, …) assigned in the inspector.

6. **Place it.** Add the enemy (or a spawner) into a map scene under that map's
   `Enemies` node. Stats (`WEAPONATTACK`, `DEFENSE`, HP, EXP, …) are computed from
   the scene's curves sampled at `monster_level` — you do not set them by hand.

7. **AI.** Behaviour is the shared state machine in
   `scripts/Enemy/StateMachine/` (idle / patrol / attack). Reuse it; add a new
   state only for genuinely unique behaviour.

8. **Test.** Enter the map, fight the enemy, and confirm aggro, attacks, death,
   EXP, and drops.
