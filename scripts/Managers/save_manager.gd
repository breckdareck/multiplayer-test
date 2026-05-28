extends Node
## SaveManager — Debounced, queued persistence for player data.
##
## Only performs save logic on the server. Clients should notify the server
## via RPC, and the server routes through this manager.
##
## Usage:
##   SaveManager.register_player(username, player_node)
##   SaveManager.queue_save(username, "stats", player_node)
##   SaveManager.flush_save(username)       # before disconnect
##   SaveManager.unregister_player(username)
##
## Architecture: an HTTP pool of HTTP_POOL_SIZE HTTPRequest nodes lets several
## saves run in parallel. Each save is a SaveJob with its own `completed` signal,
## so flush_save can await its specific job without racing against other flushes
## (the old single-flag wait-loop let two flushes through on the same frame and
## tripped HTTPRequest's ERR_BUSY guard, which freezes the server). A per-
## username in-flight set still serializes saves for the same player so two
## POSTs can't race for the same backend row.

signal save_completed(username: String)
signal save_failed(username: String, error: String)

# ── Configuration ──────────────────────────────────────────────────────────
const DEBOUNCE_TIME: float = 0.5        # seconds before a queued save fires
const AUTO_SAVE_INTERVAL: float = 60.0  # periodic full-save safety net
const RETRY_DELAY: float = 1.0          # delay before a single retry
const HTTP_TIMEOUT: float = 5.0         # per-request timeout
const HTTP_POOL_SIZE: int = 8           # max concurrent in-flight saves

# "equipment" is intentionally NOT a category: equipment state is serialized
# inside the "inventory" bucket (player_inventory.save_player_inventory), so
# equipment changes queue an "inventory" save. There is no standalone equipment
# producer in get_save_data, so a separate category would save an empty payload.
const VALID_CATEGORIES: PackedStringArray = [
	"stats", "inventory", "abilities", "buffs", "pets"
]

var _api_url: String = ""  # Will be loaded from UserConfig

# ── Per-player tracking ───────────────────────────────────────────────────
## Registered players: username -> { node, dirty_categories, timer }
var _players: Dictionary = {}

# ── HTTP pool & dispatch queue ─────────────────────────────────────────────
var _http_pool: Array[HTTPRequest] = []
var _http_busy: Array[bool] = []
## Pending save jobs awaiting a free pool slot (FIFO; same-user jobs are skipped
## while that user already has a save in flight, to avoid racing POSTs).
var _save_queue: Array[SaveJob] = []
## Usernames whose save is currently being POSTed — guards against two parallel
## saves stomping on the same backend row.
var _in_flight_usernames: Dictionary = {}

var _auto_save_timer: Timer


## A single save request. Owns its own completion signal so `flush_save` can
## await exactly its own job without a flag-based wait-loop that lets multiple
## callers through on the same frame.
class SaveJob extends RefCounted:
	signal completed
	var username: String
	var data: Dictionary
	var is_flush: bool


func _ready() -> void:
	# Load API URL from config (supports environment variable override)
	_api_url = UserConfig.get_backend_api_url() + "/player"

	# SaveManager only does work on the server
	if not _is_server():
		return

	# HTTP pool — N concurrent HTTPRequest nodes. Each slot is independent.
	for i in HTTP_POOL_SIZE:
		var req := HTTPRequest.new()
		req.name = "SaveHTTPRequest_%d" % i
		req.timeout = HTTP_TIMEOUT
		add_child(req)
		_http_pool.append(req)
		_http_busy.append(false)

	# Auto-save timer
	_auto_save_timer = Timer.new()
	_auto_save_timer.name = "AutoSaveTimer"
	_auto_save_timer.wait_time = AUTO_SAVE_INTERVAL
	_auto_save_timer.autostart = true
	_auto_save_timer.one_shot = false
	add_child(_auto_save_timer)
	_auto_save_timer.timeout.connect(_on_auto_save_timeout)


# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

## Register a player so SaveManager tracks them for auto-save and flush.
func register_player(username: String, player_node: Node) -> void:
	if not _is_server() or username.is_empty():
		return
	if _players.has(username):
		# Update the node reference (e.g. after map change / respawn)
		_players[username].node = player_node
		return

	var debounce_timer := Timer.new()
	debounce_timer.name = "Debounce_" + username
	debounce_timer.one_shot = true
	debounce_timer.wait_time = DEBOUNCE_TIME
	add_child(debounce_timer)
	debounce_timer.timeout.connect(_on_debounce_timeout.bind(username))

	_players[username] = {
		"node": player_node,
		"dirty_categories": {} as Dictionary,  # category_name -> true
		"timer": debounce_timer,
	}


