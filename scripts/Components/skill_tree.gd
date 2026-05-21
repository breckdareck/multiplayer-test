class_name SkillTreeComponent
extends Node

## Per-player skill tree progression.
##
## Tracks which nodes the player has unlocked in their class tree and how many
## skill points they have available. Server-authoritative: clients send an
## "unlock node" intent via RPC; the server validates prerequisites, the level
## requirement and available points, then unlocks the node and grants the
## referenced ability through the AbilityComponent.
##
## Skill points are earned on level-up (separately from the AbilityComponent's
## own ability points — this keeps the tree progression independent of the
## legacy free-form ability leveling).
##
## Lives under the player's Components node alongside Ability, Class, Leveling.


#region #################### Signals ####################
signal node_unlocked(node_id: String)
signal skill_points_changed(new_total: int)
## Emitted after any change so UI can do a full refresh.
signal tree_state_changed()
#endregion


#region #################### Configuration ####################
## Skill points granted to the player on each level-up.
const SKILL_POINTS_PER_LEVEL: int = 1
#endregion


#region #################### Member Variables ####################
var _class_component: ClassComponent
var _ability_component: AbilityComponent
var _level_component: LevelingComponent

# State
var _unlocked_nodes: Dictionary = {}      # { node_id: true }
var _available_skill_points: int = 0
# Tracks the highest level for which skill points have already been granted,
# so retroactive grants on load award exactly the right amount.
var _last_rewarded_level: int = 1
var _loading_mode: bool = false

# Simple client-side rate limit for unlock requests.
const MAX_UNLOCK_REQUESTS_PER_SECOND: int = 10
var _unlock_request_times: Array[float] = []
#endregion


#region #################### Godot Engine Callbacks ####################
func _ready() -> void:
	_class_component = get_parent().get_node_or_null("Class")
	_ability_component = get_parent().get_node_or_null("Ability")
	_level_component = get_parent().get_node_or_null("Leveling")

	if not _class_component or not _ability_component:
		push_error("SkillTreeComponent requires ClassComponent and AbilityComponent siblings.")
		return

	# Grant skill points on level up (server only — clients receive a sync RPC).
	if _level_component and multiplayer.is_server():
		_level_component.leveled_up.connect(_on_leveled_up)
	elif not _level_component:
		push_warning("SkillTreeComponent: No LevelingComponent found. Skill points won't be granted on level up.")
#endregion


#region #################### Public API ####################
## Returns the SkillTreeData for the player's current class, or null.
func get_tree_data() -> SkillTreeData:
	if not _class_component:
		return null
	return SkillTreeManager.get_tree_for_class(_class_component.current_class)


## Attempts to unlock a node. On a client this forwards an intent RPC to the
## server; on the server (or in single-player) it runs the authoritative path.
func unlock_node(node_id: String) -> bool:
	if _is_multiplayer_client():
		request_unlock_node.rpc_id(1, node_id)
		return true
	return _unlock_node_local(node_id)


func is_node_unlocked(node_id: String) -> bool:
	return _unlocked_nodes.get(node_id, false)


func get_available_skill_points() -> int:
	return _available_skill_points


## Returns the unlock state of a node for UI display:
## "unlocked", "available" (eligible and affordable), "eligible" (prereqs met
## but not enough points / level), or "locked" (prerequisites unmet).
func get_node_state(node_id: String) -> String:
	if is_node_unlocked(node_id):
		return "unlocked"

	var tree := get_tree_data()
	if not tree:
		return "locked"
	var node := tree.get_node_by_id(node_id)
	if not node:
		return "locked"

	if not _prerequisites_met(node):
		return "locked"

	var level_ok := _level_requirement_met(node)
	var points_ok := _available_skill_points >= node.skill_point_cost
	if level_ok and points_ok:
		return "available"
	return "eligible"


## True if every requirement (prereqs, level, points) for a node is satisfied.
func can_unlock_node(node_id: String) -> bool:
	return get_node_state(node_id) == "available"
#endregion


