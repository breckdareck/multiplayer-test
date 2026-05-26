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
@warning_ignore("unused_signal")
signal quest_progress_updated(username: String, quest_id: String)
signal quest_ui_data_received(data: Dictionary)  # Emitted on client when server sends UI data

# ── Quest Registry ──────────────────────────────────────────────────────────
## All quest definitions keyed by quest_id.
var _quests: Dictionary = {}  # quest_id -> QuestData

## The starter quest auto-granted to brand-new characters during onboarding.
const ONBOARDING_QUEST_ID: String = "q_first_blood"

## Maximum number of quests the player can pin to their on-screen Quest Tracker.
## Mirrors QuestTracker.MAX_TRACKED — keep the two constants in sync.
const MAX_TRACKED_QUESTS: int = 5

# ── Per-player State (server only) ──────────────────────────────────────────
## Active quests: username -> { quest_id -> { objective_index -> current_count } }
var _active_quests: Dictionary = {}
## Completed quest IDs: username -> Array[String]
var _completed_quests: Dictionary = {}
## Quest IDs the player has pinned to their on-screen tracker.
## username -> Array[String]. Capped at MAX_TRACKED_QUESTS.
var _tracked_quests: Dictionary = {}
## Whether the onboarding flow has already run for a username. Persisted with
## quest data so it survives logout — a "no save data" check is unreliable
## because the backend creates a save row at character creation.
var _onboarded: Dictionary = {}


## Folder that the auto-loader recursively scans for QuestData .tres files at
## QuestManager._ready(). Mirrors the ResourceManager pattern for abilities,
## items, buffs, and classes. Subfolders are allowed (and used — see
## resources/Quests/Beginner/, /Early/, /Mid/, /Advancement/, /EndlessHunt/,
## /SlimeThreat/) — the scanner descends into them.
const QUESTS_DIR: String = "res://resources/Quests/"


func _ready() -> void:
	_load_quests_from_resources()
	#print("QuestManager: Loaded %d quest definitions." % _quests.size())


# ═══════════════════════════════════════════════════════════════════════════
# QUEST DEFINITIONS — loaded from .tres files in res://resources/Quests/
# ═══════════════════════════════════════════════════════════════════════════
#
# Each quest lives in its own .tres file. Quest IDs are stable strings (not
# auto-generated UUIDs) because player save data persists references to them
# in `_active_quests`, `_completed_quests`, and `_tracked_quests`, and scene
# files (town.tscn, game.tscn) bake quest IDs into NPC `offered_quest_ids`.
# Renaming a quest_id is a breaking change.
#
# To add a quest: drop a new .tres under res://resources/Quests/<chain>/,
# fill in the QuestData fields (use a unique quest_id, set sort_order to
# control its position in the Q-window's Available tab), and reload the
# editor. No code change required.

func _load_quests_from_resources() -> void:
	var loaded: Array[QuestData] = []
	_scan_quests_recursive(QUESTS_DIR, loaded)
	# Sort by `sort_order` so curated narrative order survives the move from
	# `_define_quests()` (insertion order) to scanning files off disk
	# (filesystem/alphabetical order). Dictionary preserves insertion order
	# in GDScript, so inserting in sorted order is sufficient.
	loaded.sort_custom(func(a: QuestData, b: QuestData) -> bool:
		return a.sort_order < b.sort_order)
	for q in loaded:
		if q.quest_id.is_empty():
			push_warning("QuestManager: skipping quest with empty quest_id (file: %s)" % q.resource_path)
			continue
		if _quests.has(q.quest_id):
			push_warning("QuestManager: duplicate quest_id '%s' — '%s' overwrites '%s'" % [
				q.quest_id, q.resource_path, _quests[q.quest_id].resource_path
			])
		_quests[q.quest_id] = q


