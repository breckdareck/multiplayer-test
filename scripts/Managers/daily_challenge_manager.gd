extends Node

## DailyChallengeManager — Server-authoritative Daily Co-op Challenges.
##
## Each day a single rotating challenge is active. Challenges grant BONUS
## rewards for completing content WITH A PARTY (party of 2+). Solo progress
## never counts — the feature is party-gated by design.
##
## The active challenge is chosen DETERMINISTICALLY from a fixed pool using
## today's date as a seed, so every player (and the server) independently
## agree on which challenge is active without any shared state.
##
## Progress is tracked per-player on the server and persisted through the
## normal player save flow (see MultiplayerPlayerV2.get_save_data / _load_data).
##
## NOTE: This is a separate system from QuestManager (regular quests) and the
## planned DailyQuestManager (issue #13). Do not merge them.

# ── Signals ──────────────────────────────────────────────────────────────────
signal challenge_completed(username: String, challenge_id: String)
signal challenge_progress_updated(username: String, progress: int)
## Emitted on the client when the server pushes updated UI data.
signal challenge_ui_data_received(data: Dictionary)

# ── Challenge type enum ─────────────────────────────────────────────────────
enum ChallengeType {
	PARTY_KILL,       ## Kill N enemies on a zone with a party of 2+
	SPEED,            ## Kill N enemies within a time limit with a party of 2+
	CLASS_DIVERSITY,  ## Kill N enemies with a party that has all 4 classes
	BOSS_RUSH,        ## Defeat a boss with a full party of 4
}

# ── Reward type enum ────────────────────────────────────────────────────────
enum RewardType {
	BONUS_EXP,        ## Flat bonus EXP granted to the player
	BONUS_GOLD,       ## Flat bonus coins granted to the player
	EXP_BUFF,         ## Time-limited EXP multiplier (e.g. double EXP for 30 min)
	EXTRA_DROP_ROLLS, ## Bonus drop rolls — granted as a bonus loot item bundle
}

# ── Tunables ────────────────────────────────────────────────────────────────
## EXP multiplier applied by the Speed Challenge reward buff.
const EXP_BUFF_MULTIPLIER: float = 2.0
## Duration of the Speed Challenge EXP buff in seconds (30 minutes).
const EXP_BUFF_DURATION: float = 1800.0

# ── Challenge Pool (data-driven, defined in code like QuestManager) ─────────
## Each entry: { id, type, title, description, params{}, reward{} }
var _challenge_pool: Array = []

# ── Per-player state (server only) ──────────────────────────────────────────
## Progress for the player's CURRENT active challenge.
##   username -> { "challenge_id": String, "progress": int, "completed": bool,
##                 "speed_deadline": float (unix, 0 if n/a) }
var _player_progress: Dictionary = {}
## Active EXP buffs from a completed Speed Challenge.
##   username -> unix timestamp when the buff expires
var _exp_buff_expiry: Dictionary = {}

## The challenge_id active "today" — recomputed on day rollover.
var _current_challenge_id: String = ""
## The date string (YYYY-MM-DD) the current challenge was computed for.
var _current_date_key: String = ""

# Midnight-rollover check timer.
var _rollover_timer: Timer


func _ready() -> void:
	_define_challenges()
	_refresh_active_challenge()

	# Day-rollover watcher — checks once a minute whether the date changed.
	_rollover_timer = Timer.new()
	_rollover_timer.name = "RolloverTimer"
	_rollover_timer.wait_time = 60.0
	_rollover_timer.autostart = true
	_rollover_timer.one_shot = false
	add_child(_rollover_timer)
	_rollover_timer.timeout.connect(_on_rollover_check)


# ═══════════════════════════════════════════════════════════════════════════
# CHALLENGE DEFINITIONS
# ═══════════════════════════════════════════════════════════════════════════

