# Population-driven enemy spawning — global respawn tick + player-count capacity scaling

## Status

Accepted (2026-06-15). Live in `scripts/Enemy/enemy_spawner.gd` and
`scripts/Managers/map_manager.gd`. Builds directly on the proximity-activation
half of [ADR 0007](0007-map-residency-and-enemy-activation.md); the user-facing
mechanics it implements are catalogued in
[docs/maplestory_spawn_mechanics.md](../maplestory_spawn_mechanics.md).

## Context

Enemy respawning was **per-enemy and headcount-blind**. Each `EnemySpawner` kept
a fixed pool of `pool_size` monsters and, whenever one died, started an
independent `respawn_delay` (3–5 s) `SceneTreeTimer` to re-place that specific
enemy. Consequences:

- The map's live monster count was always exactly `pool_size`, regardless of how
  many players were present. A six-player party and a solo player saw identical
  density, so grouping up never thinned the field per-head and solo play on a
  party-tuned map was a slog (or vice-versa).
- Respawns were a scatter of N uncoordinated timers rather than a legible
  "clear the wave, brief breather, wave returns" rhythm.
- There was no concept of a population *cap distinct from* the physical pool, so
  no headroom to express "this map can hold 30, but you only get 22 solo."

The game is explicitly MapleStory-modelled (see the MapleStory-direction memory),
and MapleStory's mob system solves exactly this with three coupled ideas: a fixed
spawn-point cap, a single global respawn clock, and a player-count capacity
scalar. We already had the cheap-empty-map half of the problem solved by ADR
0007's proximity scanner (zero-agent maps sleep every enemy); what was missing was
the *spawn* side.

## Decision

Adopt MapleStory's population model, but with our own cadence number rather than
copying its exact clock.

### 1. `pool_size` becomes the spawn-point cap, not the always-alive count

A spawner's pool is reinterpreted as the **physical spawn-point capacity** — the
100% / full-party value. How many of those are actually alive is decided by the
capacity curve below. A pool member is "alive" exactly while it is checked out of
the spawner's `_dormant` list; death returns it to `_dormant`. So
`alive == _pool.size() - _dormant.size()`.

### 2. One global respawn tick on `MapManager`

`MapManager` owns a single server-only clock, `SPAWN_TICK_INTERVAL`, accumulated
in `_process` and emitted as the `spawn_tick` signal. Every `EnemySpawner`
connects to it and, on each tick, replenishes its own map up to the current cap.
There are no per-enemy respawn timers anymore.

- **The interval is a gameplay choice, set to `5.0 s`.** It is deliberately *not*
  tied to MapleStory's 7.56 s (which is itself 7 × a 1.08 s engine heartbeat) —
  we owe nothing to that engine's clock. 5 s preserves the feel of the old 3–5 s
  per-enemy delay while making respawns arrive as a coherent wave. It is a single
  named constant; retune freely.
- The tick is emitted **before** the activation-scan early-return in `_process`
  so it fires every frame-budget cycle, and spawners on a zero-occupant map
  compute a cap of 0 and no-op, so a global broadcast is cheap.

### 3. Capacity scales with map occupancy

`EnemySpawner.capacity_for(pool, occupants)` is a pure function:

```
occupants <= 0            -> 0                       # hibernation
else  floor(pool * clamp(0.75 + 0.05*(occupants-1), 0.75, 1.0)), min 1
```

Solo = 75% of the pool, rising +5%/occupant to 100% at a party of six, matching
MapleStory's published table (`floor` reproduces its 30→22/25/28 values). The
`min 1` keeps a tiny pool (e.g. a lone-boss spawner) from being scaled out of
existence. Occupancy is read from `MapManager.get_players_on_map(map_id)`.

**Bots count as occupants by default** (`count_bots_as_players`, per-spawner
toggle). Bots are this game's ambient population
([ADR 0011](0011-bot-ambient-population.md)); having them raise the cap makes a
bot-busy map denser, which is the living-world goal. The whole behaviour is
gated by `enable_population_scaling` (default on); off = the old always-full pool.

### 4. Over-cap / "spawn debt" falls out for free

`_replenish()` only ever *adds* (`to_spawn = cap - alive`, clamped to ≥0); it
never despawns. So if a party fills a map to 28 and leaves, a solo entrant (cap
22) keeps all 28 — fully killable for full reward — and the map self-corrects
down only as those extras die (no respawn until `alive < cap`). This is exactly
MapleStory's spawn-debt behaviour, achieved by the clamp alone.

### 5. Hibernation reuses ADR 0007

A zero-occupant map already sleeps every enemy via the proximity scanner. With
capacity 0 at zero occupants and a replenish that never despawns, survivors stay
frozen in place until re-entry — no new freeze logic needed. On entry,
`_finalize_player_spawn` calls `_replenish_map_spawners(map_id)` (spawners found
via the `EnemySpawners` group, filtered to the map's subtree) for an immediate
fill to 75%, so a re-entered map isn't sparse for up to one tick.

## Considered Options

- **Keep per-enemy `respawn_delay` timers, add a separate headcount multiplier.**
  Rejected: two coupled mechanisms (N timers *and* a cap) with no single source
  of truth for "how many should be alive"; the tick + dormant-pool model collapses
  both into one.
- **Match MapleStory exactly (1.08 s heartbeat × 7 = 7.56 s).** Rejected by the
  user — we're inspired by, not bound to, that engine. We kept the *structure*
  (one global tick, capacity scalar, spawn debt) and chose our own number.
- **Per-spawner respawn cadence.** Deferred (YAGNI): a global interval is simpler
  and MapleStory-faithful; per-spawner phase tracking can be added later if a map
  ever needs a bespoke rhythm.
- **Despawn over-cap monsters when a party leaves.** Rejected: punishes the solo
  entrant and contradicts the (desirable) MapleStory bonus-wave behaviour the
  clamp gives for free.

## Consequences

- **Solo density dropped to 75% of `pool_size`.** Existing maps were authored
  with `pool_size` = intended-alive-count, so solo play is now lighter on them.
  Authors wanting a specific solo count should set `pool_size ≈ desired / 0.75`.
  (No map `pool_size` values were changed in this ADR — a follow-up balance pass
  owns that.)
- **Over-cap persistence is bounded by the warm pool.** MapleStory freezes an
  empty map indefinitely; here ADR 0007's evictor frees a fully-empty map ~20 s
  after its last agent leaves, so the leftover bonus wave only survives while the
  map stays warm. Acceptable; not worth fighting the evictor.
- No save-format change, no new RPCs, no authority change — purely a server-side
  reshaping of already-server-authoritative spawning.
- `respawn_delay` is retained as a deprecated, unused `@export` so existing scene
  files load unchanged; it no longer affects anything.
- New constant `MapManager.SPAWN_TICK_INTERVAL` and signal `spawn_tick` are the
  single tuning/extension seam. Unit coverage:
  `test/enemy/test_spawn_capacity.gd` (curve table, hibernation, full-party clamp,
  min-1 floor, spawn-debt invariant).
