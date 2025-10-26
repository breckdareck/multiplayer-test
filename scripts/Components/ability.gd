@tool
class_name AbilityComponent
extends Node

## Manages a character's abilities, including learning, leveling, usage, cooldowns,
## passive effects, and multiplayer synchronization.
## Requires ClassComponent and StatsComponent as siblings to function correctly.


#region #################### Signals ####################
signal ability_used(ability_id: String)
signal cooldown_started(ability_id: String, duration: float)
signal ability_leveled_up(ability_id: String, new_level: int)
signal ability_learned(ability_id: String)
signal ability_points_changed(new_total: int)
#endregion


#region #################### Exports & Properties ####################
@export_category("Debug")
@export var hitbox: CollisionShape2D
@export var debug_ability: AbilityData:
	get:
		return debug_ability
	set(new_ability_data):
		debug_ability = new_ability_data
		if not is_instance_valid(hitbox):
			printerr("Hitbox is not valid. Cannot set shape.")
			return
		
		# Update the debug hitbox shape and position based on the assigned AbilityData
		if new_ability_data and new_ability_data.active_behavior and is_instance_valid(new_ability_data.active_behavior.hit_box_shape_data):
			print("Setting debug hitbox from: %s" % new_ability_data.ability_name)
			hitbox.shape = new_ability_data.active_behavior.hit_box_shape_data.duplicate()
			hitbox.position = new_ability_data.active_behavior.hit_box_position_data
		else:
			# Fallback to a default shape if the ability data is invalid
			print("Setting debug hitbox to default shape.")
			var default_shape := RectangleShape2D.new()
			default_shape.size = Vector2(21, 21)
			hitbox.shape = default_shape
			hitbox.position = Vector2(9.5, -10.5)
#endregion


#region #################### Member Variables ####################
# Component references
var _class_component: ClassComponent
var _stats_component: StatsComponent
var _level_component: LevelingComponent

# State variables
var _cooldowns: Dictionary = {}  # { ability_id: time_remaining }
var _ability_levels: Dictionary = {} # { ability_id: current_level }
var _available_ability_points: int = 0

# NEW: Track proc cooldowns per passive ability
var _passive_proc_cooldowns: Dictionary = {}  # { "ability_id_event_type": last_proc_time }

# NEW: Track active passive abilities for easy access
var _active_passive_abilities: Array[AbilityData] = []

# UI references
@onready var hotbar: Hotbar = $"../../CanvasLayer/PlayerHUD/Hotbar"
#endregion


#region #################### Godot Engine Callbacks ####################
func _ready() -> void:
	# Fetch required sibling components
	_class_component = get_parent().get_node_or_null("Class")
	_stats_component = get_parent().get_node_or_null("Stats")
	_level_component = get_parent().get_node_or_null("Leveling")
	
	if not _class_component or not _stats_component:
		push_error("AbilityComponent requires ClassComponent and StatsComponent siblings.")
		set_process(false)
		return

	# Connect to the LevelingComponent to grant ability points on level up
	if _level_component:
		if multiplayer.is_server():
			_level_component.leveled_up.connect(_on_leveled_up)
	else:
		push_warning("AbilityComponent: No LevelingComponent found. Points won't be granted on level up.")
		
	# Initialize class abilities on the server or in single-player.
	# Clients will receive this data via an RPC sync when they connect.
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		for ability_data in _class_component.get_class_abilities():
			if ability_data and not _ability_levels.has(ability_data.ability_id):
				# Level 0 signifies the ability is known but not yet leveled up.
				_learn_ability_local(ability_data.ability_id, 0, false)

	print("AbilityComponent ready. Loaded abilities: ", _ability_levels)


func _process(delta: float) -> void:
	# Tick down active cooldowns
	var finished_cooldowns = []
	for ability_id in _cooldowns:
		_cooldowns[ability_id] -= delta
		if _cooldowns[ability_id] <= 0.0:
			finished_cooldowns.append(ability_id)

	for ability_id in finished_cooldowns:
		_cooldowns.erase(ability_id)
#endregion


