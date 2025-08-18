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
	_setup_menu_container()
	host_mode_enabled = true
	
	if ServerManager.start_listen_server(CONFIG.DEFAULT_PORT):
		PlayerManager.add_host_player()
		_update_ui_for_host()

func join_game():
	print("Joining game as client...")
	_setup_menu_container()
	
	var ip = _get_target_ip()
	if not NetworkUtils.is_valid_ip(ip):
		_show_connection_error("Invalid IP Address")
		return
	
	ClientManager.connect_to_server(ip, CONFIG.DEFAULT_PORT)

func switch_channel(new_port: int):
	await ChannelManager.switch_channel(new_port)

func reset_data():
	host_mode_enabled = false
	ServerManager.stop_server()
	ClientManager._disconnect()
	PlayerManager.cleanup()
	
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

func change_level(scene: PackedScene):
	var level = get_tree().current_scene.get_node("Level")
	for child in level.get_children():
		level.remove_child(child)
		child.queue_free()
	level.add_child(scene.instantiate())

# === EVENT HANDLERS ===
func _on_server_started():
	server_has_started.emit()
	
	# Connect multiplayer signals for both dedicated and listen servers
	# Use safe connection to avoid duplicate connections
	if not multiplayer.peer_connected.is_connected(PlayerManager.add_player):
		multiplayer.peer_connected.connect(PlayerManager.add_player)
	if not multiplayer.peer_disconnected.is_connected(PlayerManager.remove_player):
		multiplayer.peer_disconnected.connect(PlayerManager.remove_player)
	
	change_level.call_deferred(load("res://scenes/Levels/game.tscn"))

func _on_client_connected():
	print("Successfully connected to server!")
	_update_ui_for_client()

func _on_client_failed():
	print("Failed to connect to server")
	_show_connection_error("Connection Failed")

func _on_server_disconnected():
	if ChannelManager.is_switching():
		return
	
	print("Disconnected from server")
	menu_container._connection_status_label.text = "Disconnected from server."
	get_tree().change_scene_to_file("res://scenes/Levels/main_menu.tscn")

# === UTILITY METHODS ===
func _setup_menu_container():
	menu_container = get_tree().get_current_scene().get_node("%MenuContainer")
	if menu_container:
		menu_container._connection_status_label.text = ""

func _get_target_ip() -> String:
	if not menu_container:
		return CONFIG.DEFAULT_IP
	var input_ip = menu_container.ip_address_input.text
	return input_ip if not input_ip.is_empty() else CONFIG.DEFAULT_IP

func _show_connection_error(message: String):
	print("Connection error: " + message)
	if menu_container:
		menu_container._connection_status_label.text = "Error: " + message
		menu_container._join_button.disabled = false
		menu_container._host_button.disabled = false

func _update_ui_for_host():
	if not menu_container:
		return
	menu_container.hide()
	menu_container.setup_PID_label(true, multiplayer.get_unique_id())
	menu_container.connection_panel.show()

func _update_ui_for_client():
	if not menu_container:
		return
	menu_container.hide()
	menu_container.setup_PID_label(false, multiplayer.get_unique_id())
	menu_container.connection_panel.show()

# === LEGACY COMPATIBILITY ===
func get_public_IP_address() -> String:
	return NetworkUtils.get_public_ip_address()

func is_valid_ip(text: String) -> bool:
	return NetworkUtils.is_valid_ip(text)
