# Population-driven enemy spawning — global respawn tick + player-count capacity scaling

## Status

Accepted (2026-06-15). **Revised 2026-06-16**: the capacity cap was lifted from
per-spawner to **map-wide** — the decision text below describes the live model; see
[Revision](#revision-2026-06-16--cap-lifted-from-per-spawner-to-map-wide). Live in
`scripts/Enemy/enemy_spawner.gd` and `scripts/Managers/map_manager.gd`. Builds
directly on the proximity-activation half of
[ADR 0007](0007-map-residency-and-enemy-activation.md); the user-facing mechanics
it implements are catalogued in
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

### 1. Each spawner's pool is its typed contribution to the map's spawn points

`EnemySpawner` stays the authoring unit: one mob type + its spawn-point markers
in the scene (mirroring MapleStory's *typed* spawn points). A spawner's
`pool_size` is the number of physical spawn points it contributes. How many are
alive is decided by the **map-wide** cap (§3), not per spawner. A pool member is
"alive" exactly while checked out of the spawner's `_dormant` list; death returns
it. So `spawner.get_alive_count() == _pool.size() - _dormant.size()`. Spawners are
intentionally "dumb" — they expose `get_pool_capacity()`, `get_alive_count()`,
`free_room()`, `spawn_one()` and let MapManager run the budget.

### 2. One global respawn tick on `MapManager`

`MapManager` owns a single server-only clock, `SPAWN_TICK_INTERVAL`, accumulated
in `_process`. On each tick it brings **every active map** up to its cap
(`replenish_map_population`) and then emits `spawn_tick` as a notification seam.
There are no per-enemy respawn timers and spawners do not self-schedule.

- **The interval is a gameplay choice, set to `5.0 s`.** It is deliberately *not*
  tied to MapleStory's 7.56 s (which is itself 7 × a 1.08 s engine heartbeat) —
  we owe nothing to that engine's clock. 5 s preserves the feel of the old 3–5 s
  per-enemy delay while making respawns arrive as a coherent wave. It is a single
  named constant; retune freely.
- The tick runs **before** the activation-scan early-return in `_process`; a
  zero-occupant map yields a cap of 0 and no-ops (hibernation), so running it over
  every map each tick is cheap.

### 3. ONE cap scales the whole map's spawn points (not per spawner)

The cap is applied to the map's **total** spawn-point pool, summed across every
spawner, via the pure curve:

```
EnemySpawner.capacity_for(total_pool, occupants):
  occupants <= 0            -> 0                       # hibernation
  else  floor(total_pool * clamp(0.75 + 0.05*(occupants-1), 0.75, 1.0)), min 1
```

Solo = 75% of the map total, rising +5%/occupant to 100% at a party of six,
matching MapleStory's published table (`floor` reproduces its 30→22/25/28). This
is the crux: applying the scalar per spawner throws away each spawner's fractional
part, so on small pools the occupancy ramp barely moves (`floor(6·0.75)=4` for
several steps). Summing first recovers it — `floor(12·0.75)=9` vs `4+4=8` — so the
ramp is meaningful even with small per-spawner pools (test:
`test_map_wide_cap_beats_summed_per_spawner_floors`).

`replenish_map_population(map_id)` computes `deficit = map_cap - total_alive`,
then fills `deficit` **random empty spawn points** chosen across all spawners
(build one entry per free slot, `shuffle`, take `deficit`). That's MapleStory's
"the server randomly selects which physical spawn points to activate," and it
shares density across mob types in proportion to their open capacity.

**Bots count as occupants by default** (`MapManager.SPAWN_COUNT_BOTS`). Bots are
this game's ambient population ([ADR 0011](0011-bot-ambient-population.md)); having
them raise the cap makes a bot-busy map denser, the living-world goal. A spawner
flagged `exclude_from_map_cap` (bosses / set-pieces) is *not* in the budget and
simply keeps its whole pool alive (`fill_to_pool`).

### 4. Over-cap / "spawn debt" falls out for free

`replenish_map_population` only ever *adds* (`deficit = map_cap - total_alive`,
filled only when positive); it never despawns. So if a party fills a map to 28 and
leaves, a solo entrant (cap 22) keeps all 28 — fully killable for full reward — and
the map self-corrects down only as those extras die (no respawn until
`total_alive < map_cap`). Exactly MapleStory's spawn-debt behaviour.

### 5. Hibernation reuses ADR 0007

A zero-occupant map already sleeps every enemy via the proximity scanner. With a
cap of 0 at zero occupants and a replenish that never despawns, survivors stay
frozen until re-entry — no new freeze logic. On entry, `_finalize_player_spawn`
calls `replenish_map_population(map_id)` for an immediate fill to the solo cap, so
a re-entered map isn't sparse for up to one tick. A spawner also requests a fill
once its deferred setup completes, covering freshly-loaded maps.

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
- **Per-spawner capacity (the original form of this ADR).** Rejected on review:
  flooring each small spawner independently makes the occupancy ramp nearly
  inert and lumpy. Replaced by the map-wide cap — see the Revision.
- **Collapse to a single map-wide spawner.** Rejected: loses the per-spawner
  authoring unit (one typed mob + its markers grouped in the scene, mirroring
  MapleStory's typed spawn points). The map-wide *cap* gives the benefit without
  the authoring cost.

## Consequences

- **Solo density dropped to 75% of the map's total pool.** Existing maps were
  authored with each `pool_size` = intended-alive-count, so solo play is now
  lighter. Authors wanting a specific solo *map* count should size the summed
  pools to `desired / 0.75`. (No map `pool_size` values were changed here — a
  follow-up balance pass owns that.)
- **Over-cap persistence is bounded by the warm pool.** MapleStory freezes an
  empty map indefinitely; here ADR 0007's evictor frees a fully-empty map ~20 s
  after its last agent leaves, so the leftover bonus wave only survives while the
  map stays warm. Acceptable; not worth fighting the evictor.
- No save-format change, no new RPCs, no authority change — purely a server-side
  reshaping of already-server-authoritative spawning.
- `respawn_delay` is retained as a deprecated, unused `@export` so existing scene
  files load unchanged; it no longer affects anything.
- New constant `MapManager.SPAWN_TICK_INTERVAL`, `MapManager.SPAWN_COUNT_BOTS`,
  and the `replenish_map_population` / `get_map_population_summary` methods are the
  tuning/extension seam. Unit coverage: `test/enemy/test_spawn_capacity.gd` (curve
  table, hibernation, full-party clamp, min-1 floor, spawn-debt invariant,
  map-wide-beats-per-spawner, report shape).
- **Dev tooling:** the console `spawns` command (`scripts/UI/debug_panel.gd`)
  toggles a `DebugSpawnOverlay` (`scripts/UI/debug_spawn_overlay.gd`) that draws
  each spawner's spawn-point markers, a per-spawner `alive/pool` label, and a
  MAP-wide headline (`total alive / map cap · occ`); `spawns report` prints the
  same as text. They read `EnemySpawner.get_population_report()` (per-spawner) and
  `MapManager.get_map_population_summary()` (map cap) — both server-authoritative,
  so numbers are host-only; markers still draw on a client.

## Revision (2026-06-16) — cap lifted from per-spawner to map-wide

The first form of this ADR applied `capacity_for` **per spawner**. On review that
was wrong for the same reason MapleStory uses a map-wide cap: flooring a small
pool independently makes the occupancy scalar nearly inert and lumpy —
`floor(6·0.75)=4` stays 4 across several player counts, and a map's scaling is the
sum of those coarse steps. MapleStory instead caps the map's **total** spawn
points and fills random empty ones.

Changed to match: `pool_size` is now a spawner's *contribution* to the map total;
`MapManager.replenish_map_population` sums all (non-excluded) spawners' pools,
applies `capacity_for(total_pool, occupants)` once, and fills the deficit across
random empty spawn points. Spawners became "dumb" (`get_pool_capacity` /
`get_alive_count` / `free_room` / `spawn_one` / `fill_to_pool`); the per-spawner
`enable_population_scaling` + `count_bots_as_players` exports were removed (bots now
counted map-wide via `SPAWN_COUNT_BOTS`), replaced by a single
`exclude_from_map_cap` flag for always-present boss/set-piece spawns. The pure
`capacity_for` curve and its tests are unchanged — only its *input* moved from one
spawner's pool to the map total.
