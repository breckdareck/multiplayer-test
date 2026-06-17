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

### Visualize spawns + migrate hard-placed enemies (tools added 2026-06-16)

Two **map-agnostic** tools that work on any map's `.tscn`, however it was built.
Godot is at `C:\Program Files\Godot\Godot.exe`; edit the `MAPS` list at the top of
each `.gd` to choose which maps to process.

**Annotated spawn previews (meowdb-style)** — use these whenever you show a map
preview, so spawn points + the enemy roster are visible:
- `tools/render_map_previews.gd` reads each scene, renders it faithfully from the
  tile layers, and extracts every spawner's enemy type + `pool_size` + each spawn
  marker projected into image pixels → `docs/map_previews/<map>.png` + `spawns.json`.
- `tools/annotate_map_previews.py` (`pip install Pillow`) draws numbered, colour-coded
  pins (one per spawn marker) + a legend listing each enemy with its **spawn-point
  count and pool size** → `docs/map_previews/<map>_annotated.png`.
```bash
"$GODOT" --headless --path . --script res://tools/render_map_previews.gd
python tools/annotate_map_previews.py
```
The renderer parses the `TileMap` node's `position` to align pins with tiles, so it
is correct even for maps whose layers are offset (e.g. ruins clones at `-119,-269`).

**Convert hard-placed enemies → pooled spawners** — `tools/convert_to_spawners.gd`
rewrites a map that places enemy *instances* under `Enemies` into the pooled method:
one `EnemySpawner` per enemy type, a `Marker2D` per original enemy **10px above** its
old spot, `pool_size` = that type's count, + a `MultiplayerSpawner` child wired with
`enemy_spawner = NodePath("..")`. **Bosses** (any instance that sets `respawn_delay`)
and friendly NPCs (training_dummy / merchant / quest_giver) are left in place. It is
idempotent (a converted map has no instances left to convert).
```bash
"$GODOT" --headless --path . --script res://tools/convert_to_spawners.gd
```
This put all combat maps on the new method (2026-06-16). **Hard-placed enemies do
not respawn** under the current system — no spawner listens for their death — which
is why bare instances under `Enemies` must become spawners.

**Spawn-marker convention:** put markers ~**10px above** the ground (or just reuse
the current enemy spot lifted 10px). `pool_size` is the MapleStory 100% / full-party
cap; a **solo** player sees `floor(0.75 * pool_size)`, ramping +5%/occupant to 100%
at 6 occupants (bots count). Respawns ride `MapManager.spawn_tick` (every **5s**,
`SPAWN_TICK_INTERVAL`); `respawn_delay` on the spawner is deprecated. Markers are
candidate spots chosen at random per spawn — they set WHERE, `pool_size` sets HOW
MANY (so they need not equal; more pool than markers guarantees doubling-up).

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

### Vertical layout, safe perches & ropes (authoritative rules — mines hand-edit pass, 2026-06-17)

Established interactively with the user; these OVERRIDE looser defaults above and apply
whether building from a layout or fixing a hand-edited map.

