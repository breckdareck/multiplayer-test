---
name: add-enemy
description: >-
  Use when creating or editing an enemy/monster for this Godot RPG. Covers
  building the SpriteFrames from an outlined spritesheet, the EnemyData .tres,
  drop tables, and the enemy scene.
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

2. **SpriteFrames from the spritesheet** — see the dedicated section below. Output
   is `SF_<Name>.tres`.

3. **EnemyData** — make `ED_<Name>.tres`:
   - `monster_name`, `monster_level`, `movement_speed`
   - `sprite_frames` → the `SF_` resource
   - `character_collision_shape`, `body_hitbox_shape`, `attack_hitbox_shape`
     (`Shape2D` each)
   - `item_drops` → `Array[ItemDropResource]` (see step 4)
   - optional: `is_aggressive`, `archetype`, `is_magic_attacker`, the `*_mult`
     fine-tune knobs (see `combat_scaling_and_enemy_tuning` memory).

4. **Drops.** Each `item_drops` entry is an `ItemDropResource`: `item_name`
   (an existing item's `name`), `drop_chance` (0.0–1.0), `min_amount`/`max_amount`,
   and `randomize_stats` for rolled equipment. A `Coin` drop is auto-added from a
   curve if you don't define one. Gear drops should match the enemy's level —
   `tools/assign_enemy_drops.gd` retiers an enemy's gear drops to the tier at or
   below its `monster_level` (run after the item generator). New items come from
   the `add-item` skill.

5. **Scene.** The simplest reliable path is to **duplicate an existing enemy
   scene** under `scenes/NPC/` (e.g. `enemy_template.tscn`, or `goblin.tscn` for an
   attacker) and point its exported `enemy_data` at your new `ED_` resource. A
   from-scratch scene needs a root extending `EnemyBase` with children
   `AnimatedSprite2D`, `StateMachine`, `AttackHitbox` (+ shape), `BodyHitbox`
   (+ `EnemyBody` shape), `CollisionShape2D`, `MultiplayerSynchronizer`, a name
   `Label`, and the stat curves (`health_curve`, `experience_curve`,
   `wep_att_curve`, …) assigned in the inspector.

6. **Wire the animation names.** Each state node under `StateMachine` has an
   `animation_name` that must EXACTLY match an animation in your SpriteFrames —
   see "Animation name contract" below. If your sheet uses `attack_1`/`attack_2`
   but you duplicated a scene whose attack state plays `slash_attack`, either
   rename the SF animation or set that state's `animation_name = "attack_1"`.

7. **Place it.** Add the enemy (or a spawner) into a map scene under that map's
   `Enemies` node. Stats (`WEAPONATTACK`, `DEFENSE`, HP, EXP, …) are computed from
   the scene's curves sampled at `monster_level` — you do not set them by hand.

8. **Test.** Enter the map, fight the enemy, and confirm aggro, attacks, the hit
   reaction, death, EXP, and drops.

## Building SpriteFrames from an outlined spritesheet

Enemy art lives in `assets/sprites/`. The **MiniBeastmens** pack
(`assets/sprites/MiniBeastmens/MiniBeastmens/`) ships every creature as one grid
**spritesheet** in two variants — `Outline/` and `Without Outline/`. **Use the
`Outline/` version** (`Mini<Creature>-Sheet.png`). Each sheet is a uniform grid of
**40×32** cells; each **row is one animation** laid left-to-right, padded with
blank cells out to the widest animation. The standard MiniBeastmens row order is:

| row | animation | loops? | notes |
|---|---|---|---|
| 0 | idle | yes | |
| 1 | patrol (walk) | yes | |
| 2 | jump / fall / land | — | 3 frames; usually unused by enemies — skip it |
| 3 | attack_1 | no | |
| 4 | attack_2 | no | second attack (optional) |
| 5 | hit | no | damage reaction |
| 6 | death | no | |

Frame counts vary per creature and some rows may be blank — never assume; detect.

### Workflow

1. **Find the Outline sheet** for your creature, e.g.
   `assets/sprites/MiniBeastmens/MiniBeastmens/Outline/MiniWolfPathfinder-Sheet.png`.

2. **VIEW the sheet** with the Read tool (it renders PNGs). Confirm the cell size
   (MiniBeastmens = 40×32; other packs differ — divide the sheet width by the
   widest animation's frame count, or check the pack readme), the row order, which
   rows you want, and which loop.

3. **Report mode** — list the frame count of every row so you can map rows to
   names. Pillow isn't installed; this uses Godot's `Image` API:
   ```
   godot --headless --path . --script res://tools/gen_enemy_spriteframes.gd -- \
     --sheet res://assets/sprites/MiniBeastmens/MiniBeastmens/Outline/MiniWolfPathfinder-Sheet.png \
     --cell 40x32
   ```
   It prints e.g. `row 0 (y=0): 4 frame(s)`, flagging `[BLANK]` rows.

4. **Generate mode** — map rows → animation names and write the SpriteFrames.
   `--anims` is an ordered comma list mapped to `--rows` (omit `--rows` to use the
   auto-detected non-blank rows in order). Suffix a name with `*` to LOOP it.
   Skip the jump/fall/land row by leaving it out of `--rows`:
   ```
   godot --headless --path . --script res://tools/gen_enemy_spriteframes.gd -- \
     --sheet res://.../Outline/MiniWolfPathfinder-Sheet.png --cell 40x32 \
     --out res://resources/Enemies/WolfPathfinder/SF_WolfPathfinder.tres \
     --rows 0,1,3,4,5,6 --anims "idle*,patrol*,attack_1,attack_2,hit,death" --speed 10
   ```
   The tool slices each cell into an `AtlasTexture` region and detects each row's
   real frame count (trailing blank cells ignored). Re-runnable.

5. **Verify** the result loads (`SF_BearWarrior.tres` is a good reference) — open
   it in the editor or instance the enemy scene headless.

Some creatures have fewer/more animations (no attack_2, an extra cast row, etc.).
Adjust `--rows`/`--anims` to match what you VIEWED. For packs that ship one PNG
per animation (e.g. the older Goblin: `Attack.png`, `Death.png`), this grid tool
doesn't apply — build the SpriteFrames per-file in the editor instead.

## Animation name contract

The names in the SpriteFrames must match what the code/scene plays:

- **`death`** — REQUIRED, this exact name. `enemy_base.gd` keys the death →
  pooling flow off `animation == "death"`.
- **`idle`, `patrol`** — the idle/patrol/chase states play these via each state
  node's `animation_name` in the scene. These two loop.
- **`hit`** — OPTIONAL, this exact name. `enemy_base.gd` auto-plays it on damage
  only if `sprite_frames.has_animation("hit")`.
- **attack** — the attack state's `animation_name`. Current scene templates use
  **`slash_attack`**; the MiniBeastmens sheets provide **`attack_1`** (and
  `attack_2`). Pick one and make the SF animation name and the state's
  `animation_name` agree.
- **jump / fall / land** — only needed if you add states that play them; enemies
  don't by default, so the jump/fall/land row is normally skipped.
