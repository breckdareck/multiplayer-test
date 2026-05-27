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
			##print("Setting debug hitbox from: %s" % new_ability_data.ability_name)
			hitbox.shape = new_ability_data.active_behavior.hit_box_shape_data.duplicate()
			hitbox.position = new_ability_data.active_behavior.hit_box_position_data
		else:
			# Fallback to a default shape if the ability data is invalid
			##print("Setting debug hitbox to default shape.")
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
var _mana_component: ManaComponent

# State variables
var _cooldowns: Dictionary = {} # { ability_id: time_remaining }
var _ability_levels: Dictionary = {} # { ability_id: current_level }
var _available_ability_points: int = 0
var _loading_mode: bool = false

# Track proc cooldowns per passive ability
var _passive_proc_cooldowns: Dictionary = {} # { "ability_id_event_type": last_proc_time }

# Track active passive abilities for easy access
@warning_ignore("unused_private_class_variable")
var _active_passive_abilities: Array[AbilityData] = []

const MAX_ABILITY_REQUESTS_PER_SECOND: int = 10
var _ability_request_times: Array[float] = []

# Projectile container
var _projectiles_container: Node

# UI references
@onready var hotbar: Hotbar = $"../../CanvasLayer/PlayerHUD/Hotbar"
#endregion


#region #################### Godot Engine Callbacks ####################
func _ready() -> void:
	# Fetch required sibling components
	_class_component = get_parent().get_node_or_null("Class")
	_stats_component = get_parent().get_node_or_null("Stats")
	_level_component = get_parent().get_node_or_null("Leveling")
	_mana_component = get_parent().get_node_or_null("Mana")
	
	if not _class_component or not _stats_component:
		push_error("AbilityComponent requires ClassComponent and StatsComponent siblings.")
		set_process(false)
		return

	# Connect to ClassComponent to handle class changes
	if _class_component:
		_class_component.class_changed.connect(_on_class_changed)

	# Find or create the projectiles container inside the current visible map.
	var map_node = MapManager.get_current_visible_map()
	if map_node:
		_projectiles_container = map_node.get_node_or_null("Projectiles")
		if not is_instance_valid(_projectiles_container):
			_projectiles_container = Node.new()
			_projectiles_container.name = "Projectiles"
			map_node.add_child(_projectiles_container)
	else:
		# Fallback to legacy path if available
		var legacy = get_node_or_null("/root/MainMenu/Level/Game")
		if legacy:
			_projectiles_container = legacy.get_node_or_null("Projectiles")
			if not is_instance_valid(_projectiles_container):
				_projectiles_container = Node.new()
				_projectiles_container.name = "Projectiles"
				legacy.add_child(_projectiles_container)

	# Connect to the LevelingComponent to grant ability points on level up
	if _level_component:
		if multiplayer.is_server():
			_level_component.leveled_up.connect(_on_leveled_up)
	else:
		push_warning("AbilityComponent: No LevelingComponent found. Points won't be granted on level up.")
		
	# Initialize class abilities on the server or in single-player.
	# Clients will receive this data via an RPC sync when they connect.
	#
	# Each discipline's starter ability (configured on WeaponDisciplineData.starter_ability)
	# is auto-leveled to 1 so a fresh character can cast something immediately.
	# Without this, classes like Mage (whose basic attack uses the staff's
	# tiny WEAPONATTACK while their kit is built around MAGICATTACK abilities)
	# can't fight effectively until they earn their first ability point on
	# level-up. Save data still overrides this — returning characters keep
	# whatever level they had leveled the ability to.
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		var starter: AbilityData = _class_component.get_starter_ability() if _class_component else null
		for ability_data in _class_component.get_class_abilities():
			if ability_data and not _ability_levels.has(ability_data.ability_id):
				var initial_level: int = 1 if (starter and ability_data == starter) else 0
				_learn_ability_local(ability_data.ability_id, initial_level, false)

	##print("AbilityComponent ready. Loaded abilities: ", _ability_levels)


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
	var validation = _validate_ability_use(ability_id)
	if not validation.valid:
		return false
	
	# Client-side check to prevent sending pointless requests
	if _cooldowns.has(ability_id):
		##print("Ability '%s' is on cooldown." % validation.ability.ability_name)
		return false
		
	# In multiplayer, clients request the server to use the ability.
	if _is_multiplayer_client():
		_request_ability_use(ability_id)
		return true
	
	# In single-player or on the server, execute directly.
	return _handle_authoritative_use(ability_id, validation.ability, validation.level_stats)