func _define_challenges() -> void:
	# --- Party Kill Challenges (one per combat zone) ---
	_add_challenge("dc_party_kill_game", ChallengeType.PARTY_KILL,
		"Party Hunt: Green Fields",
		"Kill 30 enemies in the Green Fields with a party of 2 or more.",
		{"map": "game", "amount": 30},
		{"type": RewardType.EXTRA_DROP_ROLLS, "item": "Coin", "amount": 500})

	_add_challenge("dc_party_kill_game2", ChallengeType.PARTY_KILL,
		"Party Hunt: Deep Caverns",
		"Kill 30 enemies in the Deep Caverns with a party of 2 or more.",
		{"map": "game2", "amount": 30},
		{"type": RewardType.EXTRA_DROP_ROLLS, "item": "Coin", "amount": 800})

	_add_challenge("dc_party_kill_game3", ChallengeType.PARTY_KILL,
		"Party Hunt: Astral Reach",
		"Kill 30 enemies in the Astral Reach with a party of 2 or more.",
		{"map": "game3", "amount": 30},
		{"type": RewardType.EXTRA_DROP_ROLLS, "item": "Coin", "amount": 1200})

	# --- Speed Challenge ---
	_add_challenge("dc_speed", ChallengeType.SPEED,
		"Blitz Run",
		"Kill 50 enemies within 10 minutes while in a party of 2 or more. "
		+ "Reward: double EXP for 30 minutes!",
		{"amount": 50, "time_limit": 600.0},
		{"type": RewardType.EXP_BUFF})

	# --- Class Diversity Challenge ---
	_add_challenge("dc_class_diversity", ChallengeType.CLASS_DIVERSITY,
		"United We Stand",
		"Kill 40 enemies in a party that has all 4 classes represented "
		+ "(Swordsman, Archer, Mage, Rogue).",
		{"amount": 40},
		{"type": RewardType.BONUS_EXP, "amount": 5000})

	# --- Boss Rush Challenge ---
	_add_challenge("dc_boss_rush", ChallengeType.BOSS_RUSH,
		"Warlord's Bane",
		"Defeat the Eternal Warlord with a full party of 4.",
		{"boss": "Eternal Warlord", "party_size": 4},
		{"type": RewardType.EXTRA_DROP_ROLLS, "item": "Coin", "amount": 3000})


func _add_challenge(id: String, type: ChallengeType, title: String,
		desc: String, params: Dictionary, reward: Dictionary) -> void:
	_challenge_pool.append({
		"id": id,
		"type": type,
		"title": title,
		"description": desc,
		"params": params,
		"reward": reward,
	})


# ═══════════════════════════════════════════════════════════════════════════
# DETERMINISTIC DAILY SEED
# ═══════════════════════════════════════════════════════════════════════════

## Returns the date key (YYYY-MM-DD) for the system's current date.
func _today_key() -> String:
	var d: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.get("year", 0), d.get("month", 0), d.get("day", 0)]


## Deterministically picks the challenge index for a given date key. Every
## player and the server compute the same value with no shared state.
func _challenge_index_for_date(date_key: String) -> int:
	if _challenge_pool.is_empty():
		return 0
	# Hash the date string to a stable integer, then mod into the pool.
	var seed_val: int = abs(date_key.hash())
	return seed_val % _challenge_pool.size()


## Recomputes the active challenge for today. If the day changed, resets all
## tracked player progress (challenge of the day has rotated).
func _refresh_active_challenge() -> void:
	var today: String = _today_key()
	if today == _current_date_key and not _current_challenge_id.is_empty():
		return  # No change.

	var idx: int = _challenge_index_for_date(today)
	var new_id: String = _challenge_pool[idx].get("id", "")

	var day_rolled: bool = not _current_date_key.is_empty() and today != _current_date_key
	_current_date_key = today
	_current_challenge_id = new_id

	if day_rolled:
		# A new day — every player's progress resets to the new challenge.
		_player_progress.clear()
		#print("DailyChallengeManager: Day rolled over. New challenge: %s" % new_id)


func _on_rollover_check() -> void:
	var prev_id: String = _current_challenge_id
	_refresh_active_challenge()
	if multiplayer.is_server() and _current_challenge_id != prev_id:
		# Push fresh UI to every connected real player.
		for node in get_tree().get_nodes_in_group("Players"):
			if is_instance_valid(node) and "player_id" in node and "username" in node:
				if not BotManager.is_bot(node.player_id):
					_send_ui_data(node.player_id, node.username)


# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API — challenge lookup
# ═══════════════════════════════════════════════════════════════════════════

## Returns the config dictionary of today's active challenge (or {} if none).
func get_active_challenge() -> Dictionary:
	_refresh_active_challenge()
	for c in _challenge_pool:
		if c.get("id", "") == _current_challenge_id:
			return c
	return {}


func get_active_challenge_id() -> String:
	_refresh_active_challenge()
	return _current_challenge_id


# ═══════════════════════════════════════════════════════════════════════════
# PROGRESS TRACKING — called from game systems (server only)
# ═══════════════════════════════════════════════════════════════════════════

## Returns the mutable per-player progress record, creating it if needed and
## migrating it to today's challenge if it is stale.
func _get_progress_record(username: String) -> Dictionary:
	var active_id: String = get_active_challenge_id()
	var rec: Dictionary = _player_progress.get(username, {})
	if rec.is_empty() or rec.get("challenge_id", "") != active_id:
		# New player or challenge rotated since last tracked — fresh record.
		rec = {
			"challenge_id": active_id,
			"progress": 0,
			"completed": false,
			"speed_deadline": 0.0,
		}
		_player_progress[username] = rec
	return rec


## Called from EnemyBase when a player gets credit for an enemy kill.
## party_member_ids: ids of party members on the same map (incl. the killer);
## empty/size 1 means the player was effectively solo and it does not count.
func record_party_enemy_kill(username: String, enemy_name: String, map_id: String,
		party_member_ids: Array) -> void:
	if not multiplayer.is_server():
		return

	# Party gate: must be in a party of 2+.
	if party_member_ids.size() < 2:
		return

	var challenge: Dictionary = get_active_challenge()
	if challenge.is_empty():
		return

	var type: int = challenge.get("type", -1)
	match type:
		ChallengeType.PARTY_KILL:
			var params: Dictionary = challenge.get("params", {})
			if map_id != params.get("map", ""):
				return  # Wrong zone.
			_advance_kill_progress(username, challenge)
		ChallengeType.SPEED:
			_advance_speed_progress(username, challenge)
		ChallengeType.CLASS_DIVERSITY:
			if not _party_has_all_classes(party_member_ids):
				return  # Party does not cover all 4 classes.
			_advance_kill_progress(username, challenge)
		ChallengeType.BOSS_RUSH:
			# Boss kills are handled by record_party_boss_kill, not here.
			pass


## Called from EnemyBase when a boss enemy is defeated by a party.
func record_party_boss_kill(username: String, boss_name: String,
		party_member_ids: Array) -> void:
	if not multiplayer.is_server():
		return

	var challenge: Dictionary = get_active_challenge()
	if challenge.is_empty() or challenge.get("type", -1) != ChallengeType.BOSS_RUSH:
		return

	var params: Dictionary = challenge.get("params", {})
	if boss_name != params.get("boss", ""):
		return
	if party_member_ids.size() < params.get("party_size", 4):
		return  # Needs a full party.

	var rec: Dictionary = _get_progress_record(username)
	if rec.get("completed", false):
		return
	rec["progress"] = 1
	rec["completed"] = true
	_player_progress[username] = rec
	_grant_reward(username, challenge)
	_finish_challenge(username, challenge)


func _advance_kill_progress(username: String, challenge: Dictionary) -> void:
	var rec: Dictionary = _get_progress_record(username)
	if rec.get("completed", false):
		return

	var goal: int = challenge.get("params", {}).get("amount", 1)
	rec["progress"] = min(rec.get("progress", 0) + 1, goal)
	_player_progress[username] = rec

	challenge_progress_updated.emit(username, rec["progress"])

	if rec["progress"] >= goal:
		rec["completed"] = true
		_player_progress[username] = rec
		_grant_reward(username, challenge)
		_finish_challenge(username, challenge)
	else:
		_save_progress(username)
		_push_ui_update(username)


