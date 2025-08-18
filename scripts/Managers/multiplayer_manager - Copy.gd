extends Node

# Emitted when this node successfully creates a server (dedicated or listen).
signal server_has_started

# Emitted during the channel switching process for UI feedback.
signal channel_switch_started
signal channel_switch_success
signal channel_switch_failed

# --- Configuration ---
const SERVER_PORT: int = 8080
var SERVER_IP: String = "127.0.0.1"
var multiplayer_player_warrior: PackedScene = preload("res://scenes/multiplayer_player.tscn")
var multiplayer_player_swordsman: PackedScene = preload("res://scenes/Player/swordsman_player.tscn")
var multiplayer_player_archer: PackedScene = preload("res://scenes/Player/archer_player.tscn")
var multiplayer_player_mage: PackedScene = preload("res://scenes/Player/mage_player.tscn")

# --- State ---
var host_mode_enabled: bool = false
var respawn_point: Vector2 = Vector2(0, 0)

var current_server_ip: String = ""
var current_server_port: int = 0
var _is_switching_channels: bool = false

var menu_container: Control


# --- Entry Point ---
func _ready():
	if OS.has_feature("dedicated_server"):
		var port: int = _get_port_from_args()
		_start_dedicated_server(port)

	# Connect signals for handling client connection status.
	multiplayer.connected_to_server.connect(_on_connection_succeeded)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Server Functions ---
func _start_dedicated_server(port: int = SERVER_PORT) -> void:
	print("--- Starting Dedicated Server ---")
	print("Process ID: %d" % OS.get_process_id())

	const MAX_PORT_ATTEMPTS: int = 10
	var server_peer = ENetMultiplayerPeer.new()

	for i in range(MAX_PORT_ATTEMPTS):
		var current_port = port + i
		var error = server_peer.create_server(current_port)

		if error == OK:
			print("Server started successfully on port %d." % current_port)
			multiplayer.multiplayer_peer = server_peer
			server_has_started.emit()

			var IP_ADDRESS: String = get_public_IP_address()
			print("Dedicated Server started successfully on IP: %s, Port: %d." % [IP_ADDRESS, current_port])

			# The server listens for players connecting and disconnecting.
			multiplayer.peer_connected.connect(_add_player_to_game)
			multiplayer.peer_disconnected.connect(_del_player)

			change_level.call_deferred(load("res://scenes/Levels/game.tscn"))

			return

		print("ERROR: Could not start dedicated server on port %d. Trying next port..." % current_port)

	# If the loop completes, all attempts have failed.
	print("ERROR: Could not start dedicated server after %d attempts. Quitting." % MAX_PORT_ATTEMPTS)
	get_tree().quit(1)


# Parse command line arguments to get the port
func _get_port_from_args() -> int:
	var args = OS.get_cmdline_args()
	var default_port = SERVER_PORT

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

# --- UI-Driven Functions (for Clients and Listen Servers) ---

# Call this from a "Host" button in UI.
func host_game():
	print("--- Starting Listen Server (Host) ---")
	menu_container = get_tree().get_current_scene().get_node("%MenuContainer")
	host_mode_enabled = true

	var server_peer = ENetMultiplayerPeer.new()
	server_peer.create_server(SERVER_PORT)
	multiplayer.multiplayer_peer = server_peer
	server_has_started.emit()

	multiplayer.peer_connected.connect(_add_player_to_game)
	multiplayer.peer_disconnected.connect(_del_player)

	change_level.call_deferred(load("res://scenes/Levels/game.tscn"))

	# In listen server mode, the host is also a player.
	# We spawn a character for the host (ID 1).
	_add_player_to_game.call_deferred(1)

	menu_container.hide()
	menu_container.setup_PID_label(true, multiplayer.multiplayer_peer.get_unique_id())
	menu_container.connection_panel.show()

# var IP_ADDRESS: String = get_public_IP_address()


# Call this from a "Join" button in UI.
func join_game() -> void:
	print("--- Joining Game (Client) ---")
	menu_container = get_tree().get_current_scene().get_node("%MenuContainer")

	menu_container._connection_status_label.text = "" # Clear previous status/errors

	var ip_to_join: String = menu_container.ip_address_input.text
	if ip_to_join.is_empty():
		ip_to_join = SERVER_IP # Use default if empty

	if not is_valid_ip(ip_to_join):
		print("%s isn't a valid IP" % ip_to_join)
		menu_container._connection_status_label.text = "Error: Invalid IP Address."
		return

	menu_container._connection_status_label.text = "Connecting to %s..." % ip_to_join
	menu_container._host_button.disabled = true
	menu_container._join_button.disabled = true

	var client_peer = ENetMultiplayerPeer.new()
	# Store connection details in case we need to switch channels later.
	current_server_ip = ip_to_join
	current_server_port = SERVER_PORT
	var error = client_peer.create_client(current_server_ip, current_server_port)

	if error != OK:
		menu_container._connection_status_label.text = "Error: Could not create client."
		menu_container._join_button.disabled = false
		menu_container._host_button.disabled = false
		return

	multiplayer.multiplayer_peer = client_peer

