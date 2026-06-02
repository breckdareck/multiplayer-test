# multiplayer_manager.gd - Main AutoLoad Coordinator
extends Node

# === SIGNALS ===
signal server_has_started
signal channel_switch_started
signal channel_switch_success
signal channel_switch_failed

# === CONFIGURATION ===
const CONFIG = {
	"DEFAULT_PORT": 8080,
	"DEFAULT_IP": "127.0.0.1"
}

# === STATE ===
var host_mode_enabled: bool = false
var respawn_point: Vector2 = Vector2.ZERO
var menu_container: Control
var _pending_shutdown_reason: String = ""
var disconnect_reason: String = ""
var _was_connected_to_server: bool = false
var _handling_disconnect: bool = false
var _kicked_before_game: bool = false
var _connection_lost_scene = preload("res://scenes/UI/connection_lost_popup.tscn")
var _connection_lost_popup: CanvasLayer = null

# === INITIALIZATION ===
func _ready():
	_setup_signals()
	get_tree().set_auto_accept_quit(false)

	if OS.has_feature("dedicated_server"):
		var port = NetworkUtils.get_port_from_args(CONFIG.DEFAULT_PORT)
		ServerManager.start_dedicated_server(port)

func _process(_delta):
	if _handling_disconnect or not _was_connected_to_server:
		return
	var peer = multiplayer.multiplayer_peer
	if not peer or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		#print("MultiplayerManager: Connection lost detected via poll")
		_handle_server_disconnect()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if multiplayer.is_server():
			_graceful_shutdown()
		else:
			get_tree().quit()

