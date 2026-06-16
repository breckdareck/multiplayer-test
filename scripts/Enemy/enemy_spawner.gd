extends Node
class_name EnemySpawner

@export_group("Spawning Configuration")
@export var enemy_scene: PackedScene:
	set(value):
		if not value and is_inside_tree():
			printerr("Enemy scene cannot be empty.")
		enemy_scene = value

@export var spawn_locations: Array[Marker2D] = []
@export var spawn_container: Node

@export_group("Pooling")
## The enemy pool size. In the MapleStory spawn model this IS the physical
## spawn-point cap (the 100% / full-party value). A solo player sees
## floor(0.75 * pool_size) alive at once. See docs/maplestory_spawn_mechanics.md.
@export var pool_size: int = 5
## DEPRECATED. Respawns are now gated by MapManager's global spawn_tick (~7.56s),
## not a per-enemy delay. Kept only so existing scene files load unchanged.
@export var respawn_delay: float = 3.0

@export_group("Population (MapleStory model)")
## When true, this spawner is managed independently of the map population budget
## and simply keeps its WHOLE pool alive — use for bosses / set-piece spawns that
## must always be present. When false (default), it contributes its spawn points
## to the MAP-WIDE cap, which MapManager scales by occupancy and fills by picking
## random empty points across every spawner on the map. See ADR 0015.
@export var exclude_from_map_cap: bool = false

## MapleStory capacity curve: pct = clamp(SOLO + STEP*(occupants-1), SOLO, 1.0).
## Applied by MapManager to the MAP's TOTAL spawn-point pool, not per spawner —
## floor(6*0.75) barely scales, but floor(20*0.75) across the whole map does.
const _SOLO_CAPACITY_PCT := 0.75
const _PER_OCCUPANT_STEP := 0.05

var _pool: Array[Node] = []
## Pool members currently dead/parked and available to (re)spawn. A member is
## "alive" exactly while it is OUT of this list, so alive == _pool.size() -
## _dormant.size(). The over-cap rule falls out for free: _replenish only ever
## pulls FROM this list and never pushes a live enemy back into it.
var _dormant: Array[Node] = []
var _is_initialized: bool = false
var _multiplayer_spawner: MultiplayerSpawner = null

func _ready() -> void:
	if not is_multiplayer_authority():
		return
	# We wait for the MultiplayerManager to signal that the server has started.
	# This requires MultiplayerManager to be an Autoload singleton as recommended.
	MultiplayerManager.server_has_started.connect(_on_server_created)

	# It's also possible this spawner is added to the scene tree *after* the
	# server has already started (e.g., loading a new level).
	# This check handles that case.
	# We must check that the active peer is NOT the default OfflineMultiplayerPeer.
	# The default peer makes `is_server()` return true even when offline.
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_on_server_created()

func _on_server_created() -> void:
	# Ensure this logic only runs once and only on the server.
	if _is_initialized or not is_multiplayer_authority():
		return
	
	_is_initialized = true

	# Defer pool creation to ensure the scene tree is fully ready.
	call_deferred("_setup_spawner")

func _setup_spawner() -> void:
	# Get reference to MultiplayerSpawner now that we are deferred and on the server
	_multiplayer_spawner = get_node_or_null("MultiplayerSpawner")
	if not _multiplayer_spawner:
		push_error("EnemySpawner: Could not find MultiplayerSpawner child node! Enemies won't replicate to clients.")
		return

	_create_pool()

	# This spawner contributes its pool to the MAP-WIDE population budget, which
	# MapManager computes and fills once per global spawn tick (ADR 0015). Register
	# so MapManager can find us, then ask for an immediate fill so a freshly-loaded
	# map isn't empty until the next tick (0 if the map has no occupants yet).
	add_to_group("EnemySpawners")
	var map_id := _get_map_id()
	if map_id != "":
		MapManager.replenish_map_population(map_id)