# --- Client-Side Connection Handlers ---

func _on_connection_succeeded() -> void:
	print("Successfully connected to the server!")
	menu_container.hide()
	menu_container.setup_PID_label(false, multiplayer.multiplayer_peer.get_unique_id())
	menu_container.connection_panel.show()


func _on_connection_failed() -> void:
	print("ERROR: Could not connect to the server.")
	multiplayer.multiplayer_peer = null
	current_server_ip = ""
	current_server_port = 0

	menu_container._connection_status_label.text = "Error: Connection Failed."
	menu_container._join_button.disabled = false
	menu_container._host_button.disabled = false


func _on_server_disconnected() -> void:
	print("Disconnected from the server.")
	# If we are in the middle of a channel switch, the switch logic will handle everything.
	# We must not execute the default disconnection behavior (like returning to the main menu).
	if _is_switching_channels:
		return

	multiplayer.multiplayer_peer = null

	# Reset UI to the pre-connection state.
	menu_container._connection_status_label.text = "Disconnected from server."
	get_tree().change_scene_to_file("res://scenes/Levels/main_menu.tscn")


# --- Channel Switching (Client-Side) ---


func switch_channel(new_port: int) -> void:
	await _async_switch_channel(new_port)


func _async_switch_channel(new_port: int) -> void:
	# Can't switch if we are the server or not connected.
	if multiplayer.is_server() or not multiplayer.multiplayer_peer:
		return

	if new_port == current_server_port:
		print("Already connected to this channel port.")
		return

	_is_switching_channels = true
	channel_switch_started.emit()
	print("Attempting to switch to channel on port %d..." % new_port)

	# Store connection info for potential rollback
	var old_peer: MultiplayerPeer = multiplayer.multiplayer_peer

	# Skip the pre-test and go directly to the switch
	# This eliminates any possibility of peer conflicts
	print("Testing connection...")
	var connection_succeeded = await _test_connection_simple(current_server_ip, new_port)
	if connection_succeeded:
		var switch_success = await _perform_clean_switch(old_peer, new_port)

		if switch_success:
			print("Successfully switched to channel on port %d." % new_port)
			channel_switch_success.emit()
		else:
			print("Failed to switch to channel on port %d." % new_port)
			# Since we already disconnected, handle as complete disconnection
			current_server_ip = ""
			current_server_port = 0
			menu_container._connection_status_label.text = "Channel switch failed. Disconnected."
			get_tree().change_scene_to_file("res://scenes/Levels/main_menu.tscn")
			channel_switch_failed.emit()
	else:
		print("Failed to switch to channel on port %d." % new_port)
		channel_switch_failed.emit()

	_is_switching_channels = false


func _temporarily_disable_connection_signals() -> void:
	# Disconnect multiplayer signals to prevent issues during switch
	if multiplayer.peer_connected.is_connected(_add_player_to_game):
		multiplayer.peer_connected.disconnect(_add_player_to_game)
	if multiplayer.peer_disconnected.is_connected(_del_player):
		multiplayer.peer_disconnected.disconnect(_del_player)


# --- Player Management (Server-Side) ---

@rpc("call_local","any_peer") 
func request_selected_character_from_client(id: int):
	#print("Client: Selected %s " % str(menu_container.selected_character))
	rpc_id(1, "receive_selected_character_from_client", id, menu_container.selected_character)

@rpc("call_local","any_peer")
func receive_selected_character_from_client(id: int, value: int):
	#print("Server: Received Value %s from Client %s" % [str(value),str(id)])
	_create_character_for_client(id, value)
	

func _create_character_for_client(id: int, value: int):
	var player_to_add: Node
	match value:
		0:
			player_to_add = multiplayer_player_swordsman.instantiate()
		1:
			player_to_add = multiplayer_player_archer.instantiate()
		2:
			player_to_add = multiplayer_player_mage.instantiate()
		_:
			player_to_add = multiplayer_player_warrior.instantiate()

	player_to_add.player_id = id
	player_to_add.name = str(id)

	var players_spawn_node = _get_players_spawn_node()
	if players_spawn_node:
		players_spawn_node.add_child(player_to_add, true)
	else:
		push_error("Could not find 'Players' node in the current scene when adding player.")
	

func _add_player_to_game(id: int):
	print("Player %s joined the game! Spawning character." % id)

	# When a new client joins, we must sync the state of all existing entities
	# to them. This loop will be empty for the very first player (the host).
	for entity in get_tree().get_nodes_in_group("networked_entities"):
		# Sync the StateMachine so they see the correct animation.
		var state_machine: Node = entity.get_node_or_null("StateMachine")
		if state_machine:
			state_machine.sync_state_to_peer(id)

	rpc_id(id, "request_selected_character_from_client", id)


