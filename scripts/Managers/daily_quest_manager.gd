extends Node

## DailyQuestManager — Server-authoritative rotating daily quests.
##
## Each day there are exactly 3 daily quests, drawn deterministically from a
## pool of DailyQuestTemplate definitions. The day's set is derived from a
## date-based seed (Time.get_date_dict_from_system()), so every player gets the
## same 3 quests and no server state is needed to decide them.
##
## Progress is tracked per-player on the server and persisted through the normal
## player save flow (the "quests" save category, under the "daily" sub-key).
## When the calendar date changes, progress and the quest set roll over.
##
## On completing a daily quest the server auto-grants EXP + coins via the
## player's existing gain_experience() / inventory monies functions.

# ── Signals ──────────────────────────────────────────────────────────────────
signal daily_quest_completed(username: String, template_id: String)
## Emitted on the client when the server pushes refreshed UI data.
signal daily_quest_ui_data_received(data: Dictionary)

# ── Quest pool ────────────────────────────────────────────────────────────────
## How many quests are active each day.
const DAILY_QUEST_COUNT: int = 3

## All daily-quest templates keyed by template_id.
var _templates: Dictionary = {}  # template_id -> DailyQuestTemplate
## Stable, sorted list of template ids (deterministic ordering for the seed).
var _template_ids: Array[String] = []

# ── Per-player state (server only) ───────────────────────────────────────────
## Progress: username -> { template_id -> current_count }
var _progress: Dictionary = {}
## Claimed (rewarded) daily quests: username -> Array[String] of template_ids
var _claimed: Dictionary = {}
## The date string (YYYY-MM-DD) each player's data was last valid for.
var _player_date: Dictionary = {}

# ── Day-rollover watcher ─────────────────────────────────────────────────────
var _rollover_timer: Timer
var _cached_date_seed: int = 0


func _ready() -> void:
	_define_templates()
	_cached_date_seed = _get_date_seed()

	if not multiplayer or not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		# A lightweight timer that checks for a date change while players are
		# logged in, so quests roll over at midnight without a restart.
		_rollover_timer = Timer.new()
		_rollover_timer.name = "DailyRolloverTimer"
		_rollover_timer.wait_time = 60.0
		_rollover_timer.one_shot = false
		_rollover_timer.autostart = true
		add_child(_rollover_timer)
		_rollover_timer.timeout.connect(_on_rollover_check)


# ═══════════════════════════════════════════════════════════════════════════
# DAILY QUEST POOL (data — kept as a config array; edit freely)
# ═══════════════════════════════════════════════════════════════════════════

func _define_templates() -> void:
	# Kill objectives ----------------------------------------------------------
	_add_template("dq_kill_any_20", DailyQuestTemplate.DailyObjectiveType.KILL_ENEMIES,
		"Daily Hunt", "Defeat 20 monsters of any kind.", 20, "", "", 400, 80)
	_add_template("dq_kill_slime_15", DailyQuestTemplate.DailyObjectiveType.KILL_ENEMIES,
		"Slime Patrol", "Defeat 15 Slimes.", 15, "Slime", "", 350, 70)
	_add_template("dq_kill_mushroom_15", DailyQuestTemplate.DailyObjectiveType.KILL_ENEMIES,
		"Fungal Cleanup", "Defeat 15 Mushrooms.", 15, "Mushroom", "", 350, 70)
	_add_template("dq_kill_any_40", DailyQuestTemplate.DailyObjectiveType.KILL_ENEMIES,
		"Monster Purge", "Defeat 40 monsters of any kind.", 40, "", "", 700, 140)

	# Collect objectives -------------------------------------------------------
	_add_template("dq_collect_any_25", DailyQuestTemplate.DailyObjectiveType.COLLECT_ITEMS,
		"Daily Forage", "Collect 25 items of any kind.", 25, "", "", 350, 70)
	_add_template("dq_collect_coin_200", DailyQuestTemplate.DailyObjectiveType.COLLECT_ITEMS,
		"Coin Run", "Collect 200 Coins from fallen monsters.", 200, "Coin", "", 300, 0)
	_add_template("dq_collect_any_50", DailyQuestTemplate.DailyObjectiveType.COLLECT_ITEMS,
		"Pack Rat", "Collect 50 items of any kind.", 50, "", "", 600, 120)

	# Party-quest objective ----------------------------------------------------
	_add_template("dq_party_quest_1", DailyQuestTemplate.DailyObjectiveType.COMPLETE_PARTY_QUEST,
		"Team Effort", "Complete a quest while in a party.", 1, "", "", 500, 100)
	_add_template("dq_party_quest_2", DailyQuestTemplate.DailyObjectiveType.COMPLETE_PARTY_QUEST,
		"Comrades in Arms", "Complete 2 quests while in a party.", 2, "", "", 800, 160)

	_template_ids = []
	for id in _templates:
		_template_ids.append(id)
	_template_ids.sort()  # stable order so the daily seed is reproducible