func _advance_speed_progress(username: String, challenge: Dictionary) -> void:
	var rec: Dictionary = _get_progress_record(username)
	if rec.get("completed", false):
		return

	var now: float = Time.get_unix_time_from_system()
	var time_limit: float = challenge.get("params", {}).get("time_limit", 600.0)
	var deadline: float = rec.get("speed_deadline", 0.0)

	# Start the timer on the first qualifying kill, or restart it if the
	# previous window already expired without completing.
	if deadline <= 0.0 or now > deadline:
		rec["speed_deadline"] = now + time_limit
		rec["progress"] = 0

	rec["progress"] = rec.get("progress", 0) + 1
	_player_progress[username] = rec

	var goal: int = challenge.get("params", {}).get("amount", 50)
	challenge_progress_updated.emit(username, rec["progress"])

	if rec["progress"] >= goal:
		# Completed in time (deadline freshly checked above).
		rec["completed"] = true
		_player_progress[username] = rec
		_grant_reward(username, challenge)
		_finish_challenge(username, challenge)
	else:
		_save_progress(username)
		_push_ui_update(username)


func _finish_challenge(username: String, challenge: Dictionary) -> void:
	challenge_completed.emit(username, challenge.get("id", ""))
	var pid: int = PlayerManager.get_player_id_from_name(username)
	if pid != -1:
		_send_message(pid, "[Daily Challenge] COMPLETED: %s!" % challenge.get("title", ""), Color.GOLD)
	_save_progress(username)
	_push_ui_update(username)


# ═══════════════════════════════════════════════════════════════════════════
# CLASS DIVERSITY HELPER
# ═══════════════════════════════════════════════════════════════════════════

## True if the given party covers all 4 base class archetypes. Advanced
## classes count as their base archetype (Crusader -> Swordsman, etc.).
func _party_has_all_classes(member_ids: Array) -> bool:
	var archetypes: Dictionary = {}
	for mid in member_ids:
		var node: Node = PlayerManager.get_player_node(mid)
		if not is_instance_valid(node) or not is_instance_valid(node.class_component):
			continue
		archetypes[_base_archetype(node.class_component.current_class)] = true
	return archetypes.has(Constants.ClassType.SWORDSMAN) \
		and archetypes.has(Constants.ClassType.ARCHER) \
		and archetypes.has(Constants.ClassType.MAGE) \
		and archetypes.has(Constants.ClassType.ROGUE)


func _base_archetype(class_type: int) -> int:
	match class_type:
		Constants.ClassType.CRUSADER:
			return Constants.ClassType.SWORDSMAN
		Constants.ClassType.RANGER:
			return Constants.ClassType.ARCHER
		Constants.ClassType.ARCHMAGE:
			return Constants.ClassType.MAGE
		Constants.ClassType.ASSASSIN:
			return Constants.ClassType.ROGUE
		_:
			return class_type


# ═══════════════════════════════════════════════════════════════════════════
# REWARD GRANTING
# ═══════════════════════════════════════════════════════════════════════════

func _grant_reward(username: String, challenge: Dictionary) -> void:
	var reward: Dictionary = challenge.get("reward", {})
	var pid: int = PlayerManager.get_player_id_from_name(username)
	var player_node: MultiplayerPlayerV2 = null
	if pid != -1:
		player_node = PlayerManager.get_player_node(pid)

	match reward.get("type", -1):
		RewardType.BONUS_EXP:
			var exp: int = reward.get("amount", 0)
			if is_instance_valid(player_node) and exp > 0:
				player_node.gain_experience(exp)
			if pid != -1:
				_send_message(pid, "  +%d bonus EXP" % exp, Color.GREEN)

		RewardType.BONUS_GOLD:
			var gold: int = reward.get("amount", 0)
			_grant_coins(player_node, gold)
			if pid != -1:
				_send_message(pid, "  +%d bonus Coins" % gold, Color.GOLD)

		RewardType.EXP_BUFF:
			# Activate a server-tracked double-EXP window. gain_experience()
			# multiplies all EXP gains while this is active.
			var expiry: float = Time.get_unix_time_from_system() + EXP_BUFF_DURATION
			_exp_buff_expiry[username] = expiry
			if pid != -1:
				_send_message(pid, "  Double EXP active for %d minutes!" % int(EXP_BUFF_DURATION / 60.0), Color.GREEN)

		RewardType.EXTRA_DROP_ROLLS:
			# "Extra drop rolls" are realised as a guaranteed bonus loot bundle
			# — the daily challenge has no enemy to roll against on completion.
			var item_name: String = reward.get("item", "Coin")
			var amount: int = reward.get("amount", 1)
			if item_name == "Coin":
				_grant_coins(player_node, amount)
			elif is_instance_valid(player_node) and is_instance_valid(player_node.inventory_component):
				var item = ResourceManager.get_item_by_name(item_name)
				if item:
					var item_copy = item.duplicate_with_path()
					player_node.inventory_component.add_item(item_copy)
			if pid != -1:
				_send_message(pid, "  Bonus loot: %dx %s" % [amount, item_name], Color.GOLD)


