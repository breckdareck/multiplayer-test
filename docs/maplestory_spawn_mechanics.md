# Comprehensive Guide to MapleStory Mob Capacity and Spawn Mechanics

This document breaks down how the MapleStory game engine handles monster capacity, player scaling, map hibernation, and population corrections.

> **Emberwilds implementation:** see [How this maps to Emberwilds](#how-this-maps-to-emberwilds) at the end. The model below is implemented by `scripts/Enemy/enemy_spawner.gd` (per-map capacity + replenish) driven by a global `spawn_tick` on `MapManager`, layered on the existing proximity-sleep activation system (ADR 0007).

---

## 1. Core Mechanics

### The Spawn Point Cap
Every map in MapleStory has a hardcoded number of physical **spawn points**. This is the absolute maximum number of monsters that can theoretically exist on that map. 

### The Fixed Tick Timer
Monsters do not respawn instantly upon death. Instead, the server runs on a fixed global clock cycle (often referred to as a **tick**) of approximately **7.56 seconds**.
* When you kill a wave, the server checks the map on the next tick and replenishes the missing monsters up to your allowed capacity.
* Since the removal of spawn-enhancing items (like Frenzy Totems or Kishin Shoukan), this baseline dictates the ultimate speed of all grinding.

> **Emberwilds:** we adopt the *concept* of a single global respawn tick but pick our own cadence (not MapleStory's 7.56 s) — `MapManager.SPAWN_TICK_INTERVAL`, **5.0 s**, one constant to tune. Recorded in [ADR 0015](adr/0015-population-driven-enemy-spawning.md).

---

## 2. Player-Count Scaling

The game engine dynamically restricts or expands a map's maximum monster population based on the number of players actively inside the instance. It uses a linear scaling system:

| Player Count | Capacity Scalar | Example (On a 30-Spawn-Point Map) |
| :--- | :--- | :--- |
| **1 Player (Solo)** | **75% of max capacity** | ~22 Monsters alive simultaneously |
| **2 Players** | **80% of max capacity** | ~24 Monsters alive simultaneously |
| **3 Players** | **85% of max capacity** | ~25 Monsters alive simultaneously |
| **4 Players** | **90% of max capacity** | ~27 Monsters alive simultaneously |
| **5 Players** | **95% of max capacity** | ~28 Monsters alive simultaneously |
| **6 Players (Full Party)** | **100% of max capacity** | 30 Monsters alive simultaneously |

*Note: The server randomly selects which specific physical spawn points to activate or leave dormant to fulfill these percentages.*

---

## 3. Map Hibernation (Empty Maps)

When the player count on a map drops to zero, the server puts the map instance into **Hibernation Mode** to preserve processing power.

1. **State Preservation:** The map does not wipe, reset, or clear. Whatever monsters were standing alive at that exact millisecond remain frozen in place.
2. **The Freeze:** The 7.56-second spawn tick stops counting. Monsters stop moving, attacking, or walking. Environmental elements like Burning Fields, Runes, and Elite Boss progress are paused.
3. **Re-Entry Unfreeze:** The moment a new player enters the map, the server instantly wakes it up, registers **1 player**, and sets the legal population cap back to the solo **75% threshold**.

---

## 4. Population Over-Cap and "Spawn Debt"

A unique engine interaction occurs when a large party populates a map to maximum capacity and then suddenly leaves right before a solo player enters.

### Step-by-Step Scenario
Using a map with **30 total spawn points**:

1. **The Setup:** A party of 5 players trains on the map, scaling the capacity to **95%**. The map fills up to **28 monsters**.
2. **The Departure:** All 5 players leave the map simultaneously without killing anything. The map freezes with 28 monsters alive.
3. **Solo Entry:** You enter the map alone. The map unfreezes. The engine detects you and adjusts your legal cap to **75% (22 monsters)**. 
4. **The Over-Cap State:** The engine **does not** despawn the extra 6 monsters. You see 28 monsters on your screen and can successfully kill all of them for full Experience and Mesos.

### The Correction (Spawn Debt)
While you get to clear the over-populated wave, the engine strictly enforces the solo limit during the next respawn check:

* **Kill 1 Monster (27 remain):** 27 is higher than your solo cap of 22. **0 monsters spawn** on the next 7.56s tick.
* **Kill 6 Monsters (22 remain):** 22 is exactly at your solo cap. **0 monsters spawn** on the next 7.56s tick.
* **Kill the 7th Monster (21 remain):** The population is finally below your 22-monster cap. On the next tick, the server spawns **1 new monster** to bring you back to 22.

**Summary:** You receive a one-time "bonus" wave of extra monsters left behind by the group. Once cleared, the map permanently corrects itself down to your standard 75% capacity.

---

## How this maps to Emberwilds

This server-authoritative Godot RPG already had the bones of the model; the spawn
system was extended to match MapleStory's cadence rather than rebuilt.

| MapleStory concept | Emberwilds implementation |
| :--- | :--- |
| **Spawn-point cap** (§1) | `EnemySpawner.pool_size` — the spawner's fixed enemy pool *is* the physical spawn-point cap (the 100% / full-party value). |
| **Fixed tick** (§1) | `MapManager.SPAWN_TICK_INTERVAL`, **5.0 s** (our own cadence, not MapleStory's 7.56 s) — a single server-only global clock that emits `MapManager.spawn_tick`. Every `EnemySpawner` replenishes its map on that one signal — there is no per-enemy respawn timer anymore. |
| **Player-count scaling** (§2) | `EnemySpawner._current_capacity()` — `floor(pool_size × pct)`, `pct = clamp(0.75 + 0.05·(occupants−1), 0.75, 1.0)`. Occupancy is read from `MapManager.get_players_on_map(map_id)`. Because this game uses **bots as ambient population** (Erenshor pattern), bots count as occupants by default (`count_bots_as_players`, toggleable). |
| **Hibernation freeze** (§3) | Already provided by the ADR 0007 proximity-activation scanner: a zero-agent map sleeps every enemy (`activation_sleep`), and `_current_capacity()` returns **0** for zero occupants, so the tick never spawns and **never despawns** — survivors stay frozen. |
| **Re-entry unfreeze** (§3) | `MapManager._finalize_player_spawn` → `_replenish_map_spawners(map_id)` fires an immediate replenish the moment an agent arrives, so a re-entered map fills to 75% without waiting up to 7.56 s. |
| **Over-cap / spawn debt** (§4) | `_replenish()` only ever *adds* enemies (`to_spawn = cap − alive`, clamped to ≥0). When `alive ≥ cap` it spawns nothing and despawns nothing, so a party's leftover over-population is fully killable and corrects down naturally as it's cleared. |

### Notable differences (intentional)

- **`pool_size` is now the full-party cap, not the always-alive count.** A solo
  player sees `floor(0.75 × pool_size)` enemies. Authors who want a given *solo*
  density should set `pool_size ≈ desired_solo_count / 0.75`.
- **Hibernation persistence is bounded by the warm pool.** MapleStory freezes an
  empty map indefinitely; here, a fully-empty map is evicted ~20 s after its last
  agent leaves (ADR 0007 warm-pool evictor) and re-instantiated cold on the next
  visit, so the over-cap "bonus wave" only survives while the map stays warm.
- **Bots are occupants.** Unlike MapleStory's human-only count, roaming bots raise
  the cap by default, so a bot-populated map is denser — matching the
  living-world design goal. Set `count_bots_as_players = false` per spawner to
  restore human-only scaling.
- Scaling and the whole feature are per-spawner toggleable via
  `enable_population_scaling` (default on).
