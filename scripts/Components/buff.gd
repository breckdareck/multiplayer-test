class_name BuffComponent
extends Node

## Manages temporary and permanent buffs/debuffs on a character.
## Integrates with StatsComponent for stat modifications and supports custom logic.

#region #################### Signals ####################
signal buff_applied(buff_id: String, duration: float)
signal buff_removed(buff_id: String)
signal buff_refreshed(buff_id: String, new_duration: float)
#endregion

#region #################### Active Buff Tracking ####################
class ActiveBuff:
	var buff_data: BuffData
	var stacks: int = 1
	var remaining_duration: float = 0.0
	var source_node: Node = null  # Who applied this buff
	var custom_logic_instance: Node = null  # For buffs with custom scripts
	
	func _init(data: BuffData, src: Node = null):
		buff_data = data
		source_node = src
		remaining_duration = data.duration
		
		# Instantiate custom logic if the buff has a script
		if data.logic_script:
			custom_logic_instance = data.logic_script.new()
#endregion

#region #################### Member Variables ####################
var _active_buffs: Dictionary = {}  # buff_id -> ActiveBuff
var _stats_component: StatsComponent
var _health_component: HealthComponent
var _combat_component: CombatComponent

var _loading_mode: bool = false
#endregion

#region #################### Godot Engine Callbacks ####################
func _ready() -> void:
	_stats_component = get_parent().get_node_or_null("Stats")
	_health_component = get_parent().get_node_or_null("Health")
	_combat_component = get_parent().get_node_or_null("Combat")
	
	if not _stats_component:
		push_error("BuffComponent requires StatsComponent sibling.")
		set_process(false)
		return
	
	# Listen for damage events to trigger reactive buffs like Power Guard
	if _health_component and multiplayer.is_server():
		_health_component.damaged.connect(_on_damaged)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
		
	var expired_buffs: Array[String] = []
	
	for buff_id in _active_buffs:
		var active_buff: ActiveBuff = _active_buffs[buff_id]
		
		# Skip permanent buffs
		if active_buff.buff_data.duration <= 0:
			continue
			
		active_buff.remaining_duration -= delta
		
		# Tick custom logic if available
		if active_buff.custom_logic_instance and active_buff.custom_logic_instance.has_method("on_tick"):
			active_buff.custom_logic_instance.on_tick(owner, active_buff, delta)
		
		if active_buff.remaining_duration <= 0:
			expired_buffs.append(buff_id)
	
	# Remove expired buffs
	for buff_id in expired_buffs:
		remove_buff(buff_id)
#endregion

#region #################### Public API ####################
## Applies a buff to this character
func apply_buff(buff_id: String, source: Node = null, custom_duration: float = -1.0) -> bool:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		apply_buff_request.rpc_id(1, buff_id, source.get_path() if source else NodePath(), custom_duration)
		return true
	
	return _apply_buff_local(buff_id, source, custom_duration)


## Removes a buff from this character
func remove_buff(buff_id: String) -> bool:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		remove_buff_request.rpc_id(1, buff_id)
		return true
		
	return _remove_buff_local(buff_id)


## Checks if a specific buff is active
func has_buff(buff_id: String) -> bool:
	return _active_buffs.has(buff_id)


## Gets the remaining duration of a buff
func get_buff_duration(buff_id: String) -> float:
	if not _active_buffs.has(buff_id):
		return 0.0
	return _active_buffs[buff_id].remaining_duration


## Gets the stack count of a buff
func get_buff_stacks(buff_id: String) -> int:
	if not _active_buffs.has(buff_id):
		return 0
	return _active_buffs[buff_id].stacks


## Returns all active buff IDs
func get_active_buff_ids() -> Array[String]:
	var ids: Array[String] = []
	for buff_id in _active_buffs:
		ids.append(buff_id)
	return ids
#endregion

#region #################### Internal Logic ####################
func _apply_buff_local(buff_id: String, source: Node = null, custom_duration: float = -1.0) -> bool:
	var buff_data: BuffData = ResourceManager.get_buff_data(buff_id)
	if not buff_data:
		printerr("Buff ID '%s' not found." % buff_id)
		return false
	
	# Use custom duration if provided, otherwise use buff_data duration
	var duration = custom_duration if custom_duration >= 0.0 else buff_data.duration
	
	# Check if buff already exists
	if _active_buffs.has(buff_id):
		return _handle_existing_buff(buff_id, buff_data, source, duration)
	
	# Create new active buff
	var active_buff := ActiveBuff.new(buff_data, source)
	active_buff.remaining_duration = duration
	_active_buffs[buff_id] = active_buff
	
	# Call custom logic on_apply if available
	if active_buff.custom_logic_instance and active_buff.custom_logic_instance.has_method("on_apply"):
		active_buff.custom_logic_instance.on_apply(owner, active_buff)
	
	# Trigger stat recalculation to apply stat modifiers
	if not _loading_mode:
		_force_stat_recalc()
	
	# Emit signal and sync to clients
	buff_applied.emit(buff_id, duration)
	print("Applied buff: %s (duration: %.1fs)" % [buff_data.buff_name, duration])
	
	if multiplayer.is_server():
		sync_buff_applied.rpc(buff_id, duration)
	
	return true