#region #################### Public API ####################
## Attempts to use an ability.
func use_ability(ability_id: String) -> bool:
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability:
		printerr("Ability ID '%s' not found." % ability_id)
		return false

	var ability_level := get_ability_level(ability_id)
	if ability_level <= 0:
		print("Ability '%s' has not been learned." % ability.ability_name)
		return false

	if ability.ability_type != Constants.AbilityType.ACTIVE:
		print("Ability '%s' is not an active ability." % ability.ability_name)
		return false
	
	# Client-side check to prevent sending pointless requests
	if _cooldowns.has(ability_id):
		print("Ability '%s' is on cooldown." % ability.ability_name)
		return false
		
	# In multiplayer, clients request the server to use the ability.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_ability_use(ability_id)
		return true
	
	# In single-player or on the server, execute directly.
	var level_stats = ability.get_level_stats(ability_level)
	if not level_stats:
		printerr("Invalid level data for '%s' at level %d" % [ability.ability_name, ability_level])
		return false
	
	return _handle_authoritative_use(ability_id, ability, level_stats)


## Attempts to level up an ability.
func level_up_ability(ability_id: String) -> bool:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		level_up_ability_request.rpc_id(1, ability_id)
		return true
	
	return _level_up_ability_local(ability_id)


## Learns a new ability.
func learn_ability(ability_id: String, initial_level: int = 0) -> bool:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		learn_ability_request.rpc_id(1, ability_id, initial_level)
		return true

	return _learn_ability_local(ability_id, initial_level)


func get_passive_effect_modifiers() -> Dictionary:
	var modifiers = {}
	
	for ability_id in _ability_levels:
		var ability = ResourceManager.get_ability_data(ability_id)
		var ability_level = _ability_levels[ability_id]
		
		# Skip unlearned abilities
		if ability_level <= 0:
			continue
			
		var level_stats = ability.get_level_stats(ability_level)
		
		# Only process learned abilities with valid level stats that are Passive
		if ability and ability.ability_type == Constants.AbilityType.PASSIVE and level_stats:
			
			# Use stat bonuses from the level data
			for stat_name in level_stats.stat_bonuses:
				if not modifiers.has(stat_name):
					modifiers[stat_name] = StatData.new(stat_name, 0)
				# Accumulate bonuses from multiple passives
				modifiers[stat_name].flat_bonus_value += level_stats.stat_bonuses[stat_name].flat_bonus_value
				modifiers[stat_name].percent_bonus_value += level_stats.stat_bonuses[stat_name].percent_bonus_value
	
	return modifiers


func get_ability_damage_modifier(ability_id: String) -> float:
	var total_modifier: float = 1.0
	
	for passive_ability_id in _ability_levels:
		var passive_ability = ResourceManager.get_ability_data(passive_ability_id)
		var passive_level = _ability_levels[passive_ability_id]
		
		# Skip unlearned passives
		if passive_level <= 0:
			continue
			
		if passive_ability and passive_ability.ability_type == Constants.AbilityType.PASSIVE:
			var level_stats = passive_ability.get_level_stats(passive_level)
			if level_stats:
				total_modifier *= level_stats.get_ability_damage_modifier(ability_id)
	
	return total_modifier


func get_ability_cooldown_modifier(ability_id: String) -> float:
	var total_modifier: float = 1.0
	
	for passive_ability_id in _ability_levels:
		var passive_ability = ResourceManager.get_ability_data(passive_ability_id)
		var passive_level = _ability_levels[passive_ability_id]
		
		if passive_level <= 0:
			continue
			
		if passive_ability and passive_ability.ability_type == Constants.AbilityType.PASSIVE:
			var level_stats = passive_ability.get_level_stats(passive_level)
			if level_stats:
				total_modifier *= level_stats.get_ability_cooldown_modifier(ability_id)
	
	return total_modifier


func get_ability_mana_modifier(ability_id: String) -> float:
	var total_modifier: float = 1.0
	
	for passive_ability_id in _ability_levels:
		var passive_ability = ResourceManager.get_ability_data(passive_ability_id)
		var passive_level = _ability_levels[passive_ability_id]
		
		if passive_level <= 0:
			continue
			
		if passive_ability and passive_ability.ability_type == Constants.AbilityType.PASSIVE:
			var level_stats = passive_ability.get_level_stats(passive_level)
			if level_stats:
				total_modifier *= level_stats.get_ability_mana_modifier(ability_id)
	
	return total_modifier

#endregion


