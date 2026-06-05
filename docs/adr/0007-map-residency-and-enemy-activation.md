# Map residency and enemy activation — pre-instantiate all maps at boot, sleep enemies by proximity

## Context

The host hitched whenever a player (or a roaming bot) entered a map that was
not currently resident. Maps were loaded on demand and freed the instant their
last occupant left (`active_maps[map_id].player_ids` empty →
`_unload_map_on_server`), so re-entering a recently-vacated map paid a full cold
`load()` + `instantiate()` + `_ready` cascade — the confirmed source of the
hiccup. Bots make this worse: they are auto-spawned roaming population
(`bot_config.json` `auto_spawn`, `patrol_route`, `map_difficulty` bands) that
travel maps autonomously, so they both *trigger* the churn and keep most maps
intermittently occupied.

Two separable problems: (1) the per-join instantiation cost, and (2) the
sustained server cost of keeping maps resident while their enemies tick.

## Decision

### 1. Residency — pre-instantiate all maps at boot, never free (v1)

On `server_has_started`, instantiate every map in `MAP_SCENES` (staggered a few
per frame so boot doesn't hitch), wrap each in its SubViewport as today, and
keep them resident for the server's lifetime. There is no per-join
instantiation — first-visit and re-visit are both free. The throwaway
all-maps-instantiate pass in `_build_map_connections` is deleted; the portal
connectivity graph is derived from the now-resident instances.

The trade accepted: ~5 maps' worth of node trees + enemy pools resident in
server RAM at all times (trivial for small 2D pixel-art scenes), and a heavier
one-time server boot (not latency-sensitive).

**Revisit trigger:** at ~10–15 maps this stops being free. At that point replace
"resident set" with a bounded **warm pool** — deferred-unload TTL + LRU cap,
occupied maps (human *or bot*) pinned, least-recently-vacated empty map evicted
past the cap. The LRU cap ships now as a stub set above the map count so turning
on eviction later is a config flip, not a redesign.

### 2. Simulation — per-enemy activation by proximity, not per-map slow-tick

Resident-but-empty maps are made cheap by sleeping their enemies, not by keeping
the whole map at a reduced tick. A **central, server-only proximity scanner in
`MapManager`** runs at ~10 Hz: for each map that has ≥1 agent (player *or* bot,
read from `active_maps[map_id].player_ids`), it wakes enemies within
`detection_radius + margin` of any agent and sleeps the rest. A map with zero
agents runs no scanner, so all its enemies stay asleep — that is the only
"paused map" state.

- **Awake** = full enemy state-machine tick. **Asleep** = `_process` /
  `_physics_process` disabled (≈0 cost).
- The scanner is **external** because aggro detection (`enemy_base.acquire_target`)
  is a per-frame self-scan — an asleep enemy cannot wake itself.
- **Hysteresis:** sleep radius > wake radius (≥ the chase-drop distance) to stop
  boundary flapping.
- **Sleep predicate is `is_idle_or_patrol AND far_from_all_agents`** — never
  sleep an enemy with an active target or mid-attack, or a kited monster would
  freeze mid-chase.
- An asleep enemy keeps its `MultiplayerSynchronizer` (nothing to send while
  static; disabling it risks a freshly-joined client missing its resting
  position) — unlike the pool-deactivate path, which fully disables it.

"Living world" falls out for free: a roaming bot is an agent, so the scanner
keeps the enemies around it awake — they fight and drop loot — while distant
enemies sleep.

## Considered Options

- **Per-map attention slow-tick (HOT/WARM/IDLE + tick-divisor).** Rejected:
  bots drive full-rate character physics via input flags and their brains live
  under `BotManager` (outside the map subtree), so a blanket per-map slow-tick
  either breaks bot-vs-enemy combat fidelity or forces a `MapManager`→
  `BotManager` throttle coupling plus delta-compensation. Per-enemy proximity is
  correct by construction (an engaged enemy is always near its attacker) and
  also reduces cost on populated maps (distant enemies sleep).
- **Lazy-load-once, never free** (instantiate on genuine first-visit, then keep).
  Avoids the boot hitch but keeps a one-time first-visit hitch per map; rejected
  for v1 because front-loading all instantiation to "start the server" is better
  UX for a player-host than hitching mid-play. Kept as the fallback if boot cost
  becomes a problem.
- **Full TTL/LRU warm pool now.** Deferred — too many moving parts for a 5-map
  roster where maps rarely stay empty. Becomes the plan at 10–15 maps (above).

## Consequences

- No save-format change; enemies are transient and not persisted.
- No new RPCs and no authority change — the scanner is a pure server-side
  optimization over already-server-authoritative enemies.
- Maps are no longer freed on empty, so anything that assumed "map gone ⇒ its
  transient state gone" (e.g. ground-loot cleanup that relied on map unload)
  must rely on its own despawn timer instead. Verify ground-drop despawn does
  not depend on `_unload_map_on_server`.
- The disconnect hard-reset (`_handle_server_disconnect` frees the `Maps`
  container) and any channel switch must re-run boot-time pre-instantiation.
- Enemies must initialize **asleep** at boot (no agents on any map yet); the
  first agent to enter a map should trigger an immediate scan for that map so
  wake latency on spawn-in isn't a visible ~100 ms.