func _del_player(id: int) -> void:
	print("Player %s left the game! Removing character." % id)
	var players_spawn_node = _get_players_spawn_node()
	if players_spawn_node and players_spawn_node.has_node(str(id)):
		players_spawn_node.get_node(str(id)).queue_free()


# --- Utility ---
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


func _get_players_spawn_node() -> Node:
	var scene = get_tree().current_scene.get_node("Level")
	if scene:
		# Recursively search for the "Players" node, instead of only checking immediate children.
		return scene.find_child("Players", true, false)
	return null


func reset_data():
	host_mode_enabled = false
	_temporarily_disable_connection_signals()
	# Close and null the peer if it exists
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	await get_tree().process_frame
	_clear_networked_entities()


func _clear_networked_entities() -> void:
	"""
	Removes all networked entities (including players) from the scene.
	This is a client-side cleanup crucial for clearing the state of the old world 
	before a new world's state is synchronized (e.g., when switching channels or returning to menu).
	It iterates through a group, which is more robust than relying on scene structure.
	"""
	# NOTE: Ensure your player and other networked objects are in the "networked_entities" group.
	var scene_root = get_tree().get_current_scene()
	if scene_root:
		for entity in scene_root.get_tree().get_nodes_in_group("networked_entities"):
			entity.queue_free()


func change_level(scene: PackedScene):
	# Remove old level if any.
	var level = get_tree().current_scene.get_node("Level")
	for c in level.get_children():
		level.remove_child(c)
		c.queue_free()
	# Add new level.
	level.add_child(scene.instantiate())


# Alternative simpler approach - UDP socket test for ENet servers
func _test_connection_simple(ip: String, port: int) -> bool:
	# ENet servers use UDP, not TCP, so let's try a different approach
	# We'll use a very quick ENet connection test with immediate disconnection

	var test_peer = ENetMultiplayerPeer.new()
	var error = test_peer.create_client(ip, port)

	if error != OK:
		print("Failed to create ENet test client: Error %d" % error)
		return false

	# Very short timeout for just basic reachability
	const TIMEOUT: float = 2.0
	var time_waited: float = 0.0
	var connection_succeeded: bool = false

	while time_waited < TIMEOUT:
		test_peer.poll()
		var status = test_peer.get_connection_status()

		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			connection_succeeded = true
			break

		if status == MultiplayerPeer.CONNECTION_DISCONNECTED and time_waited > 0.2:
			# If it disconnects quickly, it might mean server rejected us
			# but at least we know something is listening on that port
			connection_succeeded = true
			break

		await get_tree().process_frame
		time_waited += get_process_delta_time()

	# Important: Close the test peer immediately to avoid conflicts
	test_peer.close()

	# Give it a moment to properly close
	await get_tree().process_frame

	return connection_succeeded


# Clean switch method that properly handles the transition
func _perform_clean_switch(old_peer: ENetMultiplayerPeer, new_port: int) -> bool:
	print("Starting clean switch process...")

	# Step 1: Temporarily disable signal handlers
	_temporarily_disable_connection_signals()

	# Step 2: Clean up old game state but keep the connection alive for now
	_clear_networked_entities()

	# Step 3: Wait for entity cleanup
	await get_tree().process_frame

	# Step 4: Now disconnect from old server
	print("Disconnecting from old server...")
	old_peer.close()
	multiplayer.multiplayer_peer = null

	# Step 5: Wait for proper cleanup - be more thorough
	print("Waiting for cleanup...")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame  # Extra frames for safety

	# Step 6: Force garbage collection if available to clean up any lingering references
	if Engine.has_method("force_garbage_collection"):
		print("Forcing garbage collection...")
		# This method doesn't exist, but let's add extra wait time instead
		pass

	# Extra wait time to ensure ENet cleanup
	await get_tree().create_timer(0.1).timeout

	print("Creating new connection to port %d..." % new_port)

	# Step 7: Create and connect new peer
	var new_peer = ENetMultiplayerPeer.new()
	var error = new_peer.create_client(current_server_ip, new_port)

	if error != OK:
		print("ERROR: Failed to create new client during switch! Error: %d" % error)
		return false

	multiplayer.multiplayer_peer = new_peer
	current_server_port = new_port

	# Step 8: Wait for the connection to establish with timeout
	print("Waiting for new connection to establish...")
	const TIMEOUT: float = 8.0  # Longer timeout
	var time_waited: float = 0.0

	while time_waited < TIMEOUT:
		var status = new_peer.get_connection_status()

		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			# Connection successful!
			print("New connection established successfully!")
			menu_container.setup_PID_label(false, multiplayer.get_unique_id())
			return true

		if status == MultiplayerPeer.CONNECTION_DISCONNECTED and time_waited > 0.5:
			print("New connection was rejected or failed")
			return false

		await get_tree().process_frame
		time_waited += get_process_delta_time()

	print("New connection timed out after %.2f seconds" % TIMEOUT)
	return false
