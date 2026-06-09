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
   **A map missing from `MAP_SCENES` cannot be loaded.** Also add a themed entry
   to the adjacent `MAP_DISPLAY_NAMES` table (the loading screen reads it *before*
   the scene loads, so it can't use the instance's `display_name`).

4. **Portals.** Place portal scenes and set each portal's `target_map_id` (and
   target spawn-point name). `MapManager` builds its map-connectivity graph by
   scanning portals — bots use that graph to route between maps.

   **Spawn-point naming convention** (used across all maps): the arrival
   `Marker2D` in map **A** for travellers coming from map **B** is named
   `<APascal>_<BPascal>_Portal_Spawn` (PascalCase of the map ids, e.g.
   `Mines_Keep_Portal_Spawn`). A portal in **A** going to **B** therefore sets
   `target_spawn_point_name = "<BPascal>_<APascal>_Portal_Spawn"` — i.e. B's
   marker for arrivals from A. Secret portals use a `…Secret` suffix on the
   tokens (`NearWildsSecret_DeepWoodsSecret_Portal_Spawn`). Every portal target
   must match a real marker in the destination, or the player falls back to that
   map's `PlayerSpawn`.

5. **Bots** (optional). To let bots patrol/travel the new map, add it to
   `map_difficulty` (level band) and any relevant `patrol_route` arrays in
   `config/bot_config.json`.

6. **Test.** Portal into the map and confirm the spawn point, enemies, loot
   drops, BGM, and return portals all work. `DEFAULT_MAP` is `lanterns_rest`.

## Generating a map programmatically (headless, no editor)

You can author a complete painted map without opening Godot, using the build
tools in `tools/`. This is the reliable way for an agent to create maps, and it
fills the gap `tools/gen_emberwilds_maps.py` leaves (that one clones the template
and leaves geometry as a placeholder for an in-editor art pass). A
`TileMapLayer`'s painted cells live in an **opaque** `tile_map_data`
`PackedByteArray` (scene `format=4`; older scenes used `tile_data`
`PackedInt32Array`) — never hand-write it. Let the engine's own `set_cell()` +
`PackedScene.pack()` + `ResourceSaver.save()` emit it.

**Tools** (all are SceneTree `--script` runners; Godot is at
`C:\Program Files\Godot\Godot.exe`):

| File | Role |
|---|---|
| `tools/map_layouts.json` | Data-driven layout specs (one entry per map) |
| `tools/build_map.gd` | Builds + saves `scenes/Levels/<id>.tscn` from a layout |
| `tools/verify_map.gd` | Headless smoke test: loads, instantiates, asserts invariants |
| `tools/render_map.gd` | Renders the scene to `docs/render_<id>.png` to eyeball it |

```bash
GODOT="/c/Program Files/Godot/Godot.exe"
# 1. add/edit an entry in tools/map_layouts.json, then build:
"$GODOT" --headless --path . --script res://tools/build_map.gd -- <map_id>
# 2. register <map_id> in MAP_SCENES + MAP_DISPLAY_NAMES (step 3 above)
# 3. verify it loads + runs _ready with collision/portal/camera wired:
"$GODOT" --headless --path . --script res://tools/verify_map.gd -- <map_id>
# 4. (optional) eyeball the real in-engine render — needs a real driver:
"$GODOT" --path . --rendering-driver opengl3 --script res://tools/render_map.gd -- <map_id>
```

**How `build_map.gd` works** — it instantiates `map_template.tscn` (reusing its
TileSet, whose tiles already carry physics-collision polygons) **without adding
it to the tree** (so no node `_ready()` networking side effects), repaints the
`Mid` layer, wires the portal/killzone/spawn/enemy markers from the layout, then
packs and saves.

**Two gotchas that will silently break the output if ignored:**

1. **Run the build on the first `_process` frame, NOT in `_init()`.** Autoload
   singletons (`MapManager`, `ResourceManager`, …) only finish `_ready` after
   the first frame. `portal.gd` / `killzone.gd` reference those autoloads, so
   building in `_init()` loads them with *compile errors* and any
   `set("target_map_id", …)` on the portal **silently no-ops** — you get a map
   whose portals go nowhere. (Same reason `test/run_tests.gd` defers to
   `_process`.) `build_map.gd` already does this; preserve it.
2. **Do NOT build via `--editor`.** A headless `--editor --quit` run disables the
   resource-editor plugin in `project.godot` and re-serializes touched `.tres`.
   Use the plain `--script` runner above. (If you ever do run `--editor`,
   `git checkout -- project.godot resources/` afterward.)