## Attempts to level up an ability.
func level_up_ability(ability_id: String) -> bool:
	if _is_multiplayer_client():
		level_up_ability_request.rpc_id(1, ability_id)
		return true
	
	return _level_up_ability_local(ability_id)


## Learns a new ability.
func learn_ability(ability_id: String, initial_level: int = 0) -> bool:
	if _is_multiplayer_client():
		learn_ability_request.rpc_id(1, ability_id, initial_level)
		return true

	return _learn_ability_local(ability_id, initial_level)


func get_passive_effect_modifiers() -> Dictionary:
	var modifiers = {}
	
	_foreach_learned_passive(func(_ability: AbilityData, level_stats: AbilityLevelData, _ability_id: String):
		# Use stat bonuses from the level data
		for stat_name in level_stats.stat_bonuses:
			if not modifiers.has(stat_name):
				modifiers[stat_name] = StatData.new(stat_name, 0)
			# Accumulate bonuses from multiple passives
			modifiers[stat_name].flat_bonus_value += level_stats.stat_bonuses[stat_name].flat_bonus_value
			modifiers[stat_name].percent_bonus_value += level_stats.stat_bonuses[stat_name].percent_bonus_value
	)
	
	return modifiers


func get_ability_damage_modifier(ability_id: String) -> float:
	return _get_ability_modifier(ability_id, func(level_stats, id): return level_stats.get_ability_damage_modifier(id))


func get_ability_cooldown_modifier(ability_id: String) -> float:
	return _get_ability_modifier(ability_id, func(level_stats, id): return level_stats.get_ability_cooldown_modifier(id))


func get_ability_mana_modifier(ability_id: String) -> float:
	return _get_ability_modifier(ability_id, func(level_stats, id): return level_stats.get_ability_mana_modifier(id))


