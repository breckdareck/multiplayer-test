# map_manager.gd - AutoLoad singleton
# FINAL REFACTOR - Uses MultiplayerSpawners for both maps and players.
extends Node

signal map_loaded(map_id: String)
signal map_unloaded(map_id: String)
signal player_spawned(player_id: int)
## Fires on THIS client (host included, via client_identify_player's call_local)
## whenever the local player's body is (re)identified — every spawn and every map
## change — carrying the live body, or null on teardown (disconnect / main menu).
## The persistent local-player UI layer (ADR 0009 Stage B) binds its widgets to
## the body here, replacing the body's one-shot _ready (which does not re-run
## after a reparent — a latent ADR 0008 bug).
signal local_player_changed(body: Node)

# Map configuration - add your map scenes here
const MAP_SCENES = {
	"near_wilds": "res://scenes/Levels/near_wilds.tscn",
	"ember_meadows": "res://scenes/Levels/ember_meadows.tscn",
	"deep_woods": "res://scenes/Levels/deep_woods.tscn",
	"ruins": "res://scenes/Levels/ruins.tscn",
	"mines": "res://scenes/Levels/mines.tscn",
	"emberwatch": "res://scenes/Levels/emberwatch.tscn",
	"keep": "res://scenes/Levels/keep.tscn",
	"emberscar": "res://scenes/Levels/emberscar.tscn",
	"weave": "res://scenes/Levels/weave.tscn",
	"warlord": "res://scenes/Levels/warlord.tscn",
	"lanterns_rest": "res://scenes/Levels/lanterns_rest.tscn",
	"meadow_path": "res://scenes/Levels/meadow_path.tscn",
	"three_terraces": "res://scenes/Levels/three_terraces.tscn",
	"thornroot": "res://scenes/Levels/thornroot.tscn",
	"dust_warren": "res://scenes/Levels/dust_warren.tscn",
	"gen_open": "res://scenes/Levels/gen_open.tscn",
	"gen_tower": "res://scenes/Levels/gen_tower.tscn",
	"gen_cliffs": "res://scenes/Levels/gen_cliffs.tscn",
	"old_battlefield": "res://scenes/Levels/old_battlefield.tscn",
	"mustering_fields": "res://scenes/Levels/mustering_fields.tscn",
	"ashvigil": "res://scenes/Levels/ashvigil.tscn",
	"cinderwaste": "res://scenes/Levels/cinderwaste.tscn",
	"bramble_downs": "res://scenes/Levels/bramble_downs.tscn",
	"bandit_bluffs": "res://scenes/Levels/bandit_bluffs.tscn",
	"the_undercroft": "res://scenes/Levels/the_undercroft.tscn",
	"the_scorchline": "res://scenes/Levels/the_scorchline.tscn",
	"the_unraveling": "res://scenes/Levels/the_unraveling.tscn",
}

## Themed display names for the loading screen (the in-world zone banner reads the
## scene's MapBase.display_name directly). Keep these in sync with each level
## scene's display_name. A client shows this BEFORE the target map is loaded, so
## it can't read the instance — hence the lookup table.
const MAP_DISPLAY_NAMES = {
	"lanterns_rest": "Lantern's Rest",
	"near_wilds": "The Near-Wilds",
	"ember_meadows": "Ember-Meadows",
	"deep_woods": "The Deep Woods",
	"ruins": "The Ruins",
	"mines": "The Drowned Mines",
	"emberwatch": "Emberwatch",
	"keep": "The Warded Keep",
	"emberscar": "The Ember-Scar",
	"weave": "The Weave's Edge",
	"warlord": "The Sundered Heart",
	"meadow_path": "Slime Meadow",
	"three_terraces": "Windmill Terraces",
	"thornroot": "Thornroot Hollow",
	"dust_warren": "The Dust Warren",
	"gen_open": "Gen open",
	"gen_tower": "Gen tower",
	"gen_cliffs": "Gen cliffs",
	"old_battlefield": "The Old Battlefield",
	"mustering_fields": "The Mustering Fields",
	"ashvigil": "Ashvigil",
	"cinderwaste": "The Cinderwaste",
	"bramble_downs": "Bramble Downs",
	"bandit_bluffs": "Bandit Bluffs",
	"the_undercroft": "The Undercroft",
	"the_scorchline": "The Scorchline",
	"the_unraveling": "The Unraveling",
}

const DEFAULT_MAP = "lanterns_rest"

## Safe hearth (town) maps, in priority order. Single source of truth for "where
## is safe" — used by Hearthstone/Town-Scroll teleports (nearest-hearth BFS) and
## the world map's town styling. Add a town here when you add one.
const HEARTH_MAPS: Array[String] = ["lanterns_rest", "emberwatch", "ashvigil"]


## Themed name for a map_id (falls back to the raw id for unknown maps).
func _map_display_name(map_id: String) -> String:
	return MAP_DISPLAY_NAMES.get(map_id, map_id)

# --- Map residency & enemy activation (ADR 0007) ---
## Bounded WARM POOL (ADR 0007 revisit — triggered at 10 maps). Instead of
## pre-instantiating EVERY map at boot, the server warms only the starting Hearth
## and its portal-neighbours, lazily loads maps as agents travel into them, and a
## periodic evictor frees maps that are empty AND outside the warm set (the town +
## every populated map + each populated map's neighbours). Boot stays cheap and
## steady-state memory is bounded, while adjacent travel keeps the no-hitch
## fast-reparent path (a populated map's neighbours are always resident).
## On empty, a map's enemies are put to sleep immediately (≈free); the evictor
## unloads it later only if it's also cold (outside the warm set).
const KEEP_MAPS_RESIDENT := true
## How often (seconds) the warm-pool evictor frees cold, empty, non-warm maps.
const WARM_EVICT_INTERVAL := 20.0
## How often (seconds) the server re-evaluates which enemies are awake.
const ACTIVATION_SCAN_INTERVAL := 0.1
## Wake an enemy when an agent (player OR bot) is within this distance; sleep it
## only past the larger radius (hysteresis prevents boundary flapping). The wake
## radius comfortably exceeds aggro (detection_radius ~160), chase leash (480),
## and the on-screen view, so enemies in combat or visible to a player are never
## asleep — only those every agent has left far behind, plus every enemy on a
## zero-agent map.
const ACTIVATION_WAKE_RADIUS := 960.0
const ACTIVATION_SLEEP_RADIUS := 1280.0
var _activation_scan_accum := 0.0
var _warm_evict_accum := 0.0

# --- Global spawn tick (MapleStory-style population model, ADR 0015) ---
## The single server-wide spawn clock. Enemy spawners do NOT respawn on per-enemy
## timers; instead they replenish their map up to its player-scaled capacity once
## per tick. The value is our own gameplay choice (NOT tied to MapleStory's 7.56 s
## cadence) — tune this one number to make respawns snappier/slower. See
## docs/adr/0015-population-driven-enemy-spawning.md and
## docs/maplestory_spawn_mechanics.md.
const SPAWN_TICK_INTERVAL := 5.0
## Emitted server-only after each map-wide population replenish (a notification
## seam for tooling/overlays). The actual respawn work is driven directly by
## replenish_map_population below, not by listeners of this signal.
signal spawn_tick
var _spawn_tick_accum := 0.0
## Count bots as occupants when scaling a map's monster cap. Bots are ambient
## population in this game (ADR 0011), so a bot-busy map is denser by default.
const SPAWN_COUNT_BOTS := true

# Server-side tracking
var active_maps: Dictionary = {} ## {map_id: {scene_instance, player_ids: []}}
var player_current_maps: Dictionary = {} ## {player_id: map_id}

## Map adjacency graph {map_id: Array[String]} derived from portal target_map_id
## values. Built once, server-side; used by bots to route across maps.
var map_connections: Dictionary = {}

# Client-side state
var current_map_id: String = ""
var current_map_instance: Node = null
var my_player_node: Node = null
var _warned_missing_paths: Dictionary = {}
var _synchronizer_cache: Dictionary = {} ## {node_instance_id: Array[MultiplayerSynchronizer]}

var _loading_overlay_scene = preload("res://scenes/UI/loading_overlay.tscn")
var _loading_overlay: CanvasLayer = null

# ADR 0009 Stage B: the persistent local-player UI layer. One instance per client,
# created lazily on the local player's first identify, freed on client reset.
var _local_player_ui_scene = preload("res://scenes/UI/local_player_ui.tscn")
var _local_ui: CanvasLayer = null


## Creates the persistent local-player UI under /root once per client (host
## included). The caller emits local_player_changed right after, which binds it.
func _ensure_local_ui() -> void:
	if is_instance_valid(_local_ui):
		return
	_local_ui = _local_player_ui_scene.instantiate()
	get_tree().root.add_child(_local_ui)


## The persistent local-player UI layer, or null before first spawn / after reset.
func get_local_ui() -> CanvasLayer:
	return _local_ui


## The persistent layer's MoveableWindows container — where transient windows
## (trade, bot-inspect, context menu, debug) mount. Null when no local UI exists.
## Replaces the old `<body>/CanvasLayer/MoveableWindows` lookups (ADR 0009 Stage B).
func get_local_ui_moveable_windows() -> Node:
	return _local_ui.get_node_or_null("MoveableWindows") if is_instance_valid(_local_ui) else null


## The persistent layer's PlayerHUD — where always-on overlays (quest popups,
## welcome overlay) mount. Null when no local UI exists.
func get_local_ui_hud() -> Node:
	return _local_ui.get_node_or_null("PlayerHUD") if is_instance_valid(_local_ui) else null

func _get_loading_overlay() -> CanvasLayer:
	if not _loading_overlay or not is_instance_valid(_loading_overlay):
		_loading_overlay = _loading_overlay_scene.instantiate()
		get_tree().root.add_child(_loading_overlay)
	return _loading_overlay


func _ready():
	# Defer server-side setup until the server is confirmed to be running.
	MultiplayerManager.server_has_started.connect(_on_server_started)


func _on_scene_changed():
	# This function is no longer needed since MapSpawner is persistent
	pass


func _exit_tree():
	if MultiplayerManager.server_has_started.is_connected(_on_server_started):
		MultiplayerManager.server_has_started.disconnect(_on_server_started)


func _on_server_started():
	# WARM POOL (revised ADR 0007). Build the portal graph first — its off-tree
	# scan reads portals from non-resident maps, so it no longer needs every map
	# instantiated. Then warm ONLY the starting Hearth + its neighbours; the rest
	# load lazily on travel and the evictor frees cold ones. Keeps boot cheap as
	# the map roster grows.
	_build_map_connections()
	_warm_around(DEFAULT_MAP)


