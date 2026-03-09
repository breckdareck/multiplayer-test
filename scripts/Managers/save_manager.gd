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

signal save_completed(username: String)
signal save_failed(username: String, error: String)

# ── Configuration ──────────────────────────────────────────────────────────
const DEBOUNCE_TIME: float = 0.5        # seconds before a queued save fires
const AUTO_SAVE_INTERVAL: float = 60.0  # periodic full save for all players
const RETRY_DELAY: float = 1.0          # delay before a single retry
const HTTP_TIMEOUT: float = 5.0         # per-request timeout
const HTTP_POOL_SIZE: int = 4           # parallel HTTP save slots

const VALID_CATEGORIES: PackedStringArray = [
	"stats", "inventory", "abilities", "buffs", "equipment"
]

var _api_url: String = ""  # Will be loaded from UserConfig

# ── Per-player tracking ───────────────────────────────────────────────────
## Registered players: username -> { node, dirty_categories, timer, in_flight }
var _players: Dictionary = {}

# ── Nodes ─────────────────────────────────────────────────────────────────
var _http_pool: Array[HTTPRequest] = []
var _auto_save_timer: Timer

# ── In-flight tracking (parallel saves via pool) ─────────────────────────
var _in_flight: Dictionary = {}        # username -> true
var _pending_queue: Array[String] = [] # usernames waiting for a free slot


func _ready() -> void:
	# Load API URL from config (supports environment variable override)
	_api_url = UserConfig.get_backend_api_url() + "/player"
	print("SaveManager: Using API URL: %s" % _api_url)
	
	# SaveManager only does work on the server
	if not _is_server():
		return

	# Pool of HTTPRequest nodes for parallel saves
	for i in range(HTTP_POOL_SIZE):
		var http = HTTPRequest.new()
		http.name = "SaveHTTP_%d" % i
		http.timeout = HTTP_TIMEOUT
		add_child(http)
		_http_pool.append(http)

	# Auto-save timer
	_auto_save_timer = Timer.new()
	_auto_save_timer.name = "AutoSaveTimer"
	_auto_save_timer.wait_time = AUTO_SAVE_INTERVAL
	_auto_save_timer.autostart = true
	_auto_save_timer.one_shot = false
	add_child(_auto_save_timer)
	_auto_save_timer.timeout.connect(_on_auto_save_timeout)

	print("SaveManager: Initialized on server.")


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
		"in_flight": false,
	}
	print("SaveManager: Registered player '%s'." % username)


## Unregister a player. Flushes any pending data first.
func unregister_player(username: String) -> void:
	if not _is_server() or not _players.has(username):
		return

	# Flush remaining data before removing
	flush_save(username)

	var info: Dictionary = _players[username]
	if is_instance_valid(info.timer):
		info.timer.stop()
		info.timer.queue_free()

	_players.erase(username)

	# Clean up pending queue references
	_pending_queue.erase(username)

	print("SaveManager: Unregistered player '%s'." % username)


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

	# (Re)start debounce timer
	if is_instance_valid(info.timer):
		info.timer.start(DEBOUNCE_TIME)


## Immediately collect and send any pending dirty data for this player.
## Used before disconnect / map change to ensure nothing is lost.
func flush_save(username: String) -> void:
	if not _is_server() or not _players.has(username):
		return

	var info: Dictionary = _players[username]

	# Stop the debounce timer so it doesn't double-fire
	if is_instance_valid(info.timer):
		info.timer.stop()

	# If nothing is dirty, skip
	if info.dirty_categories.is_empty():
		return

	# Collect data and save synchronously (blocking via local file as last resort)
	var data := _collect_save_data(username)
	if data.is_empty():
		return

	# If all pool slots are busy, fall back to file save for the flush
	var http = _get_free_http()
	if not http:
		print("SaveManager: Flush for '%s' — HTTP pool busy, saving to file." % username)
		_save_to_file(data)
		info.dirty_categories.clear()
		save_completed.emit(username)
		return

	# Otherwise attempt HTTP save (blocking via await)
	info.dirty_categories.clear()
	await _send_http_save(username, data, true, http)  # is_flush = true


# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL — DEBOUNCE & SCHEDULING
# ═══════════════════════════════════════════════════════════════════════════

func _on_debounce_timeout(username: String) -> void:
	if not _players.has(username):
		return
	_schedule_save(username)


func _on_auto_save_timeout() -> void:
	for username in _players.keys():
		# Mark everything dirty for auto-save
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

	# Skip if already in flight
	if _in_flight.has(username):
		return

	# If no free HTTP slot, queue this username for later
	var http = _get_free_http()
	if not http:
		if username not in _pending_queue:
			_pending_queue.append(username)
		return

	# Collect data now (lazy collection)
	var data := _collect_save_data(username)
	if data.is_empty():
		info.dirty_categories.clear()
		return

	info.dirty_categories.clear()
	_send_http_save(username, data, false, http)


