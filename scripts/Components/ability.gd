@tool
class_name AbilityComponent
extends Node

# Signals
signal ability_used(ability_id: String)
signal cooldown_started(ability_id: String, duration: float)
signal ability_leveled_up(ability_id: String, new_level: int)
signal ability_learned(ability_id: String)

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
		if x and x.active_behavior:
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

var _cooldowns: Dictionary = {}

## {"ability_id": current_level}
var _ability_levels: Dictionary = {}

var _available_ability_points: int = 0


func _ready() -> void:
	_class_component = get_parent().get_node_or_null("Class")
	_stats_component = get_parent().get_node_or_null("Stats")
	
	if not _class_component or not _stats_component:
		push_error("AbilityComponent requires ClassComponent and StatsComponent siblings.")
		set_process(false)
		return
		
	set_process(true)
	
	# Initialize class abilities at level 1
	for ability_data in _class_component.get_class_abilities():
		if ability_data != null:
			_ability_levels[ability_data.ability_id] = 1
			_apply_passive_effect(ability_data, 1)
	
	print("Loaded abilities: ", _ability_levels)


func _process(delta: float) -> void:
	# Tick down cooldowns
	var to_remove = []
	for ability_id in _cooldowns:
		_cooldowns[ability_id] -= delta
		if _cooldowns[ability_id] <= 0.0:
			to_remove.append(ability_id)

	for ability_id in to_remove:
		_cooldowns.erase(ability_id)


## NEW: Level up a ability using ability points
func level_up_ability(ability_id: String) -> bool:
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
	if ability.prerequisite_ability_id:
		var prereq_level = _ability_levels.get(ability.prerequisite_ability_id, 0)
		if prereq_level < ability.prerequisite_ability_level:
			print("Prerequisite not met for %s" % ability.ability_name)
			return false
	
	# Level up!
	_available_ability_points -= 1
	_ability_levels[ability_id] = current_level + 1
	
	# Update passive effects if applicable
	if ability.passive_effect:
		_apply_passive_effect(ability, current_level + 1)
	
	ability_leveled_up.emit(ability_id, current_level + 1)
	print("Leveled up %s to level %d" % [ability.ability_name, current_level + 1])
	
	return true


## NEW: Learn a new ability (set it to level 1)
func learn_ability(ability_id: String, initial_level: int = 1) -> bool:
	if _ability_levels.has(ability_id):
		print("ability already learned: %s" % ability_id)
		return false
	
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability:
		print("Ability not found: %s" % ability_id)
		return false
	
	_ability_levels[ability_id] = initial_level
	_apply_passive_effect(ability, initial_level)
	ability_learned.emit(ability_id)
	
	print("Learned ability: %s at level %d" % [ability.ability_name, initial_level])
	return true


## NEW: Add ability points (called when character levels up)
func add_ability_points(amount: int) -> void:
	_available_ability_points += amount
	print("Added %d ability points. Total: %d" % [amount, _available_ability_points])


## NEW: Get current level of a ability
func get_ability_level(ability_id: String) -> int:
	return _ability_levels.get(ability_id, 0)


## NEW: Get available ability points
func get_available_ability_points() -> int:
	return _available_ability_points


## NEW: Check if a ability can be leveled up
func can_level_up_ability(ability_id: String) -> bool:
	if _available_ability_points <= 0:
		return false
	
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability:
		return false
	
	var current_level = get_ability_level(ability_id)
	if current_level <= 0 or current_level >= ability.max_level:
		return false
	
	# Check prerequisites
	if ability.prerequisite_ability_id:
		var prereq_level = get_ability_level(ability.prerequisite_ability_id)
		if prereq_level < ability.prerequisite_ability_level:
			return false
	
	return true


func use_ability(ability_id: String) -> bool:
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability:
		print("AbilityComponent: Ability ID '%s' not found." % ability_id)
		return false

	# NEW: Get current ability level
	var ability_level = get_ability_level(ability_id)
	if ability_level <= 0:
		print("AbilityComponent: ability '%s' not learned." % ability.ability_name)
		return false

	# NEW: Get level-specific stats
	var level_stats = ability.get_level_stats(ability_level)
	if not level_stats:
		print("AbilityComponent: Invalid level data for '%s' at level %d" % [ability.ability_name, ability_level])
		return false
	
	# Check if it's an active ability
	if ability.ability_type and ability.ability_type not in ["ACTIVE_ATTACK", "ACTIVE_BUFF"]:
		print("AbilityComponent: Ability '%s' is not an active ability." % ability.ability_name)
		return false
	
	# Backward compatibility: If no ability_type, check for active_behavior
	if not ability.ability_type and not ability.active_behavior:
		print("AbilityComponent: Ability '%s' is not an active ability." % ability.ability_name)
		return false
	
	# Check Cooldown
	if _cooldowns.has(ability_id):
		print("AbilityComponent: Ability '%s' is on cooldown." % ability.ability_name)
		return false
		
	# NEW: Check Mana Cost from level stats
	var mana_cost = level_stats.mana_cost
	if _stats_component.current_mana < mana_cost:
		print("AbilityComponent: Not enough mana to use '%s' (need %d)." % [ability.ability_name, mana_cost])
		return false
		
	# Success! Deduct cost and start cooldown
	_stats_component.current_mana -= mana_cost
	_cooldowns[ability_id] = level_stats.cooldown_time
	cooldown_started.emit(ability_id, level_stats.cooldown_time)

	# NEW: Execute with level stats
	_execute_active_ability(ability, level_stats)
	ability_used.emit(ability_id)
	
	return true


