# Leaper enemies: hopping locomotion that follows the player ±1 platform

Status: accepted

## Context

Enemies have no pathfinding — they move in 1D along their platform and stop at
ledges (they can't jump). The ranged-caster system (ADR-0016) made *vertical
separation* the player's main escape: a caster only hits within ±1 tile, so the
counterplay is to get onto a platform two tiles up. The attack-pattern set needs a
"charger" — the deliberate counter to ranged/kiting — that denies that escape.

A dash gap-closer was considered and rejected: a teleport-style lunge reads as a
*boss* mechanic, not a basic mob (user call). We wanted something grounded and
unmistakably trash-mob.

## Decision

The charger is a **leaper** — a "ribbon-pig" mob that **runs straight at the
target and hops a wall/step in its path**, climbing one tile up without breaking
its run, so it can follow the player onto a platform one up. It does NOT bounce
everywhere or stop when it gets close: it keeps charging and rams on contact (the
MapleStory ribbon-pig behaviour). It is the *only* enemy type that changes
platforms; everyone else still stays put.

A `is_leaper: bool` flag on `EnemyData` opts an enemy in. In `enemy_chase.gd`,
a leaper uses the normal run-toward-target locomotion (`_leaper_charge`), with two
differences from the walker: (1) it hops (an upward `HOP_FORCE` impulse, ~1-2
tiles at the default 980 gravity, keeping its horizontal run) in **either** of two
cases, gated differently: climbing a **solid wall/step in its path is FREE** (no
cooldown — it should always be able to get up a platform that's blocking it; the
`is_on_floor` gate keeps an unclimbable wall to a per-landing bounce, not a
vibration), whereas hopping **up to a player overhead with no wall to climb** (a
floating ledge, within `LEAP_UP_RANGE`) is rate-limited by `LEAP_JUMP_COOLDOWN`
*and* reaction-delayed by `LEAP_UP_REACTION` so it can't spam-match the player.
Mid-air it preserves the run velocity to carry up and over. (2) It never paces
away or holds short — the only time it stops is at a genuine cliff that does *not*
drop toward the target (`_target_below`), so it won't dive into a pit. A leaper
that also carries an attack still holds in range to swing (the `in_zone` branch
runs first).

The separate **ambient idle hop** (`enemy_base._tick_ambient_leaper_hop`, not
aggroed) has its own independent 5-15s cadence.

This is the **first enemy jumping in the codebase**, and it is deliberately NOT
general pathfinding: a bounded one-tile hop-the-obstacle, not nav-mesh traversal.
It runs server-side like the rest of the enemy state machine.

## Considered Options

- **(chosen) Hopping leaper.** Grounded, trash-mob-appropriate, and it answers the
  exact vertical escape ADR-0016 created. Adds a contained hop loop, no nav graph.
- **Dash/lunge gap-closer.** Rejected — reads as a boss telegraph, not a basic mob.
- **Fast-relentless / momentum-ramp melee.** Viable simpler chargers, but neither
  solves the *vertical* escape; they only contest horizontal kiting.
- **Real pathfinding for enemies.** Out of scope — large, and unnecessary for a
  ±1-platform follow.

## Consequences

- `is_leaper` defaults false; every existing enemy is unaffected. The Boar (Lv6,
  aggressive rammer) is the first leaper.
- Current sprites have no jump clip, so a leaper bounces on its walk clip (a
  cosmetic gap; a jump frame can be sliced later via `add-enemy`).
- Even when NOT aggroed, a leaper does an **ambient idle hop** every 5-15s
  (`_tick_ambient_leaper_hop` in `enemy_base`, ribbon-pig flavour). It's a purely
  vertical impulse applied before the state machine ticks, so the active idle/patrol
  state carries it out and it lands in place — it never hops the enemy off its
  platform. Directional chase hopping stands down while engaged.
- A leaper can still strand itself in a deep pit chasing a target below; the leash
  + proximity-activation recovery handle the stray, as for any enemy.
