# Blocker enemies: a timed frontal guard

Status: accepted

## Context

The attack-pattern set (ADR-0016, 0017) covers a ranged check and a vertical-
follow check. It still lacked a *defensive* check — an enemy that punishes
mindless hold-to-attack and rewards timing and positioning. The "blocker" fills
that slot.

## Decision

A blocker (`is_blocker` on `EnemyData`) periodically raises a **frontal guard**.
An `enemy_block` state is injected at runtime (same `_ensure_*_state` pattern as
hit / ranged); from `chase`, when the target is in attack range and the guard is
off `BLOCK_COOLDOWN`, the enemy enters it instead of that attack cycle, faces the
target, plays its `block` clip, and holds for `BLOCK_DURATION`. While guarding,
`EnemyBase` reports `_guarding`, which does two things:

- **Frontal damage reduction** — `CombatComponent._execute_hit` (which both melee
  and projectile player hits route through) calls the enemy's `guard_reduced_damage`
  on the final damage, BEFORE the damage number and `take_damage`, so the number
  shown and the HP lost agree. A hit from the side the enemy faces is cut to
  `BLOCK_FRONTAL_DAMAGE_TAKEN` (20%); a hit from **behind** (a dagger flank) passes
  at full damage. DoT / environmental damage doesn't route through `_execute_hit`,
  so it isn't blocked — sensible (a shield doesn't stop poison ticking).
- **No knockback** — `apply_knockback` bails while guarding, so a braced shield
  isn't shoved by hits.
- **No flinch** — `_try_enter_hit_state` bails while guarding, so chip damage
  can't stagger it out of the guard.

Counterplay: wait the guard out and strike on the drop, or flank it. The host is
a new **SW Knight** enemy (ARMORED archetype) — the first enemy built from the
Star Wanderers pack, since no existing enemy had a Block animation.

## Considered Options

- **(chosen) Timed frontal guard.** Readable (a Block-pose telegraph), grounded,
  full of counterplay, and it specifically rewards the dagger flank identity.
- **Reactive parry** (guard in response to the player's swing). More dynamic but
  harder to read and more complex; deferred.
- **Passive armor only** (just the ARMORED archetype + never flinch). Cheapest,
  but it's a tanky stat block, not a *pattern* — no active counterplay.

## Consequences

- `is_blocker` defaults false; existing enemies are unaffected.
- The `block` clip is **hand-driven** by the state (`process_frame`, server-only):
  raise to a guard frame, hold there for the whole window, and play the impact
  frames only when a frontal hit is absorbed (flagged via `consume_block_react`),
  then snap back to the hold. The host (server+client) renders this; a remote
  client, which only gets the `block` state via `_set_state_rpc`, plays the clip
  straight through once on `enter` — an accepted limitation, same tier as other
  server-timed enemy visuals.
- The guard reduction is server-authoritative and applied to the final damage in
  `_execute_hit`, so the floating damage number and the HP both show the reduced
  value (the earlier take_damage-only hook reduced HP but left the number showing
  the full hit, which read as "no reduction").
- Frontal is judged against the enemy's `facing_direction`, which the block state
  locks onto the aggro target — so a second, flanking attacker is "behind" and
  deals full damage even though the enemy faces someone else.
