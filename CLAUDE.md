# CLAUDE.md

Guidance for Claude Code in this repository. This is the **lean root** — it holds
only repo-wide truths. Each major subsystem carries its own `CLAUDE.md` that loads
additively when you work in that directory; see [Subsystem guides](#subsystem-guides).

## What this is

A **server-authoritative multiplayer RPG** built in Godot 4, with a Flask +
PostgreSQL backend for account and character persistence.

**The rule that governs everything:** the server owns all critical state. Clients
send *intent* via RPCs; the server validates it, mutates state, and broadcasts the
authoritative result back. Never mutate health, stats, inventory, drops, abilities,
or progression on a client and assume it sticks — it will be overwritten.

## Running the game

- **Engine**: Godot 4.5+ (Forward Plus rendering)
- **Main scene**: `scenes/UI/LoginScreen.tscn`
- **Run in editor**: F5
- **Local multiplayer testing**: launch extra instances from the editor's Debug
  menu, or run the exported binary
- **Dedicated server** (headless):
  `godot --headless --feature dedicated_server --path . -- --port 8080`
- **Windows helpers**: `start_server.bat` / `stop_server.bat`

## Backend (required for account/character persistence)

```
docker-compose up -d
```

| Service | URL / port | Credentials |
|---|---|---|
| Flask API | http://localhost:5000 | — |
| PostgreSQL | localhost:5432 | `postgres` / `password` / db `gamedb` |
| Adminer (DB UI) | http://localhost:8080 | — |

Logs: `docker-compose logs api`. Schema and endpoint conventions live in
[backend/CLAUDE.md](backend/CLAUDE.md).

## Autoload singletons

Registered in `project.godot`; globally accessible by name from any script.

| Singleton | Script | Purpose |
|---|---|---|
| `MultiplayerManager` | `scripts/Managers/multiplayer_manager.gd` | Host/join, channel switching, level loading; emits `server_has_started` |
| `ServerManager` | `scripts/Networking/server_manager.gd` | ENet server lifecycle |
| `ClientManager` | `scripts/Networking/client_manager.gd` | ENet client connection |
| `PlayerManager` | `scripts/Networking/player_manager.gd` | Player/bot spawn & cleanup, player-node lookup |
| `ChannelManager` | `scripts/Networking/channel_manager.gd` | Port switching without a restart |
| `NetworkUtils` | `scripts/Networking/network_utils.gd` | IP/port validation, scene helpers |
| `NetworkManager` | `scripts/Networking/network_manager.gd` | Backend HTTP API (login, characters, save/load) |
| `ResourceManager` | `scripts/Managers/resource_manager.gd` | Loads & caches ability/item/buff/class `.tres` |
| `SaveManager` | `scripts/Managers/save_manager.gd` | Debounced player-data persistence |
| `MapManager` | `scripts/Managers/map_manager.gd` | Map registry, transitions, visibility, spawning |
| `PartyManager` | `scripts/Managers/party_manager.gd` | Party creation/joining |
| `BotManager` | `scripts/Bot/bot_manager.gd` | Server-side AI bot lifecycle, `/bot` commands |
| `TradeManager` | `scripts/Trading/trade_manager.gd` | Player-to-player trading |
| `QuestManager` | `scripts/Managers/quest_manager.gd` | Quest tracking and objectives |
| `JobAdvancementManager` | `scripts/Managers/job_advancement_manager.gd` | Class advancement at level 30 |
| `ChatManager` | `scripts/Managers/ChatManager.gd` | In-game messaging and slash commands |
| `KeybindManager` | `scripts/Managers/keybind_manager.gd` | Custom keybindings |
| `UserConfig` | `scripts/Managers/user_config.gd` | User-preference persistence |
| `InputManager` | `scripts/Managers/InputManager.gd` | Global input lock/unlock |
| `AudioManager` | `scripts/Managers/audio_manager.gd` | Music and SFX |
| `LogManager` | `scripts/Managers/LogManager.gd` | In-game debug logging |
| `DebugPanel` | `scripts/UI/debug_panel.gd` | Backtick-toggled in-game debug / bot overlay |

## RPC conventions

```gdscript
# Server -> all peers (authoritative state). call_local: the host is also a
# client, so it must run the update too.
@rpc("authority", "call_local", "reliable")

# Client -> server (intent request). Always guard the body:
@rpc("any_peer", "call_local", "reliable")
func do_something_server(arg) -> void:
    if not multiplayer.is_server():
        return
    ...

# Server -> clients only (the server must NOT run it itself):
@rpc("authority", "call_remote", "reliable")
```

- The **server is always peer ID 1**. Clients reach it with `rpc_id(1, ...)`.
- Guard server-only logic with `if not multiplayer.is_server(): return` (or
  `is_multiplayer_authority()` for per-entity authority).
- **Bots have negative peer IDs** and no client. Never send a node-addressed RPC
  to a bot — route bot-related visuals through an autoload (e.g. `MapManager`),
  which resolves on every peer. See [scripts/Bot/CLAUDE.md](scripts/Bot/CLAUDE.md).

Full networking detail: [scripts/Networking/CLAUDE.md](scripts/Networking/CLAUDE.md).

## Global groups

- `networked_entities` — every network-spawned node; cleared on disconnect /
  channel switch. Add new networked entities to this group.
- `Players` — player (and bot) character nodes.
- `Enemies` — enemy nodes. This group is **global across all maps**; filter by map
  when iterating (see how `bot_brain.gd` does it).

## Persistence

Two layers:

- **Account / character records** → PostgreSQL via the Flask API. `username` is
  the unique **character name**. See [backend/CLAUDE.md](backend/CLAUDE.md).
- **In-game character state** (health, level, exp, abilities, buffs, equipment,
  inventory, monies) → persisted through `SaveManager` to the backend.

## Component-based characters

Player and enemy characters are composed of `Node` components under a root
character node (`Player/Components/Health`, `.../Stats`, …). The root player
script is `scripts/Player/multiplayer_controller_v2.gd` (`MultiplayerPlayerV2`).
See [scripts/Components/CLAUDE.md](scripts/Components/CLAUDE.md).

## Data-driven content

Game content is Godot `.tres` resources under `resources/`, defined by classes in
`scripts/Resources/`. `ResourceManager` auto-loads abilities, items, buffs, and
classes recursively — no manual registration. See
[scripts/Resources/CLAUDE.md](scripts/Resources/CLAUDE.md).

## Subsystem guides

| Area | Guide |
|---|---|
| Networking, RPCs, ENet, channels | [scripts/Networking/CLAUDE.md](scripts/Networking/CLAUDE.md) |
| Character components | [scripts/Components/CLAUDE.md](scripts/Components/CLAUDE.md) |
| Data resource classes | [scripts/Resources/CLAUDE.md](scripts/Resources/CLAUDE.md) |
| AI bots | [scripts/Bot/CLAUDE.md](scripts/Bot/CLAUDE.md) |
| Backend (Flask / Postgres) | [backend/CLAUDE.md](backend/CLAUDE.md) |

## Skills — workflow recipes

Repeatable workflows packaged as Claude Code skills under `.claude/skills/`.
The `add-*` skills are path-scoped and load automatically when you work in
the matching files; `grill-with-docs` is intent-triggered (no path scope) —
invoke it when you want to stress-test a plan before building.

| Skill | Use when |
|---|---|
| `add-ability` | Creating/editing an ability (`resources/Abilities/`, `scripts/Abilities/`) |
| `add-buff` | Creating/editing a buff or debuff (`resources/Buffs/`, `scripts/Buffs/`) |
| `add-item` | Creating a weapon, armor, or consumable (`resources/Items/`) |
| `add-enemy` | Creating an enemy (`resources/Enemies/`, `scenes/NPC/`) |
| `add-map` | Creating a map/level (`scenes/Levels/`) |
| `add-backend-endpoint` | Adding a Flask route or model (`backend/`) |
| `grill-with-docs` | Socratic interview that stress-tests a plan against this repo's server-authoritative invariants, components, .tres content, RPC patterns, and persistence layers; maintains `CONTEXT.md` glossary and `docs/adr/`. No path scope — invoke by intent. |

## The AI Layer

This repo's Claude Code configuration — the CLAUDE.md hierarchy, the skills above,
the read-only `explorer` subagent, and the `SessionStart` orientation hook — is
catalogued in [AI-LAYER.md](AI-LAYER.md).
