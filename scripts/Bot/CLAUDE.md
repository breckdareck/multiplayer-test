# AI bots

Server-side AI players. A bot drives the *same* `MultiplayerPlayerV2` character a
human would — it just supplies input flags instead of a keyboard.

## Files

| File | Role |
|---|---|
| `bot_manager.gd` | Autoload. Spawns/despawns bots, owns `/bot` chat commands, loads `config/bot_config.json` |
| `bot_brain.gd` | Per-bot AI: a think-loop FSM (idle / wander / fight / retreat / loot / travel) |
| `bot_equipment_logic.gd` | Scores gear and decides equip/sell swaps |

## Key facts

- **Bots have negative peer IDs.** `BotManager.is_bot(id)` is exactly `id < 0`.
- **A bot has no client.** On spawn it frees its whole `CanvasLayer` UI subtree.
  Never send a bot a node-addressed RPC; never assume a bot has buff/hotbar UI.
- **The brain outlives the body.** `BotBrain` is parented to `BotManager`, not the
  character. A map change frees and recreates the character node; the brain is then
  re-pointed at the new body via `attach_to_player()`, preserving travel timers,
  patrol progress, and cooldowns.
- **Bots are server-only.** All bot logic is gated behind `multiplayer.is_server()`.

## The think loop

`bot_brain._process()` ticks several timers and, every `think_interval` (~0.3s),
runs `_think()`, which sets `current_action`. `_apply_current_action()` then
translates that action into input flags on the character (`player.direction`,
`player.do_attack`, `player.do_jump`, `player.do_pickup`, …). The server's normal
character `_physics_process` consumes those flags — the bot never moves the body
directly. Add new behaviour by extending the `_think()` decision tree and the
`_apply_current_action()` match.

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

## `/bot` commands

`spawn`, `despawn`, `despawn_all`, `list`, `teleport`, `set_level`, `party`,
`travel info`, `inspect`, `trade`, `reload_config` — dispatched by
`BotManager.handle_command()`.
