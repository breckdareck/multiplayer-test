@tool
class_name AbilityComponent
extends Node

# Signals
signal ability_used(ability_id: String)
signal cooldown_started(ability_id: String, duration: float)
signal ability_leveled_up(ability_id: String, new_level: int)
signal ability_learned(ability_id: String)
signal ability_points_changed(new_total: int)

@export_category("Debug")
@export var hitbox: CollisionShape2D
@export var debug_ability: AbilityData:
	get:
		return debug_ability
	set(x):
		debug_ability = x
		if not is_instance_valid(hitbox):
			print("Hitbox is not valid. Cannot set shape.")
			return
		if x and x.active_behavior and is_instance_valid(x.active_behavior.hit_box_shape_data):
			print("Setting hitbox to %s's data" % x.ability_name)
			hitbox.shape = x.active_behavior.hit_box_shape_data.duplicate()
			hitbox.position = x.active_behavior.hit_box_position_data
		else:
			print("Setting hitbox to default")
			hitbox.shape = RectangleShape2D.new()
			(hitbox.shape as RectangleShape2D).size = Vector2(21,21)
			hitbox.position = Vector2(9.5,-10.5)

var _class_component: ClassComponent
var _stats_component: StatsComponent
var _level_component: LevelingComponent


var _cooldowns: Dictionary = {}
## {"ability_id": current_level}
var _ability_levels: Dictionary = {}
var _available_ability_points: int = 0

@onready var hotbar: Hotbar = $"../../CanvasLayer/PlayerHUD/Hotbar"


func _ready() -> void:
	_class_component = get_parent().get_node_or_null("Class")
	_stats_component = get_parent().get_node_or_null("Stats")
	_level_component = get_parent().get_node_or_null("Leveling")
	
	if not _class_component or not _stats_component:
		push_error("AbilityComponent requires ClassComponent and StatsComponent siblings.")
		set_process(false)
		return
	
	# Connect to leveling component if it exists
	if _level_component:
		_level_component.leveled_up.connect(_on_leveled_up)
		print("AbilityComponent: Connected to LevelingComponent")
	else:
		push_warning("AbilityComponent: No LevelingComponent found - ability points won't be granted on level up")
		
	set_process(true)
	
	# Only initialize abilities on the server or in single player
	# Clients will receive the data via RPC sync
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		# Initialize class abilities at level 0 (unlearned but visible)
		for ability_data in _class_component.get_class_abilities():
			if ability_data != null and not _ability_levels.has(ability_data.ability_id):
				# Don't send RPCs during initialization
				_learn_ability_local(ability_data.ability_id, 0, false)
	
	print("Loaded abilities: ", _ability_levels)