**Training platforms** — FEW and LONG, not many short stubs. ~**17–19 tiles** wide so a
player can pace and fight a pack with room (the complaint was "barren for how long they
are" AND, separately, "too many and not long enough"). Tiers ~5 rows apart, columns
staggered between tiers.

**Headroom / ceilings** — a ceiling counts as ground too: leave enough vertical room above
every walkable surface for a player to stand AND jump (~3 tiles clear) without hitting the
ceiling above. In caves, keep the spiky ceiling band well above the top tier; don't let a
stalactite hang into a platform's jump space.

**Safe rest platforms** — small (**3–5 tiles**), **ISOLATED** (floating, NOT connected to
any training platform — gaps all around), reached by **ONE short access rope**. Place each
in an **open gap, clear of the tier climbs** — NEVER where the tier platforms converge (a
perch jammed into the convergence makes ropes pile through it; give it breathing room, e.g.
hang it over a row-gap above a wide ledge). Enemies never spawn on them. A few per map.

**Ropes/ladders** — SHORT and few:
- **One per platform** — every platform needs just *a* way up; no redundant climbs. Do NOT
  thread one tall rope through multiple tiers (the "optimal" multi-tier shaft was explicitly
  rejected).
- **Connect only ADJACENT levels** — a rope bridges a platform to the one directly below
  (or a perch to the platform below it).
- **Hang above the surface below** — rope bottom sits ~**2 tiles above** the lower surface
  (a jump-and-grab gap); it must **NEVER touch** the ground/platform beneath. Top reaches
  the platform being climbed to. Exception: a platform with nothing directly beneath gets one
  longer rope to the floor.
- Rope = `Area2D` + `RectangleShape2D` (climb zone) + `NinePatchRect` (visual) + `ladder.gd`;
  build from scratch (instancing drops child-resize overrides). Bots climb them.

**Spawn placement** — enemies go on flat top-surface stretches only; EXCLUDE the ceiling/roof
(a real spawn surface has solid above it in-column, else it's the roof top), the safe perches,
and a thin column buffer at each portal/spawn edge so a player isn't dropped onto a mob.

**Density** — `pool_size` is the COUNT lever (solo sees `floor(0.75 * sum of all spawner
pools)` alive map-wide); markers only set WHERE (each spawn picks a random marker). For long
platforms aim ~3–4 enemies each: ~10–12 markers/spawner and pools ~10–12. Barren long
platforms = too few markers AND too-small pools — raise both.

### Wiring the whole world's portal graph (branching, lore-accurate — 2026-06-17)

The lore's gazetteer (docs/LORE.md, "the road, in level order") is the source of truth for which
maps exist, their level band, and the order to the final boss (Eternal Warlord @ `warlord`, lv 100).
Two safe Hearth hubs anchor it: **Lantern's Rest** (home, lv 1) and **Emberwatch** (forward, ~48).
The user wants MapleStory-style BRANCHING, not a single chain: each hub fans out to several maps,
same-band maps cross-link, and there can be more than one route forward.

`tools/rebuild_portals.gd` rebuilds the entire portal graph from a `GRAPH` adjacency dict (+ a
`TOKEN` map for the marker-name convention, + a `LEVEL` map for ordering). Per map it: clears old
portal instances + `*_Portal_Spawn` markers, then lays one (portal + co-located arrival marker)
pair per connection, spread across the map's FLOOR (seated on the ground via the Mid bottom-run
top), ordered left→right by destination level. Names follow `<OtherToken>_<ThisToken>_Portal_Spawn`
for the target and `<ThisToken>_<OtherToken>_Portal_Spawn` for the arrival marker. Tokens are NOT
pure PascalCase — extract them from existing markers (meadow_path→`Meadow`, three_terraces→`Terraces`).
GRAPH must be symmetric (A lists B ⟺ B lists A) or you get one-way doors.

Verify after: (1) `tools/check_load.gd` smoke-loads every map; (2) grep each portal's
`target_spawn_point_name` against `name="…"` in the target scene (0 misses); (3) regenerate
`config/world_map_data.json` via `tools/dump_world_map.gd` (it emits per-map `connections` +
`min/max/avg_level` + `enemies`; an autoload compile-warning is non-fatal — check it still prints
"wrote …"). Realign bot routing bands in `config/bot_config.json` `map_difficulty` to the lore
levels in the same pass.

Watch for a generator bug: a spawner's `enemy_scene` ext_resource can disagree with its
`MultiplayerSpawner` `_spawnable_scenes` uid and its node name (mines shipped goblins while named/
whitelisted for Wolf Pathfinder etc.). The name + replication uid are the intent; fix `enemy_scene`
to match, and the map's level band falls back into place.

**Transition safety — `tools/clear_portal_spawns.gd`.** After (re)wiring portals, run this map-agnostic
pass: it moves any enemy spawn marker sitting within ~4 tiles of a portal off to a clear floor column,
so portaling in never drops you onto a mob. Only floor-level markers near a door move (platform markers
above stay); matches any `M#` Marker2D regardless of spawner naming (`Spawn_*` OR `<Enemy>Spawner`).
Idempotent — a second pass should move 0. Do this INSTEAD of re-running fix_spawns on generate-built
maps (build_map already distributes their enemies on platforms thoughtfully; a full re-place would undo that).

**Adding maps for branching.** Author a `generate` spec in `tools/map_layouts.json` (NO `portals` key —
let rebuild_portals wire them), `build_map.gd` it, register in `MAP_SCENES` + `MAP_DISPLAY_NAMES`, then
`convert_to_spawners.gd` (the `populate` path makes hard-placed instances that DON'T respawn — convert
them to pooled spawners). Gotcha: `convert_to_spawners`'s node regex must match to end-of-line
(`[^\n]*\]` not `[^\]]*\]`), or the `groups=[…]` `]` inside newer Mob headers truncates it and it finds
"no enemies". A safe hub = a `generate` with no `populate` (terrain, zero enemies — e.g. Ashvigil).

### Fixing a hand-edited map (surgery toolset — mines pass, 2026-06-17)

When the user hand-edits a map's terrain in the editor and asks to fix spawns / platforms /
ropes, use these headless tools (`tools/`, each with a `MAP :=` const at the top — point it at
the target map). They decode the live `.tscn`, so they work regardless of how the map was built
or which tileset tiles were used. Verify with the schematic, NOT a tile-art render (the user may
have added tiles at atlas coords you don't know). Godot at `C:\Program Files\Godot\Godot.exe`.

| Tool | Role |
|---|---|
| `tools/fix_spawns.gd` | Re-snap every `Spawn_*` marker + `PlayerSpawn` onto flat surfaces; excludes roof + safe perches (`SAFE_PLATFORMS`) + edge buffer (`EDGE_SAFE`). Re-run after ANY platform/terrain move. |
| `tools/rebuild_platforms.gd` | Clear tier rows + relay platforms from a `NEW` dict (row → spans); reuses the rock-top L/M/R tiles already on those rows. |
| `tools/rebuild_ropes.gd` | Replace all ropes from a `ROPES` list of short `[col, top_row, bottom_row]` climbs (per the rope rules above). |
| `tools/add_markers.gd` | Raise density: grow markers per spawner to `TARGET` + bump `pool_size`. |
| `tools/verify_spawns.gd` | Tile-art-independent schematic → `docs/map_previews/_<map>_spawncheck.png`: terrain blocks, enemies (red), player (green), safe surfaces (cyan), ropes (yellow). Prints rope col+row spans + a floating-marker count (target 0). |

Typical loop: `rebuild_platforms → rebuild_ropes → add_markers (if sparse) → fix_spawns →
verify_spawns`, then eyeball the schematic. Keep `SAFE_PLATFORMS`/`EDGE_SAFE` in sync between
fix_spawns and verify_spawns. Mines-style cloned-map geometry: TileMap offset `(-119,-269)`;
tile(col,row)→world `(col*16-111, row*16-269)` (centred).

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
