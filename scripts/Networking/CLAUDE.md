# Networking

ENet transport, the backend HTTP bridge, and all multiplayer RPC plumbing. Most of
these scripts are autoloads (see the root `CLAUDE.md` autoload table).

## Files

| File | Role |
|---|---|
| `server_manager.gd` | ENet server lifecycle — create/close the listen socket |
| `client_manager.gd` | ENet client connection, peer-id assignment, disconnect handling |
| `player_manager.gd` | Spawns/despawns player & bot characters; `get_player_node(id)` lookup |
| `channel_manager.gd` | Switches server channels (ports) without a full restart |
| `network_utils.gd` | IP/port validation and scene-path helpers |
| `network_manager.gd` | HTTP bridge to the Flask backend (login, character CRUD, character load) |
| `player_persistence.gd` | `PlayerPersistence` — shared local-file fallback (canonical `res://saves` path + read-merge-write) used by the three HTTP autoloads |
| `PartyData.gd` | Plain data class for a party (members, leader, invites) |

## Server-authoritative model

Every critical mutation happens on the server. The flow is always:

1. The client presses a button / triggers an action.
2. The client sends an **intent** RPC to the server (`rpc_id(1, ...)`).
3. The server validates it (cooldowns, resources, range, ownership) and mutates state.
4. The server broadcasts the authoritative result to all relevant peers.

A client never decides the outcome — it asks, and renders what the server says back.

## RPC annotations

| Annotation | Direction | Notes |
|---|---|---|
| `@rpc("authority", "call_local", "reliable")` | server → all | `call_local` so the host (also a client) runs it too |
| `@rpc("authority", "call_remote", "reliable")` | server → clients | the server skips it; use when the server already applied the change |
| `@rpc("any_peer", "call_local", "reliable")` | client → server | guard the body with `if not multiplayer.is_server(): return` |

High-frequency state (movement, position) uses `MultiplayerSynchronizer` nodes with
per-peer visibility rather than hand-written RPCs — see how `MapManager` toggles
`public_visibility` and `set_visibility_for()`.

## Peers, the server, and bots

- The **server is peer ID 1**. `multiplayer.get_unique_id()` on the host returns 1.
- **Bots have negative peer IDs** (`BotManager.is_bot(id)` is just `id < 0`). A bot
  has no client and no `MultiplayerSynchronizer` audience. Skip any node-addressed
  RPC to a bot peer; if a bot needs a visual on real clients, route it through an
  autoload that resolves on every peer (the pattern `MapManager.bot_ability_used`
  and `MapManager.spawn_projectile_visual` use).
- Mid map-transition a client may not yet have a given character's node, so a
  node-addressed RPC can fail silently — prefer autoload-routed RPCs for anything
  that must survive a map change.

## Cleanup

Add every network-spawned node to the `networked_entities` group; channel switches
and disconnects clear that group. Character nodes implement `cleanup_before_removal()`
to disconnect signals before `queue_free()`.

## Backend bridge

Three autoloads talk HTTP to Flask via `HTTPRequest` (against `http://localhost:5000`):
`network_manager.gd` (account / character CRUD, login), `player_manager.gd`
(character *load* on spawn), and `save_manager.gd` (debounced *saves*). They each
own their own `HTTPRequest` lifecycle and retry, but share one local-file fallback:
`player_persistence.gd` (`PlayerPersistence`) owns the canonical `res://saves`
path and the read-merge-write helpers, so the offline fallback behaves identically
across all three. The backend URL is resolved on demand from `UserConfig` in every
HTTP caller, so a runtime `set_backend_api_url()` takes effect without a restart.
Endpoints and payloads: [backend/CLAUDE.md](../../backend/CLAUDE.md).
