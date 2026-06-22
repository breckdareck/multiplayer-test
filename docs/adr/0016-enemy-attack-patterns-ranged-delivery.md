# Enemy attack patterns via data-selected delivery (ranged = projectile)

Status: accepted

## Context

The weapon-discipline overhaul (ADR-0004) made identity come from *how each
weapon fights*, but enemy AI never reacted to it: every enemy chased the nearest
player and swung a melee `slash_attack`, so sword/bow/staff/dagger all *played*
the same regardless of how different they are on paper. The differentiation was
true on the character sheet and invisible in the fight. We want enemies whose
**attack pattern** pressures some disciplines and rewards others (a ranged
plinker punishes slow melee and rewards range; a charger punishes kiting), so
weapon choice becomes a moment-to-moment read.

## Decision

An enemy's combat behaviour is selected by **data, not by a hardcoded state**.
`EnemyData` gains `attack_type: Constants.AttackType` (the enum already existed,
unused): `MELEE` keeps the contact `slash_attack`; `RANGED`/`MAGIC` inject a new
`enemy_ranged_attack` state at runtime (the same `_ensure_*_state` pattern as
`chase`/`hit`). That state fires a **homing projectile** at the target — the same
projectile the player uses (`scripts/Gameplay/projectile.gd`, scene
`projectile_base.tscn`), spawned server-side and mirrored to clients via the
existing `MapManager.spawn_projectile_visual` path (so it works for bots too). The
hit resolves through the enemy's **own `damage_on_overlap`** (projectile.gd
branches on the caster: players route through `CombatComponent`, enemies through
`damage_on_overlap`), so a projectile deals exactly what the enemy's melee would —
no duplicated damage math. The enemy projectile masks the player hitbox layer (the
mirror of the player projectile masking the enemy layer).

Engagement is gated by a **box, not a radius**: `target_in_attack_zone` requires
the target within `attack_range` *horizontally* AND within ±1 tile (≈16px, +8px
slack) *vertically*. This is what stops a ranged enemy firing at a target several
platforms up/down — it only engages the same platform or one tile above/below.

Crucially the ranged attack is a **primary attack in the normal `chase → attack
→ chase` loop**, NOT routed through the `is_boss`-gated special scheduler, so
bosses are completely untouched. `has_attack_state()` generalises from "is there
a node named `slash_attack`" to "does my `attack_type` give me an attack state,"
and `chase` hands off via `get_attack_state_node()` instead of a literal
`../slash_attack` lookup.

## Considered Options

- **(chosen) Reuse the player's homing projectile + the enemy's own damage path.**
  Matches what the player does (the explicit design ask), reuses the proven
  spawn/replication/lifetime machinery, and adds no new damage math.
- **Telegraphed RECT zone reusing the boss telegraph + shape-damage path**
  (`broadcast_attack_telegraph` / `deal_boss_special_damage`). Built first and
  playtested; rejected — it read as a mini-boss slam, not a caster, and the AoE
  felt wrong for a basic ranged attack. The boss telegraph system still exists for
  bosses and remains the path if a *zone*-style enemy attack is wanted later.
- **Ungate the boss special scheduler (`_boss_special_tick`) for all enemies.**
  Rejected: a boss special is an *occasional* attack layered on melee; a caster's
  shot is its *only* attack. Ungating risks regressing every boss.
- **True repositioning/kiting AI** (the "smartest" pressure). Deferred: enemies
  have no pathfinding (pure 1D physics), so kiting is a navigation rewrite. We
  get the pressure from attack *pattern*, not movement, and instead use a melee
  *charger* as the deliberate counter to ranged so no single weapon dominates.

## Consequences

- `EnemyData` is a `.tres` content resource, not player-save state, and the new
  field defaults to `MELEE` — every existing enemy is unaffected, no migration.
- Damage axis (`is_magic_attacker`, physical vs magic) stays orthogonal to
  delivery (`attack_type`). A caster sets both; a physical archer sets
  `RANGED` + `is_magic_attacker = false`.
- The projectile is **homing** (the player projectile only hit-detects with a live
  target). Counterplay is leaving `attack_range` or breaking the ±1-tile band
  (jumping two platforms up), not sidestepping. A straight, dodgeable shot would
  need projectile.gd's non-homing branch fixed (it currently disables monitoring).
- A ranged caster with no pathfinding does **not** kite — once meleed it keeps
  casting at point-blank and dies fast (squishy by design). That gap is the
  melee player's intended answer; kiting AI is explicitly out of scope here.
- First slice fixes `RabbitWizard`/`DeerDruid`, which were authored as casters
  (`is_magic_attacker = true`) but behaved as melee bruisers.
