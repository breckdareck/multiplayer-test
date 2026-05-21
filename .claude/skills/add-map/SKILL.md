---
name: add-map
description: >-
  Use when creating or editing a map/level/zone for this Godot RPG. Covers the
  scene structure, the required nodes, registering the map with MapManager, and
  wiring portals.
paths: scenes/Levels/**, scripts/Gameplay/**
---

# Adding a map

Maps are scenes under `scenes/Levels/`. `MapManager` instantiates them
server-side and streams them to clients.

## Steps

1. **Create the scene** `scenes/Levels/<map_id>.tscn`. The root is a `Node2D`
   with the `MapBase` script (`scripts/Gameplay/map_base.gd`), or a script
   extending it. Set `bgm_path` for per-map background music.

2. **Required child nodes:**
   - `Players` — empty; `MapManager` spawns player/bot characters into it.
   - A spawn point — name it `PlayerSpawn` (the `MapManager` default), or
     `SpawnPoint` / `Spawn`. Add extra named nodes for portal-specific arrivals.
   - `Enemies` — holds enemies and enemy spawners.
   - `GlobalDropHandler` — **required** for loot to drop; `enemy_base.gd` looks
     for it by this name on the map.
   - Level geometry (tilemap / platforms). Physics layers: `World` = 1,
     `Platforms` = 3.
   - `Projectiles` is created on demand if absent, but add it for clarity.

3. **Register the map.** Add an entry to the `MAP_SCENES` constant in
   `scripts/Managers/map_manager.gd`:
   ```gdscript
   const MAP_SCENES = {
       ...
       "<map_id>": "res://scenes/Levels/<map_id>.tscn",
   }
   ```
   **A map missing from `MAP_SCENES` cannot be loaded.**

4. **Portals.** Place portal scenes and set each portal's `target_map_id` (and
   target spawn-point name). `MapManager` builds its map-connectivity graph by
   scanning portals — bots use that graph to route between maps.

5. **Bots** (optional). To let bots patrol/travel the new map, add it to
   `map_difficulty` (level band) and any relevant `patrol_route` arrays in
   `config/bot_config.json`.

6. **Test.** Portal into the map and confirm the spawn point, enemies, loot
   drops, BGM, and return portals all work. `DEFAULT_MAP` is `town`.