## Unregister a player. Flushes any pending data first.
func unregister_player(username: String) -> void:
	if not _is_server() or not _players.has(username):
		return

	# Flush remaining data before removing
	await flush_save(username)

	if not _players.has(username):
		return  # someone else unregistered us during the flush

	var info: Dictionary = _players[username]
	if is_instance_valid(info.timer):
		info.timer.stop()
		info.timer.queue_free()

	_players.erase(username)


## Mark a category as dirty and (re)start the debounce timer.
## The actual data is collected lazily when the timer fires.
func queue_save(username: String, category: String, player_node: Node) -> void:
	if not _is_server():
		return

	# Auto-register if not yet tracked
	if not _players.has(username):
		register_player(username, player_node)

	var info: Dictionary = _players[username]

	# Keep node reference fresh
	if is_instance_valid(player_node):
		info.node = player_node

	# Mark dirty categories
	if category == "all":
		for cat in VALID_CATEGORIES:
			info.dirty_categories[cat] = true
	elif category in VALID_CATEGORIES:
		info.dirty_categories[category] = true
	else:
		push_warning("SaveManager: Unknown save category '%s', treating as 'all'." % category)
		for cat in VALID_CATEGORIES:
			info.dirty_categories[cat] = true

	# (Re)start the debounce timer. Bots save on change just like real players
	# — the debounce coalesces rapid changes and the pool dispatch serializes
	# per-username, so frequent activity can't corrupt the backend row.
	if is_instance_valid(info.timer):
		info.timer.start(DEBOUNCE_TIME)


## Immediately enqueue any pending dirty data for this player and await its
## completion. Used before disconnect / map change to ensure nothing is lost.
func flush_save(username: String) -> void:
	if not _is_server() or not _players.has(username):
		return

	var info: Dictionary = _players[username]

	# Stop the debounce timer so it doesn't double-fire after we drain it.
	if is_instance_valid(info.timer):
		info.timer.stop()

	if info.dirty_categories.is_empty():
		return

	var data := _collect_save_data(username)
	if data.is_empty():
		info.dirty_categories.clear()
		return
	info.dirty_categories.clear()

	var job := SaveJob.new()
	job.username = username
	job.data = data
	job.is_flush = true

	_save_queue.append(job)
	# Defer dispatch so the `await job.completed` below is set up BEFORE the
	# synchronous local-save dispatch path could fire `_release_slot` and emit
	# the signal. Without this, in local-save mode `_send_via_slot` runs to
	# completion synchronously inside `_try_dispatch`, the signal emits, and
	# the await below would then hang forever waiting for a signal that has
	# already fired (Godot await is one-shot — it cannot catch past emissions).
	call_deferred("_try_dispatch")

	# Wait for this specific job to finish. The signal is per-job, so two
	# concurrent flush_save callers each await their own SaveJob and never
	# race for the shared HTTP pool the way the old wait-loop did.
	await job.completed


# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL — DEBOUNCE & SCHEDULING
# ═══════════════════════════════════════════════════════════════════════════

func _on_debounce_timeout(username: String) -> void:
	if not _players.has(username):
		return
	_schedule_save(username)


func _on_auto_save_timeout() -> void:
	# Periodic full-save safety net for every tracked player, bots included.
	for username in _players.keys():
		var info: Dictionary = _players[username]
		for cat in VALID_CATEGORIES:
			info.dirty_categories[cat] = true
		_schedule_save(username)


func _schedule_save(username: String) -> void:
	if not _players.has(username):
		return
	var info: Dictionary = _players[username]
	if info.dirty_categories.is_empty():
		return

	var data := _collect_save_data(username)
	if data.is_empty():
		info.dirty_categories.clear()
		return
	info.dirty_categories.clear()

	var job := SaveJob.new()
	job.username = username
	job.data = data
	job.is_flush = false

	_save_queue.append(job)
	_try_dispatch()


## Walks the queue and dispatches jobs into free pool slots. Jobs for a
## username with a save already in flight are left in place — they get picked
## up once that prior save releases the username.
func _try_dispatch() -> void:
	var i := 0
	while i < _save_queue.size():
		var slot := _find_free_slot()
		if slot == -1:
			return
		var job: SaveJob = _save_queue[i]
		if _in_flight_usernames.has(job.username):
			i += 1
			continue
		_save_queue.remove_at(i)
		_dispatch_job(slot, job)


func _find_free_slot() -> int:
	for i in _http_busy.size():
		if not _http_busy[i]:
			return i
	return -1


func _dispatch_job(slot: int, job: SaveJob) -> void:
	_http_busy[slot] = true
	_in_flight_usernames[job.username] = true
	_send_via_slot(slot, job)  # async; runs to its first await synchronously


# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL — DATA COLLECTION
# ═══════════════════════════════════════════════════════════════════════════