func _process_pending_queue() -> void:
	while not _pending_queue.is_empty() and _get_free_http() != null:
		var next_username: String = _pending_queue.pop_front()
		if _players.has(next_username):
			_schedule_save(next_username)


# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL — DATA COLLECTION
# ═══════════════════════════════════════════════════════════════════════════

func _collect_save_data(username: String) -> Dictionary:
	if not _players.has(username):
		return {}

	var info: Dictionary = _players[username]
	var player_node: Node = info.node

	if not is_instance_valid(player_node):
		push_warning("SaveManager: Player node for '%s' is invalid, skipping save." % username)
		return {}

	if not player_node.has_method("get_save_data"):
		push_warning("SaveManager: Player node for '%s' missing get_save_data()." % username)
		return {}

	# Determine the update_type string to pass
	var dirty: Dictionary = info.dirty_categories
	var update_type: String = "all"
	if dirty.size() < VALID_CATEGORIES.size():
		# Only some categories are dirty — but _get_save_data only supports
		# one category string OR "all". If multiple categories are dirty,
		# just request "all" to be safe.
		var dirty_keys: Array = dirty.keys()
		if dirty_keys.size() == 1:
			update_type = dirty_keys[0]
		else:
			update_type = "all"

	var data: Dictionary = player_node.get_save_data(update_type)
	return data


# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL — HTTP SAVE
# ═══════════════════════════════════════════════════════════════════════════

func _get_free_http() -> HTTPRequest:
	for http in _http_pool:
		if not http.get_meta("busy", false):
			return http
	return null


func _send_http_save(username: String, data: Dictionary, is_flush: bool, http: HTTPRequest) -> void:
	# Check local-save-only mode
	if NetworkManager.use_local_save:
		print("SaveManager: Local save mode — writing file for '%s'." % username)
		_save_to_file(data)
		save_completed.emit(username)
		return

	http.set_meta("busy", true)
	_in_flight[username] = true

	var payload := {
		"username": username,
		"data": data,
	}
	var json_body: String = JSON.stringify(payload)
	var headers: PackedStringArray = ["Content-Type: application/json"]

	var error := http.request(_api_url + "/save", headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		push_error("SaveManager: HTTP request failed to start for '%s'. Error: %d" % [username, error])
		http.set_meta("busy", false)
		_in_flight.erase(username)
		_save_to_file(data)
		save_failed.emit(username, "HTTP request failed to start (error %d)" % error)
		_process_pending_queue()
		return

	var result: Array = await http.request_completed
	var response_code: int = result[1]

	if response_code == 200:
		print("SaveManager: Saved '%s' to API successfully." % username)
		http.set_meta("busy", false)
		_in_flight.erase(username)
		save_completed.emit(username)

		if _players.has(username) and not _players[username].dirty_categories.is_empty():
			_schedule_save(username)

		_process_pending_queue()
		return

	# ── First failure — retry once after RETRY_DELAY ──────────────────────
	print("SaveManager: Save failed for '%s' (HTTP %d). Retrying in %0.1fs..." % [username, response_code, RETRY_DELAY])

	if not is_flush:
		await get_tree().create_timer(RETRY_DELAY).timeout

	var retry_error := http.request(_api_url + "/save", headers, HTTPClient.METHOD_POST, json_body)
	if retry_error != OK:
		push_error("SaveManager: Retry request failed to start for '%s'." % username)
		http.set_meta("busy", false)
		_in_flight.erase(username)
		_save_to_file(data)
		save_failed.emit(username, "Retry request failed to start")
		_process_pending_queue()
		return

	var retry_result: Array = await http.request_completed
	var retry_response_code: int = retry_result[1]

	http.set_meta("busy", false)
	_in_flight.erase(username)

	if retry_response_code == 200:
		print("SaveManager: Retry succeeded for '%s'." % username)
		save_completed.emit(username)
	else:
		push_error("SaveManager: Retry failed for '%s' (HTTP %d). Falling back to file." % [username, retry_response_code])
		_save_to_file(data)
		save_failed.emit(username, "HTTP save failed after retry (code %d)" % retry_response_code)

	if _players.has(username) and not _players[username].dirty_categories.is_empty():
		_schedule_save(username)
	_process_pending_queue()


# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL — LOCAL FILE FALLBACK
# ═══════════════════════════════════════════════════════════════════════════

func _save_to_file(data: Dictionary) -> void:
	var uname: String = data.get("username", "")
	if uname.is_empty():
		push_error("SaveManager: Cannot save to file — no username in data.")
		return

	var file_path: String = "res://saves/player_%s.json" % uname
	var save_dir = "res://saves"
	
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
		print("SaveManager: Saved to local file for '%s' at %s" % [uname, file_path])
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
