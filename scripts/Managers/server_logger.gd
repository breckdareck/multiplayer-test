extends Node

var _log_file: FileAccess

func _ready():
	if not OS.has_feature("dedicated_server") and not (multiplayer and multiplayer.is_server()):
		return

	var datetime = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var path = "user://server_log_%s.txt" % datetime
	_log_file = FileAccess.open(path, FileAccess.WRITE)
	if _log_file:
		print("ServerLogger: Logging to %s" % ProjectSettings.globalize_path(path))
		log_info("Server logger initialized")

	call_deferred("_connect_signals")

func _connect_signals():
	ServerManager.server_started.connect(func(): log_info("Server started on port %d" % ServerManager.get_current_port()))
	ServerManager.server_failed.connect(func(): log_error("Server failed to start"))

	multiplayer.peer_connected.connect(func(id: int): log_info("Peer connected: %d" % id))
	multiplayer.peer_disconnected.connect(func(id: int): log_info("Peer disconnected: %d" % id))

	MapManager.map_loaded.connect(func(map_id: String): log_info("Map loaded: %s" % map_id))
	MapManager.map_unloaded.connect(func(map_id: String): log_info("Map unloaded: %s" % map_id))
	MapManager.player_spawned.connect(func(player_id: int): log_info("Player spawned: %d" % player_id))

	SaveManager.save_completed.connect(func(username: String): log_info("Save completed: %s" % username))
	SaveManager.save_failed.connect(func(username: String, error: String): log_error("Save failed for %s: %s" % [username, error]))

func log_info(msg: String):
	_write_log("INFO", msg)

func log_warn(msg: String):
	_write_log("WARN", msg)

func log_error(msg: String):
	_write_log("ERROR", msg)

func flush_and_close():
	if _log_file:
		_log_file.flush()
		_log_file.close()
		_log_file = null

func _write_log(level: String, msg: String):
	if not _log_file:
		return
	var timestamp = Time.get_datetime_string_from_system()
	var line = "[%s] [%s] %s" % [timestamp, level, msg]
	_log_file.store_line(line)
	_log_file.flush()
	print(line)
