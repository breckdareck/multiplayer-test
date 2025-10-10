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

var hotbar_abilities: Dictionary = {} # Key: slot_index (int), Value: ability_id (String)

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
		if ability_data != null and not _ability_levels.has(ability_data.ability_id):
			# Use learn_ability to handle initial setup and passive application
			learn_ability(ability_data.ability_id, 1)
	
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
	# NOTE: Prerequisite check now only needs the ID, as the level is contained within AbilityData.
	if ability.prerequisite_abilities:
		# Assuming prerequisite_abilities is now a Dictionary<AbilityData, int>
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
	if ability.ability_type == Constants.AbilityType.PASSIVE:
		_apply_passive_effect() # Re-apply all passives
		
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
	
	# Check if it's an active ability (assuming you define ACTIVE_ATTACK/ACTIVE_BUFF in Constants)
	if ability.ability_type != Constants.AbilityType.ACTIVE:
		print("AbilityComponent: Ability '%s' is not an active ability." % ability.ability_name)
		return false
	
	# Check Cooldown
	if _cooldowns.has(ability_id):
		print("AbilityComponent: Ability '%s' is on cooldown." % ability.ability_name)
		return false
		
	# NEW: Check Mana Cost from level stats
	var mana_cost = level_stats.mana_cost
	# NOTE: You'd implement other costs (HP, custom resource) in the custom logic script
	if "current_mana" in _stats_component:
		if _stats_component.current_mana < mana_cost:
			print("AbilityComponent: Not enough mana to use '%s' (need %d)." % [ability.ability_name, mana_cost])
			return false
		else:
			_stats_component.current_mana -= mana_cost
	else:
		print("Mana isn't implemented yet. ---- ADD LATER ----")
		
	# Success! Deduct generic cost and start cooldown
	# The custom script will handle additional costs (like HP cost for Slash Blast)
	_cooldowns[ability_id] = level_stats.cooldown_time
	cooldown_started.emit(ability_id, level_stats.cooldown_time)

	# NEW: Execute with custom logic script
	_execute_active_ability(ability, level_stats)
	ability_used.emit(ability_id)
	
	return true


## UPDATED: Executes custom logic script
func _execute_active_ability(ability: AbilityData, level_stats: AbilityLevelData) -> void:
	print("AbilityComponent: Executing %s (Level %d, %d%% damage)" % [ability.ability_name, level_stats.level, level_stats.damage_percent])
	
	var active_behavior = ability.active_behavior
	
	if active_behavior and active_behavior.logic_script:
		# Create an instance of the specific logic script
		var custom_logic = active_behavior.logic_script.new()
		
		if custom_logic and custom_logic.has_method("execute"):
			# Pass the caster (parent), the ability data, and the level data
			custom_logic.execute(owner, ability, level_stats)
		else:
			push_error("Custom logic script for %s is missing 'execute' method." % ability.ability_name)
	else:
		push_error("Ability %s is missing a custom logic script." % ability.ability_name)
		
	# Still call the combat component for generic cleanup/processing if needed
	var combat_component = get_parent().get_node_or_null("Combat")
	if combat_component and combat_component.has_method("process_ability_hit"):
		combat_component.process_ability_hit(ability, level_stats)
	else:
		print("AbilityComponent: No combat component found to process ability hit")


## REVISED: Simplified passive effect getter
func get_passive_effect_modifiers() -> Dictionary:
	var modifiers = {}
	
	for ability_id in _ability_levels:
		var ability = ResourceManager.get_ability_data(ability_id)
		var ability_level = _ability_levels[ability_id]
		var level_stats = ability.get_level_stats(ability_level)
		
		# Only process learned abilities with valid level stats that are Passive
		if ability and ability.ability_type == Constants.AbilityType.PASSIVE and level_stats:
			
			# Use stat bonuses from the level data (stat_bonuses is now mandatory for passives)
			for stat_name in level_stats.stat_bonuses:
				if not modifiers.has(stat_name):
					modifiers[stat_name] = 0
				modifiers[stat_name] += level_stats.stat_bonuses[stat_name]
	
	return modifiers


## REVISED: Now called generically to force stat recalculation
func _apply_passive_effect() -> void:
	print("AbilityComponent: Forcing global stat recalculation for passive effects.")
	
	if _stats_component:
		if multiplayer.is_server() and _stats_component.has_method("_recalculate_stats_server"):
			_stats_component._recalculate_stats_server("AbilityPassiveChange")


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
	
	# Authoritative Checks (Only for generic costs/CDs)
	if _cooldowns.has(ability_id):
		print("Server: Cooldown check failed for %s." % ability.ability_name)
		return
	
	if _stats_component.current_mana < level_stats.mana_cost:
		print("Server: Mana check failed for %s." % ability.ability_name)
		return
		
	# Apply Generic Changes (The custom script will handle unique costs/logic)
	_stats_component.current_mana -= level_stats.mana_cost
	_cooldowns[ability_id] = level_stats.cooldown_time
	
	# Execute with custom logic script
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
		# Use ability.active_behavior.animation_name and .sfx_path here
		pass


## This gets called when character levels up
func _on_leveled_up() -> void:
	add_ability_points(3) # MapleStory gives 3 ability points per level


## Assign an ability to a hotbar slot
func set_hotbar_ability(slot_index: int, ability_data: AbilityData) -> void:
	if not ability_data:
		print("Cannot assign null ability to hotbar")
		return
	
	# Check if ability is learned
	if get_ability_level(ability_data.ability_id) <= 0:
		print("Cannot assign unlearned ability '%s' to hotbar" % ability_data.ability_name)
		return
	
	hotbar_abilities[slot_index] = ability_data.ability_id
	print("Assigned ability '%s' to hotbar slot %d" % [ability_data.ability_name, slot_index])

## Clear an ability from a hotbar slot
func clear_hotbar_ability(slot_index: int) -> void:
	if hotbar_abilities.has(slot_index):
		# var ability_id = hotbar_abilities[slot_index]
		hotbar_abilities.erase(slot_index)
		print("Cleared ability from hotbar slot %d" % slot_index)

## Use ability from hotbar slot
func use_hotbar_ability(slot_index: int) -> bool:
	if not hotbar_abilities.has(slot_index):
		print("No ability assigned to hotbar slot %d" % slot_index)
		return false
	
	var ability_id = hotbar_abilities[slot_index]
	
	# Check if this is multiplayer and if we're the client
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		use_ability_request(ability_id)
		return true
	else:
		return use_ability(ability_id)

## Get ability ID from hotbar slot
func get_hotbar_ability(slot_index: int) -> String:
	return hotbar_abilities.get(slot_index, "")

## Get all hotbar assignments
func get_hotbar_config() -> Dictionary:
	return hotbar_abilities.duplicate()

## Load hotbar configuration (for save/load system)
func load_hotbar_config(config: Dictionary) -> void:
	hotbar_abilities.clear()
	for slot_index in config:
		var ability_id = config[slot_index]
		# Verify the ability exists and is learned
		if ResourceManager.get_ability_data(ability_id) and get_ability_level(ability_id) > 0:
			hotbar_abilities[slot_index] = ability_id
		else:
			print("Warning: Could not load ability '%s' to slot %d (not learned or invalid)" % [ability_id, slot_index])
