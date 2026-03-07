extends Node

## QuestManager — Server-authoritative quest tracking and progression.
##
## Quests are defined in code via _define_quests(). Player progress is tracked
## per-username on the server side and persisted through the save system.
##
## Chat commands (client-side, routed through ChatManager):
##   /quest list       — show available and active quests
##   /quest accept <id> — accept a quest
##   /quest progress   — show progress on active quests
##   /quest abandon <id> — abandon a quest

# ── Signals ──────────────────────────────────────────────────────────────────
signal quest_accepted(username: String, quest_id: String)
signal quest_completed(username: String, quest_id: String)
signal quest_progress_updated(username: String, quest_id: String)

# ── Quest Registry ──────────────────────────────────────────────────────────
## All quest definitions keyed by quest_id.
var _quests: Dictionary = {}  # quest_id -> QuestData

# ── Per-player State (server only) ──────────────────────────────────────────
## Active quests: username -> { quest_id -> { objective_index -> current_count } }
var _active_quests: Dictionary = {}
## Completed quest IDs: username -> Array[String]
var _completed_quests: Dictionary = {}


func _ready() -> void:
	_define_quests()
	print("QuestManager: Loaded %d quest definitions." % _quests.size())


# ═══════════════════════════════════════════════════════════════════════════
# QUEST DEFINITIONS
# ═══════════════════════════════════════════════════════════════════════════

func _define_quests() -> void:
	# --- Beginner quests (level 1-5) ---
	_add_quest("q_first_blood", "First Blood", "Defeat your first Slime to prove your mettle.", 1, "",
		[{"type": QuestData.ObjectiveType.KILL, "target": "Slime", "amount": 3}],
		50, 10, [])

	_add_quest("q_slime_slayer", "Slime Slayer", "The slimes are multiplying! Thin the herd.", 2, "q_first_blood",
		[{"type": QuestData.ObjectiveType.KILL, "target": "Slime", "amount": 10}],
		150, 30, [])

	_add_quest("q_mushroom_menace", "Mushroom Menace", "The mushrooms in the forest are becoming aggressive. Deal with them.", 3, "",
		[{"type": QuestData.ObjectiveType.KILL, "target": "Mushroom", "amount": 5}],
		100, 20, [])

	# --- Early quests (level 5-10) ---
	_add_quest("q_pest_control", "Pest Control", "Multiple monster species threaten the village. Eliminate them.", 5, "q_slime_slayer",
		[
			{"type": QuestData.ObjectiveType.KILL, "target": "Slime", "amount": 15},
			{"type": QuestData.ObjectiveType.KILL, "target": "Mushroom", "amount": 10},
		],
		300, 50, [])

	_add_quest("q_level_up", "Getting Stronger", "Reach level 5 to unlock new abilities.", 1, "",
		[{"type": QuestData.ObjectiveType.REACH_LEVEL, "target": "", "amount": 5}],
		200, 25, [])

	_add_quest("q_growing_power", "Growing Power", "Continue your training and reach level 10.", 5, "q_level_up",
		[{"type": QuestData.ObjectiveType.REACH_LEVEL, "target": "", "amount": 10}],
		500, 75, [])

	# --- Mid-level quests (level 10-20) ---
	_add_quest("q_deep_woods", "Into the Deep Woods", "Venture deeper and face tougher creatures.", 10, "q_pest_control",
		[{"type": QuestData.ObjectiveType.KILL, "target": "Mushroom", "amount": 25}],
		600, 100, [])

	_add_quest("q_slime_exterminator", "Slime Exterminator", "The slime population is out of control. A massive cull is needed.", 8, "q_slime_slayer",
		[{"type": QuestData.ObjectiveType.KILL, "target": "Slime", "amount": 50}],
		800, 120, [])

	_add_quest("q_seasoned_warrior", "Seasoned Warrior", "Prove your dedication by reaching level 20.", 10, "q_growing_power",
		[{"type": QuestData.ObjectiveType.REACH_LEVEL, "target": "", "amount": 20}],
		1000, 200, [])

	_add_quest("q_collector", "The Collector", "Gather coins from fallen monsters to fund the village defense.", 5, "",
		[{"type": QuestData.ObjectiveType.COLLECT, "target": "Coin", "amount": 100}],
		250, 0, [])


func _add_quest(id: String, qname: String, desc: String, req_level: int, prereq: String,
		objectives: Array, exp: int, coins: int, items: Array) -> void:
	var quest := QuestData.new()
	quest.quest_id = id
	quest.quest_name = qname
	quest.description = desc
	quest.required_level = req_level
	quest.prerequisite_quest_id = prereq
	for obj in objectives:
		quest.objectives.append(obj)
	quest.reward_exp = exp
	quest.reward_coins = coins
	for item_name in items:
		quest.reward_items.append(item_name)
	_quests[id] = quest


# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API — called from ChatManager / game systems
# ═══════════════════════════════════════════════════════════════════════════

func handle_quest_command(args: String, sender_id: int) -> void:
	if not multiplayer.is_server():
		return

	var player_node = PlayerManager.get_player_node(sender_id)
	if not player_node:
		return
	var username: String = player_node.username

	var parts: PackedStringArray = args.strip_edges().split(" ", false, 2)
	if parts.is_empty():
		_send_message(sender_id, "[Quest] Usage: /quest list | accept <id> | progress | abandon <id>", Color.YELLOW)
		return

	match parts[0].to_lower():
		"list":
			_cmd_list(sender_id, username, player_node)
		"accept":
			if parts.size() < 2:
				_send_message(sender_id, "[Quest] Usage: /quest accept <quest_id>", Color.YELLOW)
				return
			_cmd_accept(sender_id, username, player_node, parts[1])
		"progress":
			_cmd_progress(sender_id, username)
		"abandon":
			if parts.size() < 2:
				_send_message(sender_id, "[Quest] Usage: /quest abandon <quest_id>", Color.YELLOW)
				return
			_cmd_abandon(sender_id, username, parts[1])
		_:
			_send_message(sender_id, "[Quest] Unknown subcommand. Use: list, accept, progress, abandon", Color.YELLOW)


# ── List available quests ────────────────────────────────────────────────
func _cmd_list(sender_id: int, username: String, player_node: MultiplayerPlayerV2) -> void:
	var player_level: int = 1
	if is_instance_valid(player_node.level_component):
		player_level = player_node.level_component.level

	var completed: Array = _completed_quests.get(username, [])
	var active: Dictionary = _active_quests.get(username, {})

	var available: Array[QuestData] = []
	for quest_id in _quests:
		if quest_id in completed:
			continue
		if active.has(quest_id):
			continue
		var quest: QuestData = _quests[quest_id]
		if player_level < quest.required_level:
			continue
		if not quest.prerequisite_quest_id.is_empty() and quest.prerequisite_quest_id not in completed:
			continue
		available.append(quest)

	if available.is_empty():
		_send_message(sender_id, "[Quest] No new quests available at your level.", Color.YELLOW)
	else:
		_send_message(sender_id, "[Quest] Available quests:", Color.GOLD)
		for q in available:
			_send_message(sender_id, "  %s — %s (Lv.%d)" % [q.quest_id, q.quest_name, q.required_level], Color.GOLD)

	if not active.is_empty():
		_send_message(sender_id, "[Quest] Active quests:", Color.CYAN)
		for qid in active:
			if _quests.has(qid):
				_send_message(sender_id, "  %s — %s" % [qid, _quests[qid].quest_name], Color.CYAN)


# ── Accept a quest ──────────────────────────────────────────────────────
func _cmd_accept(sender_id: int, username: String, player_node: MultiplayerPlayerV2, quest_id: String) -> void:
	if not _quests.has(quest_id):
		_send_message(sender_id, "[Quest] Quest '%s' not found." % quest_id, Color.RED)
		return

	var quest: QuestData = _quests[quest_id]
	var completed: Array = _completed_quests.get(username, [])
	var active: Dictionary = _active_quests.get(username, {})

	if quest_id in completed:
		_send_message(sender_id, "[Quest] You already completed '%s'." % quest.quest_name, Color.YELLOW)
		return
	if active.has(quest_id):
		_send_message(sender_id, "[Quest] You already have '%s' active." % quest.quest_name, Color.YELLOW)
		return

	var player_level: int = 1
	if is_instance_valid(player_node.level_component):
		player_level = player_node.level_component.level
	if player_level < quest.required_level:
		_send_message(sender_id, "[Quest] You need level %d to accept this quest." % quest.required_level, Color.RED)
		return
	if not quest.prerequisite_quest_id.is_empty() and quest.prerequisite_quest_id not in completed:
		_send_message(sender_id, "[Quest] You must complete '%s' first." % quest.prerequisite_quest_id, Color.RED)
		return

	# Limit active quests
	if active.size() >= 10:
		_send_message(sender_id, "[Quest] You can only have 10 active quests.", Color.RED)
		return

	# Initialize progress for each objective
	if not _active_quests.has(username):
		_active_quests[username] = {}
	var progress: Dictionary = {}
	for i in range(quest.objectives.size()):
		progress[i] = 0
	_active_quests[username][quest_id] = progress

	# Check if any REACH_LEVEL objectives are already met
	_check_level_objectives(username, player_node)

	_send_message(sender_id, "[Quest] Accepted: %s" % quest.quest_name, Color.GREEN)
	_send_message(sender_id, "  %s" % quest.description, Color.GREEN)
	quest_accepted.emit(username, quest_id)
	_save_quest_data(username)