func _collect_save_data(username: String) -> Dictionary:
	if not _players.has(username):
		return {}

	var info: Dictionary = _players[username]

	# Validate the raw Dictionary value before the typed assignment below — a
	# typed assignment of a freed instance (e.g. a player node freed by a map
	# change before its debounce timer fired) raises a runtime error.
	if not is_instance_valid(info.node):
		push_warning("SaveManager: Player node for '%s' is invalid, skipping save." % username)
		return {}

	var player_node: Node = info.node

	if not player_node.has_method("get_save_data"):
		push_warning("SaveManager: Player node for '%s' missing get_save_data()." % username)
		return {}

	# Determine the update_type string to pass
	var dirty: Dictionary = info.dirty_categories
	var update_type: String = "all"
	if dirty.size() < VALID_CATEGORIES.size():
		var dirty_keys: Array = dirty.keys()
		if dirty_keys.size() == 1:
			update_type = dirty_keys[0]
		else:
			update_type = "all"

	var data: Dictionary = player_node.get_save_data(update_type)
	return data


# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL — HTTP SEND
# ═══════════════════════════════════════════════════════════════════════════

func _send_via_slot(slot: int, job: SaveJob) -> void:
	if NetworkManager.use_local_save:
		_save_to_file(job.data)
		_release_slot(slot, job, true, "")
		return

	var req: HTTPRequest = _http_pool[slot]
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var payload := {
		"username": job.username,
		"data": job.data,
		# Bots have no player account — the backend routes them to the shared
		# bot account so their Player row satisfies the NOT NULL account FK.
		"is_bot": BotManager.is_bot_username(job.username),
	}
	var json_body: String = JSON.stringify(payload)

	var error := req.request(_api_url + "/save", headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		push_error("SaveManager: HTTP request failed to start for '%s'. Error: %d" % [job.username, error])
		_save_to_file(job.data)
		_release_slot(slot, job, false, "HTTP request failed to start (error %d)" % error)
		return

	var result: Array = await req.request_completed
	var response_code: int = result[1]

	if response_code == 200:
		_release_slot(slot, job, true, "")
		return

	# ── First failure — retry once after RETRY_DELAY ──────────────────────
	if not job.is_flush:
		await get_tree().create_timer(RETRY_DELAY).timeout

	var retry_error := req.request(_api_url + "/save", headers, HTTPClient.METHOD_POST, json_body)
	if retry_error != OK:
		push_error("SaveManager: Retry request failed to start for '%s'." % job.username)
		_save_to_file(job.data)
		_release_slot(slot, job, false, "Retry request failed to start")
		return

	var retry_result: Array = await req.request_completed
	var retry_response_code: int = retry_result[1]

	if retry_response_code == 200:
		_release_slot(slot, job, true, "")
	else:
		push_error("SaveManager: Retry failed for '%s' (HTTP %d). Falling back to file." % [job.username, retry_response_code])
		_save_to_file(job.data)
		_release_slot(slot, job, false, "HTTP save failed after retry (code %d)" % retry_response_code)


## Frees the pool slot and unblocks anyone awaiting this job. If new dirty data
## accumulated during the in-flight window, reschedule the user. Then walk the
## queue for the next dispatch.
func _release_slot(slot: int, job: SaveJob, success: bool, err: String) -> void:
	_http_busy[slot] = false
	_in_flight_usernames.erase(job.username)

	if success:
		save_completed.emit(job.username)
	else:
		save_failed.emit(job.username, err)

	# Wake any flush_save caller awaiting this specific job.
	job.completed.emit()

	# More data dirtied during the in-flight window? Schedule another pass.
	if _players.has(job.username) and not _players[job.username].dirty_categories.is_empty():
		_schedule_save(job.username)

	_try_dispatch()


# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL — LOCAL FILE FALLBACK
# ═══════════════════════════════════════════════════════════════════════════

func _save_to_file(data: Dictionary) -> void:
	var uname: String = data.get("username", "")
	if uname.is_empty():
		push_error("SaveManager: Cannot save to file — no username in data.")
		return

	var file_path: String = "res://saves/player_%s.json" % uname

	# Create saves directory if it doesn't exist
	var dir = DirAccess.open("res://")
	if dir:
		if not dir.dir_exists("saves"):
			dir.make_dir("saves")

	var existing_data: Dictionary = {}

	if FileAccess.file_exists(file_path):
		var file_read := FileAccess.open(file_path, FileAccess.READ)
		if file_read:
			var parsed = JSON.parse_string(file_read.get_as_text())
			file_read.close()
			if parsed is Dictionary:
				existing_data = parsed

	# Merge new data into existing (overwrite matching keys)
	existing_data.merge(data, true)

	var file_write := FileAccess.open(file_path, FileAccess.WRITE)
	if file_write:
		file_write.store_string(JSON.stringify(existing_data))
		file_write.close()
	else:
		push_error("SaveManager: Failed to open file for writing: %s" % file_path)


# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _is_server() -> bool:
	if not multiplayer:
		return false
	if not multiplayer.has_multiplayer_peer():
		return false
	return multiplayer.is_server()