## Walk QUESTS_DIR (and any subfolders) for QuestData .tres files. Mirrors
## ResourceManager._load_resources_recursively but specialized to QuestData
## so we get the type guard for free.
func _scan_quests_recursive(path: String, into: Array[QuestData]) -> void:
	var items: PackedStringArray = ResourceLoader.list_directory(path)
	for item_name in items:
		var full_path: String = path + item_name
		if item_name.ends_with("/"):
			_scan_quests_recursive(full_path, into)
		elif full_path.ends_with(".tres") or full_path.ends_with(".res"):
			var resource: Resource = ResourceLoader.load(full_path)
			if resource is QuestData:
				into.append(resource)


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
		_send_message(sender_id, "[Quest] Usage: /quest list | accept <id> | progress | abandon <id> | track <id>", Color.YELLOW)
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
		"track":
			if parts.size() < 2:
				_send_message(sender_id, "[Quest] Usage: /quest track <quest_id>", Color.YELLOW)
				return
			_cmd_toggle_track(sender_id, username, parts[1])
		_:
			_send_message(sender_id, "[Quest] Unknown subcommand. Use: list, accept, progress, abandon, track", Color.YELLOW)


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

	# Auto-pin to the tracker if there's room — saves the player a click on the
	# common case where they only have a handful of active quests.
	var tracked: Array = _tracked_quests.get(username, [])
	if quest_id not in tracked and tracked.size() < MAX_TRACKED_QUESTS:
		tracked.append(quest_id)
		_tracked_quests[username] = tracked

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
	_untrack_quest(username, quest_id)
	var quest_name: String = _quests[quest_id].quest_name if _quests.has(quest_id) else quest_id
	_send_message(sender_id, "[Quest] Abandoned: %s" % quest_name, Color.ORANGE_RED)
	_save_quest_data(username)


# ── Track / untrack a quest ─────────────────────────────────────────────
func _cmd_toggle_track(sender_id: int, username: String, quest_id: String) -> void:
	var active: Dictionary = _active_quests.get(username, {})
	if not active.has(quest_id):
		_send_message(sender_id, "[Quest] Only active quests can be tracked.", Color.RED)
		return

	var tracked: Array = _tracked_quests.get(username, [])
	var qname: String = _quests[quest_id].quest_name if _quests.has(quest_id) else quest_id
	if quest_id in tracked:
		tracked.erase(quest_id)
		_send_message(sender_id, "[Quest] Untracked: %s" % qname, Color.YELLOW)
	else:
		if tracked.size() >= MAX_TRACKED_QUESTS:
			_send_message(sender_id, "[Quest] You can only track %d quests at a time." % MAX_TRACKED_QUESTS, Color.RED)
			return
		tracked.append(quest_id)
		_send_message(sender_id, "[Quest] Tracking: %s" % qname, Color.GREEN)

	_tracked_quests[username] = tracked
	_save_quest_data(username)
	_push_quest_ui_update(username)


## Quietly remove a quest from the tracker — used when it ends (abandon/complete).
func _untrack_quest(username: String, quest_id: String) -> void:
	if not _tracked_quests.has(username):
		return
	_tracked_quests[username].erase(quest_id)


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
	# Snapshot the keys: _check_quest_completion can grant EXP that triggers
	# another level-up, which re-enters this function and may erase entries
	# we haven't visited yet. The .has() guard inside the loop catches that.
	for quest_id in active.keys():
		if not _quests.has(quest_id):
			continue
		if not active.has(quest_id):
			continue  # erased by a re-entrant completion
		var quest: QuestData = _quests[quest_id]
		var progress: Dictionary = active[quest_id]
		for i in range(quest.objectives.size()):
			var obj: Dictionary = quest.objectives[i]
			if obj.get("type", -1) == QuestData.ObjectiveType.REACH_LEVEL:
				progress[i] = new_level
		_active_quests[username][quest_id] = progress
		_check_quest_completion(username, quest_id)
	_push_quest_ui_update(username)