func _handle_existing_buff(buff_id: String, buff_data: BuffData, source: Node, duration: float = -1.0) -> bool:
	var active_buff: ActiveBuff = _active_buffs[buff_id]
	
	# Use custom duration if provided, otherwise use buff_data duration
	var new_duration = duration if duration >= 0.0 else buff_data.duration
	
	match buff_data.stack_behavior:
		BuffData.StackBehavior.REFRESH:
			# Reset duration to new duration
			active_buff.remaining_duration = new_duration
			
			_force_stat_recalc()
					
			buff_refreshed.emit(buff_id, new_duration)
			
			if multiplayer.is_server():
				sync_buff_refreshed.rpc(buff_id, new_duration)
			
		BuffData.StackBehavior.STACK:
			# Increase stack count up to max
			if active_buff.stacks < buff_data.max_stacks:
				active_buff.stacks += 1
				active_buff.remaining_duration = new_duration
				
				_force_stat_recalc()
				
				buff_refreshed.emit(buff_id, new_duration)
				
				if multiplayer.is_server():
					sync_buff_stacks.rpc(buff_id, active_buff.stacks, new_duration)
			else:
				# At max stacks, just refresh
				active_buff.remaining_duration = new_duration
				
		BuffData.StackBehavior.IGNORE:
			# Do nothing, keep existing buff running
			pass
	
	return true


func _remove_buff_local(buff_id: String) -> bool:
	if not _active_buffs.has(buff_id):
		return false
	
	var active_buff: ActiveBuff = _active_buffs[buff_id]
	
	# Call custom logic on_remove if available
	if active_buff.custom_logic_instance and active_buff.custom_logic_instance.has_method("on_remove"):
		active_buff.custom_logic_instance.on_remove(owner, active_buff)
	
	# Clean up custom logic instance
	if active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.queue_free()
	
	_active_buffs.erase(buff_id)
	
	# Trigger stat recalculation to remove stat modifiers
	if not _loading_mode:
		_force_stat_recalc()
	
	# Emit signal and sync to clients
	buff_removed.emit(buff_id)
	print("Removed buff: %s" % buff_id)
	
	if multiplayer.is_server():
		sync_buff_removed.rpc(buff_id)
	
	return true


## Returns all stat modifiers from active buffs (called by StatsComponent)
func get_buff_stat_modifiers() -> Dictionary:
	var modifiers: Dictionary = {}
	
	for buff_id in _active_buffs:
		var active_buff: ActiveBuff = _active_buffs[buff_id]
		var buff_data: BuffData = active_buff.buff_data
		
		# Multiply stat bonuses by stack count
		for stat_type in buff_data.stat_modifiers:
			if not modifiers.has(stat_type):
				modifiers[stat_type] = StatData.new(stat_type, 0)
			
			var buff_stat: StatData = buff_data.stat_modifiers[stat_type]
			modifiers[stat_type].flat_bonus_value += buff_stat.flat_bonus_value * active_buff.stacks
			modifiers[stat_type].percent_bonus_value += buff_stat.percent_bonus_value * active_buff.stacks
	
	return modifiers


func _force_stat_recalc() -> void:
	if _stats_component and multiplayer.is_server():
		_stats_component.mark_stats_dirty()


func _on_damaged(amount: int, source: Node) -> void:
	# Trigger reactive buff logic (like Power Guard)
	for buff_id in _active_buffs:
		var active_buff: ActiveBuff = _active_buffs[buff_id]
		
		if active_buff.custom_logic_instance and active_buff.custom_logic_instance.has_method("on_damaged"):
			active_buff.custom_logic_instance.on_damaged(owner, active_buff, amount, source)
#endregion

#region #################### Multiplayer & RPCs ####################
@rpc("any_peer", "call_local", "reliable")
func apply_buff_request(buff_id: String, source_path: NodePath, custom_duration: float = -1.0) -> void:
	if not multiplayer.is_server():
		return
		
	var source_node = get_node_or_null(source_path) if source_path else null
	_apply_buff_local(buff_id, source_node, custom_duration)