func _setup_signals():
	# Forward signals from components
	ServerManager.server_started.connect(_on_server_started)
	ClientManager.connection_succeeded.connect(_on_client_connected)
	ClientManager.connection_failed.connect(_on_client_failed)
	ChannelManager.switch_started.connect(channel_switch_started.emit)
	ChannelManager.switch_success.connect(channel_switch_success.emit)
	ChannelManager.switch_failed.connect(channel_switch_failed.emit)

	# Setup core multiplayer signals
	multiplayer.connected_to_server.connect(ClientManager._on_connection_succeeded)
	multiplayer.connection_failed.connect(ClientManager._on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# === PUBLIC API ===
func host_game():
	#print("Starting listen server...")
	host_mode_enabled = true

	if ServerManager.start_listen_server(CONFIG.DEFAULT_PORT):
		PlayerManager.add_host_player()
		#print("Host server started successfully")

func join_game(ip: String = ""):
	#print("Joining game as client...")

	# Use provided IP or fall back to stored IP in ClientManager
	var target_ip = ip if not ip.is_empty() else CONFIG.DEFAULT_IP

	if not NetworkUtils.is_valid_ip(target_ip):
		#print("Invalid IP Address: " + target_ip)
		return

	ClientManager.connect_to_server(target_ip, CONFIG.DEFAULT_PORT)

func switch_channel(new_port: int):
	await ChannelManager.switch_channel(new_port)

func reset_data():
	host_mode_enabled = false
	_was_connected_to_server = false
	_handling_disconnect = false
	# Flush all player saves BEFORE closing the peer — SaveManager._is_server()
	# returns false once the peer is gone, so saves must complete while it is still active.
	if multiplayer.is_server():
		await PlayerManager.save_all_players()
	ServerManager.stop_server()
	ClientManager._disconnect()
	PlayerManager.cleanup()

	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

# === EVENT HANDLERS ===
func _on_server_started():
	server_has_started.emit()

	# Connect multiplayer signals
	if not multiplayer.peer_connected.is_connected(PlayerManager.add_player):
		multiplayer.peer_connected.connect(PlayerManager.add_player)
	if not multiplayer.peer_disconnected.is_connected(PlayerManager.remove_player):
		multiplayer.peer_disconnected.connect(PlayerManager.remove_player)

func _on_client_connected():
	#print("Successfully connected to server!")
	_was_connected_to_server = true
	_handling_disconnect = false
	_update_ui_for_client()

func _on_client_failed():
	print("Failed to connect to %s:%d" % [ClientManager.current_server_ip, ClientManager.current_server_port])

func _on_server_disconnected():
	#print("MultiplayerManager: server_disconnected signal fired")
	_handle_server_disconnect()

func _handle_server_disconnect():
	if ChannelManager.is_switching():
		return
	if _handling_disconnect:
		return
	if _kicked_before_game:
		_kicked_before_game = false
		_was_connected_to_server = false
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
		return
	_handling_disconnect = true
	_was_connected_to_server = false

	var reason = _pending_shutdown_reason if _pending_shutdown_reason != "" else "Disconnected from server."
	_pending_shutdown_reason = ""
	#print("MultiplayerManager: Cleaning up network state...")
	disconnect_reason = reason

	# Save connection info before cleanup clears them
	var ip = ClientManager.current_server_ip
	var port = ClientManager.current_server_port

	# Kill the peer first to stop all network errors
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	ClientManager._disconnect()

	# Stop music
	AudioManager.stop_song()

	# Free all networked entities and maps
	for node in get_tree().get_nodes_in_group("networked_entities"):
		node.queue_free()
	PlayerManager.cleanup()
	MapManager.reset_client_state()
	var maps_container = get_tree().root.get_node_or_null("Maps")
	if maps_container:
		get_tree().root.remove_child(maps_container)
		maps_container.free()

	#print("MultiplayerManager: Connection lost — %s" % reason)
	_show_connection_lost_popup(reason, ip, port)

func _show_connection_lost_popup(reason: String, ip: String = "", port: int = 0):
	if not _connection_lost_popup or not is_instance_valid(_connection_lost_popup):
		_connection_lost_popup = _connection_lost_scene.instantiate()
		get_tree().root.add_child(_connection_lost_popup)
	_connection_lost_popup.show_popup(reason, ip, port)


# === GRACEFUL SHUTDOWN ===

func _graceful_shutdown():
	#print("Server shutting down gracefully...")
	_notify_clients_shutdown.rpc()
	# Let the RPC packet actually send before we start tearing down
	await get_tree().create_timer(0.5).timeout
	await PlayerManager.save_all_players()
	# Close the peer properly so clients get a clean ENet disconnect
	# instead of waiting for the ~30s timeout
	ServerManager.stop_server()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	# Brief delay for disconnect packets to propagate
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()

@rpc("authority", "call_local", "reliable")
func _notify_clients_shutdown():
	if multiplayer.is_server():
		return
	_pending_shutdown_reason = "Server is shutting down."

@rpc("authority", "call_local", "reliable")
func _notify_client_kicked(reason: String):
	if multiplayer.is_server():
		return
	_pending_shutdown_reason = reason
	_kicked_before_game = true

# === PING ===
var _ping_display: Label = null

func set_ping_display(label: Label):
	_ping_display = label

@rpc("any_peer", "call_remote", "unreliable")
func _ping_request():
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	_ping_response.rpc_id(sender)

@rpc("authority", "call_remote", "unreliable")
func _ping_response():
	if _ping_display and is_instance_valid(_ping_display):
		var rtt = Time.get_ticks_msec() - _ping_display._ping_send_time
		_ping_display.text = "Ping: %dms" % rtt
		if rtt < 80:
			_ping_display.add_theme_color_override("font_color", Color.GREEN)
		elif rtt < 150:
			_ping_display.add_theme_color_override("font_color", Color.YELLOW)
		else:
			_ping_display.add_theme_color_override("font_color", Color.RED)

# === UTILITY METHODS ===
func _update_ui_for_client():
	if not menu_container or not is_instance_valid(menu_container):
		#print("MultiplayerManager: No menu container, skipping UI update")
		return
	menu_container.hide()
	if menu_container.has_method("setup_PID_label"):
		menu_container.setup_PID_label(false, multiplayer.get_unique_id())
	if menu_container.has_node("connection_panel"):
		menu_container.connection_panel.show()

# === LEGACY COMPATIBILITY ===
func get_public_IP_address() -> String:
	return NetworkUtils.get_public_ip_address()

func is_valid_ip(text: String) -> bool:
	return NetworkUtils.is_valid_ip(text)
