# Map-change via live-node reparent (no rebuild)

Phased: **Phase 1** = server-tree peers (bots + host); **Phase 2** = remote
clients via a portal-neighbor-prefetch client residency model. See Scope below.

## Context

Moving a character between maps tore the character node down and rebuilt it
every time: snapshot live state to a dict (`get_save_data("all")`) →
`queue_free` the node → re-`instantiate()` `player.tscn` (98 sub-resources, full
component tree, a CanvasLayer the bot immediately frees) → run `JoinHandshake`,
which **re-deserializes the dict back into the components** and **awaits 5
frames** of fragile spawn-timing. The character's state round-trips through a
dictionary even though it never left server memory.

This is the dominant remaining hitch, and it runs *constantly*: ADR 0007 keeps
maps resident and bots are auto-spawned roaming population that travel maps on
their own, so bot map-swaps fire continuously. The synchronous frame spikes also
tunnel the host through one-way platforms (characters don't collide with each
other — `collision_mask` excludes the character layer — so the fall-through is
frame-spike tunneling, not crowd-shoving).

## Decision

For a **server-tree peer** changing maps (a **bot**, or the **host** / peer 1) —
not its first spawn — **reparent the live character node** from the old map's
`Players` container to the new map's `Players` container instead of free +
recreate. No `_ready` re-run, no `JoinHandshake`, no serialize/deserialize — all
live component state is preserved in place. The bullets below describe the bot
case; the host follows the same mechanism with the UI/camera/visibility
differences noted under Scope → Phase 1.

- **Triggered inside `request_map_change`** (one entry point, so portals,
  `/bot travel`, and `/bot teleport` all benefit), gated on `BotManager.is_bot`
  **and** the bot already being on a map. A bot's **first spawn still uses the
  full recreate + `JoinHandshake`** — it needs `_load_data` once to come alive.
- **Recreate fallback:** if any reparent precondition fails (source/target map
  not resident, node or `Players` node invalid), fall through to the existing
  recreate flow. A reparent bug degrades to the old behavior, not a broken bot.
- **Reuses the exact client-facing RPCs** of the recreate path —
  `client_despawn_player` to old-map peers, `client_spawn_player` to new-map
  peers, per-peer synchronizer visibility, `broadcast_player_appearance`. From
  every client's perspective nothing changes (despawn-on-old / spawn-on-new);
  only the server swaps free+instantiate for a reparent. The host shares the
  server tree, so it sees the node move automatically.
- **Arrival reset** (what recreate gave for free, since the live node carries
  transient state across the hop): zero `velocity`, set `global_position` to the
  spawn point, reset the state machine to a neutral state, reset per-weapon
  gauges (SwordCombo / BowMomentum / StaffElement / Shadowmeld). Bots only
  portal while in a *travel* state, so there is no combat target — clearing is
  belt-and-suspenders. Persistent buffs survive (legitimately the bot's).
- **Bookkeeping:** update `player_current_maps[bot]` and move the id between
  `active_maps[*].player_ids`; `invalidate_synchronizer_cache` on **both** maps;
  `brain.attach_to_player()` (drops the old map's nav path and used portal so the
  bot re-routes on the new map, while preserving travel/patrol/cooldown state);
  immediate `_scan_map_activation(new_map)` (ADR 0007).
- **Persistence:** skip the `carried_state` snapshot. Safe — the node is never
  freed, so `SaveManager`'s node ref stays valid and the periodic safety-net save
  keeps persisting the live bot (bots already skip the per-map-change backend
  flush). Implementation note: ensure the bot's `last_map` reflects the new map.

Because `combat.gd`'s `_get_owner_map_node()` cache self-invalidates off
`MapManager.get_player_map()`, and every other map lookup resolves fresh, the
dangling-reference surface on the character is nil once `player_current_maps` is
updated. No component holds a persistent enemy target — the brain does.

## Scope — phased by peer type

Reparent is trivial for peers whose character lives **in the server tree and
needs no client-side map rebuild**, and hard for peers whose client rebuilds its
map every hop. That splits cleanly:

### Phase 1 (this ADR): bots + host

- **Bots** (negative peer id, no client, UI already freed) and the **host**
  (peer 1) both live in the server tree and their `JoinHandshake` **skips SYNC**
  (`_has_client` is false for both). The host, post-ADR-0007, doesn't even
  rebuild its map on a change — it just flips local map visibility
  (`_set_local_map_visible`) and re-spawns its character. So the host's *only*
  per-hop cost is the same free+recreate reparent eliminates.
- The host **keeps** its CanvasLayer UI + Camera2D (we don't free them, unlike
  bots); reparenting the **whole** Player subtree preserves every internal
  NodePath (`../../CanvasLayer/...` resolves the same — the subtree moves as a
  unit), and the camera stays current. The host path additionally does the
  local-visibility flip + BGM; bot appearance is pushed via
  `broadcast_player_appearance`, host appearance via the normal appearance sync.

### Phase 2 (next, separate PR — needs 2-instance validation): remote clients

A remote client holds one live map and free/recreates it (and its character)
every hop, so reparenting only the *server* node still leaves the client
rebuilding + needing a SYNC re-push. The fix is a **client residency model that
mirrors the portal graph, not the whole map set** — critically **not** the
host's all-resident model, which does not scale (100 maps × 20–30 enemies):

- The client keeps its **current** map live (visible) and **asynchronously
  prefetches the portal-adjacent maps** (`get_map_connections`) hidden +
  render-target-off, ready to enter. This holds ~`1 + neighbors` maps regardless
  of total map count.
- Portal to an adjacent (already-prefetched) map → reparent the client's own
  character + flip visibility = instant, and the SYNC re-push is unnecessary
  because the live client node kept its state. Re-roll the prefetch set after.
- A **non-adjacent** teleport (target not prefetched) falls back to
  load-then-spawn — a brief loading moment, rare, exactly MapleStory's model
  (one live map + cached assets + server-spawned mobs).

The server and client converge on "prefetch along the portal graph," with
different pin rules: the **server** pins *occupied* maps (authority duty — it
must simulate enemies for any map with players or bots) plus a bounded warm set;
the **client** pins only its *current* map (render duty only) plus neighbors.
This is also the shape ADR 0007's "revisit as a warm pool at ~10–15 maps"
should take server-side.

## Considered Options

- **Warm-body pool** (pre-instantiated `player.tscn` bodies checked out per
  hop): avoids `instantiate()` but still pays `_load_data`/deserialize + reset
  every hop, and the deep `CanvasLayer/GameWindow` NodePath exports complicate
  reuse. Reparent avoids the deserialize entirely.
- **Bot fast path** (preload the scene, skip the 5-frame await): incremental,
  touches the fragile spawn-timing, and still rebuilds the node. Reparent
  subsumes it and deletes the await from the bot path outright.

## Consequences

- Bot map changes become O(reparent) instead of O(instantiate + handshake) —
  kills the hitch and, with it, the frame-spike one-way-platform tunneling.
- No save-format change, no new RPCs, no authority change (server stays
  authoritative; clients receive the same despawn/spawn).
- **Open implementation risk:** whether a reparented `MultiplayerSynchronizer`
  re-pushes full state to newly-visible peers as cleanly as a freshly-spawned
  one. Must be confirmed in a live smoke test; the recreate-fallback is the
  backstop.
- Watch: `last_map` correctness for the periodic save; the `_finalize`
  post-`await` window if a bot reparents during another player's spawn frame
  (the existing `active_maps` existence guard covers the map; list mutation
  mid-await re-reads after the guard).