## Called by the server to sync all ability data to a newly connected client
func sync_all_abilities_to_client(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	print("DEBUG: Syncing abilities to peer %d - Current points: %d, Levels: %s" % [peer_id, _available_ability_points, _ability_levels])
	
	# Sync ability points
	sync_ability_points.rpc_id(peer_id, _available_ability_points)
	
	# Sync all learned abilities
	for ability_id in _ability_levels:
		var level = _ability_levels[ability_id]
		sync_ability_learned.rpc_id(peer_id, ability_id, level)
	
	print("Synced all abilities to peer %d" % peer_id)


func _process(delta: float) -> void:
	# Tick down cooldowns
	var to_remove = []
	for ability_id in _cooldowns:
		_cooldowns[ability_id] -= delta
		if _cooldowns[ability_id] <= 0.0:
			to_remove.append(ability_id)

	for ability_id in to_remove:
		_cooldowns.erase(ability_id)


## Level up a ability using ability points
func level_up_ability(ability_id: String) -> bool:
	# If multiplayer and we're a client, send request to server
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		level_up_ability_request.rpc_id(1, ability_id)
		return true
	
	# Server or singleplayer: execute locally
	return _level_up_ability_local(ability_id)


func _level_up_ability_local(ability_id: String) -> bool:
	"""Server-side ability level up logic"""
	if _available_ability_points <= 0:
		print("No ability points available")
		return false
	
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability:
		print("Ability not found: %s" % ability_id)
		return false
	
	# Check if ability is learned
	if not _ability_levels.has(ability_id):
		print("ability not learned yet: %s" % ability.ability_name)
		return false
	
	var current_level = _ability_levels[ability_id]
	
	# Check max level
	if current_level >= ability.max_level:
		print("ability already at max level: %s" % ability.ability_name)
		return false
	
	# Check prerequisites
	if ability.prerequisite_abilities:
		for prereq_ability in ability.prerequisite_abilities:
			var prereq_level = _ability_levels.get(prereq_ability.ability_id, 0)
			if prereq_level < ability.prerequisite_abilities[prereq_ability]:
				print("Prerequisite not met for %s" % ability.ability_name)
				return false
	
	# Level up!
	_available_ability_points -= 1
	_ability_levels[ability_id] = current_level + 1
	
	# Update passive effects if applicable
	if ability.ability_type == Constants.AbilityType.PASSIVE:
		_apply_passive_effect() # Re-apply all passives
	
	ability_leveled_up.emit(ability_id, current_level + 1)
	print("Leveled up %s to level %d" % [ability.ability_name, current_level + 1])
	
	# Sync to all clients if on server
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		# Sync both the level and the new ability points total
		sync_ability_level.rpc(ability_id, current_level + 1)
		sync_ability_points.rpc(_available_ability_points)
	
	return true


@rpc("any_peer", "call_local", "reliable")
func level_up_ability_request(ability_id: String) -> void:
	"""Client requests to level up an ability"""
	if not multiplayer.is_server():
		return
	
	_level_up_ability_local(ability_id)


@rpc("authority", "call_local", "reliable")
func sync_ability_level(ability_id: String, new_level: int) -> void:
	"""Server syncs ability level to all clients"""
	_ability_levels[ability_id] = new_level
	ability_leveled_up.emit(ability_id, new_level)
	print("Synced ability level: %s to %d" % [ability_id, new_level])


## Learn a new ability (set it to level 1)
func learn_ability(ability_id: String, initial_level: int = 1) -> bool:
	# If multiplayer and we're a client, send request to server
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		learn_ability_request.rpc_id(1, ability_id, initial_level)
		return true
	
	# Server or singleplayer: execute locally
	return _learn_ability_local(ability_id, initial_level)


func _learn_ability_local(ability_id: String, initial_level: int = 1, send_rpc: bool = true) -> bool:
	"""Server-side ability learning logic"""
	if _ability_levels.has(ability_id):
		print("ability already learned: %s" % ability_id)
		return false
	
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability:
		print("Ability not found: %s" % ability_id)
		return false
	
	_ability_levels[ability_id] = initial_level
	if ability.ability_type == Constants.AbilityType.PASSIVE:
		_apply_passive_effect() # Re-apply all passives
		
	ability_learned.emit(ability_id)
	
	print("Learned ability: %s at level %d" % [ability.ability_name, initial_level])
	
	# Sync to all clients if on server and send_rpc is true
	if send_rpc and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_ability_learned.rpc(ability_id, initial_level)
	
	return true


@rpc("any_peer", "call_local", "reliable")
func learn_ability_request(ability_id: String, initial_level: int) -> void:
	"""Client requests to learn an ability"""
	if not multiplayer.is_server():
		return
	
	_learn_ability_local(ability_id, initial_level)


@rpc("authority", "call_local", "reliable")
func sync_ability_learned(ability_id: String, initial_level: int) -> void:
	"""Server syncs newly learned ability to all clients"""
	_ability_levels[ability_id] = initial_level
	ability_learned.emit(ability_id)
	print("Synced learned ability: %s at level %d" % [ability_id, initial_level])


## Add ability points (called when character levels up)
func add_ability_points(amount: int) -> void:
	_available_ability_points += amount
	print("Added %d ability points. Total: %d" % [amount, _available_ability_points])
	ability_points_changed.emit(_available_ability_points)
	
	# Sync to all clients if on server
	# This ensures clients always have the correct point total
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_ability_points.rpc(_available_ability_points)


@rpc("authority", "reliable")
func sync_ability_points(new_total: int) -> void:
	"""Server syncs ability points to clients (not call_local - don't overwrite server!)"""
	print("DEBUG: sync_ability_points called - Old: %d, New: %d, IsServer: %s" % [_available_ability_points, new_total, multiplayer.is_server()])
	_available_ability_points = new_total
	ability_points_changed.emit(_available_ability_points)
	print("Synced ability points: %d" % new_total)


## Get current level of a ability
func get_ability_level(ability_id: String) -> int:
	return _ability_levels.get(ability_id, 0)


## Get available ability points
func get_available_ability_points() -> int:
	return _available_ability_points


## Check if a ability can be leveled up
func can_level_up_ability(ability_id: String) -> bool:
	if _available_ability_points <= 0:
		return false
	
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability:
		return false
	
	var current_level = get_ability_level(ability_id)
	if current_level < 0 or current_level >= ability.max_level:
		return false
	
	# Check prerequisites
	if ability.prerequisite_abilities:
		for prereq_ability in ability.prerequisite_abilities:
			var prereq_level = _ability_levels.get(prereq_ability.ability_id, 0)
			if prereq_level < ability.prerequisite_abilities[prereq_ability]:
				return false
	
	return true


func use_ability(ability_id: String) -> bool:
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability:
		print("AbilityComponent: Ability ID '%s' not found." % ability_id)
		return false

	# Get current ability level
	var ability_level = get_ability_level(ability_id)
	if ability_level <= 0:
		print("AbilityComponent: ability '%s' not learned." % ability.ability_name)
		return false

	# Get level-specific stats
	var level_stats = ability.get_level_stats(ability_level)
	if not level_stats:
		print("AbilityComponent: Invalid level data for '%s' at level %d" % [ability.ability_name, ability_level])
		return false
	
	# Check if it's an active ability
	if ability.ability_type != Constants.AbilityType.ACTIVE:
		print("AbilityComponent: Ability '%s' is not an active ability." % ability.ability_name)
		return false
	
	# CLIENT-SIDE CHECKS (prevent unnecessary RPC calls)
	if _cooldowns.has(ability_id):
		print("AbilityComponent: Ability '%s' is on cooldown." % ability.ability_name)
		return false
		
	# Check if this is multiplayer and if we're the client
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		# Client: Send RPC request to server
		use_ability_request(ability_id)
		return true
	else:
		# Server or Singleplayer: Execute directly
		return _execute_ability_locally(ability_id, ability, level_stats)


func _execute_ability_locally(ability_id: String, ability: AbilityData, level_stats: AbilityLevelData) -> bool:
	"""Execute ability locally (server-side only)"""
	# Server-side authoritative checks
	if _cooldowns.has(ability_id):
		print("Server: Cooldown check failed for %s." % ability.ability_name)
		return false
	
	var mana_cost = level_stats.mana_cost
	if "current_mana" in _stats_component:
		if _stats_component.current_mana < mana_cost:
			print("Server: Not enough mana to use '%s' (need %d)." % [ability.ability_name, mana_cost])
			return false
		else:
			_stats_component.current_mana -= mana_cost
	
	# Success! Deduct generic cost and start cooldown
	_cooldowns[ability_id] = level_stats.cooldown_time
	cooldown_started.emit(ability_id, level_stats.cooldown_time)

	# Execute the ability (transition to attack state)
	_execute_active_ability(ability, level_stats)
	ability_used.emit(ability_id)
	
	return true


func _execute_active_ability(ability: AbilityData, level_stats: AbilityLevelData) -> void:
	print("AbilityComponent: Executing %s (Level %d, %d%% damage)" % [ability.ability_name, level_stats.level, level_stats.damage_percent])
	
	var active_behavior = ability.active_behavior
	
	if not active_behavior:
		push_error("Ability %s is missing active behavior data." % ability.ability_name)
		return
	
	# Get the player's state machine and attack state
	var player = owner as Node
	var state_machine = player.get_node_or_null("StateMachine")
	
	if not state_machine:
		push_error("Could not find StateMachine on player")
		return
	
	var attack_state = state_machine.get_node_or_null("attack")
	
	if not attack_state:
		push_error("Could not find Attack state in StateMachine")
		return
	
	# Set the ability data on the attack state
	if attack_state.has_method("set_ability_data"):
		attack_state.set_ability_data(ability, level_stats)
	else:
		push_error("Attack state missing set_ability_data method")
		return
	
	# Transition to attack state
	# The state will be synced by MultiplayerSynchronizer
	if "current_state" in state_machine:
		state_machine.current_state = attack_state
		attack_state.enter()
	else:
		push_error("Could not change state - state_machine missing current_state property")
	
	# Optional: Execute custom logic script if provided
	if active_behavior.logic_script:
		var custom_logic = active_behavior.logic_script.new()
		
		if custom_logic and custom_logic.has_method("execute"):
			custom_logic.execute(owner, ability, level_stats)
		else:
			push_warning("Custom logic script for %s is missing 'execute' method." % ability.ability_name)


## Simplified passive effect getter
func get_passive_effect_modifiers() -> Dictionary:
	var modifiers = {}
	
	for ability_id in _ability_levels:
		var ability = ResourceManager.get_ability_data(ability_id)
		var ability_level = _ability_levels[ability_id]
		var level_stats = ability.get_level_stats(ability_level)
		
		# Only process learned abilities with valid level stats that are Passive
		if ability and ability.ability_type == Constants.AbilityType.PASSIVE and level_stats:
			
			# Use stat bonuses from the level data
			for stat_name in level_stats.stat_bonuses:
				if not modifiers.has(stat_name):
					modifiers[stat_name] = 0
				modifiers[stat_name] += level_stats.stat_bonuses[stat_name]
	
	return modifiers


## Now called generically to force stat recalculation
func _apply_passive_effect() -> void:
	print("AbilityComponent: Forcing global stat recalculation for passive effects.")
	
	if _stats_component:
		if multiplayer.is_server() and _stats_component.has_method("_recalculate_stats_server"):
			_stats_component._recalculate_stats_server("AbilityPassiveChange")


func use_ability_request(ability_id: String) -> void:
	"""Client-side function to request ability use from server"""
	if _cooldowns.has(ability_id):
		print("Client: Ability is on cooldown (UX check).")
		return
	
	print("Client: Sending RPC request to use ability %s" % ability_id)
	use_ability_server.rpc_id(1, ability_id)  # Always send to server (peer ID 1)
	
	
func get_cooldown_remaining(ability_id: String) -> float:
	return _cooldowns.get(ability_id, 0.0)


@rpc("any_peer", "call_local", "reliable")
func use_ability_server(ability_id: String) -> void:
	# Only process on server
	if not multiplayer.is_server():
		return

	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability:
		print("Server: Invalid ability: %s" % ability_id)
		return

	# Check ability level
	var ability_level = get_ability_level(ability_id)
	if ability_level <= 0:
		print("Server: ability not learned: %s" % ability_id)
		return

	# Get level stats
	var level_stats = ability.get_level_stats(ability_level)
	if not level_stats:
		print("Server: Invalid level stats for %s" % ability_id)
		return
	
	# Execute ability locally on server
	if _execute_ability_locally(ability_id, ability, level_stats):
		# Notify all clients about the ability use
		ability_used_client.rpc(ability_id, level_stats.cooldown_time)


@rpc("authority", "call_local", "reliable")
func ability_used_client(ability_id: String, cooldown_time: float) -> void:
	# This runs on all clients (and server due to call_local)
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability:
		return
		
	var ability_level = get_ability_level(ability_id)
	var level_stats = ability.get_level_stats(ability_level)
	if not level_stats:
		return
	
	# Sync cooldown
	_cooldowns[ability_id] = cooldown_time
	
	# Emit signals
	ability_used.emit(ability_id)
	cooldown_started.emit(ability_id, cooldown_time)
	
	# On clients, we need to execute the visual part (state change + animation)
	if not multiplayer.is_server():
		_execute_active_ability(ability, level_stats)
	
	print("Client: Synchronized ability use for %s." % ability_id)


## This gets called when character levels up
func _on_leveled_up(new_level: int) -> void:
	add_ability_points(3) # MapleStory gives 3 ability points per level
	print("AbilityComponent: Level up! Now level %d. Added 3 ability points." % new_level)


## Save ability data to dictionary
func save_abilities() -> Dictionary:
	var save_data = {
		"ability_levels": _ability_levels.duplicate(),
		"available_points": _available_ability_points,
		"hotbar_config": hotbar.save_hotbar_config()
	}
	return save_data


## Load ability data from dictionary
func load_abilities(data: Dictionary) -> void:
	if data.is_empty():
		print("AbilityComponent: No ability data to load")
		return
	
	# Clear existing data
	_ability_levels.clear()
	
	# Load ability levels
	var loaded_levels = data.get("ability_levels", {})
	for ability_id in loaded_levels:
		var level = loaded_levels[ability_id]
		_ability_levels[ability_id] = level
		print("Loaded ability: %s at level %d" % [ability_id, level])
	
	# Load ability points
	_available_ability_points = data.get("available_points", 0)
	print("Loaded ability points: %d" % _available_ability_points)
	
	# Load hotbar configuration
	var loaded_hotbar = data.get("hotbar_config", {})
	hotbar.load_hotbar_config(loaded_hotbar)
	
	# Re-apply passive effects after loading
	_apply_passive_effect()
	
	# Emit signals to update UI
	ability_points_changed.emit(_available_ability_points)
	for ability_id in _ability_levels:
		var level = _ability_levels[ability_id]
		if level > 0:
			ability_learned.emit(ability_id)
			ability_leveled_up.emit(ability_id, level)


## Disconnect from leveling component signals (for loading)
func disconnect_level_signals() -> void:
	if _level_component and _level_component.leveled_up.is_connected(_on_leveled_up):
		_level_component.leveled_up.disconnect(_on_leveled_up)
		print("AbilityComponent: Disconnected from leveling signals")


## Reconnect to leveling component signals (after loading)
func reconnect_level_signals() -> void:
	if _level_component and not _level_component.leveled_up.is_connected(_on_leveled_up):
		_level_component.leveled_up.connect(_on_leveled_up)
		print("AbilityComponent: Reconnected to leveling signals")