func _create_pool() -> void:
	if not _validate_exports():
		return
	
	if not _multiplayer_spawner:
		push_error("EnemySpawner: Cannot create pool, MultiplayerSpawner not available!")
		return
	
	# Ensure the spawn function is set up on the MultiplayerSpawner
	if _multiplayer_spawner.spawn_function == null:
		#print("EnemySpawner: Setting up spawn function on MultiplayerSpawner")
		_multiplayer_spawner.spawn_function = _create_enemy_instance
	
	#print("EnemySpawner: Creating pool of %d enemies using MultiplayerSpawner" % pool_size)
	
	for i in range(pool_size):
		var enemy: EnemyBase = enemy_scene.instantiate() as EnemyBase
		
		if not enemy:
			printerr("EnemySpawner: Failed to spawn enemy %d through MultiplayerSpawner." % i)
			continue
		
		if not enemy.health_component:
			printerr("EnemySpawner: Enemy instance %d is missing a HealthComponent." % i)
			enemy.queue_free()
			continue

		# Pool-managed enemies must be respawnable; otherwise enemy_base.gd's
		# death path queue_free's them and the pool never refills.
		enemy.respawnable = true

		# CRITICAL: Set public_visibility = false on enemy synchronizers BEFORE adding to tree
		# This ensures the MultiplayerSpawner tracks it with correct visibility from the start
		_set_enemy_synchronizers_visibility(enemy, false)
		
		# Now add to tree - MultiplayerSpawner will track it with visibility already configured
		spawn_container.add_child(enemy, true)
		
		# Connect to the enemy's own signal, which fires after its death animation is complete.
		enemy.ready_for_pooling.connect(_on_enemy_ready_for_pooling.bind(enemy))
		_pool.append(enemy)
		
		# Deactivate the enemy until it's needed
		enemy.pool_deactivate()

	# Every freshly created member starts parked and available; _replenish pulls
	# from here up to the current cap.
	_dormant = _pool.duplicate()

	#print("EnemySpawner: Pool created with %d enemies" % _pool.size())
	
	# Update visibility for all players on this map
	# This ensures the enemies are visible to the right players
	await get_tree().process_frame
	_update_all_player_visibility()


func _on_enemy_ready_for_pooling(enemy: EnemyBase) -> void:
	# Death sequence done: park it and return it to the dormant pool. WHEN it
	# actually respawns is decided by the global spawn_tick (or an agent entering
	# the map), up to the current player-scaled cap — not a per-enemy timer.
	enemy.pool_deactivate()
	if enemy not in _dormant:
		_dormant.append(enemy)


# --- Map-driven population (MapleStory model, ADR 0015) ------------------------
# This spawner is intentionally "dumb": it owns a typed pool of enemies and its
# spawn-point markers, and exposes alive/room so MapManager can run ONE map-wide
# cap across every spawner (floor(map_total * pct)) and fill random empty points.
# Respawns ride MapManager's global spawn tick; over-cap waves left by a departing
# party are kept (we never despawn) and corrected only as they die.

## Total spawn-point capacity this spawner contributes (its pool size). Falls back
## to the export before the pool is built (e.g. on a client, or pre-setup).
func get_pool_capacity() -> int:
	return _pool.size() if not _pool.is_empty() else pool_size


## How many of this spawner's enemies are currently alive (out in the world).
func get_alive_count() -> int:
	return maxi(0, _pool.size() - _dormant.size())


## Parked enemies available to (re)spawn — i.e. this spawner's empty spawn points.
func free_room() -> int:
	return _dormant.size()


## Spawn a single parked enemy at a random spawn point. Returns false if none were
## available. MapManager calls this to fill the map's population budget.
func spawn_one() -> bool:
	if not is_multiplayer_authority() or _dormant.is_empty():
		return false
	var enemy: Node = _dormant.pop_back()
	if not is_instance_valid(enemy):
		return false
	# Slight stagger so a refilled wave doesn't pop in a single frame.
	var timer: SceneTreeTimer = get_tree().create_timer(randf_range(0.05, 0.45))
	timer.timeout.connect(_spawn_enemy.bind(enemy))
	return true


## Keep this spawner's WHOLE pool alive (used when exclude_from_map_cap is set).
func fill_to_pool() -> void:
	if not is_multiplayer_authority():
		return
	while not _dormant.is_empty():
		if not spawn_one():
			break