## [Server] Instantiate every configured map at once. No longer called at boot
## (the warm pool replaced it); kept as a debug "warm everything" helper.
func _preinstantiate_all_maps() -> void:
	if not multiplayer.is_server():
		return
	for map_id in MAP_SCENES:
		_load_map_on_server(map_id)


## [Server] Ensure a map and its portal-neighbours are resident (idempotent).
## Called at boot for the town and on every spawn, so the next hop is already
## warm and adjacent travel uses the no-hitch fast-reparent path.
func _warm_around(center_map_id: String) -> void:
	if not multiplayer.is_server():
		return
	_load_map_on_server(center_map_id)
	for neighbor in get_map_connections(center_map_id):
		_load_map_on_server(neighbor)


## Maps that must stay resident: the town hub, every map with players, and every
## map one portal-hop from a populated map.
func _compute_warm_set() -> Dictionary:
	var warm := {DEFAULT_MAP: true}
	for map_id in active_maps:
		if active_maps[map_id].get("player_ids", []).is_empty():
			continue
		warm[map_id] = true
		for neighbor in get_map_connections(map_id):
			warm[neighbor] = true
	return warm


## [Server] Free resident maps that are empty AND outside the warm set. Runs on a
## slow timer (never inside a transition), so it can't free a map mid-handoff.
## active_maps.keys() snapshots, so unloading during iteration is safe.
func _evict_cold_maps() -> void:
	if not multiplayer.is_server():
		return
	var warm := _compute_warm_set()
	for map_id in active_maps.keys():
		if map_id in warm:
			continue
		if not active_maps[map_id].get("player_ids", []).is_empty():
			continue
		_unload_map_on_server(map_id)


# === ENEMY PROXIMITY ACTIVATION (ADR 0007) ===
# Server-side only. Each tick, enemies near any agent (player or bot) are woken
# and the rest are put to sleep, so resident maps with no nearby agents — and
# every enemy on a zero-agent map — cost ≈0 without ever unloading the map.

func _process(delta: float) -> void:
	# has_multiplayer_peer() first: post-disconnect the peer is null and
	# is_server() calls get_unique_id() internally, which errors with no peer.
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or active_maps.is_empty():
		return
	# Warm-pool eviction (slow tick): free cold, empty, non-warm maps.
	_warm_evict_accum += delta
	if _warm_evict_accum >= WARM_EVICT_INTERVAL:
		_warm_evict_accum = 0.0
		_evict_cold_maps()
	# Global spawn clock — must run before the activation-scan early-return below.
	# A zero-occupant map yields a cap of 0 and no-ops (hibernation), so running
	# this over every map each tick is cheap.
	_spawn_tick_accum += delta
	if _spawn_tick_accum >= SPAWN_TICK_INTERVAL:
		_spawn_tick_accum = 0.0
		for map_id in active_maps.keys():
			replenish_map_population(map_id)
		spawn_tick.emit()
	_activation_scan_accum += delta
	if _activation_scan_accum < ACTIVATION_SCAN_INTERVAL:
		return
	_activation_scan_accum = 0.0
	for map_id in active_maps.keys():
		_scan_map_activation(map_id)


## Evaluate wake/sleep for every eligible enemy on one map.
func _scan_map_activation(map_id: String) -> void:
	var data: Dictionary = active_maps.get(map_id, {})
	var map_instance = data.get("scene_instance")
	if not is_instance_valid(map_instance):
		return
	var enemies_node: Node = map_instance.get_node_or_null("Enemies")
	if enemies_node == null:
		return # e.g. town — nothing to manage

	# Collect valid agent positions (players AND bots) currently on this map.
	var agent_positions: Array[Vector2] = []
	for pid in data.get("player_ids", []):
		var node = PlayerManager.get_player_node(pid)
		if is_instance_valid(node):
			agent_positions.append(node.global_position)

	var no_agents: bool = agent_positions.is_empty()
	var wake_sq := ACTIVATION_WAKE_RADIUS * ACTIVATION_WAKE_RADIUS
	var sleep_sq := ACTIVATION_SLEEP_RADIUS * ACTIVATION_SLEEP_RADIUS
	for enemy in _collect_enemies(enemies_node, []):
		if not enemy.is_activation_eligible():
			continue
		if no_agents:
			enemy.activation_sleep()
			continue
		if enemy.is_engaged():
			enemy.activation_wake()
			continue
		var nearest_sq := INF
		var epos: Vector2 = enemy.global_position
		for apos in agent_positions:
			nearest_sq = minf(nearest_sq, epos.distance_squared_to(apos))
		if nearest_sq <= wake_sq:
			enemy.activation_wake()
		elif nearest_sq > sleep_sq:
			enemy.activation_sleep()
		# else: in the hysteresis band — leave the current state unchanged.


## Server-only. Bring one map's monster population up to its MAP-WIDE cap
## (MapleStory model, ADR 0015). The cap scales ONE budget across the map's total
## spawn points — floor(total_pool * pct(occupants)) — not per spawner, so the
## 75%->100% ramp is meaningful even when individual spawners are small. The
## deficit is filled by picking random empty spawn points across every spawner
## (MapleStory's "randomly select which points to activate"). Over-cap waves are
## never despawned. Spawners flagged exclude_from_map_cap (bosses) self-fill.
## Called on the global spawn tick, on map entry, and when a spawner finishes setup.
func replenish_map_population(map_id: String) -> void:
	if not multiplayer.is_server() or not map_id in active_maps:
		return
	var map_instance = active_maps[map_id].scene_instance
	if not is_instance_valid(map_instance):
		return

	var capped: Array = []
	var total_pool := 0
	var total_alive := 0
	for spawner in get_tree().get_nodes_in_group("EnemySpawners"):
		if not (is_instance_valid(spawner) and map_instance.is_ancestor_of(spawner) \
				and spawner.has_method("get_pool_capacity")):
			continue
		if spawner.exclude_from_map_cap:
			spawner.fill_to_pool() # always-present (boss / set-piece)
			continue
		capped.append(spawner)
		total_pool += spawner.get_pool_capacity()
		total_alive += spawner.get_alive_count()
	if capped.is_empty():
		return

	var occupants := _spawn_occupant_count(map_id)
	var map_cap: int = EnemySpawner.capacity_for(total_pool, occupants)
	var deficit := map_cap - total_alive
	# deficit <= 0 -> at/over cap: add nothing, despawn nothing (spawn debt).
	if deficit <= 0:
		return

	# Build the set of empty spawn points (one entry per free slot) and fill a
	# random subset, so density is shared across spawners by their open capacity.
	var slots: Array = []
	for spawner in capped:
		for _i in spawner.free_room():
			slots.append(spawner)
	slots.shuffle()
	var n: int = mini(deficit, slots.size())
	for i in n:
		slots[i].spawn_one()


## Occupants on a map for spawn scaling (bots included per SPAWN_COUNT_BOTS).
func _spawn_occupant_count(map_id: String) -> int:
	var ids: Array = active_maps[map_id].get("player_ids", [])
	if SPAWN_COUNT_BOTS:
		return ids.size()
	var n := 0
	for pid in ids:
		if not BotManager.is_bot(pid):
			n += 1
	return n


## Read-only map population snapshot for dev tooling (the `spawns` command /
## DebugSpawnOverlay). Server-only — clients get an empty dict. Mirrors the cap
## math in replenish_map_population without mutating anything.
func get_map_population_summary(map_id: String) -> Dictionary:
	if not multiplayer.is_server() or not map_id in active_maps:
		return {}
	var map_instance = active_maps[map_id].scene_instance
	if not is_instance_valid(map_instance):
		return {}
	var spawners: Array = []
	var total_pool := 0
	var total_alive := 0
	for spawner in get_tree().get_nodes_in_group("EnemySpawners"):
		if not (is_instance_valid(spawner) and map_instance.is_ancestor_of(spawner) \
				and spawner.has_method("get_population_report")):
			continue
		var rep: Dictionary = spawner.get_population_report()
		spawners.append(rep)
		if not rep.get("excluded", false):
			total_pool += int(rep.get("pool", 0))
			total_alive += int(rep.get("alive", 0))
	var occupants := _spawn_occupant_count(map_id)
	return {
		"map_id": map_id,
		"occupants": occupants,
		"total_pool": total_pool,
		"total_alive": total_alive,
		"map_cap": EnemySpawner.capacity_for(total_pool, occupants),
		"spawners": spawners,
	}


## Gather enemy nodes under a map's Enemies container. Matched by the "Enemies"
## group (added in EnemyBase._ready) rather than a class reference, so MapManager
## needn't depend on EnemyBase's class-load order.
func _collect_enemies(node: Node, out: Array) -> Array:
	for child in node.get_children():
		if child.is_in_group("Enemies") and child.has_method("activation_sleep"):
			out.append(child)
		else:
			_collect_enemies(child, out)
	return out


# === MAP CONTAINER + SUBVIEWPORT WRAPPING ===
# Each map lives inside its own SubViewport with a fresh World2D, so physics,
# navigation, canvas (lights), and audio listeners are fully isolated between
# maps. Authors keep editing map scenes at (0,0); the wrap is added at runtime.
# Both server and client mirror the same wrapping so absolute node paths line up
# for MultiplayerSynchronizer replication and RPC routing.

func _ensure_maps_container() -> SubViewportContainer:
	var existing := get_tree().root.get_node_or_null("Maps")
	if existing is SubViewportContainer:
		return existing
	if existing != null:
		push_warning("MapManager: /root/Maps exists but is not a SubViewportContainer; replacing.")
		get_tree().root.remove_child(existing)
		existing.queue_free()
	# Opaque backdrop directly BEHIND the maps. The map SubViewports render with
	# transparent_bg (so hidden maps don't stack on the host's screen), which means
	# anything sitting further back in /root shows through during the spawn frame
	# before the map paints — notably the login/character scene ("remnants ... for
	# a very brief moment"). This black ColorRect is the immediate sibling behind
	# the Maps container, so transparent areas reveal black instead. Re-created here
	# right before the container so it's always positioned correctly: a backdrop
	# that persisted across a disconnect would otherwise end up BEHIND a freshly
	# re-added login scene. Mouse-ignore; harmless at the login screen (the current
	# scene is appended after it, so it draws in front).
	var old_backdrop := get_tree().root.get_node_or_null("MapsBackdrop")
	if is_instance_valid(old_backdrop):
		old_backdrop.free()
	var backdrop := ColorRect.new()
	backdrop.name = "MapsBackdrop"
	# Match the window's default clear color (the grey that showed through before),
	# so the backdrop is indistinguishable from the engine's default background.
	backdrop.color = RenderingServer.get_default_clear_color()
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(backdrop)

	var container := SubViewportContainer.new()
	container.name = "Maps"
	container.anchor_right = 1.0
	container.anchor_bottom = 1.0
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	# Keep the per-viewport render texture sampled as nearest-neighbor when
	# blitted to the window, so pixel-art doesn't go blurry through the wrap.
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_tree().root.add_child(container)
	return container