@rpc("any_peer", "call_local", "reliable")
func remove_buff_request(buff_id: String) -> void:
	if not multiplayer.is_server():
		return
		
	_remove_buff_local(buff_id)


@rpc("authority", "call_local", "reliable")
func sync_buff_applied(buff_id: String, duration: float) -> void:
	if multiplayer.is_server():
		return
		
	var buff_data: BuffData = ResourceManager.get_buff_data(buff_id)
	if not buff_data:
		return
	
	var active_buff := ActiveBuff.new(buff_data, null)
	active_buff.remaining_duration = duration
	_active_buffs[buff_id] = active_buff
	
	buff_applied.emit(buff_id, duration)


@rpc("authority", "call_local", "reliable")
func sync_buff_removed(buff_id: String) -> void:
	if multiplayer.is_server():
		return
		
	if _active_buffs.has(buff_id):
		var active_buff: ActiveBuff = _active_buffs[buff_id]
		if active_buff.custom_logic_instance:
			active_buff.custom_logic_instance.queue_free()
		_active_buffs.erase(buff_id)
		buff_removed.emit(buff_id)


@rpc("authority", "call_local", "reliable")
func sync_buff_refreshed(buff_id: String, new_duration: float) -> void:
	if multiplayer.is_server():
		return
		
	if _active_buffs.has(buff_id):
		_active_buffs[buff_id].remaining_duration = new_duration
		buff_refreshed.emit(buff_id, new_duration)


@rpc("authority", "call_local", "reliable")
func sync_buff_stacks(buff_id: String, new_stacks: int, new_duration: float) -> void:
	if multiplayer.is_server():
		return
		
	if _active_buffs.has(buff_id):
		_active_buffs[buff_id].stacks = new_stacks
		_active_buffs[buff_id].remaining_duration = new_duration
		buff_refreshed.emit(buff_id, new_duration)


## [Server->Client] Sends all buff data to a newly connected client
func sync_all_buffs_to_client(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	print("Syncing all buff data to peer %d" % peer_id)
	for buff_id in _active_buffs:
		var active_buff: ActiveBuff = _active_buffs[buff_id]
		sync_buff_with_stacks.rpc_id(peer_id, buff_id, active_buff.stacks, active_buff.remaining_duration)


@rpc("authority", "call_local", "reliable")
func sync_buff_with_stacks(buff_id: String, stacks: int, duration: float) -> void:
	if multiplayer.is_server():
		return
		
	var buff_data: BuffData = ResourceManager.get_buff_data(buff_id)
	if not buff_data:
		return
	
	var active_buff := ActiveBuff.new(buff_data, null)
	active_buff.stacks = stacks
	active_buff.remaining_duration = duration
	_active_buffs[buff_id] = active_buff
	
	buff_applied.emit(buff_id, duration)
#endregion

#region #################### Save & Load System ####################
func save_buffs() -> Dictionary:
	var buff_data: Array = []
	
	for buff_id in _active_buffs:
		var active_buff: ActiveBuff = _active_buffs[buff_id]
		buff_data.append({
			"buff_id": buff_id,
			"stacks": active_buff.stacks,
			"remaining_duration": active_buff.remaining_duration
		})
	
	return {
		"active_buffs": buff_data
	}


func load_buffs(data: Dictionary) -> void:
	if data.is_empty():
		return
	
	_loading_mode = true
	
	# Clear existing buffs without triggering stat recalc
	for buff_id in _active_buffs.keys():
		var active_buff: ActiveBuff = _active_buffs[buff_id]
		if active_buff.custom_logic_instance:
			active_buff.custom_logic_instance.queue_free()
	_active_buffs.clear()
	
	# Load saved buffs
	var buff_data: Array = data.get("active_buffs", [])
	for buff_entry in buff_data:
		var buff_id: String = buff_entry.get("buff_id", "")
		var stacks: int = buff_entry.get("stacks", 1)
		var duration: float = buff_entry.get("remaining_duration", 0.0)
		
		var buff_resource: BuffData = ResourceManager.get_buff_data(buff_id)
		if buff_resource:
			var active_buff := ActiveBuff.new(buff_resource, null)
			active_buff.stacks = stacks
			active_buff.remaining_duration = duration
			_active_buffs[buff_id] = active_buff

			# Skip on_apply during load — we are restoring persisted state,
			# not freshly applying a buff. on_apply callbacks may trigger
			# side effects (damage, heals, signals) that are inappropriate
			# during the load phase. Stat modifiers are handled by the
			# _force_stat_recalc() call after all buffs are loaded.
	
	_loading_mode = false
	
	# Single stat recalc after loading all buffs
	_force_stat_recalc()


func set_loading_mode(enabled: bool) -> void:
	_loading_mode = enabled
#endregion