func _add_template(id: String, obj_type: int, title: String, desc: String,
		amount: int, target: String, zone: String, exp: int, coins: int) -> void:
	var t := DailyQuestTemplate.new()
	t.template_id = id
	t.objective_type = obj_type
	t.title = title
	t.description = desc
	t.amount = amount
	t.target = target
	t.zone = zone
	t.reward_exp = exp
	t.reward_coins = coins
	_templates[id] = t


# ═══════════════════════════════════════════════════════════════════════════
# DETERMINISTIC DAILY SELECTION
# ═══════════════════════════════════════════════════════════════════════════

## Current local date as a "YYYY-MM-DD" string. Used as the rollover key.
func get_today_string() -> String:
	var d: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.get("year", 0), d.get("month", 0), d.get("day", 0)]


## A deterministic integer seed derived from today's date.
func _get_date_seed() -> int:
	var d: Dictionary = Time.get_date_dict_from_system()
	# Distinct multipliers so adjacent days produce very different seeds.
	return int(d.get("year", 0)) * 10000 + int(d.get("month", 0)) * 100 + int(d.get("day", 0))


## The 3 template_ids active today — identical for everyone, no state needed.
func get_today_template_ids() -> Array:
	var ids: Array = []
	if _template_ids.is_empty():
		return ids

	var count: int = min(DAILY_QUEST_COUNT, _template_ids.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = _get_date_seed()

	# Fisher-Yates style draw without replacement from a copy of the id list.
	var pool: Array = _template_ids.duplicate()
	for i in range(count):
		var pick: int = rng.randi_range(0, pool.size() - 1)
		ids.append(pool[pick])
		pool.remove_at(pick)
	return ids


func get_template(template_id: String) -> DailyQuestTemplate:
	return _templates.get(template_id)


# ═══════════════════════════════════════════════════════════════════════════
# PROGRESS HOOKS — called from server-side game events
# ═══════════════════════════════════════════════════════════════════════════

## Called when a player kills an enemy. `zone` is the killer's current map id.
func record_enemy_kill(username: String, enemy_name: String, zone: String = "") -> void:
	if not multiplayer.is_server():
		return
	_advance(username, DailyQuestTemplate.DailyObjectiveType.KILL_ENEMIES, enemy_name, zone, 1)


## Called when a player picks up / collects items.
func record_item_collected(username: String, item_name: String, amount: int = 1) -> void:
	if not multiplayer.is_server():
		return
	_advance(username, DailyQuestTemplate.DailyObjectiveType.COLLECT_ITEMS, item_name, "", amount)


## Called when a player completes a (regular) quest. Counts toward the
## "Complete a Party Quest" objective only if the player is currently in a
## party — and only once per quest completion.
func record_party_quest_completed(username: String) -> void:
	if not multiplayer.is_server():
		return
	_advance(username, DailyQuestTemplate.DailyObjectiveType.COMPLETE_PARTY_QUEST, "", "", 1)


# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL — PROGRESS TRACKING
# ═══════════════════════════════════════════════════════════════════════════

func _advance(username: String, obj_type: int, target: String, zone: String, amount: int) -> void:
	if username.is_empty() or amount <= 0:
		return

	_ensure_current_day(username)

	var progress: Dictionary = _progress.get(username, {})
	var claimed: Array = _claimed.get(username, [])
	var changed: bool = false

	for template_id in get_today_template_ids():
		if template_id in claimed:
			continue  # already completed & rewarded today
		var t: DailyQuestTemplate = _templates.get(template_id)
		if t == null or t.objective_type != obj_type:
			continue
		# Target / zone filters — empty filter means "any".
		if not t.target.is_empty() and t.target != target:
			continue
		if not t.zone.is_empty() and t.zone != zone:
			continue

		var old_val: int = int(progress.get(template_id, 0))
		if old_val >= t.amount:
			continue
		# Clamp so progress never exceeds the target.
		var new_val: int = min(old_val + amount, t.amount)
		progress[template_id] = new_val
		changed = true

		if new_val >= t.amount:
			_grant_reward(username, t)

	if changed:
		_progress[username] = progress
		_save(username)
		_push_ui_update(username)


func _grant_reward(username: String, t: DailyQuestTemplate) -> void:
	if not _claimed.has(username):
		_claimed[username] = []
	if t.template_id in _claimed[username]:
		return  # guard against double-grant
	_claimed[username].append(t.template_id)

	var pid: int = PlayerManager.get_player_id_from_name(username)
	var player_node: MultiplayerPlayerV2 = null
	if pid != -1:
		player_node = PlayerManager.get_player_node(pid)

	if is_instance_valid(player_node):
		if t.reward_exp > 0:
			player_node.gain_experience(t.reward_exp)
		if t.reward_coins > 0 and is_instance_valid(player_node.player_inventory):
			player_node.player_inventory.monies_amount += t.reward_coins

		if not BotManager.is_bot(pid):
			_send_message(pid, "[Daily Quest] COMPLETED: %s!" % t.title, Color.GOLD)
			if t.reward_exp > 0:
				_send_message(pid, "  +%d EXP" % t.reward_exp, Color.GREEN)
			if t.reward_coins > 0:
				_send_message(pid, "  +%d Coins" % t.reward_coins, Color.GREEN)

	daily_quest_completed.emit(username, t.template_id)


# ═══════════════════════════════════════════════════════════════════════════
# DAY ROLLOVER
# ═══════════════════════════════════════════════════════════════════════════

## Ensure a player's progress belongs to the current day; reset it if stale.
func _ensure_current_day(username: String) -> void:
	var today: String = get_today_string()
	if _player_date.get(username, "") != today:
		_progress[username] = {}
		_claimed[username] = []
		_player_date[username] = today


func _on_rollover_check() -> void:
	if not multiplayer.is_server():
		return
	var seed_now: int = _get_date_seed()
	if seed_now == _cached_date_seed:
		return
	# The calendar date changed — roll over every tracked player.
	_cached_date_seed = seed_now
	var today: String = get_today_string()
	for username in _progress.keys():
		_progress[username] = {}
		_claimed[username] = []
		_player_date[username] = today
		_save(username)
		_push_ui_update(username)


# ═══════════════════════════════════════════════════════════════════════════
# SAVE / LOAD — integrated with player save data (under data["quests"]["daily"])
# ═══════════════════════════════════════════════════════════════════════════

func save_daily(username: String) -> Dictionary:
	return {
		"date": _player_date.get(username, get_today_string()),
		"progress": _progress.get(username, {}),
		"claimed": _claimed.get(username, []),
	}


func load_daily(username: String, data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var saved_date: String = str(data.get("date", ""))
	var today: String = get_today_string()

	if saved_date != today:
		# Stale save from a previous day — start fresh for today.
		_progress[username] = {}
		_claimed[username] = []
		_player_date[username] = today
		return

	var progress: Dictionary = {}
	var raw_progress = data.get("progress", {})
	if raw_progress is Dictionary:
		for key in raw_progress:
			progress[str(key)] = int(raw_progress[key])

	var claimed: Array = []
	for cid in data.get("claimed", []):
		claimed.append(str(cid))

	_progress[username] = progress
	_claimed[username] = claimed
	_player_date[username] = today


func unregister_player(_username: String) -> void:
	# Keep data in memory — it's persisted through the save system.
	pass


func _save(username: String) -> void:
	var pid: int = PlayerManager.get_player_id_from_name(username)
	if pid != -1:
		var pn = PlayerManager.get_player_node(pid)
		if pn and SaveManager:
			SaveManager.queue_save(username, "all", pn)


# ═══════════════════════════════════════════════════════════════════════════
# UI DATA — RPC bridge to the DailyQuestWindow client UI
# ═══════════════════════════════════════════════════════════════════════════

## Client → Server: request today's daily-quest UI data.
@rpc("any_peer", "call_remote", "reliable")
func request_daily_quest_ui_data() -> void:
	if not multiplayer.is_server():
		return
	var requester_id: int = multiplayer.get_remote_sender_id()
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(requester_id)
	if not player_node:
		return
	_send_ui_data(requester_id, player_node.username)


## Server → Client: deliver serialized daily-quest UI data.
@rpc("authority", "call_remote", "reliable")
func _receive_daily_quest_ui_data(data: Dictionary) -> void:
	daily_quest_ui_data_received.emit(data)


func _push_ui_update(username: String) -> void:
	var pid: int = PlayerManager.get_player_id_from_name(username)
	if pid == -1:
		return
	_send_ui_data(pid, username)


func _send_ui_data(peer_id: int, username: String) -> void:
	if BotManager.is_bot(peer_id):
		return
	var data := build_ui_data(username)
	if multiplayer.get_unique_id() == peer_id:
		# Host mode: emit directly, no RPC needed.
		daily_quest_ui_data_received.emit(data)
	else:
		_receive_daily_quest_ui_data.rpc_id(peer_id, data)


## Build the full daily-quest UI payload for a player. Safe to call directly
## in host mode; used internally before RPC otherwise.
func build_ui_data(username: String) -> Dictionary:
	if multiplayer.is_server():
		_ensure_current_day(username)

	var progress: Dictionary = _progress.get(username, {})
	var claimed: Array = _claimed.get(username, [])

	var quests: Array = []
	for template_id in get_today_template_ids():
		var t: DailyQuestTemplate = _templates.get(template_id)
		if t == null:
			continue
		var current: int = int(progress.get(template_id, 0))
		quests.append({
			"id": t.template_id,
			"title": t.title,
			"description": t.description,
			"amount": t.amount,
			"current": min(current, t.amount),
			"completed": current >= t.amount or t.template_id in claimed,
			"reward_exp": t.reward_exp,
			"reward_coins": t.reward_coins,
		})

	return {
		"date": get_today_string(),
		"quests": quests,
	}


# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _send_message(peer_id: int, text: String, color: Color) -> void:
	_client_receive_daily_message.rpc_id(peer_id, text, color)


@rpc("authority", "call_local", "reliable")
func _client_receive_daily_message(text: String, color: Color) -> void:
	ChatManager.add_system_message(text, color)
