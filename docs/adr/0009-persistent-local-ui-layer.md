# Persistent local-player UI layer (lift the HUD out of the character body)

Status: proposed (design; not yet built). Enables the host/remote-client half of
ADR 0008.

## Context

`player.tscn` fuses two concerns that every well-structured game keeps apart:

1. **The world entity** — the in-map avatar: sprite, collision, movement, the
   gameplay components, the overhead name/health (`PlayerWorldHUD`), the camera.
2. **The local presentation layer** — the HUD (HP/MP/exp, hotbar, buffbar, the
   weapon-signature + synergy widgets, boss bar), the `MoveableWindows`
   (`GameWindow` = inventory/equipment/stats/abilities/pet, `QuestWindow`), the
   keybinds menu, game menu, quest tracker, zone banner.

Today the presentation layer is a `CanvasLayer` **child of the character body**,
and the coupling is bidirectional: components hold `@export` NodePaths pointing
*up into* that UI (`Equipment.{head..secondary_weapon}_slot`,
`InventoryComponent.inventory_grids`, `PlayerInventory.monies_label`, the root's
`player_HUD` / `quest_window`).

This fusion is the root cause of two problems:

- **The host can't be reparented** (ADR 0008): moving the body drags the live UI
  subtree, whose children (`KeybindsMenu`, …) fire `NOTIFICATION_EXIT_TREE`
  cleanup and leave the host's camera/input dead. So the host — a player who, in
  a MapleStory-style game, portals as often as anyone — still pays the full
  free+recreate rebuild every map change.
- **Every remote-player and bot node instantiates a full UI subtree it never
  uses** (gated invisible, or explicitly freed for bots via a hack), wasting
  instantiate + memory on crowded maps.

**What de-risks this:** the components **already own their data**. `equipment.gd`
holds `slots_data` (key→`SlotData`, "the real store", with UI-independent
accessors proven headless-safe on bots); `inventory.gd` owns `slots_data:
Array[SlotData]` and saves/loads through it; the EquipmentSlot / grid nodes are
**views bound to that model** via `bind_slot_data`. So this is **not** a data
migration — it's inverting the *view* wiring.

## Decision

Lift the local presentation layer **out of the character body** into a single
**persistent client-side UI layer**, and invert the component→UI dependency to
model + signals. The body becomes lean (sprite/collision/components/camera/
overhead HUD) and reparents cleanly — unblocking host-carry now and the
remote-client body-carry half of ADR 0008 Phase 2.

### What moves vs what stays

- **Moves to the persistent layer:** the whole `CanvasLayer` subtree — PlayerHUD
  (bars, hotbar, buffbar, signature/synergy/boss widgets), `MoveableWindows`
  (GameWindow, QuestWindow), KeybindsMenu, GameMenu, QuestTracker, ZoneBanner.
- **Stays on the body:** `Camera2D` (world camera that follows the avatar; the
  tree-notification breakage was the *UI* children, not the camera — re-make
  current on reparent, already handled), and `PlayerWorldHUD` (overhead name +
  health bar — world-space, replicated, seen by every peer; `Health.health_bar_path`
  keeps pointing here).

### Ownership & rebinding

- The persistent layer is **one scene** (`local_player_ui.tscn`, a `CanvasLayer`)
  instantiated **once per client** under `/root`, created on the local player's
  first spawn and freed in `reset_client_state` (disconnect / channel switch). No
  new autoload — it's a lazily-created client scene; `MapManager` already owns the
  client-presentation seam (`my_player_node`, the `Maps` container).
- Add a **`local_player_changed(body)`** signal on `MapManager`, emitted from
  `client_identify_player` (which already fires on every spawn *and* every map
  change, for the host via `call_local`). The persistent layer subscribes and
  **(re)binds** its widgets to the new body. On a *reparent* the body persists, so
  no rebind fires; on a *recreate* (host today, remotes) the new body triggers a
  rebind. This replaces the current reliance on the body's one-shot `_ready`
  (which does NOT re-run after a reparent — a latent bug for ADR 0008).
- Binding is **pull, not push**: on bind, the persistent UI asks each component
  for its model (`equipment.get_all_slot_data()`, `inventory.get_slots()`, …),
  binds its view slots to those `SlotData`, and connects the component change
  signals (which already exist: `inventory_changed`, `on_equipment_changed`,
  `monies_changed`, `health_changed`, `mana_changed`, `stats_changed`,
  `ability_*`, `buff_*`). Components stop holding view NodePaths.

### Sequencing (stage to bound risk — broad but shallow)

- **Stage A — invert the coupling, UI still under the body.** Remove the
  component→UI `@export` NodePaths; route binding through a component API +
  signals; switch `JoinHandshake`'s starter-kit from `ec.weapon_slot.item = …`
  (a view write) to a model setter on `slots_data`. No behaviour change, no node
  moves — pure dependency inversion, validated by everything still working.
- **Stage B — move the CanvasLayer out** into `local_player_ui.tscn`; widgets
  switch from `owner`-resolution to an injected `bind_player(body)`; the
  persistent layer binds on `local_player_changed`; update the three autoloads
  that hard-code `"CanvasLayer/MoveableWindows"` (`TradeManager`, `BotManager`
  inspect, `DebugPanel`) to the persistent-layer accessor; delete the bot
  "free the CanvasLayer" hack (the body no longer has one).
- **Stage C — enable the carry.** With a UI-less body, route the host (and, with
  Phase 2's client residency, the remote client's own body) through the ADR 0008
  reparent path. Host-carry falls out.

## Considered Options

- **Reparent the body while temporarily detaching/reattaching the UI.** Rejected:
  `remove_child`/`reparent` fire EXIT_TREE on the UI regardless, so the cleanup
  still runs — it only hides the fusion, doesn't fix it.
- **A new `HUDManager` autoload.** Rejected for now: no existing autoload's
  responsibility is "the local player's HUD", but the layer is a *scene* with a
  lifecycle tied to the local-player spawn, which `MapManager`'s
  `client_identify_player` / `reset_client_state` already bracket. A lazily-created
  scene + one `MapManager` signal keeps the autoload count flat. Revisit if the
  binding logic outgrows that.
- **Leave the host on recreate.** Rejected: the host portals as often as any
  player; the rebuild hitch is not "occasional."

## Consequences

- **Host carried every portal** (the goal); **remote-client body-carry unblocked**
  for ADR 0008 Phase 2.
- **Leaner remote/bot bodies** — no UI subtree instantiated per non-local player;
  the bot UI-free hack is deleted.
- **Fixes a latent ADR 0008 bug**: UI/local-systems setup currently rides the
  body's one-shot `_ready`, which doesn't re-run after a reparent; moving (re)bind
  onto `local_player_changed` makes it correct for both recreate and reparent.
- **Breadth of change**: ~12 UI scripts switch `owner`→injection; 3 components
  drop view NodePaths and expose model/signals; 3 autoloads change a hard-coded
  path; `JoinHandshake` starter-kit uses the model setter; new persistent scene +
  one `MapManager` signal. No save-format change; no server-authority change (the
  server already owns all of this — the UI is client presentation only).
- **Must NOT move** `PlayerWorldHUD` (replicated overhead label/health) or the
  `Camera2D` off the body; must keep the mobile-button signal connections (they
  live in `player.tscn` wired to the `InputSynchronizer` sibling) intact by moving
  them with the HUD or rewiring to the persistent layer.