func try_trigger_procs(event_type: String, target: Node = null, context: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return
	
	_foreach_learned_passive(func(_ability: AbilityData, level_stats: AbilityLevelData, ability_id: String):
		var proc_key = ability_id + "_" + event_type
		var last_proc_time = _passive_proc_cooldowns.get(proc_key, 0.0)
		
		var proc_effect = level_stats.try_proc_event(event_type, {event_type: last_proc_time})
		if proc_effect:
			_execute_proc(proc_effect, target, context)
			_passive_proc_cooldowns[proc_key] = Time.get_ticks_msec() / 1000.0
	)

#endregion


#region #################### Helper Functions ####################
## Helper to check if we're a client in a multiplayer session
func _is_multiplayer_client() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.is_server()


## Helper function to iterate through all learned passive abilities
## Calls the provided callable for each passive ability with its data
func _foreach_learned_passive(callback: Callable) -> void:
	for ability_id in _ability_levels:
		var ability_level = _ability_levels[ability_id]
		
		# Skip unlearned abilities
		if ability_level <= 0:
			continue
			
		var ability = ResourceManager.get_ability_data(ability_id)
		if not ability or ability.ability_type != Constants.AbilityType.PASSIVE:
			continue
			
		var level_stats = ability.get_level_stats(ability_level)
		if not level_stats:
			continue
			
		# Call the callback with the ability data
		callback.call(ability, level_stats, ability_id)


## Generic modifier calculator - reduces code duplication
func _get_ability_modifier(ability_id: String, modifier_getter: Callable) -> float:
	var total_modifier: float = 1.0
	# Iterate synchronously - avoid capturing outer-scope reassignments inside lambdas
	for passive_id in _ability_levels:
		var lvl = _ability_levels[passive_id]
		if lvl <= 0:
			continue
		var ability = ResourceManager.get_ability_data(passive_id)
		if not ability or ability.ability_type != Constants.AbilityType.PASSIVE:
			continue
		var level_stats = ability.get_level_stats(lvl)
		if not level_stats:
			continue
		total_modifier *= modifier_getter.call(level_stats, ability_id)

	return total_modifier


## Validates if an ability can be used - reduces duplication
func _validate_ability_use(ability_id: String) -> Dictionary:
	var result = {
		"valid": false,
		"ability": null,
		"level": 0,
		"level_stats": null
	}
	
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability:
		#printerr("Ability ID '%s' not found." % ability_id)
		return result
	
	var ability_level := get_ability_level(ability_id)
	if ability_level <= 0:
		##print("Ability '%s' has not been learned." % ability.ability_name)
		return result
	
	if ability.ability_type != Constants.AbilityType.ACTIVE:
		##print("Ability '%s' is not an active ability." % ability.ability_name)
		return result
	
	var level_stats = ability.get_level_stats(ability_level)
	if not level_stats:
		#printerr("Invalid level data for '%s' at level %d" % [ability.ability_name, ability_level])
		return result
	
	result.valid = true
	result.ability = ability
	result.level = ability_level
	result.level_stats = level_stats
	return result


## Checks if resources and state allow ability use
func _can_afford_ability(ability_id: String, level_stats: AbilityLevelData) -> bool:
	# Check mana
	var modified_mana_cost = level_stats.mana_cost * get_ability_mana_modifier(ability_id)
	if _mana_component.current_mana < modified_mana_cost:
		##print("Server: Not enough mana.")
		return false
	
	# Check if already attacking
	var state_machine = owner.get_node_or_null("StateMachine")
	if state_machine:
		var attack_state = state_machine.get_node_or_null("attack")
		if "current_state" in state_machine and state_machine.current_state == attack_state:
			##print("Server: Cannot use ability, an attack is already in progress.")
			return false
	
	return true


## Consumes resources and starts cooldown for an ability
func _consume_ability_resources(ability_id: String, level_stats: AbilityLevelData) -> float:
	# Consume mana
	if _mana_component.current_mana:
		var modified_mana_cost = roundi(level_stats.mana_cost * get_ability_mana_modifier(ability_id))
		_mana_component.current_mana -= modified_mana_cost
	
	# Start cooldown
	var modified_cooldown = level_stats.cooldown_time * get_ability_cooldown_modifier(ability_id)
	_cooldowns[ability_id] = modified_cooldown
	
	return modified_cooldown

#endregion


#region #################### Internal Logic & Execution ####################
## The authoritative logic for using an ability (runs on server or in single-player).
func _handle_authoritative_use(ability_id: String, ability: AbilityData, level_stats: AbilityLevelData) -> bool:
	# Final server-side validation
	if _cooldowns.has(ability_id):
		return false
	
	# Check resources and state
	if not _can_afford_ability(ability_id, level_stats):
		return false
	
	# Consume resources and start cooldown
	var cooldown_duration = _consume_ability_resources(ability_id, level_stats)
	
	# Trigger the visual/gameplay effect
	_trigger_ability_state_change(ability, level_stats)
	
	# Trigger on_ability_cast procs
	try_trigger_procs("on_ability_cast", null, {"ability": ability, "level_stats": level_stats})
	
	# Emit signals and notify clients
	ability_used.emit(ability_id)
	cooldown_started.emit(ability_id, cooldown_duration)
	
	if multiplayer.is_server():
		if BotManager.is_bot(owner.player_id):
			# A bot's AbilityComponent node may be missing on a client mid
			# map-transition; route the cast visual through MapManager instead.
			_broadcast_bot_ability_visual(ability_id, level_stats.level)
		else:
			ability_used_client.rpc(ability_id, cooldown_duration)

	return true


## Routes a bot's ability-cast visual through MapManager (an autoload that
## always resolves) rather than the bot's AbilityComponent node, which a client
## may lack mid map-transition.
func _broadcast_bot_ability_visual(ability_id: String, level: int) -> void:
	var map_name: String = MapManager.get_player_map(owner.player_id)
	for peer_id in MapManager.get_real_players_on_map(map_name):
		if peer_id != 1:
			MapManager.bot_ability_used.rpc_id(peer_id, owner.player_id, ability_id, level)


## Triggers the state machine transition and custom logic for an active ability.
func _trigger_ability_state_change(ability: AbilityData, level_stats: AbilityLevelData) -> void:
	##print("Executing %s (Level %d)" % [ability.ability_name, level_stats.level])
	
	var active_behavior = ability.active_behavior
	if not active_behavior:
		push_error("Ability '%s' is missing ActiveBehavior data." % ability.ability_name)
		return

	# All active abilities now go through the state machine.
	# The CombatComponent will handle the difference between projectile and hitbox attacks.
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
			AudioManager.play_sfx_for_map(MapManager.get_player_map(owner.player_id), active_behavior.sfx_path, owner.global_position)

	# Execute optional custom logic from the ability's script resource
	if active_behavior.logic_script:
		var custom_logic = active_behavior.logic_script.new()
		if custom_logic.has_method("execute"):
			custom_logic.execute(owner, ability, level_stats)


## The authoritative logic for leveling up an ability.
func _level_up_ability_local(ability_id: String) -> bool:
	if not can_level_up_ability(ability_id):
		##print("Validation failed for leveling up ability: %s." % ability_id)
		return false

	var ability = ResourceManager.get_ability_data(ability_id)
	var current_level = _ability_levels[ability_id]
	
	_available_ability_points -= 1
	_ability_levels[ability_id] = current_level + 1
	
	# Re-apply passive effects if a passive ability was leveled up
	if ability.ability_type == Constants.AbilityType.PASSIVE:
		_apply_passive_effects()

	ability_leveled_up.emit(ability_id, current_level + 1)
	##print("Leveled up %s to level %d" % [ability.ability_name, current_level + 1])
	
	# Sync changes to clients (bots have no client UI — skip to avoid a
	# node-addressed RPC failing on clients that lack the bot node).
	if multiplayer.is_server() and not BotManager.is_bot(owner.player_id):
		sync_ability_level.rpc(ability_id, current_level + 1)
		sync_ability_points.rpc(_available_ability_points)
	
	return true


## The authoritative logic for learning an ability.
func _learn_ability_local(ability_id: String, initial_level: int = 0, send_rpc: bool = true) -> bool:
	if _ability_levels.has(ability_id):
		return false
	
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability:
		#printerr("AbilityData not found for ID: %s" % ability_id)
		return false
	
	_ability_levels[ability_id] = initial_level
	
	if ability.ability_type == Constants.AbilityType.PASSIVE:
		_apply_passive_effects()
		
	ability_learned.emit(ability_id)
	##print("Learned ability: %s at level %d" % [ability.ability_name, initial_level])
	
	if send_rpc and multiplayer.is_server() and not BotManager.is_bot(owner.player_id):
		sync_ability_learned.rpc(ability_id, initial_level)
	
	return true


## Forces the StatsComponent to recalculate stats, applying all passive bonuses.
func _apply_passive_effects() -> void:
	if _stats_component and multiplayer.is_server():
		_stats_component.mark_stats_dirty()


## Adds ability points, typically called after leveling up.
func _add_ability_points(amount: int) -> void:
	_available_ability_points += amount
	##print("Added %d ability points. Total: %d" % [amount, _available_ability_points])
	ability_points_changed.emit(_available_ability_points)

	if multiplayer.is_server() and not BotManager.is_bot(owner.player_id):
		sync_ability_points.rpc(_available_ability_points)


func _execute_proc(proc: ProcEffectData, target: Node, context: Dictionary) -> void:
	##print("Proc triggered! Chance was: %.1f%%" % (proc.proc_chance * 100))
	
	# Deal damage if specified
	if proc.damage_percent > 0 and target and "health_component" in target:
		var base_damage = context.get("base_damage", 0)
		var proc_damage = base_damage * (proc.damage_percent / 100.0)
		target.health_component.take_damage(proc_damage, owner, true)
		##print("Proc dealt %d damage" % proc_damage)
	
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
		AudioManager.play_sfx_for_map(MapManager.get_player_map(owner.player_id), proc.sfx_path, owner.global_position)
	
	# Custom logic
	if proc.logic_script:
		var script_instance = proc.logic_script.new()
		if script_instance.has_method("on_proc"):
			script_instance.on_proc(owner, target, context)

#endregion


#region #################### Multiplayer & RPCs ####################
func spawn_projectile(ability: AbilityData, level_stats: AbilityLevelData, target: Node2D):
	if not multiplayer.is_server():
		return

	var active_behavior = ability.active_behavior
	if not active_behavior.projectile_scene:
		printerr("Projectile scene not set for ability: %s" % ability.ability_name)
		return

	# Target can be null. If it is, we fire straight.
	var initial_direction: Vector2
	if is_instance_valid(target):
		var target_position = target.global_position
		if target.has_node("aim_target"):
			target_position = target.get_node("aim_target").global_position
		initial_direction = (target_position - owner.global_position).normalized()
	else:
		# No target, fire straight ahead based on player's facing direction.
		initial_direction = Vector2(owner.facing_direction, 0).normalized()

	var projectile_instance = active_behavior.projectile_scene.instantiate()
	var proj_name := "Proj_%d_%d" % [Time.get_ticks_msec(), randi()]
	projectile_instance.name = proj_name

	# The projectile will now store the ability data and call back to the CombatComponent to process the hit.
	projectile_instance.initialize(owner, target, ability, level_stats, active_behavior.projectile_speed, initial_direction)
	
	# Find the correct container based on the player's current map
	# Player structure: Map -> Players -> Player -> AbilityComponent
	# So owner (Player) -> parent (Players) -> parent (Map)
	var current_map = owner.get_parent().get_parent()
	var target_container = _projectiles_container # Default fallback
	
	if current_map and current_map.is_in_group("map_base"):
		var map_container = current_map.get_node_or_null("Projectiles")
		if map_container:
			target_container = map_container
		else:
			# Create if missing on this map
			var new_container = Node.new()
			new_container.name = "Projectiles"
			current_map.add_child(new_container)
			target_container = new_container
			#print("Created missing Projectiles container on map: %s" % current_map.name)
	
	if not is_instance_valid(target_container):
		printerr("Could not find valid Projectiles container for ability: %s" % ability.ability_name)
		return

	# Add projectile to scene tree first, then set global position
	target_container.add_child(projectile_instance, true)
	
	var spawn_pos = owner.global_position
	if is_instance_valid(owner.projectile_spawn_location):
		spawn_pos = owner.projectile_spawn_location.global_position
	else:
		printerr("Projectile spawn location not set on player controller. Spawning at player position.")
	
	projectile_instance.global_position = spawn_pos
	
	# Replicate the visual to same-map clients. Routed through MapManager (an
	# autoload that always resolves on every peer) so it works for bot casters
	# too. Clients simulate the projectile locally; the server is authoritative
	# for hit detection.
	var target_path = NodePath("")
	if is_instance_valid(target):
		target_path = target.get_path()

	if current_map and current_map.is_in_group("map_base"):
		var map_name = current_map.name.replace("Map_", "")
		var scene_path: String = active_behavior.projectile_scene.resource_path
		for peer_id in MapManager.get_real_players_on_map(map_name):
			if peer_id != 1: # Server already has it
				MapManager.spawn_projectile_visual.rpc_id(peer_id, proj_name, scene_path, spawn_pos, initial_direction, active_behavior.projectile_speed, target_path)


## [Client] Plays an ability's cast visual without the cooldown/UI bookkeeping
## that ability_used_client does. Used for bot casts, which are routed through
## MapManager (the bot's AbilityComponent node may be missing on this client).
func play_ability_visual(ability_id: String, level: int) -> void:
	if multiplayer.is_server():
		return
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability:
		return
	var level_stats = ability.get_level_stats(level)
	if level_stats:
		_trigger_ability_state_change(ability, level_stats)


## [Server->Client] Sends all ability data to a newly connected client in a single RPC.
func sync_all_abilities_to_client(peer_id: int) -> void:
	if not multiplayer.is_server(): return

	#print("Syncing all ability data to peer %d" % peer_id)
	var hotbar_config: Dictionary = hotbar.save_hotbar_config() if is_instance_valid(hotbar) else {}
	sync_all_abilities_batch.rpc_id(peer_id, _ability_levels.duplicate(), _available_ability_points, hotbar_config, _cooldowns.duplicate())


@rpc("authority", "call_local", "reliable")
func sync_all_abilities_batch(abilities: Dictionary, ability_points: int, hotbar_config: Dictionary = {}, cooldowns: Dictionary = {}) -> void:
	if multiplayer.is_server(): return

	for ability_id in abilities:
		_ability_levels[ability_id] = abilities[ability_id]
		ability_learned.emit(ability_id)
	_available_ability_points = ability_points
	ability_points_changed.emit(_available_ability_points)

	if is_instance_valid(hotbar):
		hotbar.load_hotbar_config(hotbar_config)

	for ability_id in cooldowns:
		var remaining: float = cooldowns[ability_id]
		if remaining > 0.0:
			_cooldowns[ability_id] = remaining
			cooldown_started.emit(ability_id, remaining)


## [Client->Server] Client-side wrapper to request ability use from the server.
func _request_ability_use(ability_id: String) -> void:
	#print("Client: Sending request to use ability %s" % ability_id)
	use_ability_server.rpc_id(1, ability_id) # Server is always peer ID 1


func _is_ability_rpc_rate_limited() -> bool:
	var now = Time.get_ticks_msec() / 1000.0
	while _ability_request_times.size() > 0 and now - _ability_request_times[0] > 1.0:
		_ability_request_times.pop_front()
	if _ability_request_times.size() >= MAX_ABILITY_REQUESTS_PER_SECOND:
		return true
	_ability_request_times.append(now)
	return false


@rpc("any_peer", "call_local", "reliable")
## [Client->Server] RPC for a client to request using an ability.
func use_ability_server(ability_id: String) -> void:
	if not multiplayer.is_server(): return

	if _is_ability_rpc_rate_limited():
		return

	var validation = _validate_ability_use(ability_id)
	if not validation.valid:
		return
	
	# Let the authoritative function handle the final execution
	_handle_authoritative_use(ability_id, validation.ability, validation.level_stats)


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
	
	#print("Synchronized ability use for %s." % ability_id)


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
	#print("Synced ability level: %s to %d" % [ability_id, new_level])


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
func _on_leveled_up(_new_level: int) -> void:
	# Grant 3 ability points on level up
	#print("Leveled up to %d. Gaining 3 ability points." % new_level)
	_add_ability_points(3)


func _on_class_changed(_new_class_name: String) -> void:
	# On initial character creation the component pre-loaded the default
	# class's abilities in _ready() (including its starter at level 1)
	# before the real class was assigned, so anything not in the new class
	# must be dropped — including a stale level-1 starter from the default
	# class. Job advancement stays safe because the advanced class's skill
	# list is a superset of the base class's, so any leveled ability is
	# present in new_class_ids and survives.
	#
	# RPCs are not broadcast here because the class change itself is synced,
	# so clients run this same logic locally.
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		var new_class_ids: Dictionary = {}
		for ability_data in _class_component.get_class_abilities():
			if ability_data:
				new_class_ids[ability_data.ability_id] = true

		for ability_id in _ability_levels.keys():
			if not new_class_ids.has(ability_id):
				_ability_levels.erase(ability_id)

		var starter: AbilityData = _class_component.get_starter_ability()
		for ability_data in _class_component.get_class_abilities():
			if ability_data and not _ability_levels.has(ability_data.ability_id):
				var initial_level: int = 1 if (starter and ability_data == starter) else 0
				_learn_ability_local(ability_data.ability_id, initial_level, false)

#endregion


#region #################### Save & Load System ####################
## Returns a dictionary of all ability data for saving.
func save_abilities() -> Dictionary:
	# `hotbar` is a UI node; a bot frees its UI subtree, so guard the access.
	return {
		"ability_levels": _ability_levels.duplicate(),
		"available_points": _available_ability_points,
		"hotbar_config": hotbar.save_hotbar_config() if is_instance_valid(hotbar) else {},
		"cooldowns": _cooldowns.duplicate()
	}


## Loads and applies ability data from a dictionary.
func load_abilities(data: Dictionary) -> void:
	if data.is_empty(): return
	
	# First, ensure all current class abilities are initialized
	for ability_data in _class_component.get_class_abilities():
		if ability_data != null and not _ability_levels.has(ability_data.ability_id):
			_ability_levels[ability_data.ability_id] = 0
			#print("Added new ability from class: %s at level 0" % ability_data.ability_id)
			
	# Load saved data by merging (not replacing) to preserve new abilities
	var saved_levels = data.get("ability_levels", {})
	for ability_id in saved_levels:
		_ability_levels[ability_id] = saved_levels[ability_id]
	
	_available_ability_points = data.get("available_points", 0)
	if is_instance_valid(hotbar):
		hotbar.load_hotbar_config(data.get("hotbar_config", {}))

	var saved_cooldowns: Dictionary = data.get("cooldowns", {})
	for ability_id in saved_cooldowns:
		var remaining: float = saved_cooldowns[ability_id]
		if remaining > 0.0:
			_cooldowns[ability_id] = remaining
			cooldown_started.emit(ability_id, remaining)
	
	# Re-apply passives and update UI with loaded data
	_apply_passive_effects()
	if not _loading_mode:
		ability_points_changed.emit(_available_ability_points)
		for ability_id in _ability_levels:
			var level = _ability_levels[ability_id]
			if level > 0:
				ability_learned.emit(ability_id)
				ability_leveled_up.emit(ability_id, level)
			#print("Loaded ability: %s at level %d" % [ability_id, level])
	#else:
		#for ability_id in _ability_levels:
			#print("Loaded ability: %s at level %d" % [ability_id, _ability_levels[ability_id]])
			
## Disconnects from leveling component signals to prevent side effects during loading.
func disconnect_level_signals() -> void:
	if _level_component and _level_component.leveled_up.is_connected(_on_leveled_up):
		_level_component.leveled_up.disconnect(_on_leveled_up)
		#print("AbilityComponent: Disconnected from leveling signals for loading.")


## Reconnects to leveling component signals after loading is complete.
func reconnect_level_signals() -> void:
	if _level_component and not _level_component.leveled_up.is_connected(_on_leveled_up):
		_level_component.leveled_up.connect(_on_leveled_up)
		#print("AbilityComponent: Reconnected to leveling signals.")


func set_loading_mode(enabled: bool) -> void:
	_loading_mode = enabled
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