# ── Show progress ───────────────────────────────────────────────────────
func _cmd_progress(sender_id: int, username: String) -> void:
	var active: Dictionary = _active_quests.get(username, {})
	if active.is_empty():
		_send_message(sender_id, "[Quest] No active quests. Use /quest list to find quests.", Color.YELLOW)
		return

	for quest_id in active:
		if not _quests.has(quest_id):
			continue
		var quest: QuestData = _quests[quest_id]
		var progress: Dictionary = active[quest_id]
		_send_message(sender_id, "[Quest] %s:" % quest.quest_name, Color.CYAN)
		for i in range(quest.objectives.size()):
			var obj: Dictionary = quest.objectives[i]
			var current: int = progress.get(i, 0)
			var total: int = obj.get("amount", 1)
			var type_name: String = _objective_type_string(obj.get("type", 0))
			var target: String = obj.get("target", "")
			var label: String = "%s %s" % [type_name, target] if not target.is_empty() else type_name
			var status: String = "DONE" if current >= total else "%d/%d" % [current, total]
			_send_message(sender_id, "  %s: %s" % [label, status], Color.CYAN)


# ── Abandon a quest ─────────────────────────────────────────────────────
func _cmd_abandon(sender_id: int, username: String, quest_id: String) -> void:
	var active: Dictionary = _active_quests.get(username, {})
	if not active.has(quest_id):
		_send_message(sender_id, "[Quest] You don't have quest '%s' active." % quest_id, Color.RED)
		return

	_active_quests[username].erase(quest_id)
	var quest_name: String = _quests[quest_id].quest_name if _quests.has(quest_id) else quest_id
	_send_message(sender_id, "[Quest] Abandoned: %s" % quest_name, Color.ORANGE_RED)
	_save_quest_data(username)


# ═══════════════════════════════════════════════════════════════════════════
# OBJECTIVE TRACKING — called from game systems
# ═══════════════════════════════════════════════════════════════════════════

## Called when a player kills an enemy. Updates KILL objectives.
func record_enemy_kill(username: String, enemy_name: String) -> void:
	if not multiplayer.is_server():
		return
	_advance_objectives(username, QuestData.ObjectiveType.KILL, enemy_name, 1)


## Called when a player picks up / collects items. Updates COLLECT objectives.
func record_item_collected(username: String, item_name: String, amount: int = 1) -> void:
	if not multiplayer.is_server():
		return
	_advance_objectives(username, QuestData.ObjectiveType.COLLECT, item_name, amount)


## Called when a player levels up. Updates REACH_LEVEL objectives.
func record_level_up(username: String, new_level: int) -> void:
	if not multiplayer.is_server():
		return
	var active: Dictionary = _active_quests.get(username, {})
	for quest_id in active.keys():
		if not _quests.has(quest_id):
			continue
		var quest: QuestData = _quests[quest_id]
		var progress: Dictionary = active[quest_id]
		for i in range(quest.objectives.size()):
			var obj: Dictionary = quest.objectives[i]
			if obj.get("type", -1) == QuestData.ObjectiveType.REACH_LEVEL:
				progress[i] = new_level
		_active_quests[username][quest_id] = progress
		_check_quest_completion(username, quest_id)


func _advance_objectives(username: String, obj_type: int, target: String, amount: int) -> void:
	var active: Dictionary = _active_quests.get(username, {})
	if active.is_empty():
		return

	var changed: bool = false
	for quest_id in active.keys():
		if not _quests.has(quest_id):
			continue
		var quest: QuestData = _quests[quest_id]
		var progress: Dictionary = active[quest_id]
		for i in range(quest.objectives.size()):
			var obj: Dictionary = quest.objectives[i]
			if obj.get("type", -1) != obj_type:
				continue
			if obj_type != QuestData.ObjectiveType.REACH_LEVEL and obj.get("target", "") != target:
				continue
			var old_val: int = progress.get(i, 0)
			var max_val: int = obj.get("amount", 1)
			if old_val >= max_val:
				continue  # Already complete
			progress[i] = min(old_val + amount, max_val)
			changed = true
		_active_quests[username][quest_id] = progress
		_check_quest_completion(username, quest_id)

	if changed:
		_save_quest_data(username)


func _check_quest_completion(username: String, quest_id: String) -> void:
	if not _quests.has(quest_id):
		return
	var quest: QuestData = _quests[quest_id]
	var progress: Dictionary = _active_quests.get(username, {}).get(quest_id, {})

	for i in range(quest.objectives.size()):
		var obj: Dictionary = quest.objectives[i]
		if progress.get(i, 0) < obj.get("amount", 1):
			return  # Not all objectives met

	# All objectives complete — grant rewards
	_complete_quest(username, quest_id)