func _wrap_in_subviewport(map_instance: Node, map_id: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "Map_%s_VP" % map_id
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	viewport.handle_input_locally = false
	viewport.audio_listener_enable_2d = true
	viewport.physics_object_picking = true
	# SubViewport does NOT inherit the project's rendering/textures/canvas_textures/
	# default_texture_filter setting — it defaults to LINEAR. Force nearest so the
	# pixel-art textures rendered inside the viewport stay crisp.
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	# Render transparent when the map's content is hidden (visible=false on the
	# map root) so SubViewportContainer doesn't stack one map's render on top of
	# another on the host's screen. See _set_local_map_visible.
	viewport.transparent_bg = true
	# Default: GUI input off. _set_local_map_visible re-enables it when the
	# host moves to this map. SubViewportContainer dispatches input to EVERY
	# child SubViewport, so hidden maps would otherwise steal drag-drop hit-
	# tests from the active map. Clients only have one map loaded so this is
	# a no-op for them; matters for the host (server) which keeps every map
	# loaded for the other players.
	viewport.gui_disable_input = true
	viewport.add_child(map_instance)
	return viewport


## Show/hide a map LOCALLY on this peer. Bot/non-local maps stay loaded for
## physics, but their SubViewport content is hidden so the SubViewportContainer
## renders only the local peer's current map. Affects only the local peer's
## tree — remote clients have their own map instances and are unaffected.
##
## ALSO gates GUI input on the SubViewport. SubViewportContainer dispatches
## input to EVERY child SubViewport regardless of which one is visually on
## top, so without `gui_disable_input` the hidden maps' GUI tree silently
## competes for drag-drop hit-tests and steals drops from the host's active
## inventory the moment the host is on a map by themselves.
func _set_local_map_visible(map_id: String, vis: bool) -> void:
	if not active_maps.has(map_id):
		return
	var map_instance = active_maps[map_id].scene_instance
	if not is_instance_valid(map_instance):
		return
	map_instance.visible = vis
	var viewport: Node = map_instance.get_parent()
	if viewport is SubViewport:
		(viewport as SubViewport).gui_disable_input = not vis


# === SERVER LOGIC ===

func request_map_change(player_id: int, target_map_id: String, target_spawn_point_name: String = ""):
	"""Requests a player to be moved to a new map."""
	if not multiplayer.is_server(): return

	#print("MapManager: Player %d requesting map change to '%s' at spawn '%s'" % [player_id, target_map_id, target_spawn_point_name])

	if not target_map_id in MAP_SCENES:
		push_warning("MapManager: Invalid target_map_id '%s' for player %d. Using default map." % [target_map_id, player_id])
		target_map_id = DEFAULT_MAP

	# Track whether this is a map change (not the initial join)
	var is_map_change := player_id in player_current_maps
	# Snapshot the host's previous map BEFORE _remove_player_from_map runs —
	# that call clears current_map_id when the host's own instance is removed,
	# which would otherwise hide the wrong (now-empty) value below and leave
	# the old map's SubViewport composited on top of the new one.
	var old_map_id: String = player_current_maps.get(player_id, "")

	# Fast path (ADR 0008 + ADR 0009 Stage C): reparent a server-tree peer's LIVE
	# node — a BOT or the HOST (peer 1) — between maps instead of free+recreate.
	# Preserves all live component state in place: no JoinHandshake, no serialize
	# round-trip, no _ready re-run. The HOST is now eligible because ADR 0009
	# lifted its UI off the body (the old revert cause — reparent fired
	# NOTIFICATION_EXIT_TREE on the CanvasLayer UI children) and the
	# InputSynchronizer's _exit_tree is now reparent-guarded. Remote clients still
	# recreate (they rebuild their own single map — a future client-residency
	# phase). A first spawn (not is_map_change) uses the full flow below; a
	# precondition miss (target not resident, node missing) falls through to it.
	var _try_reparent := is_map_change and (BotManager.is_bot(player_id) or player_id == 1)
	# Stress-test toggle: force the bots down the RECREATE path so it measures the
	# server-side rebuild a remote client pays per portal (see /bot stress recreate).
	if BotManager.is_bot(player_id) and BotManager.stress_force_recreate:
		_try_reparent = false
	if _try_reparent:
		if _reparent_peer_to_map(player_id, old_map_id, target_map_id, target_spawn_point_name):
			return

	# Remove player from current map
	if is_map_change:
		# Snapshot live state before the old body is freed so the respawn can
		# restore it in-memory — no save-backend round-trip, no stale-data race.
		var old_node := PlayerManager.get_player_node(player_id)
		if is_instance_valid(old_node) and old_node.has_method("get_save_data"):
			PlayerManager.set_carried_state(player_id, old_node.get_save_data("all"))
		_remove_player_from_map(player_id, player_current_maps[player_id])

	player_current_maps[player_id] = target_map_id

	# Load target map if not active
	if not target_map_id in active_maps:
		_load_map_on_server(target_map_id)

	var map_instance = active_maps.get(target_map_id, {}).get("scene_instance")
	if not is_instance_valid(map_instance):
		push_error("Map instance for '%s' is invalid after load for player %d!" % [target_map_id, player_id])
		return

	if player_id == 1:
		# Hide the previously-active map locally so its SubViewport stops
		# compositing on top of the host's view; show the new one. Use the
		# pre-removal old_map_id — current_map_id was wiped above.
		if not old_map_id.is_empty() and old_map_id != target_map_id:
			_set_local_map_visible(old_map_id, false)
		_set_local_map_visible(target_map_id, true)

		current_map_instance = map_instance
		current_map_id = target_map_id
		# Play per-map BGM for the host player
		if map_instance is MapBase and not map_instance.bgm_path.is_empty():
			AudioManager.play_song(map_instance.bgm_path)
		_finalize_player_spawn(player_id, target_map_id, target_spawn_point_name)
		# On map changes (not initial join), emit player_spawned so
		# PlayerManager._on_player_spawned re-initializes the host player
		# with fresh data from the backend.
		if is_map_change:
			player_spawned.emit(player_id)
		return

	# Bots have no client — skip the RPC and finalize directly on server.
	if BotManager.is_bot(player_id):
		_finalize_player_spawn(player_id, target_map_id, target_spawn_point_name)
		player_spawned.emit(player_id)
		return

	client_set_current_map.rpc_id(player_id, target_map_id, target_spawn_point_name)


# === REPARENT MAP-CHANGE FAST PATH (ADR 0008) ===
# Move a server-tree peer's LIVE character node between maps without freeing and
# rebuilding it. Applies to bots and the host (peer 1) — both live in the server
# tree and skip the JoinHandshake SYNC phase. Remote clients are NOT handled here
# (their client rebuilds its own single map); that is a future phase.

## Returns true on success; false (with NO mutation performed) if a precondition
## fails, so request_map_change can fall back to the full recreate flow.
##
## NOTE: currently only reached for BOTS — the caller excludes the host (peer 1).
## The is_host branch below is retained for a future host-reparent revival once
## the host's UI subtree is decoupled from the reparented node (see ADR 0008); it
## is intentionally unreachable today.
func _reparent_peer_to_map(peer_id: int, old_map_id: String, new_map_id: String, spawn_point_name: String) -> bool:
	if not multiplayer.is_server():
		return false
	# Preconditions — both maps resident, character node present, target has Players.
	var old_data: Dictionary = active_maps.get(old_map_id, {})
	var new_data: Dictionary = active_maps.get(new_map_id, {})
	var old_map: Node = old_data.get("scene_instance")
	var new_map: Node = new_data.get("scene_instance")
	if not is_instance_valid(old_map) or not is_instance_valid(new_map):
		return false
	var char_node: Node = old_map.get_node_or_null("Players/" + str(peer_id))
	if not is_instance_valid(char_node):
		return false
	var new_players: Node = new_map.get_node_or_null("Players")
	if not is_instance_valid(new_players):
		return false

	var is_host: bool = peer_id == 1

	# 1. Remove the arriver from OTHER real players' view of the OLD map. Skip the
	#    HOST (peer 1): it shares the SERVER tree, so the arriver's node MOVES via
	#    the reparent below — it must not be despawned. client_despawn_player on
	#    the host queue_frees the live shared node, and queue_free is deferred, so
	#    it fires AFTER the reparent and destroys the just-moved character (this is
	#    why bots vanished on a map a host occupied). The host's view updates on
	#    its own: the arriver moves into a hidden SubViewport / out of the visible one.
	for p in old_data.get("player_ids", []):
		if p == peer_id or p == 1 or BotManager.is_bot(p):
			continue
		client_despawn_player.rpc_id(p, peer_id)

	# 2. Reparent the LIVE node (carries every component, synchronizer, and — for
	#    the host — the CanvasLayer UI + Camera2D, all live). The _reparenting flag
	#    makes the controller's _exit_tree skip cleanup_before_removal so the move
	#    doesn't brick the node.
	char_node._reparenting = true
	char_node.reparent(new_players, false)
	char_node._reparenting = false

	# 3. Arrival reset — the live node carried transient state across the hop.
	_reset_character_on_arrival(char_node, new_map_id, spawn_point_name)

	# 4. Bookkeeping — move the id between maps and update the current-map index so
	#    combat's self-healing map cache + every get_player_map lookup resolve to
	#    the new map. (old_data/new_data are the live dicts in active_maps.)
	old_data.get("player_ids", []).erase(peer_id)
	if not peer_id in new_data["player_ids"]:
		new_data["player_ids"].append(peer_id)
	player_current_maps[peer_id] = new_map_id
	invalidate_synchronizer_cache(old_map)
	invalidate_synchronizer_cache(new_map)

	# 5. Host-local view — flip which map the host renders, re-make its camera
	#    current in the new SubViewport, and play the new map's BGM. Mirrors the
	#    peer-1 branch of request_map_change (which _ready would otherwise do).
	if is_host:
		if old_map_id != new_map_id:
			_set_local_map_visible(old_map_id, false)
		_set_local_map_visible(new_map_id, true)
		current_map_instance = new_map
		current_map_id = new_map_id
		var cam := char_node.get_node_or_null("Camera2D") as Camera2D
		if is_instance_valid(cam):
			cam.make_current()
			# Re-apply the new map's camera limits (recreate did this via
			# _setup_client_visuals; the reparent must too or the bounds stay on
			# the old map).
			if char_node.has_method("_apply_map_camera_bounds"):
				char_node._apply_map_camera_bounds(cam)
		if new_map is MapBase and not new_map.bgm_path.is_empty():
			AudioManager.play_song(new_map.bgm_path)
		# Pets followed the player on the recreate path (via load_pets); the
		# reparent preserves the player + roster but the pet ENTITIES were on the
		# old map, so migrate them now (player_current_maps already points new).
		if "username" in char_node and not char_node.username.is_empty():
			PetManager.respawn_owner_pets(char_node.username)
		# Show the new map's zone banner. local_player_changed does NOT fire on a
		# reparent (the body persists), so the persistent UI's bind() — which shows
		# the banner on a recreate — is skipped; nudge it here.
		if is_instance_valid(_local_ui) and _local_ui.has_method("notify_map_arrival"):
			_local_ui.notify_map_arrival()

	# 6. Spawn the arriver into OTHER real players' view of the NEW map. Skip the
	#    HOST (peer 1): it already has the live node in the shared server tree
	#    (client_spawn_player would no-op anyway), symmetric with step 1.
	for p in new_data["player_ids"]:
		if p == peer_id or p == 1 or BotManager.is_bot(p):
			continue
		client_spawn_player.rpc_id(p, peer_id, char_node.global_position, _player_username(peer_id))

	# 6b. Reset the state machine to neutral NOW — after the spawn above, so the
	#     change_state RPC reaches the destination clients only once they have the
	#     arriver's node (reliable+ordered RPCs guarantee spawn-before-state).
	#     Doing this in the pre-spawn arrival reset raced the spawn and threw
	#     "Players/<id>/StateMachine not found" on every client.
	_reset_state_machine_on_arrival(char_node)

	# 7. Per-peer synchronizer visibility, recomputed off the now-updated
	#    player_current_maps (sets every real player's view of the arriver).
	update_visibility_for_player(peer_id)

	# 8. Appearance + brain. Step 6 spawned the arriver on the destination clients
	#    with the scene's DEFAULT sprite, and a reparent never re-runs _ready /
	#    JoinHandshake (whose equipment-load emit re-broadcasts the sprite on the
	#    recreate path) — so push it explicitly here. Bots route through
	#    broadcast_player_appearance; the host broadcasts its wielded discipline
	#    through the standard appearance pathway. Also re-point the bot brain
	#    (resets its transient targets/nav for the new map, keeps travel/patrol
	#    progress).
	if BotManager.is_bot(peer_id):
		broadcast_player_appearance(peer_id)
		BotManager.handle_bot_reparented(peer_id)
	elif is_instance_valid(char_node.appearance_component):
		char_node.appearance_component.refresh_on_server()

	# Party members see each other's current map in the party window — push
	# fresh member data after a reparent hop too (bots travel constantly).
	PartyManager.notify_player_data_changed(peer_id)

	# 9. Wake enemies near the arriver now; re-sleep the lighter old map (ADR 0007).
	_scan_map_activation(new_map_id)
	_scan_map_activation(old_map_id)
	return true


## Clear the transient state the reparented live node carried across the hop that
## free+recreate used to discard. Persistent buffs (and the staff stance) survive.
func _reset_character_on_arrival(char_node: Node, map_id: String, spawn_point_name: String) -> void:
	char_node.global_position = get_spawn_position_for_map(map_id, spawn_point_name)
	if "velocity" in char_node:
		char_node.velocity = Vector2.ZERO
	# NOTE: the state-machine reset is deliberately NOT here. change_state RPCs the
	# new state to the destination map's remote clients, and at this point (before
	# step 6) the arriver isn't spawned on those clients yet — the RPC would target
	# a missing node ("Players/<id>/StateMachine" not found). It runs in
	# _reset_state_machine_on_arrival() AFTER the spawn instead.
	# Reset transient per-weapon gauges (combo / charge / stealth).
	if is_instance_valid(char_node.sword_combo_component):
		char_node.sword_combo_component.reset_combo()
	if is_instance_valid(char_node.bow_momentum_component):
		char_node.bow_momentum_component.reset()
	if is_instance_valid(char_node.shadowmeld_component):
		char_node.shadowmeld_component.cancel_stealth()


## Drop any mid-attack / chase state back to the neutral starting state. Split
## from _reset_character_on_arrival and run AFTER the arriver is spawned on the
## destination clients (change_state RPCs them, so the node must exist first).
func _reset_state_machine_on_arrival(char_node: Node) -> void:
	var sm = char_node.state_machine
	if is_instance_valid(sm) and is_instance_valid(sm.starting_state) and sm.current_state != sm.starting_state:
		sm.change_state(sm.starting_state)


func _load_map_on_server(map_id: String):
	"""Server-only: Manually instantiate map scene and add to scene tree"""
	if not multiplayer.is_server(): return
	if map_id in active_maps: return
																											
	#print("MapManager: Manually spawning map '%s' on server" % map_id)
	
	# Load and instantiate map scene
	var map_path = MAP_SCENES.get(map_id)
	if not map_path:
		push_error("MapManager: Invalid map_id '%s'" % map_id)
		return
	
	var map_scene = load(map_path)
	if not map_scene:
		push_error("MapManager: Failed to load map scene at '%s'" % map_path)
		return
		
	var map_instance = map_scene.instantiate()
	if not is_instance_valid(map_instance):
		push_error("MapManager: Failed to instantiate map '%s'" % map_id)
		return
	
	map_instance.name = "Map_" + map_id

	# Wrap in a SubViewport (isolated World2D) so physics/nav don't leak across
	# maps that share the (0,0) authoring origin. See helpers above.
	var maps_container := _ensure_maps_container()
	var viewport := _wrap_in_subviewport(map_instance, map_id)
	maps_container.add_child(viewport)
	# Default to hidden locally — the host toggles it visible only when they
	# travel to this map. Bots/other peers keep simulating regardless; this
	# only suppresses local rendering on the host's screen.
	map_instance.visible = false

	active_maps[map_id] = {"scene_instance": map_instance, "player_ids": []}
	map_loaded.emit(map_id)
	
	#print("MapManager: Server spawned map '%s' at path %s" % [map_id, map_instance.get_path()])
	
	# CRITICAL: Set public_visibility to false for all synchronizers in this map
	# This prevents them from trying to sync to clients who haven't loaded the map yet
	_set_synchronizers_public_visibility(map_instance, false)
	#print("MapManager: Set public_visibility=false for all synchronizers in map '%s'" % map_id)
	
	# Update visibility for all players when new map is added
	_update_visibility_for_all_players()


func _finalize_player_spawn(player_id: int, map_id: String, spawn_point_name: String = ""):
	"""Creates the player character on the server via a PlayerSpawner."""
	if not multiplayer.is_server() or not map_id in active_maps: return

	#print("MapManager: Finalizing spawn for player %d on map %s at spawn '%s'" % [player_id, map_id, spawn_point_name])
	# Occupancy bookkeeping — scrub the id from EVERY map's list before adding.
	# _finalize_player_spawn can run twice for the same arrival (the host gets a
	# direct call AND its own client ACK), and Array.erase removes only ONE
	# occurrence — so without the scrub a duplicate survives the next map
	# change as a ghost entry that keeps receiving map-scoped traffic (bot
	# speech, bot party invites) from maps the player already left.
	for other_map_id in active_maps:
		var ids: Array = active_maps[other_map_id].player_ids
		while player_id in ids:
			ids.erase(player_id)
	active_maps[map_id].player_ids.append(player_id)

	# Party members see each other's current map in the party window — push
	# fresh member data (map / presence) to the party on every arrival.
	PartyManager.notify_player_data_changed(player_id)
	
	# Sync EXISTING players to the new joiner
	# The new joiner needs to know about everyone else already on the map
	var map_instance = active_maps[map_id].scene_instance
	var _joiner_is_bot = BotManager.is_bot(player_id)
	for existing_id in active_maps[map_id].player_ids:
		if existing_id == player_id: continue # Skip self (handled in _spawn_player_on_server_map)

		# The actual player/bot character node (get_player_map_node returns the
		# map, not the character — its components must be read off this node).
		var existing_node = PlayerManager.get_player_node(existing_id)
		if is_instance_valid(existing_node):
			# Tell the new player to spawn the existing player (skip for bots)
			if not _joiner_is_bot:
				client_spawn_player.rpc_id(player_id, existing_id, existing_node.global_position, _player_username(existing_id))
				# A bot's sprite isn't streamed via the node-addressed sprite
				# RPC, so send the joiner the bot's class/level appearance.
				if BotManager.is_bot(existing_id) and is_instance_valid(existing_node.weapon_mastery_component) \
						and is_instance_valid(existing_node.level_component):
					var bot_class: int = existing_node.weapon_mastery_component.primary_discipline
					var bot_level: int = existing_node.level_component.level
					if player_id == 1:
						# The host is the server — client_apply_appearance is a
						# call_remote RPC and can't target self; apply directly.
						existing_node.apply_appearance(bot_class, bot_level)
					else:
						client_apply_appearance.rpc_id(player_id, existing_id, bot_class, bot_level)
			# Also update visibility for the existing player
			update_visibility_for_player(existing_id)

	_spawn_player_on_server_map(player_id, map_id, spawn_point_name)

	# Warm pool: now that an agent is on this map, make sure its neighbours are
	# resident too, so the next portal hop uses the no-hitch fast-reparent path.
	_warm_around(map_id)

	# Sync existing players' buff visuals (e.g. Shadow Partner) to the new joiner (skip for bots)
	if not _joiner_is_bot:
		await get_tree().process_frame
		# The map (or this player) may have been torn down during the awaited
		# frame — a disconnect mid-spawn would leave active_maps[map_id] gone.
		if not map_id in active_maps:
			return
		for existing_id in active_maps[map_id].player_ids:
			if existing_id == player_id: continue
			var existing_player = map_instance.get_node_or_null("Players/" + str(existing_id))
			if is_instance_valid(existing_player) and existing_player.buff_component:
				existing_player.buff_component.sync_all_buffs_to_client(player_id)
	
	# After the player is spawned and on the map, update visibilities.
	update_visibility_for_player(player_id)
	
	# Sync existing dropped items to the new player (skip for bots)
	if not _joiner_is_bot:
		var drop_handler = map_instance.get_node_or_null("GlobalDropHandler")
		if drop_handler and drop_handler.has_method("sync_items_to_player"):
			drop_handler.sync_items_to_player(player_id)
		else:
			push_warning("MapManager: Could not find GlobalDropHandler to sync items for player %d on map %s" % [player_id, map_id])

	# A new agent just arrived — wake enemies near its spawn immediately rather
	# than waiting up to ACTIVATION_SCAN_INTERVAL, so spawning in next to a mob
	# never shows a frozen enemy.
	_scan_map_activation(map_id)
	# ...and fill this map's population to its (now-occupied) cap immediately, so a
	# re-entered or freshly-warmed map isn't sparse for up to one SPAWN_TICK_INTERVAL.
	# Idempotent and respects the over-cap rule.
	replenish_map_population(map_id)


func _spawn_player_on_server_map(player_id: int, map_id: String, spawn_point_name: String = ""):
	"""Spawns a player character manually and syncs to clients."""
	var map_instance = active_maps[map_id].scene_instance
	var players_node = map_instance.get_node_or_null("Players")
	if not players_node:
		push_error("Map '%s' is missing a Players node!" % map_id)
		return

	# 1. Instantiate on Server
	var player_scene = load("res://scenes/Player/player.tscn")
	var player_char = player_scene.instantiate()
	player_char.name = str(player_id)
	player_char.player_id = player_id
	
	# Set position
	player_char.global_position = get_spawn_position_for_map(map_id, spawn_point_name)
	
	# Add to tree
	players_node.add_child(player_char)

	# Invalidate map's synchronizer cache since new player subtree was added
	invalidate_synchronizer_cache(map_instance)

	# CRITICAL: Set public_visibility=false for all player synchronizers
	# Visibility will be controlled via visibility filters and _update_visibility_for_player()
	_set_synchronizers_public_visibility(player_char, false)
	#print("MapManager: Set public_visibility=false for player %d synchronizers" % player_id)
	
	#print("MapManager: Manually spawned player %d on map '%s' at %s" % [player_id, map_id, player_char.global_position])
	
	# 2. Notify ALL clients on this map to spawn this player
	# We iterate through all players currently on this map
	var players_on_map = active_maps[map_id].player_ids
	for peer_id in players_on_map:
		if BotManager.is_bot(peer_id):
			continue
		# RPC each peer to spawn this new player
		client_spawn_player.rpc_id(peer_id, player_id, player_char.global_position, _player_username(player_id))

	# Explicitly tell the client which node is theirs (for PlayerManager init)
	if not BotManager.is_bot(player_id):
		client_identify_player.rpc_id(player_id, player_char.get_path())


func _remove_player_from_map(player_id: int, map_id: String):
	if not map_id in active_maps: return
	
	var map_instance = active_maps[map_id].scene_instance
	if not is_instance_valid(map_instance): return
	
	#print("MapManager: Removing player %d from map '%s'" % [player_id, map_id])
	
	# CRITICAL: Hide this map from the player BEFORE removing them
	# This prevents "Node not found" errors during map transitions
	if player_id in active_maps[map_id].player_ids:
		# Rebuild the synchronizer list FIRST: item drops (and pooled enemies)
		# spawn into the map AFTER the cache was last built, and spawning them does
		# NOT invalidate it. Hiding off a stale cache leaves those dynamic
		# synchronizers visible to the departing peer, so the server keeps
		# replicating them to a client that has already freed the old map —
		# spamming "Node not found ... /ItemDrops/Item_.../MultiplayerSynchronizer".
		# (The join + reparent paths already invalidate before their visibility
		# pass; this is the one leave path that didn't.)
		invalidate_synchronizer_cache(map_instance)
		_set_visibility_for_node(map_instance, player_id, false)
		#print("MapManager: Hid map '%s' from player %d before removal" % [map_id, player_id])
	
	if player_id in active_maps[map_id].player_ids:
		active_maps[map_id].player_ids.erase(player_id)
	
	var player_node = map_instance.get_node_or_null("Players/" + str(player_id))
	if is_instance_valid(player_node):
		# Invalidate caches before freeing (player cache + map cache since subtree changes)
		invalidate_synchronizer_cache(player_node)
		invalidate_synchronizer_cache(map_instance)
		# Cleanup player components before freeing to prevent lingering network messages
		if player_node.has_method("cleanup_before_removal"):
			player_node.cleanup_before_removal()
		player_node.queue_free()
		
	# Notify clients on this map to remove this player (skip bot peers)
	for peer_id in active_maps[map_id].player_ids:
		if BotManager.is_bot(peer_id):
			continue
		client_despawn_player.rpc_id(peer_id, player_id)
	
	if player_id == 1 and current_map_instance == map_instance:
		current_map_instance = null
		current_map_id = ""
	
	if active_maps[map_id].player_ids.is_empty():
		if KEEP_MAPS_RESIDENT:
			# Keep the map resident (ADR 0007); put its now-agentless enemies to
			# sleep immediately so it costs ≈0 until someone returns.
			_scan_map_activation(map_id)
		else:
			_unload_map_on_server(map_id)


func _unload_map_on_server(map_id: String):
	if not map_id in active_maps: return

	#print("MapManager: Despawning empty map '%s'" % map_id)
	var map_instance = active_maps[map_id].scene_instance
	if is_instance_valid(map_instance):
		invalidate_synchronizer_cache(map_instance)
		# Free the SubViewport wrapper, not just the map, so the wrap doesn't
		# leak. Falls back to freeing the map directly if a wrap is somehow
		# missing (defensive — shouldn't happen with the current load path).
		var viewport: Node = map_instance.get_parent()
		if viewport is SubViewport:
			viewport.queue_free()
		else:
			map_instance.queue_free()

	active_maps.erase(map_id)
	map_unloaded.emit(map_id)


func handle_player_disconnect(player_id: int):
	if not multiplayer.is_server() or not player_id in player_current_maps: return
	
	var map_id = player_current_maps[player_id]
	_remove_player_from_map(player_id, map_id)
	player_current_maps.erase(player_id)


func reset_client_state():
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server(): return
	
	#print("MapManager: Resetting client-side map state.")
	current_map_id = ""
	current_map_instance = null
	my_player_node = null
	_warned_missing_paths.clear()
	# ADR 0009 Stage B: unbind then free the persistent UI on disconnect / main-menu.
	local_player_changed.emit(null)
	if is_instance_valid(_local_ui):
		_local_ui.queue_free()
		_local_ui = null


# === VISIBILITY LOGIC ===

func _get_all_synchronizers_in_node(node: Node) -> Array[MultiplayerSynchronizer]:
	"""Recursively finds all MultiplayerSynchronizer nodes under a given node."""
	var syncs: Array[MultiplayerSynchronizer] = []
	if node is MultiplayerSynchronizer:
		syncs.append(node)
	
	for child in node.get_children():
		syncs.append_array(_get_all_synchronizers_in_node(child))
		
	return syncs


func _set_visibility_for_node(node: Node, peer_id: int, visible: bool):
	"""Sets the visibility for all synchronizers within a node for a specific peer."""
	if not is_instance_valid(node): return
	if BotManager.is_bot(peer_id): return
	# The peer may already be gone — on disconnect, peer_disconnected fires AFTER
	# the peer leaves the multiplayer list, then _remove_player_from_map calls
	# here to hide the map from it. set_visibility_for errors ("peers_info has no
	# p_peer") for an absent peer, and there's nothing to hide from someone who's
	# already disconnected. The host (peer 1) is always valid.
	if peer_id != 1 and peer_id not in multiplayer.get_peers():
		return
	var synchronizers = _get_cached_synchronizers(node)
	for s in synchronizers:
		if not is_instance_valid(s): continue
		s.set_visibility_for(peer_id, visible)
		s.update_visibility(peer_id)


func _set_synchronizers_public_visibility(node: Node, visible: bool):
	"""Sets the default public visibility for all synchronizers in a node."""
	if not is_instance_valid(node): return
	var synchronizers = _get_cached_synchronizers(node)
	for s in synchronizers:
		if not is_instance_valid(s): continue
		s.public_visibility = visible


func _get_cached_synchronizers(node: Node) -> Array[MultiplayerSynchronizer]:
	"""Returns synchronizers for a node, using cache when available."""
	var id = node.get_instance_id()
	if _synchronizer_cache.has(id):
		return _synchronizer_cache[id]
	var syncs = _get_all_synchronizers_in_node(node)
	_synchronizer_cache[id] = syncs
	return syncs


func invalidate_synchronizer_cache(node: Node) -> void:
	"""Invalidates cached synchronizers for a node. Call when subtree structure changes."""
	_synchronizer_cache.erase(node.get_instance_id())


func update_visibility_for_player(player_id: int):
	"""
	Updates visibility for a given player against all other players and enemies.
	This should be called when a player changes maps.
	"""
	if not multiplayer.is_server(): return

	var player_node = PlayerManager.get_player_node(player_id)
	if not is_instance_valid(player_node): return

	var player_map = player_current_maps.get(player_id, "")
	if player_map.is_empty(): return

	var _this_is_bot = BotManager.is_bot(player_id)

	# 1. Update visibility between this player and all OTHER PLAYERS
	for other_id in player_current_maps.keys():
		if other_id == player_id: continue
		var other_node = PlayerManager.get_player_node(other_id)
		if not is_instance_valid(other_node): continue

		var other_map = player_current_maps.get(other_id, "")
		var is_visible = (player_map == other_map)

		# Update other player's view of me (skip if other is a bot)
		if not BotManager.is_bot(other_id):
			_set_visibility_for_node(player_node, other_id, is_visible)
		# Update my view of other player (skip if I'm a bot)
		if not _this_is_bot:
			_set_visibility_for_node(other_node, player_id, is_visible)

	# Bots don't need map visibility updates — they have no client to sync to.
	if _this_is_bot:
		return

	# 2. Update this player's visibility of the ENTIRE MAP
	# This includes Enemies, Items, Projectiles, etc.
	for map_id in active_maps.keys():
		var map_instance = active_maps[map_id].scene_instance
		if not is_instance_valid(map_instance): continue

		var is_visible = (player_map == map_id)

		# Set visibility for all synchronizers in this map for this player
		_set_visibility_for_node(map_instance, player_id, is_visible)


func _update_visibility_for_all_players():
	"""Updates visibility for ALL active players. Useful when a new map is added."""
	if not multiplayer.is_server(): return
	
	for player_id in player_current_maps.keys():
		update_visibility_for_player(player_id)


# === CLIENT LOGIC ===


@rpc("authority", "call_local", "reliable")
func client_set_current_map(map_id: String, spawn_point_name: String = ""):
	"""
	Server tells client which map to load.
	Client manually instantiates ONLY this map.
	"""
	if not multiplayer.is_server():
		_get_loading_overlay().show_loading(_map_display_name(map_id))

	#print("Client %d: Server requesting map '%s'" % [multiplayer.get_unique_id(), map_id])

	# Unload previous map if exists
	if is_instance_valid(current_map_instance):
		#print("Client: Unloading previous map '%s'" % current_map_id)
		# CRITICAL: Cleanup client's own player first before freeing map
		# This prevents InputSynchronizer errors during transition
		var my_id = multiplayer.get_unique_id()
		var players_node = current_map_instance.get_node_or_null("Players")
		if players_node:
			var my_player = players_node.get_node_or_null(str(my_id))
			if is_instance_valid(my_player) and my_player.has_method("cleanup_before_removal"):
				my_player.cleanup_before_removal()
				#print("Client: Cleaned up own player before map transition")

		# Free the SubViewport wrapper (created in the wrap below) so it doesn't
		# leak. Falls back to freeing the map directly if a wrap is missing.
		var old_viewport: Node = current_map_instance.get_parent()
		if old_viewport is SubViewport:
			old_viewport.queue_free()
		else:
			current_map_instance.queue_free()
		current_map_instance = null
	
	# Load and instantiate new map
	var map_path = MAP_SCENES.get(map_id)
	if not map_path:
		push_error("Client: Invalid map_id '%s'" % map_id)
		return
	
	var map_scene = load(map_path)
	if not map_scene:
		push_error("Client: Failed to load map scene at '%s'" % map_path)
		return
		
	var map_instance = map_scene.instantiate()
	if not is_instance_valid(map_instance):
		push_error("Client: Failed to instantiate map '%s'" % map_id)
		return
		
	map_instance.name = "Map_" + map_id

	# Mirror the server's wrap so the absolute node path of every map-child
	# (Players/<id>, Enemies, spawners, ...) matches between server and client.
	# Synchronizer replication and RPC routing rely on this parity.
	var maps_container := _ensure_maps_container()
	var viewport := _wrap_in_subviewport(map_instance, map_id)
	maps_container.add_child(viewport)
	# Remote clients only ever have one map loaded; it's always the local
	# peer's current map, so render it and re-enable GUI input on its
	# SubViewport (which defaults to disabled — see _wrap_in_subviewport).
	map_instance.visible = true
	viewport.gui_disable_input = false
	
	# On client, map synchronizers should start hidden and rely on server visibility updates
	# if not multiplayer.is_server():
	# 	_set_synchronizers_public_visibility(map_instance, false)
	# 	print("Client: Set public_visibility=false for map synchronizers")
	
	# Track locally
	current_map_instance = map_instance
	current_map_id = map_id
	_warned_missing_paths.clear()

	# Play per-map BGM if the map defines one
	if map_instance is MapBase and not map_instance.bgm_path.is_empty():
		AudioManager.play_song(map_instance.bgm_path)

	#print("Client %d: Loaded map '%s' at path %s" % [multiplayer.get_unique_id(), map_id, map_instance.get_path()])

	# ACK to server
	rpc_id(1, "client_map_loaded", map_id, spawn_point_name)


@rpc("authority", "call_local", "reliable")
func client_identify_player(player_node_path: String):
	"""Called by the server to tell the client which spawned player node is theirs."""
	#print("Client: Server identified my player at path: %s" % player_node_path)
	
	var node = get_node_or_null(player_node_path)
	var wait_count = 0
	while not is_instance_valid(node) and wait_count < 10:
		await get_tree().process_frame
		node = get_node_or_null(player_node_path)
		wait_count += 1
		
	if not is_instance_valid(node):
		push_error("Client: Timed out waiting for my player node at path: %s" % player_node_path)
		return
		
	my_player_node = node
	if _loading_overlay and is_instance_valid(_loading_overlay):
		_loading_overlay.hide_loading()
	# ADR 0009 Stage B: (re)bind the persistent local-player UI to THIS body — but
	# only when it is our OWN body. On the host this method also runs (call_local)
	# for every remote player's identify; the player_id guard stops us binding the
	# host's UI to a remote body. Fires on every spawn + map change for our body.
	if is_instance_valid(node) and node.player_id == multiplayer.get_unique_id():
		_ensure_local_ui()
		local_player_changed.emit(node)
	#print("Client: Found my player node. Notifying server.")
	rpc_id(1, "client_player_spawned", current_map_id)


@rpc("authority", "call_local", "reliable")
func client_spawn_player(new_player_id: int, spawn_pos: Vector2, username: String = ""):
	"""Client: Instantiate a player node manually."""
	if not is_instance_valid(current_map_instance):
		return

	var players_node = current_map_instance.get_node_or_null("Players")
	if not players_node:
		push_error("Client: Current map missing Players node!")
		return

	if players_node.has_node(str(new_player_id)):
		# Already exists
		if multiplayer.is_server():
			# Server is authority, do not reset position of existing players
			return

		var p = players_node.get_node(str(new_player_id))
		p.global_position = spawn_pos
		if not username.is_empty():
			p.set_username(username)
		return

	var player_scene = load("res://scenes/Player/player.tscn")
	var player_node = player_scene.instantiate()
	player_node.name = str(new_player_id)
	player_node.player_id = new_player_id
	player_node.global_position = spawn_pos

	players_node.add_child(player_node)

	# Apply the player's name so the floating label and right-click context
	# menu show it — covers bots, whose username is otherwise never sent to
	# clients (bot state is server-authoritative).
	if not username.is_empty():
		player_node.set_username(username)
	
	# Set public_visibility=false for player synchronizers (client-side)
	# if not multiplayer.is_server():
	# 	_set_synchronizers_public_visibility(player_node, false)
	
	#print("Client: Manually spawned player %d at %s" % [new_player_id, spawn_pos])


@rpc("authority", "call_local", "reliable")
func client_despawn_player(player_id_to_remove: int):
	"""Client: Remove a player node."""
	if not is_instance_valid(current_map_instance): return
	
	var players_node = current_map_instance.get_node_or_null("Players")
	if players_node and players_node.has_node(str(player_id_to_remove)):
		var node = players_node.get_node(str(player_id_to_remove))
		node.queue_free()
		#print("Client: Despawned player %d" % player_id_to_remove)


## [Server -> Client] Spawns a projectile visual on a client. Routed through
## MapManager (an autoload that always resolves on every peer) so it works for
## any caster — including bots, whose component nodes a client may lack during
## a map transition. Clients simulate the projectile's movement locally; the
## server stays authoritative for hit detection.
@rpc("authority", "call_remote", "reliable")
func spawn_projectile_visual(proj_name: String, scene_path: String, start_pos: Vector2, direction: Vector2, speed: float, target_path: NodePath) -> void:
	if multiplayer.is_server():
		return
	var map_node = get_current_visible_map()
	if not is_instance_valid(map_node):
		return
	var container = map_node.get_node_or_null("Projectiles")
	if not is_instance_valid(container):
		container = Node.new()
		container.name = "Projectiles"
		map_node.add_child(container)
	if container.has_node(proj_name):
		return  # already spawned — defensive against a duplicate RPC
	var scene: PackedScene = load(scene_path)
	if not scene:
		return
	var projectile = scene.instantiate()
	projectile.name = proj_name
	var target: Node = get_node_or_null(target_path) if not target_path.is_empty() else null
	projectile.initialize(null, target, null, null, speed, direction)
	# Set position BEFORE add_child to avoid an interpolation streak from (0,0).
	# See ability.gd spawn_projectile / damage_numbers.gd.
	projectile.position = start_pos - container.global_position
	container.add_child(projectile)


## [Server -> Client] Removes a projectile visual early — the server's
## authoritative copy hit something before its lifetime expired. Lifetime
## expiry is handled independently on each peer by the projectile's own timer.
@rpc("authority", "call_remote", "reliable")
func despawn_projectile_visual(proj_name: String) -> void:
	if multiplayer.is_server():
		return
	var map_node = get_current_visible_map()
	if not is_instance_valid(map_node):
		return
	var container = map_node.get_node_or_null("Projectiles")
	if not is_instance_valid(container):
		return
	var projectile = container.get_node_or_null(proj_name)
	if is_instance_valid(projectile):
		projectile.queue_free()


const _LightningArcVfx = preload("res://scripts/VFX/lightning_arc.gd")

## [Server] Broadcasts a chain-lightning arc VFX to every real client viewing the
## event's map (and draws it on the host if the host is on that map). Cosmetic
## only — the chain DAMAGE is already applied server-side by StaffElementComponent.
## `points` are GLOBAL positions: the struck target first, then each chained enemy
## in order, so each peer draws one bolt threading through the shocked enemies.
func broadcast_lightning_arc(map_id: String, points: PackedVector2Array) -> void:
	if not multiplayer.is_server():
		return
	if points.size() < 2:
		return
	# The host is also a client — draw locally only if it is viewing this map
	# (the call_remote RPC below never runs on the server).
	if get_player_map(1) == map_id:
		_spawn_lightning_arc_visual(points)
	broadcast_to_map(map_id, func(peer_id): client_show_lightning_arc.rpc_id(peer_id, points), true, true)


## [Server -> Client] Draws the chain-lightning arc on this peer. Routed through
## MapManager (an autoload that always resolves) rather than any per-entity node,
## mirroring bot_ability_used / spawn_projectile_visual.
@rpc("authority", "call_remote", "reliable")
func client_show_lightning_arc(points: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	_spawn_lightning_arc_visual(points)


## Spawns the transient bolt node under the visible map (so it renders in the
## right SubViewport) and lets it self-free. No-op on a headless peer / when no
## map is visible.
func _spawn_lightning_arc_visual(points: PackedVector2Array) -> void:
	var map_node = get_current_visible_map()
	if not is_instance_valid(map_node):
		return
	var arc = _LightningArcVfx.new()
	map_node.add_child(arc)
	arc.setup(points)


const _SpriteEffectVfx = preload("res://scripts/VFX/sprite_effect.gd")

## [Server] Plays a catalog sprite-VFX (see VfxCatalog) on EVERY peer viewing
## `map_id`, host INCLUSIVE. Use for ability cast/hit juice and looping ground
## effects — all of which the server spawns with no authoritative visual node of
## their own, so (unlike GroundZone, whose host copy renders for free) the host
## must be drawn explicitly here.
##
## `key` is a VfxEffectData effect_key (resources/VFX); `pos` is global; `scale_mult` multiplies
## the catalog's base scale; `rot` (radians) + `flip_h` orient directional
## effects; `duration` > 0 keeps a LOOPING effect alive that long (match it to a
## GroundZone's lifetime), <= 0 plays a one-shot burst that frees on finish.
func broadcast_vfx_everywhere(map_id: String, key: String, pos: Vector2, scale_mult: float = 1.0, rot: float = 0.0, flip_h: bool = false, duration: float = 0.0) -> void:
	if not multiplayer.is_server():
		return
	if key == "":
		return
	# Remote clients (bots excluded — no client; host skipped — call_remote).
	broadcast_to_map(map_id, func(peer_id): client_show_vfx.rpc_id(peer_id, key, pos, scale_mult, rot, flip_h, duration), true, true)
	# Host draws its own copy, but only when actually viewing this map (the
	# call_remote RPC above never runs on peer 1). Uses get_current_visible_map()
	# inside _spawn_vfx_visual — the SAME node DroppedItems and damage numbers use,
	# so the effect lands in the right World2D.
	if get_player_map(1) == map_id:
		_spawn_vfx_visual(key, pos, scale_mult, rot, flip_h, duration)


## [Server -> Client] Spawns the sprite-VFX on this peer. Routed through
## MapManager (an autoload that always resolves) rather than any per-entity node,
## mirroring spawn_projectile_visual / client_show_lightning_arc.
@rpc("authority", "call_remote", "reliable")
func client_show_vfx(key: String, pos: Vector2, scale_mult: float, rot: float, flip_h: bool, duration: float) -> void:
	if multiplayer.is_server():
		return
	_spawn_vfx_visual(key, pos, scale_mult, rot, flip_h, duration)


## Spawns the transient effect node under the locally-visible map (the same node
## DroppedItems / damage numbers use) and lets it self-free. No-op on a headless
## peer / when no map is visible.
##
## Positions exactly like damage_numbers.gd: set LOCAL position = pos minus the
## map's global_position, rather than assigning global_position after add_child.
## Both are equivalent for a translation-only parent, but matching the proven
## transient-cosmetic path avoids any global_position-after-reparent edge case
## inside the map's SubViewport.
func _spawn_vfx_visual(key: String, pos: Vector2, scale_mult: float, rot: float, flip_h: bool, duration: float) -> void:
	var map_node = get_current_visible_map()
	if not is_instance_valid(map_node):
		return
	var fx = _SpriteEffectVfx.new()
	# Set LOCAL position BEFORE add_child so the node never exists at (0,0) in the
	# tree — otherwise physics interpolation streaks it from the origin to pos
	# ("flies across the screen"). This is the proven order damage_numbers.gd and
	# the ground-zone visual use; assigning position AFTER add_child re-introduces
	# the streak. (Translation-only map parent, so local = pos - map global.)
	fx.position = pos - map_node.global_position
	map_node.add_child(fx)
	fx.setup(key, scale_mult, rot, flip_h, duration)


## [Server] Plays a LOOPING ground-strip VFX (tiled across `width` px, centered
## on `center`) on every peer viewing `map_id`, host inclusive — the animated
## flourish that fills a GroundZone. Call it right after spawning the zone with
## the SAME center/duration so the sprites live and die with the hazard. `width`
## should be the zone's full pixel width (rect_size.x, or 2×radius for a circle).
func broadcast_ground_vfx_everywhere(map_id: String, key: String, center: Vector2, width: float, duration: float) -> void:
	if not multiplayer.is_server():
		return
	if key == "":
		return
	broadcast_to_map(map_id, func(peer_id): client_show_ground_vfx.rpc_id(peer_id, key, center, width, duration), true, true)
	if get_player_map(1) == map_id:
		_spawn_ground_vfx_visual(key, center, width, duration)


## [Server -> Client] Spawns the tiled ground strip on this peer.
@rpc("authority", "call_remote", "reliable")
func client_show_ground_vfx(key: String, center: Vector2, width: float, duration: float) -> void:
	if multiplayer.is_server():
		return
	_spawn_ground_vfx_visual(key, center, width, duration)


func _spawn_ground_vfx_visual(key: String, center: Vector2, width: float, duration: float) -> void:
	var map_node = get_current_visible_map()
	if not is_instance_valid(map_node):
		return
	var fx = _SpriteEffectVfx.new()
	# Set position BEFORE add_child to avoid an interpolation streak from (0,0).
	# See _spawn_vfx_visual.
	fx.position = center - map_node.global_position
	map_node.add_child(fx)
	fx.setup_ground_strip(key, width, duration)


## [Server] Broadcasts a cosmetic ground-zone visual to every real CLIENT
## viewing the event's map. The authoritative GroundZone (with damage logic) is
## already added under the map's scene_instance by `GroundZone.spawn_server`,
## so the host (which is also a client) needs no extra mirror — its own zone
## renders for free. We only RPC to remote clients, where a parallel visual
## mirror is spawned via _spawn_ground_zone_visual.
##
## CIRCLE backward-compat path. New ground-rect callers should use
## broadcast_ground_zone_shaped.
func broadcast_ground_zone(map_id: String, pos: Vector2, radius: float, duration: float, color: Color) -> void:
	broadcast_ground_zone_shaped(map_id, pos, 0, radius, Vector2.ZERO, duration, color)


## [Server] Shape-aware ground-zone visual broadcast. shape_type matches the
## GroundZone.Shape enum (0=CIRCLE, 1=RECT). For CIRCLE, only `radius` is read;
## for RECT, `rect_size` is the full width × height (centered on `pos`).
func broadcast_ground_zone_shaped(map_id: String, pos: Vector2, shape_type: int, radius: float, rect_size: Vector2, duration: float, color: Color) -> void:
	if not multiplayer.is_server():
		return
	broadcast_to_map(map_id, func(peer_id): client_show_ground_zone_shaped.rpc_id(peer_id, pos, shape_type, radius, rect_size, duration, color), true, true)


## [Server] Like broadcast_ground_zone, but ALSO renders on the host. Use this
## for server-only effects (boss telegraphs / phase roars) that have NO
## authoritative GroundZone node — unlike ability casters, which already render
## their own zone locally on the host, so for those broadcast_ground_zone
## (call_remote, host-skipped) is correct. Here the host would otherwise see
## nothing: the client RPC is call_remote and broadcast_to_map skips peer 1, so
## we spawn the host's visual copy directly. Remotes still get it via the RPC.
func show_ground_zone_everywhere(map_id: String, pos: Vector2, radius: float, duration: float, color: Color) -> void:
	show_ground_zone_shaped_everywhere(map_id, pos, 0, radius, Vector2.ZERO, duration, color)


## [Server] Shape-aware host-inclusive variant. shape_type 0=CIRCLE (reads radius),
## 1=RECT (reads rect_size = full width × height, centered on pos).
func show_ground_zone_shaped_everywhere(map_id: String, pos: Vector2, shape_type: int, radius: float, rect_size: Vector2, duration: float, color: Color) -> void:
	if not multiplayer.is_server():
		return
	# Remote clients (bots excluded; host skipped — its RPC is call_remote anyway).
	broadcast_to_map(map_id, func(peer_id): client_show_ground_zone_shaped.rpc_id(peer_id, pos, shape_type, radius, rect_size, duration, color), true, true)
	# Host renders its own copy, but only when the host is actually on this map
	# (get_current_visible_map is the host's map; spawning otherwise would render
	# a telegraph for a fight the host can't see).
	if get_players_on_map(map_id).has(1):
		_spawn_ground_zone_visual(pos, shape_type, radius, rect_size, duration, color)


## [Server -> Client] Spawns a visual-only GroundZone on this peer. Routed
## through MapManager (an autoload that always resolves) rather than addressing
## any per-entity node. call_remote because the server already owns the
## authoritative damage path — it must NOT also run this visual spawn.
##
## Backward-compat: old call sites that targeted client_show_ground_zone with
## the 4-arg signature still get routed to a CIRCLE visual.
@rpc("authority", "call_remote", "reliable")
func client_show_ground_zone(pos: Vector2, radius: float, duration: float, color: Color) -> void:
	if multiplayer.is_server():
		return
	_spawn_ground_zone_visual(pos, 0, radius, Vector2.ZERO, duration, color)


## [Server -> Client] Shape-aware visual spawn — the canonical version.
@rpc("authority", "call_remote", "reliable")
func client_show_ground_zone_shaped(pos: Vector2, shape_type: int, radius: float, rect_size: Vector2, duration: float, color: Color) -> void:
	if multiplayer.is_server():
		return
	_spawn_ground_zone_visual(pos, shape_type, radius, rect_size, duration, color)


## Spawns a damage-less GroundZone under the visible map so the shape renders
## in the right SubViewport. damage_per_tick stays 0 + applier stays null on
## the visual mirror, so _do_tick early-returns and no gameplay state is
## touched. The zone self-frees via its own duration timer.
##
## NOTE: preload rather than class_name reference — MapManager is an autoload
## and its parse order may run before ground_zone.gd registers its class_name,
## causing a "GroundZone not declared" parse error. The preload locks the
## script load explicitly.
const _GroundZoneScript = preload("res://scripts/Gameplay/ground_zone.gd")

func _spawn_ground_zone_visual(pos: Vector2, shape_type: int, radius: float, rect_size: Vector2, duration: float, color: Color) -> void:
	var map_node = get_current_visible_map()
	if not is_instance_valid(map_node):
		return
	var zone = _GroundZoneScript.new()
	zone.global_position = pos
	zone.shape_type = shape_type
	zone.radius = radius
	zone.rect_size = rect_size
	zone.duration = duration
	zone.visual_color = color
	map_node.add_child(zone)


## [Server -> Client] Plays a bot's ability-cast visual. Routed through
## MapManager (an autoload that always resolves) rather than the bot's
## AbilityComponent node, which a client may lack during a map transition.
@rpc("authority", "call_remote", "reliable")
func bot_ability_used(caster_id: int, ability_id: String, level: int) -> void:
	if multiplayer.is_server():
		return
	var caster = PlayerManager.get_player_node(caster_id)
	if not is_instance_valid(caster) or not is_instance_valid(caster.ability_component):
		return  # bot not present on this client — skip the visual, no error
	caster.ability_component.play_ability_visual(ability_id, level)


## [Server] Sends a bot's class/level to every real client on its map so they
## render the correct sprite. Bot appearance isn't streamed via the
## node-addressed sprite RPC, so this delivers it on demand.
func broadcast_player_appearance(player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var node = PlayerManager.get_player_node(player_id)
	if not is_instance_valid(node) or not is_instance_valid(node.weapon_mastery_component) \
			or not is_instance_valid(node.level_component):
		return
	var class_type: int = node.weapon_mastery_component.primary_discipline
	var level: int = node.level_component.level
	# Apply on the host directly — client_apply_appearance early-returns on the
	# server, but the host is also a client and must render the bot.
	node.apply_appearance(class_type, level)
	broadcast_to_map(get_player_map(player_id), func(peer_id): client_apply_appearance.rpc_id(peer_id, player_id, class_type, level), true, true)


## [Server -> Client] Applies a player/bot's sprite frames for its class/level.
## Routed through MapManager so it always resolves even mid map-transition.
@rpc("authority", "call_remote", "reliable")
func client_apply_appearance(player_id: int, class_type: int, level: int) -> void:
	if multiplayer.is_server():
		return
	var node = PlayerManager.get_player_node(player_id)
	if is_instance_valid(node):
		node.apply_appearance(class_type, level)


# === SERVER-SIDE ACKS FROM CLIENTS ===

@rpc("any_peer", "call_local", "reliable")
func client_map_loaded(map_id: String, spawn_point_name: String = ""):
	"""ACK from client that they have a reference to the spawned map node."""
	if not multiplayer.is_server(): return

	var peer_id: int = multiplayer.get_remote_sender_id()
	#print("MapManager: Received map-loaded ACK from %d for map '%s'" % [peer_id, map_id])

	var expected_map = player_current_maps.get(peer_id, "")
	if expected_map != map_id:
		push_warning("MapManager: Peer %d reported map '%s' but server expects '%s'" % [peer_id, map_id, expected_map])
		return

	_finalize_player_spawn(peer_id, map_id, spawn_point_name)


@rpc("any_peer", "call_local", "reliable")
func client_player_spawned(_map_id: String) -> void:
	"""ACK from client that they have identified their own player character node."""
	if not multiplayer.is_server(): return

	var peer_id: int = multiplayer.get_remote_sender_id()
	#print("MapManager: Received player-spawned ACK from %d. Initializing." % peer_id)
	player_spawned.emit(peer_id)


# === MAP CONNECTIVITY ===

## Builds the map adjacency graph by scanning each map scene's portal nodes for
## their target_map_id. Done once, server-side, before bots start pathfinding.
func _build_map_connections() -> void:
	map_connections.clear()
	for map_id in MAP_SCENES:
		var connections: Array[String] = []
		# Prefer the resident instance (maps are pre-instantiated at server start,
		# ADR 0007) so we don't instantiate a throwaway copy just to read portals.
		var inst: Node = active_maps.get(map_id, {}).get("scene_instance")
		if is_instance_valid(inst):
			_collect_portal_targets(inst, map_id, connections)
		else:
			# Fallback for callers that run before pre-instantiation (e.g. a lazy
			# get_map_connections on a peer with no resident maps): instantiate
			# off-tree (no _ready) and free immediately. Property overrides on
			# instanced portals are only reliably readable off a real node.
			var scene: PackedScene = load(MAP_SCENES[map_id])
			if is_instance_valid(scene):
				var root := scene.instantiate()
				_collect_portal_targets(root, map_id, connections)
				root.free()
		map_connections[map_id] = connections
	#print("MapManager: Map connectivity graph: %s" % map_connections)


## Recursively collects portal destination map ids under `node` into `out`.
func _collect_portal_targets(node: Node, map_id: String, out: Array) -> void:
	if "target_map_id" in node:
		var dest = node.target_map_id
		if dest is String and not dest.is_empty() and dest != map_id and dest not in out:
			out.append(dest)
	for child in node.get_children():
		_collect_portal_targets(child, map_id, out)


## Maps directly reachable from `map_id` via its portals.
func get_map_connections(map_id: String) -> Array:
	if map_connections.is_empty():
		_build_map_connections()
	return map_connections.get(map_id, [])


## Returns the next map to travel to along the shortest portal route from
## `from_map` to `to_map`, or "" if they are the same or no route exists. The
## returned map is always directly connected to `from_map`.
func get_next_map_toward(from_map: String, to_map: String) -> String:
	if from_map == to_map or to_map.is_empty():
		return ""
	if map_connections.is_empty():
		_build_map_connections()
	var visited := {from_map: true}
	var queue: Array = []  # entries: [current_map, first_hop_from_origin]
	for neighbor in map_connections.get(from_map, []):
		visited[neighbor] = true
		queue.append([neighbor, neighbor])
	while not queue.is_empty():
		var entry: Array = queue.pop_front()
		if entry[0] == to_map:
			return entry[1]
		for neighbor in map_connections.get(entry[0], []):
			if neighbor in visited:
				continue
			visited[neighbor] = true
			queue.append([neighbor, entry[1]])
	return ""


## Returns the closest hearth (safe town) map to `from_map_id` by portal-hop
## distance — the destination for a generic Hearthstone. If the player is already
## at a hearth, returns it. Falls back to DEFAULT_MAP if the graph is empty / no
## hearth is reachable. Server-side (uses the portal-derived map graph).
func get_nearest_hearth(from_map_id: String) -> String:
	if from_map_id in HEARTH_MAPS:
		return from_map_id
	if map_connections.is_empty():
		_build_map_connections()
	var visited := {from_map_id: true}
	var queue: Array = []
	for neighbor in map_connections.get(from_map_id, []):
		visited[neighbor] = true
		queue.append(neighbor)
	while not queue.is_empty():
		var m: String = queue.pop_front()
		if m in HEARTH_MAPS:
			return m
		for neighbor in map_connections.get(m, []):
			if neighbor in visited:
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return DEFAULT_MAP


# === UTILITY FUNCTIONS ===

func get_current_visible_map() -> Node:
	return current_map_instance

func find_node_in_current_map(path: String) -> Node:
	if not current_map_instance:
		if not _warned_missing_paths.has(path):
			_warned_missing_paths[path] = true
			push_warning("No current map loaded - cannot find '%s'" % path)
		return null

	var node = current_map_instance.get_node_or_null(path)
	if not node:
		if not _warned_missing_paths.has(path):
			_warned_missing_paths[path] = true
			push_warning("MapManager: Node '%s' not found in current map" % path)
		return null
	return node

func get_spawn_position_for_map(map_id: String, spawn_point_name: String = "") -> Vector2:
	var map_instance = null
	if multiplayer.is_server():
		if map_id in active_maps:
			map_instance = active_maps[map_id].scene_instance
	else:
		if current_map_instance and current_map_id == map_id:
			map_instance = current_map_instance
	
	if map_instance:
		var spawn_node_name = spawn_point_name
		if spawn_node_name.is_empty():
			# Fallback to default spawn points if no specific name is provided
			spawn_node_name = "PlayerSpawn"
		
		var spawn = map_instance.get_node_or_null(spawn_node_name)
		if not spawn: spawn = map_instance.get_node_or_null("SpawnPoint")
		if not spawn: spawn = map_instance.get_node_or_null("Spawn")
		if spawn: return spawn.global_position
	
	return Vector2.ZERO

func get_players_on_map(map_id: String) -> Array:
	if not multiplayer.is_server(): return []
	if map_id in active_maps: return active_maps[map_id].player_ids.duplicate()
	return []


func get_real_players_on_map(map_id: String) -> Array:
	var all_players := get_players_on_map(map_id)
	return all_players.filter(func(id): return not BotManager.is_bot(id))


## Emitted on the requesting peer when per-map population counts arrive.
signal population_counts_received(counts: Dictionary)


## [Client -> Server] The world-map overlay asks how many characters occupy
## each map — players AND bots counted indistinguishably, which is the point
## (ADR 0012). One snapshot per request, no continuous sync.
@rpc("any_peer", "call_local", "reliable")
func request_population_counts() -> void:
	if not multiplayer.is_server():
		return
	var requester := multiplayer.get_remote_sender_id()
	if requester == 0:
		requester = multiplayer.get_unique_id()
	var counts: Dictionary = {}
	for map_id in active_maps:
		var n: int = active_maps[map_id].get("player_ids", []).size()
		if n > 0:
			counts[map_id] = n
	if requester == multiplayer.get_unique_id():
		receive_population_counts(counts)
	else:
		receive_population_counts.rpc_id(requester, counts)


## [Server -> Client] Delivers the population snapshot to the requester.
@rpc("authority", "call_local", "reliable")
func receive_population_counts(counts: Dictionary) -> void:
	population_counts_received.emit(counts)


## Server-only. Invokes `fn(peer_id)` for each client on `map_id`. The single
## seam for "send this to everyone on a map": it owns the player lookup, the
## bot exclusion (bots are clientless, so excluded by default — never
## node-address a bot), and the optional host skip (peer 1, for call_remote-style
## RPCs the server already applied locally). Replaces the
## get_real_players_on_map(...) + for-loop + `if peer_id != 1` boilerplate that
## was re-derived (inconsistently) across many broadcast sites.
func broadcast_to_map(map_id: String, fn: Callable, exclude_bots: bool = true, skip_host: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var peers: Array = get_real_players_on_map(map_id) if exclude_bots else get_players_on_map(map_id)
	for peer_id in peers:
		if skip_host and peer_id == 1:
			continue
		fn.call(peer_id)

func get_player_map(player_id: int) -> String:
	if not multiplayer.is_server(): return ""
	return player_current_maps.get(player_id, "")


## Username for a player/bot id, used to pass names to clients on spawn.
func _player_username(id: int) -> String:
	var info: Dictionary = PlayerManager.get_player_info(id)
	return info.get("username", "")
	
func get_player_map_node(player_id: int) -> Node:
	if not multiplayer.is_server(): return null
	
	var map_id = get_player_map(player_id)
	if map_id and active_maps.has(map_id):
		return active_maps[map_id].scene_instance
	return null
