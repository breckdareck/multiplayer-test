class_name AbilityComponent
extends Node

# Signals
signal ability_used(ability_id: String)
signal cooldown_started(ability_id: String, duration: float)

var _class_component: ClassComponent
var _stats_component: StatsComponent

var _cooldowns: Dictionary = {}
var _learned_abilities: Dictionary = {}

func _ready() -> void:
	_class_component = get_parent().get_node_or_null("Class")
	_stats_component = get_parent().get_node_or_null("Stats")
	
	if not _class_component or not _stats_component:
		push_error("AbilityComponent requires ClassComponent and StatsComponent siblings.")
		set_process(false)
		return
		
	set_process(true)
	
	for ability_data in _class_component.get_class_abilities():
		if ability_data != null:
			_learned_abilities[ability_data.ability_id] = 1
			_apply_passive_effect(ability_data)
	print("Loaded abilities: ", _learned_abilities.keys())


func _process(delta: float) -> void:
	# Tick down cooldowns
	var to_remove = []
	for ability_id in _cooldowns:
		_cooldowns[ability_id] -= delta
		if _cooldowns[ability_id] <= 0.0:
			to_remove.append(ability_id)

	for ability_id in to_remove:
		_cooldowns.erase(ability_id)


func use_ability(ability_id: String) -> bool:
	# 1. Get the ability data (Using ResourceManager is safer than ClassComponent here)
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability:
		print("AbilityComponent: Ability ID '%s' not found." % ability_id)
		return false

	# Check if it has an ActiveBehavior (Composition check!)
	if not ability.active_behavior:
		print("AbilityComponent: Ability '%s' is not an active skill." % ability.ability_name)
		return false
		
	var active_data = ability.active_behavior
	
	# 2. Check Cooldown
	if _cooldowns.has(ability_id):
		print("AbilityComponent: Ability '%s' is on cooldown." % ability.ability_name)
		return false
		
	# 3. Check Mana/Resource Cost
	if _stats_component.current_mana < active_data.mana_cost:
		print("AbilityComponent: Not enough mana to use '%s'." % ability.ability_name)
		return false
		
	# 4. Success! Deduct cost and start cooldown
	_stats_component.current_mana -= active_data.mana_cost
	_cooldowns[ability_id] = active_data.cooldown_time
	cooldown_started.emit(ability_id, active_data.cooldown_time)

	# 5. Execute the ability logic (This would likely be a separate manager/system)
	_execute_active_ability(ability)
	ability_used.emit(ability_id)
	
	return true


func _execute_active_ability(ability: AbilityData) -> void:
	print("AbilityComponent: Executing active skill: %s" % ability.ability_name)
	# Find the combat component
	var combat_component = get_parent().get_node_or_null("Combat")
	if combat_component and combat_component.has_method("process_ability_hit"):
		combat_component.process_ability_hit(ability)
	else:
		print("AbilityComponent: No combat component found to process ability hit")


func get_passive_effect_modifiers() -> Dictionary:
	var modifiers = {}
	
	for ability_id in _learned_abilities:
		var ability = ResourceManager.get_ability_data(ability_id)
		if ability and ability.passive_effect:
			var passive_data = ability.passive_effect
			
			# Only include "always on" passives here
			if passive_data.condition_type == "ALWAYS_ON":
				for stat_name in passive_data.stat_modifiers:
					if not modifiers.has(stat_name):
						modifiers[stat_name] = 0
					modifiers[stat_name] += passive_data.stat_modifiers[stat_name].total_value
	
	return modifiers


func _apply_passive_effect(ability: AbilityData) -> void:
	# Only process abilities that have a PassiveEffectData
	if ability.passive_effect:
		# No need to directly modify stats here anymore
		# Just log that we've registered a passive
		print("AbilityComponent: Registered passive effect from: %s" % ability.ability_name)
		
		# Since StatsComponent will now query us for passives during recalculation,
		# we only need to trigger a recalculation
		if _stats_component:
			# Trigger recalculation if this is an "ALWAYS_ON" passive that affects stats immediately
			if ability.passive_effect.condition_type == "ALWAYS_ON":
				if multiplayer.is_server() and _stats_component.has_method("_recalculate_stats_server"):
					_stats_component._recalculate_stats_server("AbilityPassiveAdded")


func use_ability_request(ability_id: String) -> void:
	# 1. Basic Client-Side Checks (For UX/Early Feedback Only)
	#    We check cooldown locally just to prevent spamming the server, 
	#    but the server's check is the only one that matters.
	if _cooldowns.has(ability_id):
		print("Client: Ability is on cooldown (UX check).")
		return
		
	# 2. Request Server Authority
	#    The client sends a message to the server (authority) asking to use the skill.
	rpc_id(multiplayer.get_server_id(), "use_ability_server", ability_id)
	print("Client: Sent RPC request to use ability %s" % ability_id)
	
	
func get_cooldown_remaining(ability_id: String) -> float:
	return _cooldowns.get(ability_id, 0.0)


@rpc("authority", "reliable")
func use_ability_server(ability_id: String) -> void:
	# IMPORTANT: Ensure the caller is authorized!
	var sender_id = multiplayer.get_rpc_sender_id()
	if sender_id != get_parent().multiplayer.get_authority():
		# This check confirms the character whose component this is 
		# is the character that the player is controlling.
		print("Server: WARNING! Unauthorized ability use attempt by ID %d" % sender_id)
		return

	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability or not ability.active_behavior:
		print("Server: Invalid ability attempt: %s" % ability_id)
		return

	var active_data = ability.active_behavior
	
	# 1. Authoritative Checks (The REAL checks)
	if _cooldowns.has(ability_id):
		print("Server: Cooldown check failed for %s." % ability.ability_name)
		return
	
	if _stats_component.current_mana < active_data.mana_cost:
		print("Server: Mana check failed for %s." % ability.ability_name)
		return
		
	# 2. Authoritative Success: Apply Changes and Notify
	
	# Deduct cost and start cooldown (ON THE SERVER)
	_stats_component.current_mana -= active_data.mana_cost
	_cooldowns[ability_id] = active_data.cooldown_time
	
	# Execute the game logic (Damage, effects, etc.)
	_execute_active_ability(ability) 
	
	# 3. Notify all relevant clients of the result
	#    Call the client RPC method on *all* peers to synchronize the result.
	rpc("ability_used_client", ability_id, active_data.cooldown_time)


@rpc("any_peer", "reliable")
func ability_used_client(ability_id: String, cooldown_time: float) -> void:
	# 1. Update the local state (cooldowns, visuals) based on the server's word.
	_cooldowns[ability_id] = cooldown_time # Server's cooldown is final
	
	# 2. Trigger Client Visuals and UI
	ability_used.emit(ability_id)
	cooldown_started.emit(ability_id, cooldown_time)
	
	# 3. Handle Client-Side VFX/SFX
	_play_vfx_sfx(ability_id)
	
	print("Client: Synchronized skill use and started cooldown for %s." % ability_id)


func _play_vfx_sfx(ability_id: String):
	# This is a client-side function to play the attack animation, sound, etc.
	var ability = ResourceManager.get_ability_data(ability_id)
	if ability and ability.active_behavior:
		# e.g., Play an animation on the character node
		# get_parent().get_node("Visuals").play_animation(ability.active_behavior.animation_name)
		pass