## Called by PlayerManager on every spawn. Idempotent: only fires once per
## character, gated on a persisted `_onboarded` flag so it survives the fact
## that the backend creates a save row at character creation (which would
## otherwise make "no save data" never true for a real new character).
func start_onboarding(username: String) -> void:
	if not multiplayer.is_server():
		return
	var pid: int = PlayerManager.get_player_id_from_name(username)
	if pid == -1 or BotManager.is_bot(pid):
		return
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(pid)
	if not is_instance_valid(player_node):
		return

	if not _onboarded.get(username, false):
		# Pre-existing characters (created before quest persistence shipped) come
		# back with no saved quest blob and `_onboarded == false` even though
		# they've clearly played. Use level / experience as a "has played before"
		# signal and mark them onboarded silently — otherwise they get the
		# welcome speech and the auto-granted First Blood quest on every login.
		if _has_played_before(player_node):
			_onboarded[username] = true
			_save_quest_data(username)
		else:
			# Mark before sending anything so a duplicate call (e.g. a race on map
			# change) can't fire the welcome twice.
			_onboarded[username] = true

			_send_message(pid, "Welcome, %s!" % username, Color.GOLD)
			_send_message(pid, "Move with A/D or the arrow keys, jump with Space, and attack with Ctrl.", Color.WHITE)
			_send_message(pid, "Press Q to open your Quest Log. Step into a glowing portal and interact to travel between areas.", Color.WHITE)
			_send_message(pid, "Reach level 30 to unlock Job Advancement. Your journey begins now:", Color.WHITE)

			# Auto-accept the starter quest so a new player always has a goal.
			var completed: Array = _completed_quests.get(username, [])
			var active: Dictionary = _active_quests.get(username, {})
			if _quests.has(ONBOARDING_QUEST_ID) and ONBOARDING_QUEST_ID not in completed and not active.has(ONBOARDING_QUEST_ID):
				_cmd_accept(pid, username, player_node, ONBOARDING_QUEST_ID)
			# Ensure the onboarded flag persists even if _cmd_accept was a no-op above.
			_save_quest_data(username)

			# Trigger the client-side WelcomeOverlay (full-screen tutorial card).
			# Sits alongside the chat messages — the overlay is the primary
			# read-this-now surface; the chat lines remain as scroll-back.
			_show_welcome_overlay.rpc_id(pid)

	# Push the current snapshot to the freshly-spawned client so the tracker
	# populates without waiting on its retry timer. Runs even for returning
	# players (the onboarding block above is gated, this is not).
	_push_quest_ui_update(username)


## Called on a genuine level-up when the player reaches the advancement level.
## Nudges them toward the /advance command.
func notify_advancement_available(username: String) -> void:
	if not multiplayer.is_server():
		return
	var pid: int = PlayerManager.get_player_id_from_name(username)
	if pid == -1 or BotManager.is_bot(pid):
		return
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(pid)
	if not is_instance_valid(player_node):
		return
	if not JobAdvancementManager.can_advance(player_node):
		return
	_send_message(pid, "You have reached Level 30 — you are ready for Job Advancement!", Color.GOLD)
	_send_message(pid, "Type /advance to choose your specialized class.", Color.GOLD)