#region #################### Validation Helpers ####################
func _is_multiplayer_client() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.is_server()


func _prerequisites_met(node: SkillTreeNodeData) -> bool:
	for prereq_id in node.prerequisite_node_ids:
		if not is_node_unlocked(prereq_id):
			return false
	return true


func _level_requirement_met(node: SkillTreeNodeData) -> bool:
	if node.required_level <= 0:
		return true
	if not _level_component:
		return true
	return _level_component.level >= node.required_level


func _is_unlock_rate_limited() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	while _unlock_request_times.size() > 0 and now - _unlock_request_times[0] > 1.0:
		_unlock_request_times.pop_front()
	if _unlock_request_times.size() >= MAX_UNLOCK_REQUESTS_PER_SECOND:
		return true
	_unlock_request_times.append(now)
	return false
#endregion


#region #################### Authoritative Logic ####################
## The authoritative unlock path. Runs on the server or in single-player.
func _unlock_node_local(node_id: String) -> bool:
	var tree := get_tree_data()
	if not tree:
		push_warning("SkillTreeComponent: No skill tree for this class.")
		return false

	var node := tree.get_node_by_id(node_id)
	if not node:
		push_warning("SkillTreeComponent: Unknown node id '%s'." % node_id)
		return false

	if is_node_unlocked(node_id):
		return false

	# Validate every requirement server-side — never trust the client.
	if not _prerequisites_met(node):
		#print("SkillTreeComponent: Prerequisites not met for '%s'." % node_id)
		return false
	if not _level_requirement_met(node):
		#print("SkillTreeComponent: Level requirement not met for '%s'." % node_id)
		return false
	if _available_skill_points < node.skill_point_cost:
		#print("SkillTreeComponent: Not enough skill points for '%s'." % node_id)
		return false

	# Commit the unlock.
	_available_skill_points -= node.skill_point_cost
	_unlocked_nodes[node_id] = true

	# Grant the referenced ability through the AbilityComponent.
	_grant_node_ability(node)

	node_unlocked.emit(node_id)
	skill_points_changed.emit(_available_skill_points)
	tree_state_changed.emit()

	# Sync to clients (bots have no UI — skip the node-addressed RPC).
	if multiplayer.is_server() and not BotManager.is_bot(owner.player_id):
		sync_node_unlocked.rpc(node_id, _available_skill_points)

	return true


## Grants the ability referenced by a node. Learns it if unknown, otherwise
## levels it once — both routed through the AbilityComponent so its existing
## passive/UI/sync logic runs unchanged.
func _grant_node_ability(node: SkillTreeNodeData) -> void:
	if node.ability_name.is_empty():
		return
	if not _ability_component:
		return

	var ability := ResourceManager.get_ability_data(node.ability_name)
	if not ability:
		push_warning("SkillTreeComponent: Node '%s' references unknown ability '%s'." % [node.node_id, node.ability_name])
		return

	var current_level: int = _ability_component.get_ability_level(ability.ability_id)
	# Unlocking a node invests exactly one rank: a brand-new ability becomes
	# level 1 (usable), an already-known one is bumped by one. grant_ability_level
	# learns it first if needed and does not consume AbilityComponent points.
	var target_level: int = maxi(current_level + 1, 1)
	_ability_component.grant_ability_level(ability.ability_id, target_level)


func _add_skill_points(amount: int) -> void:
	if amount <= 0:
		return
	_available_skill_points += amount
	skill_points_changed.emit(_available_skill_points)
	tree_state_changed.emit()
	if multiplayer.is_server() and not BotManager.is_bot(owner.player_id):
		sync_skill_points.rpc(_available_skill_points)
#endregion


#region #################### Multiplayer & RPCs ####################
## [Client->Server] Client requests to unlock a node.
@rpc("any_peer", "call_remote", "reliable")
func request_unlock_node(node_id: String) -> void:
	if not multiplayer.is_server():
		return
	if _is_unlock_rate_limited():
		return
	_unlock_node_local(node_id)