**Tileset reference (Country village, `source_id = 1` in the template's
`TileSet_lbhrr`)** — tile size is **16px**. Solid grass-topped platform body:
grass top `(17,5)/(18,5)/(19,5)` (left/mid/right), dirt body
`(17,6)/(18,6)/(19,6)`; all carry full-square collision. `build_map.gd`'s
`_paint_platform()` lays these as `{x, y, w, depth}` (y = grass-top row).

**Traversal:** the player jump apex is ≈1.8 tiles (`jump_velocity -230`), so a
jump clears step-ups ≤1.5 tiles and gaps ≤3 tiles. For taller verticality use
**ladders** — `bot_nav_graph.gd` builds ladder edges, so **bots climb them too**
(the old "bots can't use ropes" note is outdated). Add them with a `ladders`
list: `{"x": col, "top": upper_surface_row, "bottom": lower_surface_row}`;
`build_map.gd` sizes a `ladder.tscn` to span the two surfaces. See
`docs/country_map_blueprints.html` for designed layouts and exact atlas coords.

**Layout entry schema** (`tools/map_layouts.json`):
```jsonc
"<map_id>": {
  "display_name": "Slime Meadow",      // ZoneBanner title
  "bgm_path": "",                        // res:// or uid:// audio, optional
  "tile": 16,
  "platforms": [ { "x": 0, "y": 14, "w": 44, "depth": 4 } ], // y = grass-top row
  "spawn": { "x": 2, "y": 13 },          // PlayerSpawn, in tile coords
  "portals": [ {
    "x": 42,                              // tile column; y auto-snaps so the
                                          // portal foot rests on the surface
                                          // beneath it (give "y" only to override)
    "target_map_id": "lanterns_rest",
    "target_spawn_point_name": "Meadow_Return_Spawn",
    "arrival_name": "Hub_Meadow_Spawn"   // Marker2D other maps' portals target
  } ],
  "spawners": [ {                          // each -> a real EnemySpawner node
    "enemy": "res://scenes/NPC/slime.tscn",
    "pool_size": 6, "respawn_delay": 5.0,
    "locations": [ { "x": 10, "y": 13 }, { "x": 18, "y": 13 } ]
  } ],
  "killzone_y": 19,                       // WorldBoundary plane row (below floor)
  "camera_top_padding": 400, "camera_bottom_padding": 80
}
```

**Enemies must use an `EnemySpawner`, not bare markers.** A loose `Marker2D`
under `Enemies` spawns nothing. Each `spawners` entry builds the same structure
as `ember_meadows`' `GoblinSpawner`: a `Node2D` + `enemy_spawner.gd` with the
chosen `enemy_scene`, child `Marker2D` spawn `locations`, a child
`MultiplayerSpawner` (so enemies replicate to clients), and `spawn_container`
pointed at the map's `Enemies` node. `build_map.gd`'s `_build_spawner()` wires all
of that. **Portals auto-align** to the ground: the builder finds the platform
under the portal's column and seats the portal's collision foot on its surface.

The reference maps `meadow_path` and `three_terraces` were generated this way
and pass `verify_map.gd`.

### paint_existing mode — add geometry to an already-authored map

For a map that already has portals/enemies/boss (e.g. the `gen_emberwilds_maps.py`
clones) but no real ground, set `"paint_existing": true`. The builder loads the
existing scene, repaints the `Mid` ground, and **keeps all authored content**,
repositioning it onto the new surfaces instead of rebuilding from template. Make
maps **vertical and decorated**, MapleStory-style:

```jsonc
"keep": {
  "paint_existing": true, "tile": 16, "killzone_y": 9,
  "platforms": [                                  // first = main ground; rest = tiers
    { "x": -36, "y": 2, "w": 72, "depth": 4 },
    { "x": -30, "y": 0, "w": 14, "depth": 1 },    // ramparts (negative y = higher up)
    { "x": -7,  "y": -2, "w": 14, "depth": 1 }
  ],
  "ladders": [ { "x": 0, "top": -2, "bottom": 2 } ],
  "portals": [ {                                   // reposition by NODE name onto a clear ledge
    "portal": "PortalToMines",                     // current node name
    "rename": "PortalToRuins",                     // optional: de-legacy the node name
    "arrival": "Keep_Mines_Portal_Spawn",          // co-located arrival marker, moved too
    "x": -35                                        // put it at a clear main-ground end (not under a tier!)
  } ],
  "decor": {
    "backfill": { "x": -37, "y": -3, "w": 75, "h": 10, "tile": [18, 6] },
    "props": [ { "kind": "house", "x": -6, "row": -2 }, { "kind": "bush", "x": -26, "row": 0 } ]
  }
}
```

**Big varied maps — `generate` spec.** Instead of hand-listing platforms, give a
compact `generate` block and the builder procedurally lays a map (deterministic,
seeded per map id) with ladders auto-connecting every platform to an overlapping
one below. **Pick a distinct `shape` per map so the set isn't samey** — real
MapleStory hunting maps run ~30–60 monsters and vary widely in layout:

| `shape` | Look | Good for |
|---|---|---|
| `cliffs` | asymmetric ledges jutting from alternating walls at jittered heights | sprawling caves (wide) |
| `stairs` | switchback staircase zig-zagging up | "Stairway to the Sky" climbs |
| `pyramid` | wide centred platforms narrowing as they rise (ziggurat) | symmetric arenas |
| `tower` | staggered platforms in zones per level | balanced; good narrow+tall "spire" |
| (omit + `boss_center`) | hand-listed open platforms | boss arenas (clear centre for telegraphs) |

Vary `main_w` (52 narrow spire … 96 wide cave) and `levels` too, so maps differ in
footprint, not just shape.
```jsonc
"generate": {
  "shape": "cliffs", "levels": 6, "level_height": 3,
  "pw_min": 9, "pw_max": 18,            // platform width range
  "step_w": 13,                          // stairs only
  "main_x": -48, "main_w": 96, "main_y": 2,
  "enemy_spacing": 5, "max_enemies": 55  // density: one enemy per ~5 tiles, capped
}
```
**Brand-new maps from a layout alone** (no pre-existing scene): use fresh mode
(omit `paint_existing`) with `generate` + a `populate` list of enemy scene paths.
The builder makes the tower, paints decoration, and instantiates the populate
enemies (cycling) densely across every platform — plus `spawn`/`portals`/`killzone`
as usual. This is how the bridge maps `thornroot` (cliffs) and `dust_warren`
(pyramid) were made to fill the lv 22–39 gap. **Check the enemy roster for level
gaps** (`ED_*.tres` `monster_level`) — unused mid-tier enemies usually mean a
missing map. Aim for contiguous ~6–10-level bands so progression doesn't jump.

The enemy population is made DENSE by **cloning** the map's existing instances
(by their `scene_file_path`, cycling types) until every platform slot is filled —
so a map that shipped with 15 floaters becomes 30-50 enemies spread feet-on-grass
across every tier. Clones are named `Clone_*` and purged on rebuild so density
doesn't compound. For a boss arena, skip `generate`, hand-list a few open
platforms, and set `"boss_center": true` (centers the boss, leaves the middle
clear). The rock backfill auto-sizes to the whole platform tower; `decor` props:
`ground_props` (anchored on the main ground) and `scatter` (a prop on alternating
upper platforms).

### MapleStory design principles (grind-map quality)

Full write-up: [maplestory_map_design.md](maplestory_map_design.md). Apply these
when choosing a layout, density, and mob set — a map is a *rotation* (a clearing
loop), not just a pile of platforms:

- **Density 25–40+ mobs.** Our `enemy_spacing`/`max_enemies` target ~30–55; never
  ship ~15 or it bottlenecks XP/loot. Aim so a player clears the whole map in
  roughly one respawn window (don't leave them idle waiting for the next wave).
- **Design the rotation.** Pick a shape whose loop clears everything with minimal
  backtracking:
  - *Horizontal lazy-grinder* — long flat platforms stacked tightly; run one way
    spamming, turn, repeat. Lowest friction, best for early/transition maps (wide
    `main_w`, big `pw`, small `level_height`).
  - *Vertical loop* — clear top, drop tier by tier, then a **bottom→top return
    portal** restarts the loop instantly (gravity does the travel). For tall
    `stairs`/`tower` maps add a portal at the base whose `target_map_id` is the
    SAME map and whose `target_spawn_point_name` is a marker on the top platform —
    ladders alone kill momentum.
  - *Compact stay-in-place* — small map, mobs spawn around the centre; outliers
    handled by summons/pets (small `main_w`, few `levels`).
- **Tier spacing vs. attack reach.** Stack grind tiers close (~1–2 tiles) so a
  player hits the tier above without jumping; far tiers force a jump-attack per
  platform (fatigue). Reserve 3-tile gaps + ladders for *traversal* sections, not
  the core grind floor. (Jump apex ≈1.8 tiles.)
- **Mob hitboxes.** Prefer grounded, normal-sized mobs for grind maps; tiny or
  flying mobs slip under/over attacks and leave stragglers that break the loop —
  choose `populate` enemies accordingly.
- **Loot on the path.** Don't scatter platforms so jaggedly that drops land
  unreachable; the pet auto-loot follows the kill rotation, so keep platform tops
  broad and aligned.
- **One-shot timing.** The wave rhythm assumes mobs die fast at the intended
  level (see the enemy-level-balance memory); anchor mob `monster_level` to the
  band's low end so they don't take 3 hits and desync the rotation.

### Engine-architecture references → our Godot equivalents

Deeper reference (MapleStory's `.wz` data model, foothold math, VR camera, portal
types, MSW Lua): [maplestory_complete_encyclopedia.md](maplestory_complete_encyclopedia.md)
and [maplestory_architecture_encyclopedia.md](maplestory_architecture_encyclopedia.md).
Most of it is engine-specific, but several concepts map directly onto how we build
maps here — translate, don't copy:

| MapleStory concept | Our Godot equivalent / action |
|---|---|
| **VR camera quad** (`VRTop/Bottom/Left/Right`) | `MapBase` already auto-computes camera limits from the `Mid` layer's `used_rect` + padding — that *is* the VR quad. Keep the `Mid` extent tight to the play area. |
| **Footholds** (vector floor segments) | Collision comes from the TileSet physics polygons on the `Mid` layer; painted grass-top cells are the footholds. |
| **Down-jump / thin one-way platforms** | The project has one-way/drop-through platform support — use thin upper tiers so a vertical-loop map lets players *dive* down through platforms (don't make every tier solid). |
| **Portal types** (0 start, 2 ordinary/press-Up, 3 collision/instant) | `PlayerSpawn` = the Type-0 start point. Our `portal.tscn` is an `Area2D` `body_entered` trigger (≈ Type 3 instant) with an interact label. For the **vertical-loop bottom→top**, use an instant touch portal whose target is the *same map's* top-platform marker. |
| **`town` safe-zone, `fieldLimit`, `lvLimit`** | Design intents, not engine flags: `lanterns_rest` is the town/safe hub; a boss arena (warlord) is the "no-escape" map; level gating lives in bot `map_difficulty` bands (mirror it for players if you add gates). |
| **Parallax `back` layers + `rx/ry` scroll ratios, Z-sorting** | We decorate on `Background` (z −3) / `Background2` (z −2); for real depth add a `ParallaxBackground` with the `Country.png` parallax art behind those. Z-index batching = keep decoration on those two layers. |
| **Spawn restricted on short platforms** | Our slot generator only places on platform tops; keep generated platforms wide enough (`pw_min` ≥ ~6) so wandering mobs don't walk off. |
| **High density vs packet throttle / tick-rate** | Server-authoritative netcode makes 40+ synced mobs costly — but ADR 0007 proximity activation sleeps far enemies, so dense static populations are cheap until a player is near. That's why we can afford 30–55 mobs/map. |
| **`onUserEnter` / dynamic spawn-wave top-up** | Our `EnemySpawner` (pooled, respawn_delay) is the closest analog; static `populate` maps don't respawn. Use spawners where you want sustained waves. |

What the builder does in this mode (`_decorate_and_populate`):
- **Decoration uses the non-physics layers.** `backfill` paints a rock rectangle
  on the `Background` layer (z -3, `collision_enabled = false`, **darkened via
  `modulate`** so it recedes as a cave wall behind the platforms). `props`
  (`bigtree`/`smalltree`/`house`/`bush` in `PROP_DEFS`) stamp full-colour onto
  `Background2` (z -2) from the props atlas (source 2); missing atlas tiles are
  auto-created. Never paint decoration on `Mid` — it would collide.
- **Enemies are repositioned**, not respawned: `_distribute_enemies` spreads the
  existing instances across all platform tops, ≥1 per tier; a lone enemy (boss)
  is centered on the main ground (keep the arena center clear for telegraphs).
  Enemy sprites are drawn ABOVE the node origin (32px frame centred at sprite-y
  ≈ −20), so feet ≈ origin − 4. To plant feet on the grass the origin is nudged
  DOWN past the surface row: `origin = surface + ENEMY_SURFACE_NUDGE` (≈4). Origin
  *at* the surface looks like it floats; this matches the hand-placed `ruins`.
- **Ladders connect an upper tier to a lower one**, poking `LADDER_POKE` px above
  the upper platform and hanging down to the lower surface so you can jump onto
  it from below (look at `ruins`). They're **built from scratch, not instanced** —
  `PackedScene.pack()` silently drops instance-CHILD overrides, so resizing an
  instanced `ladder.tscn`'s CollisionShape/NinePatchRect produces a bare,
  zero-size ladder. (Instance ROOT properties like a portal's `target_map_id`
  DO serialize; only nested-child edits are lost.)
- **Portals** are moved to their `x` on the topmost platform there and foot-aligned.
  Put portal `x` at a column **no tier covers** (a clear main-ground end) or the
  portal ends up embedded in a ledge.

Pitfalls that bit prior passes: painting ground under content left at `y=16`
floats it; a themed ledge at a portal's column buries the portal; an instanced
ladder loses its resize. Always render (`render_map.gd`, incl. its `focus` crop
mode) and eyeball before trusting a layout.