func _grant_coins(player_node: MultiplayerPlayerV2, amount: int) -> void:
	if amount <= 0 or not is_instance_valid(player_node):
		return
	if is_instance_valid(player_node.player_inventory):
		player_node.player_inventory.monies_amount += amount


# ═══════════════════════════════════════════════════════════════════════════
# EXP BUFF — queried by MultiplayerPlayerV2.gain_experience()
# ═══════════════════════════════════════════════════════════════════════════

## Returns the EXP multiplier currently in effect for a player (1.0 = none).
func get_exp_multiplier(username: String) -> float:
	if not _exp_buff_expiry.has(username):
		return 1.0
	if Time.get_unix_time_from_system() >= _exp_buff_expiry[username]:
		_exp_buff_expiry.erase(username)
		return 1.0
	return EXP_BUFF_MULTIPLIER


## Remaining seconds on the EXP buff (0 if inactive).
func get_exp_buff_remaining(username: String) -> float:
	if not _exp_buff_expiry.has(username):
		return 0.0
	var remaining: float = _exp_buff_expiry[username] - Time.get_unix_time_from_system()
	return max(0.0, remaining)


# ═══════════════════════════════════════════════════════════════════════════
# SAVE / LOAD — integrated with the player save flow
# ═══════════════════════════════════════════════════════════════════════════

## Serialized into player_<username>.json under the "daily_challenge" key.
func save_challenge_data(username: String) -> Dictionary:
	var rec: Dictionary = _player_progress.get(username, {})
	return {
		"date_key": _current_date_key,
		"challenge_id": rec.get("challenge_id", ""),
		"progress": rec.get("progress", 0),
		"completed": rec.get("completed", false),
		"speed_deadline": rec.get("speed_deadline", 0.0),
		"exp_buff_expiry": _exp_buff_expiry.get(username, 0.0),
	}


func load_challenge_data(username: String, data: Dictionary) -> void:
	if not multiplayer.is_server() or data.is_empty():
		return

	_refresh_active_challenge()

	# Restore the EXP buff only if it has not yet expired.
	var buff_expiry: float = float(data.get("exp_buff_expiry", 0.0))
	if buff_expiry > Time.get_unix_time_from_system():
		_exp_buff_expiry[username] = buff_expiry

	# Progress is only valid if it belongs to TODAY's challenge. If the saved
	# data is from a previous day (or a different challenge), it is discarded —
	# _get_progress_record will create a fresh record on the next kill.
	var saved_date: String = str(data.get("date_key", ""))
	var saved_challenge: String = str(data.get("challenge_id", ""))
	if saved_date == _current_date_key and saved_challenge == _current_challenge_id \
			and not saved_challenge.is_empty():
		_player_progress[username] = {
			"challenge_id": saved_challenge,
			"progress": int(data.get("progress", 0)),
			"completed": bool(data.get("completed", false)),
			"speed_deadline": float(data.get("speed_deadline", 0.0)),
		}
	#print("DailyChallengeManager: Loaded challenge data for '%s'." % username)


func _save_progress(username: String) -> void:
	# Route through the player's normal debounced save flow.
	var pid: int = PlayerManager.get_player_id_from_name(username)
	if pid != -1:
		var pn = PlayerManager.get_player_node(pid)
		if pn and SaveManager:
			SaveManager.queue_save(username, "all", pn)