func _complete_quest(username: String, quest_id: String) -> void:
	if not _quests.has(quest_id):
		return
	var quest: QuestData = _quests[quest_id]

	# Move from active to completed
	if _active_quests.has(username):
		_active_quests[username].erase(quest_id)
	if not _completed_quests.has(username):
		_completed_quests[username] = []
	_completed_quests[username].append(quest_id)

	# Find player node for rewards
	var player_node: MultiplayerPlayerV2 = null
	var pid: int = PlayerManager.get_player_id_from_name(username)
	if pid != -1:
		player_node = PlayerManager.get_player_node(pid)

	if not player_node:
		print("QuestManager: Could not find player node for '%s' to grant rewards." % username)
		quest_completed.emit(username, quest_id)
		_save_quest_data(username)
		return

	var sender_id: int = player_node.player_id

	# Grant EXP
	if quest.reward_exp > 0:
		player_node.gain_experience(quest.reward_exp)

	# Grant coins via inventory
	if quest.reward_coins > 0 and is_instance_valid(player_node.inventory_component):
		var coin_item = ResourceManager.get_item_by_name("Coin")
		if coin_item:
			var coin_copy = coin_item.duplicate_with_path()
			coin_copy.current_stack_amount = quest.reward_coins
			player_node.inventory_component.add_item(coin_copy)

	# Grant items
	for item_name in quest.reward_items:
		var item = ResourceManager.get_item_by_name(item_name)
		if item and is_instance_valid(player_node.inventory_component):
			var item_copy = item.duplicate_with_path()
			player_node.inventory_component.add_item(item_copy)

	# Notify player
	_send_message(sender_id, "[Quest] COMPLETED: %s!" % quest.quest_name, Color.GOLD)
	if quest.reward_exp > 0:
		_send_message(sender_id, "  +%d EXP" % quest.reward_exp, Color.GREEN)
	if quest.reward_coins > 0:
		_send_message(sender_id, "  +%d Coins" % quest.reward_coins, Color.GREEN)
	for item_name in quest.reward_items:
		_send_message(sender_id, "  +%s" % item_name, Color.GREEN)

	quest_completed.emit(username, quest_id)
	_save_quest_data(username)


func _check_level_objectives(username: String, player_node: MultiplayerPlayerV2) -> void:
	if not is_instance_valid(player_node) or not is_instance_valid(player_node.level_component):
		return
	var current_level: int = player_node.level_component.level
	record_level_up(username, current_level)


# ═══════════════════════════════════════════════════════════════════════════
# SAVE / LOAD — integrated with player save data
# ═══════════════════════════════════════════════════════════════════════════

func save_quests(username: String) -> Dictionary:
	return {
		"active": _active_quests.get(username, {}),
		"completed": _completed_quests.get(username, []),
	}


func load_quests(username: String, data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var active_data = data.get("active", {})
	var completed_data = data.get("completed", [])

	# Convert loaded data to proper types
	var active: Dictionary = {}
	for quest_id in active_data:
		var progress: Dictionary = {}
		var raw_progress = active_data[quest_id]
		if raw_progress is Dictionary:
			for key in raw_progress:
				progress[int(key)] = int(raw_progress[key])
		active[quest_id] = progress

	var completed: Array = []
	for qid in completed_data:
		completed.append(str(qid))

	_active_quests[username] = active
	_completed_quests[username] = completed
	print("QuestManager: Loaded quest data for '%s' — %d active, %d completed." % [username, active.size(), completed.size()])


func unregister_player(username: String) -> void:
	# Keep data in memory — it's persisted through save system.
	# Only clean up if needed to free memory on large servers.
	pass


func _save_quest_data(username: String) -> void:
	# Trigger a save through the player's normal save flow
	var pid: int = PlayerManager.get_player_id_from_name(username)
	if pid != -1:
		var pn = PlayerManager.get_player_node(pid)
		if pn and SaveManager:
			SaveManager.queue_save(username, "all", pn)


# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _send_message(peer_id: int, text: String, color: Color) -> void:
	_client_receive_quest_message.rpc_id(peer_id, text, color)


@rpc("authority", "call_local", "reliable")
func _client_receive_quest_message(text: String, color: Color) -> void:
	ChatManager.add_system_message(text, color)


func _objective_type_string(type: int) -> String:
	match type:
		QuestData.ObjectiveType.KILL:
			return "Kill"
		QuestData.ObjectiveType.COLLECT:
			return "Collect"
		QuestData.ObjectiveType.REACH_LEVEL:
			return "Reach Level"
		_:
			return "Unknown"


func get_quest_data(quest_id: String) -> QuestData:
	return _quests.get(quest_id)