## Pure capacity curve (MapleStory model), extracted for testing. Returns how many
## of `pool` monsters may be alive with `occupants` agents on the map: 0 when empty
## (hibernation), else floor(pool * pct) with pct ramping 75%->100% across a party.
## MapManager applies this to the MAP's TOTAL pool, not per spawner.
static func capacity_for(pool: int, occupants: int) -> int:
	if occupants <= 0:
		return 0 # hibernation: an empty map spawns nothing (and never despawns)
	var pct: float = clampf(
		_SOLO_CAPACITY_PCT + _PER_OCCUPANT_STEP * (occupants - 1),
		_SOLO_CAPACITY_PCT, 1.0)
	# floor matches MapleStory's published values (30 * 0.75 -> 22); min 1 so a
	# tiny pool (e.g. a lone boss) is never scaled out of existence.
	return maxi(1, int(floor(pool * pct)))


## Snapshot for the `spawns` dev overlay. Per-spawner alive/pool + spawn-point
## world positions; the MAP-level cap/occupancy lives on MapManager
## (get_map_population_summary). `alive` is server-authoritative (0 on a client);
## `spawn_locations` and `pool` are readable on any peer (authored scene data).
func get_population_report() -> Dictionary:
	var locs: Array[Vector2] = []
	for m in spawn_locations:
		if is_instance_valid(m):
			locs.append(m.global_position)
	return {
		"name": name,
		"pool": get_pool_capacity(),
		"alive": get_alive_count(),
		"spawn_locations": locs,
		"excluded": exclude_from_map_cap,
	}


## The runtime map id, by walking up to the "Map_<id>" wrapper MapManager builds.
func _get_map_id() -> String:
	var map_node := get_parent()
	while map_node and not map_node.name.begins_with("Map_"):
		map_node = map_node.get_parent()
	if not map_node:
		return ""
	return map_node.name.replace("Map_", "")


func _spawn_enemy(enemy: EnemyBase) -> void:
	# Reset the enemy's state using its own method, then place it in the world.
	if not is_instance_valid(enemy):
		return

	if spawn_locations.is_empty():
		printerr("Spawner has no spawn locations assigned.")
		# Return the reserved slot so the cap self-heals once locations exist.
		if enemy not in _dormant:
			_dormant.append(enemy)
		return

	# --- Reset state ---
	if enemy.has_method("pool_reset"):
		enemy.pool_reset()
	else:
		printerr("Enemy scene is missing a 'pool_reset()' method for pooling.")

	# --- Position the enemy ---
	var spawn_point = spawn_locations.pick_random()
	if enemy is Node2D and is_instance_valid(spawn_point):
		enemy.global_position = spawn_point.global_position
	
	# --- Update visibility for this enemy ---
	# When the enemy is activated, its synchronizer is re-enabled
	# We need to ensure visibility is up-to-date for all players on this map
	if multiplayer.is_server():
		await get_tree().process_frame
		_update_all_player_visibility()

func _validate_exports() -> bool:
	var is_valid = true
	if not enemy_scene:
		printerr("Enemy Spawner: 'Enemy Scene' is not set.")
		is_valid = false
	if spawn_locations.is_empty():
		printerr("Enemy Spawner: 'Spawn Locations' array is empty.")
		is_valid = false
	if not spawn_container:
		printerr("Enemy Spawner: 'Spawn Container' is not set.")
		is_valid = false
	return is_valid


func _create_enemy_instance() -> Node:
	"""Spawn function callback for MultiplayerSpawner"""
	if not enemy_scene:
		push_error("EnemySpawner: Cannot create enemy, enemy_scene not set!")
		return null
	
	var enemy = enemy_scene.instantiate()
	if not enemy:
		push_error("EnemySpawner: Failed to instantiate enemy scene!")
		return null
	
	return enemy


func _set_enemy_synchronizers_visibility(enemy: Node, visible: bool):
	"""Recursively sets public_visibility on all MultiplayerSynchronizers in an enemy."""
	if enemy is MultiplayerSynchronizer:
		enemy.public_visibility = visible
	
	for child in enemy.get_children():
		_set_enemy_synchronizers_visibility(child, visible)


func _update_all_player_visibility():
	"""Tell MapManager to update visibility for all players on this map."""
	if not multiplayer.is_server():
		return

	var map_id := _get_map_id()
	if map_id == "":
		return
	var players_on_map = MapManager.get_real_players_on_map(map_id)

	for player_id in players_on_map:
		MapManager.update_visibility_for_player(player_id)
	
	#print("EnemySpawner: Updated visibility for %d players on map %s" % [players_on_map.size(), map_id])