## [Server->Client] Confirms a node unlock and the resulting point total.
@rpc("authority", "call_remote", "reliable")
func sync_node_unlocked(node_id: String, remaining_points: int) -> void:
	if multiplayer.is_server():
		return
	_unlocked_nodes[node_id] = true
	_available_skill_points = remaining_points

	# The granted ability itself is synced separately by the AbilityComponent's
	# own sync_ability_* RPCs; here we only update skill-tree bookkeeping.
	node_unlocked.emit(node_id)
	skill_points_changed.emit(_available_skill_points)
	tree_state_changed.emit()


## [Server->Client] Syncs the available skill point total.
@rpc("authority", "call_remote", "reliable")
func sync_skill_points(new_total: int) -> void:
	if multiplayer.is_server():
		return
	_available_skill_points = new_total
	skill_points_changed.emit(_available_skill_points)
	tree_state_changed.emit()


## [Server->Client] Sends the full skill tree state to a newly connected client.
func sync_full_state_to_client(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	sync_full_state.rpc_id(peer_id, _unlocked_nodes.duplicate(), _available_skill_points)


@rpc("authority", "call_remote", "reliable")
func sync_full_state(unlocked: Dictionary, points: int) -> void:
	if multiplayer.is_server():
		return
	_unlocked_nodes = unlocked.duplicate()
	_available_skill_points = points
	skill_points_changed.emit(_available_skill_points)
	tree_state_changed.emit()
#endregion


#region #################### Signal Callbacks ####################
func _on_leveled_up(new_level: int) -> void:
	# Grant points for every level gained since the last reward (handles
	# multi-level jumps as well as the normal single level-up).
	if new_level <= _last_rewarded_level:
		return
	var gained := new_level - _last_rewarded_level
	_last_rewarded_level = new_level
	_add_skill_points(gained * SKILL_POINTS_PER_LEVEL)
#endregion


#region #################### Save & Load ####################
## Returns a dictionary of skill tree state for persistence.
func save_skill_tree() -> Dictionary:
	return {
		"unlocked_nodes": _unlocked_nodes.keys(),
		"available_points": _available_skill_points,
		"last_rewarded_level": _last_rewarded_level,
	}


## Loads skill tree state from a dictionary. Performs a retroactive skill-point
## grant if the player gained levels while the feature did not yet exist (or if
## SKILL_POINTS_PER_LEVEL changed) — older saves simply have no skill data.
func load_skill_tree(data: Dictionary) -> void:
	_unlocked_nodes.clear()
	for node_id in data.get("unlocked_nodes", []):
		_unlocked_nodes[node_id] = true

	_available_skill_points = int(data.get("available_points", 0))
	_last_rewarded_level = int(data.get("last_rewarded_level", 1))

	# Retroactive grant: if the player is already past _last_rewarded_level
	# (e.g. first login after this feature shipped), award the missing points.
	if multiplayer.is_server() and _level_component:
		var current_level: int = _level_component.level
		if current_level > _last_rewarded_level:
			var owed := (current_level - _last_rewarded_level) * SKILL_POINTS_PER_LEVEL
			_last_rewarded_level = current_level
			_available_skill_points += owed
			#print("SkillTreeComponent: Retroactively granted %d skill points." % owed)

	if not _loading_mode:
		skill_points_changed.emit(_available_skill_points)
		for node_id in _unlocked_nodes:
			node_unlocked.emit(node_id)
		tree_state_changed.emit()


func set_loading_mode(enabled: bool) -> void:
	_loading_mode = enabled


## Disconnects from leveling signals to prevent point grants during loading.
func disconnect_level_signals() -> void:
	if _level_component and _level_component.leveled_up.is_connected(_on_leveled_up):
		_level_component.leveled_up.disconnect(_on_leveled_up)


## Reconnects to leveling signals after loading completes.
func reconnect_level_signals() -> void:
	if _level_component and multiplayer.is_server() and not _level_component.leveled_up.is_connected(_on_leveled_up):
		_level_component.leveled_up.connect(_on_leveled_up)
#endregion