## UPDATED: Now accepts level_stats parameter
func _execute_active_ability(ability: AbilityData, level_stats: AbilityLevelData) -> void:
	print("AbilityComponent: Executing %s (Level %d, %d%% damage)" % [ability.ability_name, level_stats.level, level_stats.damage_percent])
	
	var combat_component = get_parent().get_node_or_null("Combat")
	if combat_component and combat_component.has_method("process_ability_hit"):
		# Pass both ability and level stats
		combat_component.process_ability_hit(ability, level_stats)
	else:
		print("AbilityComponent: No combat component found to process ability hit")


## UPDATED: Now uses level-based stat bonuses
func get_passive_effect_modifiers() -> Dictionary:
	var modifiers = {}
	
	for ability_id in _ability_levels:
		var ability = ResourceManager.get_ability_data(ability_id)
		if ability and ability.passive_effect:
			var ability_level = _ability_levels[ability_id]
			var level_stats = ability.get_level_stats(ability_level)
			
			if level_stats and ability.passive_effect.condition_type == "ALWAYS_ON":
				# Use stat bonuses from the level data
				for stat_name in level_stats.stat_bonuses:
					if not modifiers.has(stat_name):
						modifiers[stat_name] = 0
					modifiers[stat_name] += level_stats.stat_bonuses[stat_name]
				
				# Backward compatibility: Also check old passive_effect.stat_modifiers
				if ability.passive_effect.stat_modifiers.size() > 0:
					for stat_name in ability.passive_effect.stat_modifiers:
						if not modifiers.has(stat_name):
							modifiers[stat_name] = 0
						modifiers[stat_name] += ability.passive_effect.stat_modifiers[stat_name].total_value
	
	return modifiers


## UPDATED: Now takes ability_level parameter
func _apply_passive_effect(ability: AbilityData, ability_level: int) -> void:
	if ability.passive_effect:
		print("AbilityComponent: Registered passive effect from: %s (Level %d)" % [ability.ability_name, ability_level])
		
		if _stats_component:
			if ability.passive_effect.condition_type == "ALWAYS_ON":
				if multiplayer.is_server() and _stats_component.has_method("_recalculate_stats_server"):
					_stats_component._recalculate_stats_server("AbilityPassiveAdded")


func use_ability_request(ability_id: String) -> void:
	if _cooldowns.has(ability_id):
		print("Client: Ability is on cooldown (UX check).")
		return
		
	rpc_id(multiplayer.get_server_id(), "use_ability_server", ability_id)
	print("Client: Sent RPC request to use ability %s" % ability_id)
	
	
func get_cooldown_remaining(ability_id: String) -> float:
	return _cooldowns.get(ability_id, 0.0)


@rpc("authority", "reliable")
func use_ability_server(ability_id: String) -> void:
	var sender_id = multiplayer.get_rpc_sender_id()
	if sender_id != get_parent().multiplayer.get_authority():
		print("Server: WARNING! Unauthorized ability use attempt by ID %d" % sender_id)
		return

	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability:
		print("Server: Invalid ability: %s" % ability_id)
		return

	# NEW: Check ability level
	var ability_level = get_ability_level(ability_id)
	if ability_level <= 0:
		print("Server: ability not learned: %s" % ability_id)
		return

	# NEW: Get level stats
	var level_stats = ability.get_level_stats(ability_level)
	if not level_stats:
		print("Server: Invalid level stats for %s" % ability_id)
		return
	
	# Authoritative Checks
	if _cooldowns.has(ability_id):
		print("Server: Cooldown check failed for %s." % ability.ability_name)
		return
	
	if _stats_component.current_mana < level_stats.mana_cost:
		print("Server: Mana check failed for %s." % ability.ability_name)
		return
		
	# Apply Changes
	_stats_component.current_mana -= level_stats.mana_cost
	_cooldowns[ability_id] = level_stats.cooldown_time
	
	# Execute with level stats
	_execute_active_ability(ability, level_stats)
	
	# Notify clients
	rpc("ability_used_client", ability_id, level_stats.cooldown_time)


@rpc("any_peer", "reliable")
func ability_used_client(ability_id: String, cooldown_time: float) -> void:
	_cooldowns[ability_id] = cooldown_time
	
	ability_used.emit(ability_id)
	cooldown_started.emit(ability_id, cooldown_time)
	
	_play_vfx_sfx(ability_id)
	
	print("Client: Synchronized ability use and started cooldown for %s." % ability_id)


func _play_vfx_sfx(ability_id: String):
	var ability = ResourceManager.get_ability_data(ability_id)
	if ability and ability.active_behavior:
		pass


## This gets called when character levels up
func _on_leveled_up() -> void:
	add_ability_points(3) # MapleStory gives 3 ability points per level