func _advance_objectives(username: String, obj_type: int, target: String, amount: int) -> void:
	var active: Dictionary = _active_quests.get(username, {})
	if active.is_empty():
		return

	var changed: bool = false
	# Snapshot the keys: _check_quest_completion can grant EXP that triggers
	# a level-up, which calls record_level_up and may erase entries we haven't
	# visited yet. The .has() guard inside the loop catches that.
	for quest_id in active.keys():
		if not _quests.has(quest_id):
			continue
		if not active.has(quest_id):
			continue  # erased by a re-entrant completion
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
		_push_quest_ui_update(username)


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
	_untrack_quest(username, quest_id)
	if not _completed_quests.has(username):
		_completed_quests[username] = []
	_completed_quests[username].append(quest_id)

	# Find player node for rewards
	var player_node: MultiplayerPlayerV2 = null
	var pid: int = PlayerManager.get_player_id_from_name(username)
	if pid != -1:
		player_node = PlayerManager.get_player_node(pid)

	if not player_node:
		#print("QuestManager: Could not find player node for '%s' to grant rewards." % username)
		quest_completed.emit(username, quest_id)
		_save_quest_data(username)
		return

	var sender_id: int = player_node.player_id

	# Grant EXP
	if quest.reward_exp > 0:
		player_node.gain_experience(quest.reward_exp)

	# Grant coins via inventory
	if quest.reward_coins > 0 and is_instance_valid(player_node.inventory_component):
		player_node.player_inventory.monies_amount += quest.reward_coins

	# Grant items. InventoryComponent.add_item takes an item id/name string and
	# resolves + duplicates internally via ResourceManager.get_item_data.
	for item_name in quest.reward_items:
		if not is_instance_valid(player_node.inventory_component):
			break
		if ResourceManager.get_item_by_name(item_name) == null:
			push_warning("QuestManager: reward item '%s' not found for quest '%s'." % [item_name, quest_id])
			continue
		player_node.inventory_component.add_item(item_name)

	# Single concise chat line for scroll-back history; the QuestRewardPopup
	# below is the read-this-now surface.
	var summary_parts := PackedStringArray()
	if quest.reward_exp > 0:
		summary_parts.append("%d EXP" % quest.reward_exp)
	if quest.reward_coins > 0:
		summary_parts.append("%d Coins" % quest.reward_coins)
	for item_name in quest.reward_items:
		summary_parts.append(str(item_name))
	var summary: String = ""
	if summary_parts.size() > 0:
		summary = " (+%s)" % ", ".join(summary_parts)
	_send_message(sender_id, "[Quest] Completed: %s%s" % [quest.quest_name, summary], Color.GOLD)

	# Showcase popup on the player's HUD.
	_show_quest_reward_popup.rpc_id(sender_id, quest.quest_name, quest.reward_exp, quest.reward_coins, quest.reward_items)

	# Guide the player toward whatever this completion just unlocked.
	_notify_newly_available(username, quest_id, player_node)

	quest_completed.emit(username, quest_id)
	_save_quest_data(username)
	# Push updated quest UI data to the client
	if is_instance_valid(player_node):
		_send_quest_ui_data(sender_id, username, player_node)


## After a quest completes, tell the player about any quest it just unlocked.
func _notify_newly_available(username: String, completed_id: String, player_node: MultiplayerPlayerV2) -> void:
	if not is_instance_valid(player_node):
		return
	var player_level: int = 1
	if is_instance_valid(player_node.level_component):
		player_level = player_node.level_component.level
	var completed: Array = _completed_quests.get(username, [])
	var active: Dictionary = _active_quests.get(username, {})
	var unlocked: Array = []
	for quest_id in _quests:
		if quest_id in completed or active.has(quest_id):
			continue
		var q: QuestData = _quests[quest_id]
		if q.prerequisite_quest_id != completed_id:
			continue
		if player_level < q.required_level:
			continue
		unlocked.append(q.quest_name)
	if not unlocked.is_empty():
		_send_message(player_node.player_id, "[Quest] New quest available: %s. Press Q to view." % ", ".join(unlocked), Color.GOLD)


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
		"tracked": _tracked_quests.get(username, []),
		"onboarded": _onboarded.get(username, false),
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
	_onboarded[username] = bool(data.get("onboarded", false))

	# Restore the tracker list. For legacy saves that pre-date tracking, fall
	# back to auto-tracking the first MAX_TRACKED_QUESTS active quests so the
	# player isn't greeted by an empty tracker.
	var tracked: Array = []
	if data.has("tracked"):
		for qid in data.get("tracked", []):
			var sid: String = str(qid)
			if active.has(sid) and sid not in tracked:
				tracked.append(sid)
			if tracked.size() >= MAX_TRACKED_QUESTS:
				break
	else:
		for qid in active.keys():
			tracked.append(qid)
			if tracked.size() >= MAX_TRACKED_QUESTS:
				break
	_tracked_quests[username] = tracked
	#print("QuestManager: Loaded quest data for '%s' — %d active, %d completed, %d tracked." % [username, active.size(), completed.size(), tracked.size()])


