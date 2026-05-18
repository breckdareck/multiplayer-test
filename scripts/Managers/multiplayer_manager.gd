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
var _connection_lost_scene = preload("res://scenes/UI/connection_lost_popup.tscn")
var _connection_lost_popup: CanvasLayer = null

# === INITIALIZATION ===
func _ready():
	_setup_signals()
	
	if OS.has_feature("dedicated_server"):
		var port = NetworkUtils.get_port_from_args(CONFIG.DEFAULT_PORT)
		ServerManager.start_dedicated_server(port)

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
	print("Starting listen server...")
	host_mode_enabled = true
	
	if ServerManager.start_listen_server(CONFIG.DEFAULT_PORT):
		PlayerManager.add_host_player()
		print("Host server started successfully")

func join_game(ip: String = ""):
	print("Joining game as client...")
	
	# Use provided IP or fall back to stored IP in ClientManager
	var target_ip = ip if not ip.is_empty() else CONFIG.DEFAULT_IP
	
	if not NetworkUtils.is_valid_ip(target_ip):
		print("Invalid IP Address: " + target_ip)
		return
	
	ClientManager.connect_to_server(target_ip, CONFIG.DEFAULT_PORT)

func switch_channel(new_port: int):
	await ChannelManager.switch_channel(new_port)

func reset_data():
	host_mode_enabled = false
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
	print("Successfully connected to server!")
	_update_ui_for_client()

func _on_client_failed():
	print("Failed to connect to server")

func _on_server_disconnected():
	if ChannelManager.is_switching():
		return
	print("Disconnected from server")
	var ip = ClientManager.current_server_ip
	var port = ClientManager.current_server_port
	var reason = "Lost connection to %s:%d" % [ip, port]
	_show_connection_lost_popup(reason, ip, port)

func _show_connection_lost_popup(reason: String, ip: String = "", port: int = 0):
	if not _connection_lost_popup or not is_instance_valid(_connection_lost_popup):
		_connection_lost_popup = _connection_lost_scene.instantiate()
		get_tree().root.add_child(_connection_lost_popup)
	_connection_lost_popup.show_popup(reason, ip, port)


# === UTILITY METHODS ===
# These methods are deprecated - kept for backward compatibility with main_menu
func _setup_menu_container():
	# Try to get menu_container if it exists (for backward compatibility)
	var scene = get_tree().get_current_scene()
	if scene.has_node("%MenuContainer"):
		menu_container = scene.get_node("%MenuContainer")
		if menu_container and menu_container.has_method("get_node") and menu_container.has_node("connection_status_label"):
			menu_container.connection_status_label.text = ""

func _update_ui_for_host():
	if not menu_container or not is_instance_valid(menu_container):
		print("MultiplayerManager: No menu container, skipping UI update")
		return
	menu_container.hide()
	if menu_container.has_method("setup_PID_label"):
		menu_container.setup_PID_label(true, multiplayer.get_unique_id())
	if menu_container.has_node("connection_panel"):
		menu_container.connection_panel.show()

func _update_ui_for_client():
	if not menu_container or not is_instance_valid(menu_container):
		print("MultiplayerManager: No menu container, skipping UI update")
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
