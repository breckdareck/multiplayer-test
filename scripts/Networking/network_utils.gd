# NetworkUtils.gd - AutoLoad singleton
extends Node

# === IP VALIDATION ===
func is_valid_ip(text: String) -> bool:
	var parts = text.split('.')
	
	if parts.size() != 4:
		return false
	
	for part in parts:
		if not part.is_valid_int():
			return false
		
		if part.length() > 1 and part.begins_with("0"):
			return false
		
		var num = int(part)
		if num < 0 or num > 255:
			return false
	
	return true

# === NETWORK INFO ===
func get_public_ip_address() -> String:
	var upnp = UPNP.new()
	upnp.discover(2000, 2, 'InternetGatewayDevice')
	return upnp.query_external_address()

# === COMMAND LINE PARSING ===
func get_port_from_args(default_port: int = 8080) -> int:
	var args = OS.get_cmdline_args()
	
	for i in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size():
			var port_str = args[i + 1]
			if port_str.is_valid_int():
				var port = int(port_str)
				print("Using port from command line: %d" % port)
				return port
			else:
				print("ERROR: Invalid port specified: %s" % port_str)
				break
	
	print("Using default port: %d" % default_port)
	return default_port

func get_string_arg(arg_name: String, default_value: String = "") -> String:
	var args = OS.get_cmdline_args()
	
	for i in range(args.size()):
		if args[i] == arg_name and i + 1 < args.size():
			return args[i + 1]
	
	return default_value

func has_flag(flag_name: String) -> bool:
	return flag_name in OS.get_cmdline_args()

# === SCENE UTILITIES ===
func get_players_spawn_node(scene_tree: SceneTree) -> Node:
	var scene = scene_tree.current_scene.get_node_or_null("Level")
	if scene:
		return scene.find_child("Players", true, false)
	return null

func get_node_safe(node: Node, path: String) -> Node:
	if not node:
		return null
	return node.get_node_or_null(path)

# === CLEANUP UTILITIES ===
func clear_networked_entities(scene_tree: SceneTree) -> void:
	var scene_root = scene_tree.get_current_scene()
	if not scene_root:
		return
	
	for entity in scene_root.get_tree().get_nodes_in_group("networked_entities"):
		if is_instance_valid(entity):
			entity.queue_free()

func safe_disconnect_signal(signal_obj: Signal, callable_obj: Callable):
	if signal_obj.is_connected(callable_obj):
		signal_obj.disconnect(callable_obj)

# === CONNECTION TESTING ===
func test_tcp_connection(ip: String, port: int, timeout: float = 2.0) -> bool:
	var tcp = StreamPeerTCP.new()
	var error = tcp.connect_to_host(ip, port)
	
	if error != OK:
		return false
	
	var time_waited = 0.0
	while time_waited < timeout:
		tcp.poll()
		var status = tcp.get_status()
		
		if status == StreamPeerTCP.STATUS_CONNECTED:
			tcp.disconnect_from_host()
			return true
		elif status == StreamPeerTCP.STATUS_ERROR:
			return false
		
		await Engine.get_main_loop().process_frame
		time_waited += get_process_delta_time()
	
	tcp.disconnect_from_host()
	return false

# === LOGGING UTILITIES ===
func log_network_event(event_type: String, details: String = ""):
	var timestamp = Time.get_datetime_string_from_system()
	var message = "[%s] NETWORK_%s: %s" % [timestamp, event_type, details]
	print(message)

func log_connection_attempt(ip: String, port: int):
	log_network_event("CONNECT", "Attempting connection to %s:%d" % [ip, port])

func log_connection_result(success: bool, ip: String = "", port: int = 0):
	var status = "SUCCESS" if success else "FAILED"
	var details = " to %s:%d" % [ip, port] if ip != "" else ""
	log_network_event("CONNECT_" + status, details)

# === VALIDATION UTILITIES ===
func is_valid_port(port: int) -> bool:
	return port > 0 and port <= 65535

func is_port_in_range(port: int, min_port: int, max_port: int) -> bool:
	return port >= min_port and port <= max_port

# === MULTIPLAYER UTILITIES ===
func get_multiplayer_info() -> Dictionary:
	return {
		"is_server": multiplayer.is_server(),
		"unique_id": multiplayer.get_unique_id(),
		"has_peer": multiplayer.multiplayer_peer != null,
		"connected": multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	}

func format_player_id(id: int) -> String:
	if id == 1:
		return "Host"
	else:
		return "Player_%d" % id