func unregister_player(_username: String) -> void:
	# Keep data in memory — it's persisted through save system.
	# Only clean up if needed to free memory on large servers.
	pass


func _push_quest_ui_update(username: String) -> void:
	var pid: int = PlayerManager.get_player_id_from_name(username)
	if pid == -1:
		return
	var player_node = PlayerManager.get_player_node(pid)
	if player_node:
		_send_quest_ui_data(pid, username, player_node)


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


## Server-triggered, client-rendered: spawn a QuestRewardPopup on the local
## player's HUD when a quest completes. `call_local` so the host sees its
## own popup when its character completes a quest.
@rpc("authority", "call_local", "reliable")
func _show_quest_reward_popup(quest_name: String, exp_amount: int, coins_amount: int, items: Array) -> void:
	var local_id: int = multiplayer.get_unique_id()
	for p in get_tree().get_nodes_in_group("Players"):
		if p.player_id != local_id:
			continue
		if not is_instance_valid(p.player_HUD):
			return
		var popup := QuestRewardPopup.new()
		popup.setup(quest_name, exp_amount, coins_amount, items)
		p.player_HUD.add_child(popup)
		return


## Server-triggered, client-rendered: show the first-login WelcomeOverlay
## inside the local player's HUD. The RPC is `call_local` so the host (who
## is both server and a client) sees its own overlay too.
@rpc("authority", "call_local", "reliable")
func _show_welcome_overlay() -> void:
	var local_id: int = multiplayer.get_unique_id()
	for p in get_tree().get_nodes_in_group("Players"):
		if p.player_id != local_id:
			continue
		if not is_instance_valid(p.player_HUD):
			return
		# Avoid stacking duplicates if the RPC somehow fires twice.
		for child in p.player_HUD.get_children():
			if child is WelcomeOverlay:
				return
		var overlay := WelcomeOverlay.new()
		p.player_HUD.add_child(overlay)
		return


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


## Heuristic for "this character has played before, even though we have no quest
## data on file." Used to suppress the onboarding welcome for characters whose
## save predates the `quests` blob. Brand-new characters always start at level 1
## with zero experience, so any level/exp above that is a strong tell.
func _has_played_before(player_node: MultiplayerPlayerV2) -> bool:
	if not is_instance_valid(player_node) or not is_instance_valid(player_node.level_component):
		return false
	if player_node.level_component.level > 1:
		return true
	if player_node.level_component.experience > 0:
		return true
	return false


# ═══════════════════════════════════════════════════════════════════════════
# QUEST UI — RPC methods for the QuestWindow client UI
# ═══════════════════════════════════════════════════════════════════════════

## Client → Server: request full quest UI data for the calling player.
@rpc("any_peer", "call_remote", "reliable")
func request_quest_ui_data() -> void:
	if not multiplayer.is_server():
		return
	var requester_id: int = multiplayer.get_remote_sender_id()
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(requester_id)
	if not player_node:
		return
	_send_quest_ui_data(requester_id, player_node.username, player_node)


## Client → Server: accept a quest via the UI button.
@rpc("any_peer", "call_remote", "reliable")
func request_quest_accept(quest_id: String) -> void:
	if not multiplayer.is_server():
		return
	var requester_id: int = multiplayer.get_remote_sender_id()
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(requester_id)
	if not player_node:
		return
	_cmd_accept(requester_id, player_node.username, player_node, quest_id)
	_send_quest_ui_data(requester_id, player_node.username, player_node)