#region #################### Internal Logic & Execution ####################
## The authoritative logic for using an ability (runs on server or in single-player).
func _handle_authoritative_use(ability_id: String, ability: AbilityData, level_stats: AbilityLevelData) -> bool:
	# Final server-side validation
	if _cooldowns.has(ability_id):
		return false
	
	# Apply passive mana cost modifier
	var modified_mana_cost = level_stats.mana_cost * get_ability_mana_modifier(ability_id)
	
	if "current_mana" in _stats_component and _stats_component.current_mana < modified_mana_cost:
		print("Server: Not enough mana for '%s'." % ability.ability_name)
		return false
		
	# Check if an attack is already in progress before consuming resources.
	var state_machine = owner.get_node_or_null("StateMachine")
	if state_machine:
		var attack_state = state_machine.get_node_or_null("attack")
		if "current_state" in state_machine and state_machine.current_state == attack_state:
			print("Server: Cannot use ability, an attack is already in progress.")
			return false
	
	# All checks passed, consume resources and start cooldown
	if "current_mana" in _stats_component:
		_stats_component.current_mana -= modified_mana_cost
	
	# Apply passive cooldown modifier
	var modified_cooldown = level_stats.cooldown_time * get_ability_cooldown_modifier(ability_id)
	_cooldowns[ability_id] = modified_cooldown
	
	# Trigger the visual/gameplay effect
	_trigger_ability_state_change(ability, level_stats)
	
	# NEW: Trigger on_ability_cast procs
	try_trigger_procs("on_ability_cast", null, {"ability": ability, "level_stats": level_stats})
	
	# Emit signals and notify clients
	ability_used.emit(ability_id)
	cooldown_started.emit(ability_id, modified_cooldown)
	
	if multiplayer.is_server():
		ability_used_client.rpc(ability_id, modified_cooldown)
		
	return true


## Triggers the state machine transition and custom logic for an active ability.
func _trigger_ability_state_change(ability: AbilityData, level_stats: AbilityLevelData) -> void:
	print("Executing %s (Level %d)" % [ability.ability_name, level_stats.level])
	
	var active_behavior = ability.active_behavior
	if not active_behavior:
		push_error("Ability '%s' is missing ActiveBehavior data." % ability.ability_name)
		return
		
	var state_machine = owner.get_node_or_null("StateMachine")
	if not state_machine:
		push_error("Could not find StateMachine on owner.")
		return
		
	var attack_state = state_machine.get_node_or_null("attack")
	if not attack_state or not attack_state.has_method("set_ability_data"):
		push_error("Attack state is invalid or missing 'set_ability_data' method.")
		return
	
	# Configure the attack state with this ability's data
	attack_state.set_ability_data(ability, level_stats)
	
	# Transition to the attack state
	if "current_state" in state_machine and state_machine.current_state != attack_state:
		state_machine.current_state = attack_state
		attack_state.enter()
		if active_behavior.sfx_path:
			var audio_player = AudioStreamPlayer.new()
			add_child(audio_player)
			audio_player.stream = load(active_behavior.sfx_path)
			audio_player.play()
			await audio_player.finished
			audio_player.queue_free()

	# Execute optional custom logic from the ability's script resource
	if active_behavior.logic_script:
		var custom_logic = active_behavior.logic_script.new()
		if custom_logic.has_method("execute"):
			custom_logic.execute(owner, ability, level_stats)


## The authoritative logic for leveling up an ability.
func _level_up_ability_local(ability_id: String) -> bool:
	if not can_level_up_ability(ability_id):
		print("Validation failed for leveling up ability: %s." % ability_id)
		return false

	var ability = ResourceManager.get_ability_data(ability_id)
	var current_level = _ability_levels[ability_id]
	
	_available_ability_points -= 1
	_ability_levels[ability_id] = current_level + 1
	
	# Re-apply passive effects if a passive ability was leveled up
	if ability.ability_type == Constants.AbilityType.PASSIVE:
		_apply_passive_effects()

	ability_leveled_up.emit(ability_id, current_level + 1)
	print("Leveled up %s to level %d" % [ability.ability_name, current_level + 1])
	
	# Sync changes to clients
	if multiplayer.is_server():
		sync_ability_level.rpc(ability_id, current_level + 1)
		sync_ability_points.rpc(_available_ability_points)
	
	return true


## The authoritative logic for learning an ability.
func _learn_ability_local(ability_id: String, initial_level: int = 0, send_rpc: bool = true) -> bool:
	if _ability_levels.has(ability_id):
		return false
	
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability:
		printerr("AbilityData not found for ID: %s" % ability_id)
		return false
	
	_ability_levels[ability_id] = initial_level
	
	if ability.ability_type == Constants.AbilityType.PASSIVE:
		_apply_passive_effects()
		
	ability_learned.emit(ability_id)
	print("Learned ability: %s at level %d" % [ability.ability_name, initial_level])
	
	if send_rpc and multiplayer.is_server():
		sync_ability_learned.rpc(ability_id, initial_level)
	
	return true


## Forces the StatsComponent to recalculate stats, applying all passive bonuses.
func _apply_passive_effects() -> void:
	if _stats_component and _stats_component.has_method("_recalculate_stats_server"):
		print("Applying passive ability effects and forcing stat recalculation.")
		if multiplayer.is_server():
			_stats_component._recalculate_stats_server("AbilityPassiveChange")


