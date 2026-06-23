# EnemyData decomposition: per-attack config on State nodes; collision shapes stay

Status: accepted (attack config moved; collision-shape fields deliberately kept)

## Context

`EnemyData` (`.tres`, referenced from the enemy scene — not auto-loaded) had grown
into a bag holding both enemy-wide identity AND per-attack config. After the enemy
attack states became authored scene nodes (chase/melee/ranged/secondary/block under
`StateMachine`), the attack nodes were *shallow*: they reached back into `EnemyData`
for their projectile/anim/cooldown/reach, so configuring one attack meant editing two
places and the node didn't own its behaviour. A review (`/improve-codebase-architecture`)
flagged moving per-attack config onto the nodes, and separately moving the three
collision-shape fields onto the scene nodes.

## Decision

**1. Per-attack config lives on the attack STATE node; dispatch is presence-based.**
`chase` polls its attack-state children (any node exposing `can_start(enemy, target)`)
in **child order** and enters the first ready one — off its own cooldown and with the
target in its own reach. There is no `attack_type` enum: a ranged enemy *has* a
`ranged_attack` node (and no `melee_attack`), a melee enemy the reverse, a caster can
add a `secondary_attack` node, etc. Each attack node owns its `projectile_scene/speed`
(`EnemyProjectileAttack`), `breath_sprite/breath_hitbox` (`EnemyHitboxAttack`),
`attack_anim`, and its own cooldown clock (armed via `enemy_base.attack_cooldown_until`,
which applies boss phase/enrage). `boss_special` stays on its own boss timer (ADR-0005),
out of the poll.

**Reach is an editor-authored `CollisionShape2D`, not a number.** Each attack node
declares an `in_reach(enemy, target)` predicate measured against a `CollisionShape2D`
you author and SEE in the editor (melee → its swing hitbox `melee_hitbox_shape`,
breath → its damage cone `breath_hitbox`, projectile → a dedicated `reach_shape`
cast-range box). The shared `EnemyAttackState.target_in_reach_shape` helper reads the
shape's bounds (Rectangle/Circle/Capsule, offset taken symmetrically so it's
facing-agnostic). `chase` calls the same `in_reach` (cooldown aside) for its "stop
closing in and hold" decision, so the stop distance always matches what the attack
triggers on. The old blind `reach: float` export is gone; a node with no shape
authored falls back to the enemy-wide `attack_range` box. Rationale: a number you
can't visualise is impossible to tune — the shape is WYSIWYG and reuses the hitbox
that already defines the swing/cone.

`EnemyData` keeps only **enemy-wide defaults** an attack node inherits when its own
field is unset: `attack_range` and `attack_cooldown`. Every per-attack field is gone
from `EnemyData` — `attack_type`, the entire Secondary Attack block, the Ranged Attack
block (`ranged_projectile_scene/speed` — each `ranged_attack` node now carries its own
`projectile_scene/speed`), and `is_blocker` (a blocker is now an enemy that authors an
`enemy_block` node — presence, not a flag). Also removed: the now-dead `enemy_base`
helpers (`has_secondary_attack`, `can_use_secondary`, `start_secondary_cooldown`,
`fire_secondary_projectile`, `secondary_trigger_reach`, `play/stop_secondary_breath_vfx`,
`can_attack`, `start_attack_cooldown`, the `_ensure_ranged/secondary/block` injectors).

**2. The three collision-shape fields STAY on `EnemyData` as optional overrides.**
`character_collision_shape`, `body_hitbox_shape`, `attack_hitbox_shape` remain. When
set, `enemy_base._set_collision_shapes` copies them onto the scene nodes at spawn
(they *win* over the scene); when null, the scene node's authored shape stands
(WYSIWYG — e.g. the Red Dragon's melee hitbox). They are NOT moved onto the scene
nodes, even though that would have matched the "node owns its data" direction.

## Why the collision shapes were NOT moved (the load-bearing reason)

Because the fields win at spawn, most enemy scenes carry **stale shapes** (mass-built
enemies were cloned from the goblin, so their scene `CollisionShape2D` /
`BodyHitbox/EnemyBody` / `AttackHitbox/MeleeCollisionShape` hold goblin defaults — the
ED override is what they actually use). Removing the fields naively would silently
mis-size ~100 enemies to goblin shapes.

A safe removal therefore requires baking each ED shape onto its scene node first. That
is not achievable with headless tooling:
- **`pack()` re-serialization is catastrophic** — confirmed: instantiating an enemy
  scene under `--script` leaves `enemy_base` uncompiled (it references autoload
  singletons that don't load headless), so the root node's `@export`s aren't in the
  property bag and `pack()` **drops `enemy_data`, every stat curve, and the component
  NodePaths** from the saved scene. It also strips node `unique_id`s and reformats
  every scene (huge unreviewable diff).
- **Per-type sub-resource text surgery** across ~100 scenes (copy each typed shape
  block, repoint three `shape =` refs) is non-destructive but error-prone for little
  gain.

The fields already provide the desired escape hatch (null → author on the scene node),
which is now documented on the exports. A full migration, if ever wanted, must be done
**in the Godot editor** (open each scene, bake the shape, clear the ED field) where it's
safe and WYSIWYG — not via headless tooling. Future architecture reviews should not
re-suggest removing these fields without that editor-based migration.

## Consequences

- Adding an enemy attack = drop the delivery-subclass node under `StateMachine` and set
  its exports; no `EnemyData` flags, no code. A ranged enemy must NOT carry a
  `melee_attack` node (presence = melee).
- `EnemyData` is now identity + stat tuning + AI ranges + pattern flags
  (splitter/exploder/leaper/blocker) + boss config + the three shape overrides + drops.
- See [CONTEXT.md](../../CONTEXT.md) "Attack delivery" and the
  `enemy-attack-state-architecture` memory.