## Client → Server: abandon a quest via the UI button.
@rpc("any_peer", "call_remote", "reliable")
func request_quest_abandon(quest_id: String) -> void:
	if not multiplayer.is_server():
		return
	var requester_id: int = multiplayer.get_remote_sender_id()
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(requester_id)
	if not player_node:
		return
	_cmd_abandon(requester_id, player_node.username, quest_id)
	_send_quest_ui_data(requester_id, player_node.username, player_node)


## Client → Server: toggle whether a quest is pinned to the on-screen tracker.
@rpc("any_peer", "call_remote", "reliable")
func request_quest_toggle_track(quest_id: String) -> void:
	if not multiplayer.is_server():
		return
	var requester_id: int = multiplayer.get_remote_sender_id()
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(requester_id)
	if not player_node:
		return
	_cmd_toggle_track(requester_id, player_node.username, quest_id)
	_send_quest_ui_data(requester_id, player_node.username, player_node)


## Server → Client: deliver serialized quest UI data.
@rpc("authority", "call_remote", "reliable")
func _receive_quest_ui_data(data: Dictionary) -> void:
	quest_ui_data_received.emit(data)


## Internal: build and deliver quest UI data to a specific peer.
func _send_quest_ui_data(peer_id: int, username: String, player_node: MultiplayerPlayerV2) -> void:
	if BotManager.is_bot(peer_id):
		return
	var data := _build_quest_ui_data(username, player_node)
	if multiplayer.get_unique_id() == peer_id:
		# Host mode: emit signal directly, no RPC needed
		quest_ui_data_received.emit(data)
	else:
		_receive_quest_ui_data.rpc_id(peer_id, data)


## Build the full quest UI data dictionary for a player.
## Called directly in host mode, or internally before sending via RPC.
func _build_quest_ui_data(username: String, player_node: MultiplayerPlayerV2) -> Dictionary:
	var player_level: int = 1
	if is_instance_valid(player_node) and is_instance_valid(player_node.level_component):
		player_level = player_node.level_component.level

	var completed: Array = _completed_quests.get(username, [])
	var active: Dictionary = _active_quests.get(username, {})

	var available_list: Array = []
	for quest_id in _quests:
		if quest_id in completed:
			continue
		if active.has(quest_id):
			continue
		var q: QuestData = _quests[quest_id]
		if player_level < q.required_level:
			continue
		if not q.prerequisite_quest_id.is_empty() and q.prerequisite_quest_id not in completed:
			continue
		available_list.append(_serialize_quest(q, {}))

	var tracked_list: Array = _tracked_quests.get(username, [])
	var active_list: Array = []
	for quest_id in active:
		if not _quests.has(quest_id):
			continue
		var entry: Dictionary = _serialize_quest(_quests[quest_id], active[quest_id])
		entry["tracked"] = quest_id in tracked_list
		active_list.append(entry)

	var completed_list: Array = []
	for quest_id in completed:
		if _quests.has(quest_id):
			completed_list.append(_serialize_quest(_quests[quest_id], {}))

	return {
		"available": available_list,
		"active": active_list,
		"completed": completed_list,
	}


## Serialize a QuestData resource + progress into a plain Dictionary for RPC transport.
func _serialize_quest(q: QuestData, progress: Dictionary) -> Dictionary:
	var objectives: Array = []
	for obj in q.objectives:
		objectives.append({
			"type_name": _objective_type_string(obj.get("type", 0)),
			"target": obj.get("target", ""),
			"amount": obj.get("amount", 1),
		})

	var data: Dictionary = {
		"id": q.quest_id,
		"name": q.quest_name,
		"description": q.description,
		"required_level": q.required_level,
		"reward_exp": q.reward_exp,
		"reward_coins": q.reward_coins,
		"reward_items": q.reward_items.duplicate(),
		"objectives": objectives,
		"npc_only": q.npc_only,
	}
	if not progress.is_empty():
		# Convert int keys → string keys for RPC serialization
		var str_progress: Dictionary = {}
		for k in progress:
			str_progress[str(k)] = progress[k]
		data["progress"] = str_progress
	return data