# ═══════════════════════════════════════════════════════════════════════════
# UI DATA — RPC methods for the DailyChallengeWindow client UI
# ═══════════════════════════════════════════════════════════════════════════

## Client → Server: request today's challenge + this player's progress.
@rpc("any_peer", "call_remote", "reliable")
func request_challenge_ui_data() -> void:
	if not multiplayer.is_server():
		return
	var requester_id: int = multiplayer.get_remote_sender_id()
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(requester_id)
	if not player_node:
		return
	_send_ui_data(requester_id, player_node.username)


## Server → Client: deliver serialized challenge UI data.
@rpc("authority", "call_remote", "reliable")
func _receive_challenge_ui_data(data: Dictionary) -> void:
	challenge_ui_data_received.emit(data)


func _send_ui_data(peer_id: int, username: String) -> void:
	if BotManager.is_bot(peer_id):
		return
	var data: Dictionary = _build_ui_data(username)
	if multiplayer.get_unique_id() == peer_id:
		# Host mode — emit directly, no RPC.
		challenge_ui_data_received.emit(data)
	else:
		_receive_challenge_ui_data.rpc_id(peer_id, data)


func _push_ui_update(username: String) -> void:
	var pid: int = PlayerManager.get_player_id_from_name(username)
	if pid != -1:
		_send_ui_data(pid, username)


## Builds the UI data dictionary. Safe to call on host directly; the
## DailyChallengeWindow uses it both in host mode and via RPC.
func _build_ui_data(username: String) -> Dictionary:
	var challenge: Dictionary = get_active_challenge()
	if challenge.is_empty():
		return {"has_challenge": false}

	var rec: Dictionary = _player_progress.get(username, {})
	# Treat stale progress (different challenge id) as zero.
	var progress: int = 0
	var completed: bool = false
	var speed_deadline: float = 0.0
	if rec.get("challenge_id", "") == challenge.get("id", ""):
		progress = rec.get("progress", 0)
		completed = rec.get("completed", false)
		speed_deadline = rec.get("speed_deadline", 0.0)

	var params: Dictionary = challenge.get("params", {})
	var goal: int = params.get("amount", 1)
	if challenge.get("type", -1) == ChallengeType.BOSS_RUSH:
		goal = 1

	return {
		"has_challenge": true,
		"id": challenge.get("id", ""),
		"title": challenge.get("title", ""),
		"description": challenge.get("description", ""),
		"type_name": _type_name(challenge.get("type", -1)),
		"reward_text": _reward_text(challenge.get("reward", {})),
		"progress": progress,
		"goal": goal,
		"completed": completed,
		"speed_deadline": speed_deadline,
		"exp_buff_remaining": get_exp_buff_remaining(username),
	}


# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _type_name(type: int) -> String:
	match type:
		ChallengeType.PARTY_KILL:      return "Party Kill"
		ChallengeType.SPEED:           return "Speed"
		ChallengeType.CLASS_DIVERSITY: return "Class Diversity"
		ChallengeType.BOSS_RUSH:       return "Boss Rush"
		_:                             return "Challenge"


func _reward_text(reward: Dictionary) -> String:
	match reward.get("type", -1):
		RewardType.BONUS_EXP:
			return "+%d bonus EXP" % reward.get("amount", 0)
		RewardType.BONUS_GOLD:
			return "+%d bonus Coins" % reward.get("amount", 0)
		RewardType.EXP_BUFF:
			return "Double EXP for %d min" % int(EXP_BUFF_DURATION / 60.0)
		RewardType.EXTRA_DROP_ROLLS:
			return "Bonus loot: %dx %s" % [reward.get("amount", 1), reward.get("item", "Coin")]
		_:
			return "Reward"


func _send_message(peer_id: int, text: String, color: Color) -> void:
	if BotManager.is_bot(peer_id):
		return
	_client_receive_challenge_message.rpc_id(peer_id, text, color)


@rpc("authority", "call_local", "reliable")
func _client_receive_challenge_message(text: String, color: Color) -> void:
	ChatManager.add_system_message(text, color)