## Adds ability points, typically called after leveling up.
func _add_ability_points(amount: int) -> void:
	_available_ability_points += amount
	print("Added %d ability points. Total: %d" % [amount, _available_ability_points])
	ability_points_changed.emit(_available_ability_points)
	
	if multiplayer.is_server():
		sync_ability_points.rpc(_available_ability_points)
		

func try_trigger_procs(event_type: String, target: Node = null, context: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return
	
	for passive_ability_id in _ability_levels:
		var passive_ability = ResourceManager.get_ability_data(passive_ability_id)
		var passive_level = _ability_levels[passive_ability_id]
		
		if passive_level <= 0:
			continue
			
		if passive_ability and passive_ability.ability_type == Constants.AbilityType.PASSIVE:
			var level_stats = passive_ability.get_level_stats(passive_level)
			if level_stats:
				var proc_key = passive_ability_id + "_" + event_type
				var last_proc_time = _passive_proc_cooldowns.get(proc_key, 0.0)
				
				var proc_effect = level_stats.try_proc_event(event_type, {event_type: last_proc_time})
				if proc_effect:
					_execute_proc(proc_effect, target, context)
					_passive_proc_cooldowns[proc_key] = Time.get_ticks_msec() / 1000.0


func _execute_proc(proc: ProcEffectData, target: Node, context: Dictionary) -> void:
	print("Proc triggered! Chance was: %.1f%%" % (proc.proc_chance * 100))
	
	# Deal damage if specified
	if proc.damage_percent > 0 and target and "health_component" in target:
		var base_damage = context.get("base_damage", 0)
		var proc_damage = base_damage * (proc.damage_percent / 100.0)
		target.health_component.take_damage(proc_damage, owner, true)
		print("Proc dealt %d damage" % proc_damage)
	
	# Execute ability if specified
	if proc.execute_ability:
		use_ability(proc.execute_ability.ability_id)
	
	# Apply buff if specified
	if proc.apply_buff:
		var buff_component = target.get_node_or_null("Buff")
		if buff_component:
			buff_component.apply_buff(proc.apply_buff.buff_id, owner)
	
	# Play animation
	if proc.animation_name and owner.has_method("play_animation"):
		owner.play_animation(proc.animation_name)
	
	# Play sound
	if proc.sfx_path:
		pass
	
	# Custom logic
	if proc.logic_script:
		var script_instance = proc.logic_script.new()
		if script_instance.has_method("on_proc"):
			script_instance.on_proc(owner, target, context)

#endregion


#region #################### Multiplayer & RPCs ####################
## [Server->Client] Sends all ability data to a newly connected client.
func sync_all_abilities_to_client(peer_id: int) -> void:
	if not multiplayer.is_server(): return
	
	print("Syncing all ability data to peer %d" % peer_id) 
	sync_ability_points.rpc_id(peer_id, _available_ability_points)
	for ability_id in _ability_levels:
		sync_ability_learned.rpc_id(peer_id, ability_id, _ability_levels[ability_id])


## [Client->Server] Client-side wrapper to request ability use from the server.
func _request_ability_use(ability_id: String) -> void:
	print("Client: Sending request to use ability %s" % ability_id)
	use_ability_server.rpc_id(1, ability_id) # Server is always peer ID 1


@rpc("any_peer", "call_local", "reliable")
## [Client->Server] RPC for a client to request using an ability.
func use_ability_server(ability_id: String) -> void:
	if not multiplayer.is_server(): return

	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability: return

	var ability_level = get_ability_level(ability_id) 
	if ability_level <= 0: return

	var level_stats = ability.get_level_stats(ability_level)
	if not level_stats: return
	
	# Let the authoritative function handle the final execution
	_handle_authoritative_use(ability_id, ability, level_stats)


@rpc("authority", "call_local", "reliable")
## [Server->Client] Notifies all clients that an ability was used successfully.
func ability_used_client(ability_id: String, cooldown_time: float) -> void:
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability: return
	
	# Set cooldown locally for all instances (server and clients)
	_cooldowns[ability_id] = cooldown_time
	
	# Emit signals for UI and other systems
	ability_used.emit(ability_id)
	cooldown_started.emit(ability_id, cooldown_time)
	
	# On clients, we must also trigger the visual part of the ability
	if not multiplayer.is_server():
		var level = get_ability_level(ability_id)
		var level_stats = ability.get_level_stats(level)
		if level_stats:
			_trigger_ability_state_change(ability, level_stats)
	
	print("Synchronized ability use for %s." % ability_id) 


@rpc("any_peer", "call_local", "reliable")
## [Client->Server] RPC for a client to request leveling up an ability.
func level_up_ability_request(ability_id: String) -> void:
	if multiplayer.is_server():
		_level_up_ability_local(ability_id)


@rpc("any_peer", "call_local", "reliable")
## [Client->Server] RPC for a client to request learning an ability.
func learn_ability_request(ability_id: String, initial_level: int) -> void:
	if multiplayer.is_server():
		_learn_ability_local(ability_id, initial_level)


@rpc("authority", "call_local", "reliable")
## [Server->Client] Syncs a single ability's level to all clients.
func sync_ability_level(ability_id: String, new_level: int) -> void:
	_ability_levels[ability_id] = new_level
	ability_leveled_up.emit(ability_id, new_level)
	print("Synced ability level: %s to %d" % [ability_id, new_level]) 


@rpc("authority", "call_local", "reliable")
## [Server->Client] Syncs a newly learned ability to all clients.
func sync_ability_learned(ability_id: String, initial_level: int) -> void:
	_ability_levels[ability_id] = initial_level
	ability_learned.emit(ability_id)


@rpc("authority", "reliable")
## [Server->Client] Syncs the total available ability points to all clients.
func sync_ability_points(new_total: int) -> void:
	# This RPC should only be processed by clients, not the server that sent it.
	if multiplayer.is_server(): return
	
	_available_ability_points = new_total
	ability_points_changed.emit(_available_ability_points)
#endregion


#region #################### Signal Callbacks ####################
## Called when the LevelingComponent emits the `leveled_up` signal.
func _on_leveled_up(new_level: int) -> void:
	# Grant 3 ability points on level up
	print("Leveled up to %d. Gaining 3 ability points." % new_level) 
	_add_ability_points(3)
#endregion


#region #################### Save & Load System ####################
## Returns a dictionary of all ability data for saving.
func save_abilities() -> Dictionary:
	return {
		"ability_levels": _ability_levels.duplicate(),
		"available_points": _available_ability_points,
		"hotbar_config": hotbar.save_hotbar_config()
	}


## Loads and applies ability data from a dictionary.
func load_abilities(data: Dictionary) -> void:
	if data.is_empty(): return
	
	# First, ensure all current class abilities are initialized
	for ability_data in _class_component.get_class_abilities():
		if ability_data != null and not _ability_levels.has(ability_data.ability_id):
			_ability_levels[ability_data.ability_id] = 0
			print("Added new ability from class: %s at level 0" % ability_data.ability_id)
			
	# Load saved data by merging (not replacing) to preserve new abilities
	var saved_levels = data.get("ability_levels", {})
	for ability_id in saved_levels:
		_ability_levels[ability_id] = saved_levels[ability_id]
	
	_available_ability_points = data.get("available_points", 0) 
	hotbar.load_hotbar_config(data.get("hotbar_config", {}))
			
## Disconnects from leveling component signals to prevent side effects during loading.
func disconnect_level_signals() -> void:
	if _level_component and _level_component.leveled_up.is_connected(_on_leveled_up):
		_level_component.leveled_up.disconnect(_on_leveled_up)
		print("AbilityComponent: Disconnected from leveling signals for loading.")


## Reconnects to leveling component signals after loading is complete.
func reconnect_level_signals() -> void:
	if _level_component and not _level_component.leveled_up.is_connected(_on_leveled_up):
		_level_component.leveled_up.connect(_on_leveled_up)
		print("AbilityComponent: Reconnected to leveling signals.")
#endregion


#region #################### Getters & Validation ####################
func get_ability_level(ability_id: String) -> int:
	return _ability_levels.get(ability_id, 0)


func get_available_ability_points() -> int:
	return _available_ability_points


func get_cooldown_remaining(ability_id: String) -> float:
	return _cooldowns.get(ability_id, 0.0)


## Checks if an ability meets all criteria to be leveled up.
func can_level_up_ability(ability_id: String) -> bool:
	if _available_ability_points <= 0: return false
	
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability: return false
	
	var current_level = get_ability_level(ability_id)
	if current_level >= ability.max_level: return false
	
	# Check for prerequisite ability levels
	if ability.prerequisite_abilities:
		for prereq_id in ability.prerequisite_abilities:
			var required_level = ability.prerequisite_abilities[prereq_id]
			if get_ability_level(prereq_id.ability_id) < required_level:
				return false
	
	return true
#endregion
