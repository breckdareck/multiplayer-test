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

@export_group("Population Scaling (MapleStory model)")
## Scale the live monster cap with map occupancy: solo = 75% of pool_size, rising
## +5%/occupant to 100% at a full party (6). Turn off to keep the whole pool alive
## regardless of headcount (the pre-overhaul behaviour).
@export var enable_population_scaling: bool = true
## Count bots as occupants for capacity scaling. Bots are ambient population in
## this game (Erenshor pattern), so a bot-populated map is denser by default. Set
## false to scale on real players only.
@export var count_bots_as_players: bool = true

## MapleStory capacity curve: pct = clamp(SOLO + STEP*(occupants-1), SOLO, 1.0).
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

	# Drive respawns off the single global spawn clock (MapleStory model) instead
	# of per-enemy timers. The group lets MapManager fire an immediate replenish
	# on this spawner when an agent enters its map.
	add_to_group("EnemySpawners")
	if not MapManager.spawn_tick.is_connected(_on_spawn_tick):
		MapManager.spawn_tick.connect(_on_spawn_tick)

	# Initial fill to the current player-scaled cap (0 if the map is empty — it
	# fills the instant an agent arrives, via _replenish_map_spawners).
	replenish_now()

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


# --- Tick-driven replenish + capacity (MapleStory model) ---
# See docs/maplestory_spawn_mechanics.md. Respawns ride MapManager's single
# global spawn_tick; the map's live cap scales with occupancy; over-cap waves left
# by a departing party are kept (never despawned) and corrected only as they die.

## Server-only. Replenish missing monsters up to the current player-scaled cap.
## Called on every global spawn_tick AND immediately when an agent enters the map.
func replenish_now() -> void:
	if not _is_initialized or not is_multiplayer_authority():
		return
	_replenish()


func _on_spawn_tick() -> void:
	replenish_now()


func _replenish() -> void:
	if _pool.is_empty():
		return
	var cap := _current_capacity()
	var alive := _pool.size() - _dormant.size()
	var to_spawn := cap - alive
	# to_spawn <= 0 -> at/over cap: spawn nothing and (critically) despawn nothing,
	# so an over-populated map left by a party stays fully killable ("spawn debt").
	if to_spawn <= 0:
		return
	var n: int = mini(to_spawn, _dormant.size())
	for i in n:
		var enemy: Node = _dormant.pop_back()
		if not is_instance_valid(enemy):
			continue
		# Slight per-enemy stagger so a refilled wave doesn't pop in one frame.
		var timer: SceneTreeTimer = get_tree().create_timer(randf_range(0.05, 0.45))
		timer.timeout.connect(_spawn_enemy.bind(enemy))


## The number of monsters allowed alive right now, given map occupancy.
func _current_capacity() -> int:
	if not enable_population_scaling:
		return _pool.size()
	return capacity_for(_pool.size(), _occupant_count())


## Pure capacity curve (MapleStory model), extracted for testing. Returns how many
## of `pool` monsters may be alive with `occupants` agents on the map: 0 when empty
## (hibernation), else floor(pool * pct) with pct ramping 75%->100% across a party.
static func capacity_for(pool: int, occupants: int) -> int:
	if occupants <= 0:
		return 0 # hibernation: an empty map spawns nothing (and never despawns)
	var pct: float = clampf(
		_SOLO_CAPACITY_PCT + _PER_OCCUPANT_STEP * (occupants - 1),
		_SOLO_CAPACITY_PCT, 1.0)
	# floor matches MapleStory's published values (30 * 0.75 -> 22); min 1 so a
	# tiny pool (e.g. a lone boss) is never scaled out of existence.
	return maxi(1, int(floor(pool * pct)))


func _occupant_count() -> int:
	var map_id := _get_map_id()
	if map_id == "":
		return 0
	if count_bots_as_players:
		return MapManager.get_players_on_map(map_id).size()
	return MapManager.get_real_players_on_map(map_id).size()


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
