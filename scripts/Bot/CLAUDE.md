# AI bots

Server-side AI players. A bot drives the *same* `MultiplayerPlayerV2` character a
human would — it just supplies input flags instead of a keyboard.

## Files

`bot_brain.gd` is the orchestrator — it owns the think loop and delegates
combat / navigation / economy / equipment decisions to sibling modules so
each piece stays small.

| File | Role |
|---|---|
| `bot_manager.gd` | Autoload. Spawns/despawns bots, owns `/bot` chat commands, loads `config/bot_config.json`, caches per-map nav graphs |
| `bot_brain.gd` | Per-bot think-loop FSM (idle / wander / fight / retreat / loot / travel); routes the decision through priority "considerations" and writes input flags onto the character |
| `bot_combat.gd` | Combat sub-module: target selection, attack timing, ability use; also spends ability + attribute points (see [Progression](#progression--spending-points-under-the-weapon-system)) |
| `bot_navigator.gd` | Per-bot navigation: queries `bot_nav_graph` for waypoint paths and steers the bot via input flags, with a periodic repath |
| `bot_nav_graph.gd` | Runtime-built nav graph from the map's tilemap (WALK / JUMP / DROP / GAP edges across `TileMapLayer.get_used_rect()`); built incrementally a few columns per frame; cached per `map_id` on `BotManager` |
| `bot_economy.gd` | Inventory pickup, gold management, sell decisions |
| `bot_equipment_logic.gd` | Scores gear and decides equip/sell swaps |
| `bot_debug_draw.gd` | Debug-overlay rendering for `/bot watch` and the backtick `DebugPanel` bot view (targets, HP bars, nav-graph sub-layers) |

## Key facts

- **Bots have negative peer IDs.** `BotManager.is_bot(id)` is exactly `id < 0`.
- **A bot has no client.** On spawn it frees its whole `CanvasLayer` UI subtree.
  Never send a bot a node-addressed RPC; never assume a bot has buff/hotbar UI.
- **The brain outlives the body.** `BotBrain` is parented to `BotManager`, not the
  character. As of ADR 0008 a bot map change **reparents the SAME live body** between
  maps (no free/recreate); `MapManager` then calls `BotManager.handle_bot_reparented()`
  → `attach_to_player()` to reset the brain's transient targets/nav for the new map
  while preserving travel timers, patrol progress, and cooldowns. (A bot's *first*
  spawn — and the recreate fallback — still build a fresh body.)
- **Bots are server-only.** All bot logic is gated behind `multiplayer.is_server()`.

## The think loop

`bot_brain._process()` ticks several timers and, every `think_interval` (~0.3s),
runs `_think()`, which sets `current_action`. `_apply_current_action()` then
translates that action into input flags on the character (`player.direction`,
`player.do_attack`, `player.do_jump`, `player.do_pickup`, …). The server's normal
character `_physics_process` consumes those flags — the bot never moves the body
directly. Add new behaviour by extending the `_think()` decision tree and the
`_apply_current_action()` match.

## Progression — spending points under the weapon system

A bot spends its own points to build toward its weapon identity; both spends run
in `bot_combat.build_ability_lists()`, ticked on the brain's ability timer
(~5s). They call the **server-side** component methods directly (bots have no
client to RPC).

- **Ability points** (`_auto_spend_ability_points`) — a purposeful value-weighted
  greedy, not random: each point goes to the highest *value/point* ability
  (role weight × `1/(level+1)` marginal gain), so early points spread into a
  usable kit and later points deepen the signature attack skills; once an ability
  maxes, leftover points reinvest into its upgrades (`purchase_upgrade`, lower
  tiers first). `AbilityComponent`'s per-discipline pool gating means a
  discipline's points only ever buy that discipline's content.
- **Attribute points** (`_auto_spend_attribute_points`) — allocates on the
  discipline's `stat_bonuses` ratio plus a CONSTITUTION survival bias, topping up
  only the shortfall vs. what's already spent (never unallocates, never fights the
  migration default-allocation).

**Where the points come from:** attribute points are granted by **character
level**; ability points are granted only by **weapon-mastery** level-ups
(`mastery_level_changed` → `AbilityComponent._add_ability_points`). Mastery XP is
earned **on kill** (`CombatComponent.grant_mastery_xp_server`), which fires for
bots since they deal real damage — so a grinding bot accrues both naturally.

## Configuration — `config/bot_config.json`

```jsonc
{
  "auto_spawn": true,            // spawn bots when the server starts
  "default_map": "game",
  "bots": [                      // one entry per bot; name "random" auto-generates
    { "name": "Bob", "class": "SWORDSMAN", "map": "town",
      "patrol_route": ["game", "game2", "game3"] }
  ],
  "behavior": { },               // think_interval, ranges, durations - copied into each brain
  "map_difficulty": {            // per-map level band; bots travel to stay in-band
    "game": { "min_level": 1, "max_level": 20 }
  }
}
```

Reload at runtime with `/bot reload_config` — it only affects bots spawned
afterward.

A bot spawned via `/bot spawn` has no `bots[]` entry, so no configured
`patrol_route`. `BotManager._default_patrol_route()` substitutes every map in
`map_difficulty`, sorted by `min_level`, so a manually-spawned bot still has a
way to leave town after its first restock trip (without this fallback,
`_should_change_map` returns false on town and the bot wedges there).

## `/bot` commands

`spawn`, `despawn`, `despawn_all`, `list`, `teleport`, `set_level`, `party`,
`travel info`, `inspect`, `trade`, `reload_config` — dispatched by
`BotManager.handle_command()`.

`set_level` pumps character EXP **and** raises the bot's primary-discipline
mastery to match (one mastery level per character level, capped at
`MASTERY_CAP`) — without that, a force-levelled test bot would have attribute
points but no ability points (which are mastery-gated), leaving it skill-less.
