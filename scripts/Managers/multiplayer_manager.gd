extends Node

# Emitted when this node successfully creates a server (dedicated or listen).
signal server_has_started

# --- Configuration ---
const SERVER_PORT: int = 8080
var SERVER_IP: String = "127.0.0.1"
var multiplayer_scene: PackedScene = preload("res://scenes/multiplayer_player.tscn")

# --- State ---
var host_mode_enabled: bool = false
var respawn_point: Vector2 = Vector2(0, 0)

@onready var _players_spawn_node: Node = get_tree().get_current_scene().get_node("Players")
@onready var label: Label = get_tree().get_current_scene().get_node("CanvasLayer/MultiplayerHUD/Panel2/PlayerIDLabel")
@onready var ip_address_input: LineEdit = get_tree().get_current_scene().get_node("CanvasLayer/MultiplayerHUD/Panel/VBoxContainer/IPAddress")
@onready var _join_button: Button = get_tree().get_current_scene().get_node("CanvasLayer/MultiplayerHUD/Panel/VBoxContainer/Join")
@onready var _connection_status_label: Label = get_tree().get_current_scene().get_node("CanvasLayer/MultiplayerHUD/Panel/VBoxContainer/ConnectionStatus")

# --- Entry Point ---
func _ready():
	if OS.has_feature("dedicated_server"):
		_start_dedicated_server()
	
	# Connect signals for handling client connection status.
	multiplayer.connected_to_server.connect(_on_connection_succeeded)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Server Functions ---
func _start_dedicated_server(port: int = SERVER_PORT) -> void:
	print("--- Starting Dedicated Server ---")
	var server_peer = ENetMultiplayerPeer.new()
	var error = server_peer.create_server(port)

	if error != OK:
		print("ERROR: Could not start dedicated server on port %d." % port)
		get_tree().quit(1)
		return

	multiplayer.multiplayer_peer = server_peer
	server_has_started.emit()
		
	var IP_ADDRESS: String = get_public_IP_address()
	print("Dedicated Server started successfully on IP: %s, Port: %d." % [IP_ADDRESS, port])

	# The server listens for players connecting and disconnecting.
	multiplayer.peer_connected.connect(_add_player_to_game)
	multiplayer.peer_disconnected.connect(_del_player)


# --- UI-Driven Functions (for Clients and Listen Servers) ---

# Call this from a "Host" button in UI.
func host_game():
	print("--- Starting Listen Server (Host) ---")
	host_mode_enabled = true

	var server_peer = ENetMultiplayerPeer.new()
	server_peer.create_server(SERVER_PORT)
	multiplayer.multiplayer_peer = server_peer
	server_has_started.emit()

	multiplayer.peer_connected.connect(_add_player_to_game)
	multiplayer.peer_disconnected.connect(_del_player)

	# In listen server mode, the host is also a player.
	# We spawn a character for the host (ID 1).
	_add_player_to_game(1)
	_remove_single_player_if_exists()

	# var IP_ADDRESS: String = get_public_IP_address()
	
	label.get_parent().show()
	# Hide the connection panel since we are now hosting.
	_join_button.get_parent().get_parent().hide()
	label.text = "HOST
	PID: 1"
	# IP: %s" % IP_ADDRESS


# Call this from a "Join" button in UI.
func join_game() -> void:
	print("--- Joining Game (Client) ---")
	_connection_status_label.text = "" # Clear previous status/errors

	var ip_to_join: String = ip_address_input.text
	if ip_to_join.is_empty():
		ip_to_join = SERVER_IP # Use default if empty

	if not is_valid_ip(ip_to_join):
		print("%s isn't a valid IP" % ip_to_join)
		_connection_status_label.text = "Error: Invalid IP Address."
		return

	_connection_status_label.text = "Connecting to %s..." % ip_to_join
	_join_button.disabled = true

	var client_peer = ENetMultiplayerPeer.new()
	var error = client_peer.create_client(ip_to_join, SERVER_PORT)

	if error != OK:
		_connection_status_label.text = "Error: Could not create client."
		_join_button.disabled = false
		return

	multiplayer.multiplayer_peer = client_peer


# --- Client-Side Connection Handlers ---

func _on_connection_succeeded() -> void:
	print("Successfully connected to the server!")
	# Connection is successful, now we can change the UI and game state.
	_remove_single_player_if_exists()

	# Hide the connection UI (the Panel with the IP input and buttons)
	# and show the in-game HUD (Panel2).
	_join_button.get_parent().get_parent().hide()

	label.get_parent().show()
	label.text = "CLIENT
	PID: %s" % multiplayer.get_unique_id()


func _on_connection_failed() -> void:
	print("ERROR: Could not connect to the server.")
	multiplayer.multiplayer_peer = null

	_connection_status_label.text = "Error: Connection Failed."
	_join_button.disabled = false


func _on_server_disconnected() -> void:
	print("Disconnected from the server.")
	multiplayer.multiplayer_peer = null

	# Reset UI to the pre-connection state.
	_connection_status_label.text = "Disconnected from server."
	_join_button.disabled = false
	_join_button.get_parent().get_parent().show()
	label.get_parent().hide()
	# For a robust reset, you might want to reload the entire scene.
	get_tree().reload_current_scene()

# --- Player Management (Server-Side) ---

# This function is now called for ANY connecting player, including the host in listen mode.
func _add_player_to_game(id: int):
	print("Player %s joined the game! Spawning character." % id)
	
	# When a new client joins, we must sync the state of all existing entities
	# to them. This loop will be empty for the very first player (the host).
	for entity in get_tree().get_nodes_in_group("networked_entities"):
		# Sync the StateMachine so they see the correct animation.
		var state_machine: Node = entity.get_node_or_null("StateMachine")
		if state_machine:
			state_machine.sync_state_to_peer(id)

	# Now, spawn the character for the newly connected player.
	var player_to_add: Node = multiplayer_scene.instantiate()
	player_to_add.player_id = id
	player_to_add.name = str(id)
	_players_spawn_node.add_child(player_to_add, true)


func _del_player(id: int) -> void:
	print("Player %s left the game! Removing character." % id)
	if _players_spawn_node.has_node(str(id)):
		_players_spawn_node.get_node(str(id)).queue_free()


# --- Utility ---

# Helper to remove the default single-player character when entering multiplayer.
func _remove_single_player_if_exists():
	var scene_root: Node = get_tree().get_current_scene()
	if scene_root.has_node("Player"):
		print("Removing single player character.")
		scene_root.get_node("Player").queue_free()

func get_public_IP_address() -> String:
	var upnp = UPNP.new()
	upnp.discover(2000, 2, 'InternetGatewayDevice')
	return upnp.query_external_address()

func is_valid_ip(text: String) -> bool:
	var parts = text.split('.')

	# An IPv4 address must have exactly 4 parts.
	if parts.size() != 4:
		return false

	for part in parts:
		# Check if the part is a number.
		if not part.is_valid_int():
			return false
			
		# Prevent invalid numbers like "01" or "00".
		if part.length() > 1 and part.begins_with("0"):
			return false

		var num = int(part)

		# Each part must be between 0 and 255.
		if num < 0 or num > 255:
			return false

	return true
