# channel_manager.gd - AutoLoad singleton
extends Node

signal switch_started
signal switch_success
signal switch_failed

const SWITCH_TIMEOUT = 2.0
const CONNECTION_TIMEOUT = 8.0

var _is_switching: bool = false
var _switch_start_time: float = 0.0

func switch_channel(new_port: int):
	"""Public API for switching channels"""
	if not _can_switch_channels(new_port):
		return
	
	await _perform_channel_switch(new_port)

func is_switching() -> bool:
	return _is_switching

func get_switch_progress() -> Dictionary:
	return {
		"switching": _is_switching,
		"start_time": _switch_start_time,
		"elapsed": Time.get_time_dict_from_system().hour * 3600 + Time.get_time_dict_from_system().minute * 60 + Time.get_time_dict_from_system().second - _switch_start_time if _is_switching else 0.0
	}

func _can_switch_channels(new_port: int) -> bool:
	"""Check if channel switching is possible"""
	if multiplayer.is_server():
		print("Cannot switch channels: running as server")
		return false
	
	if not multiplayer.multiplayer_peer:
		print("Cannot switch channels: not connected")
		return false
	
	if new_port == ClientManager.current_server_port:
		print("Already connected to port %d" % new_port)
		return false
	
	if _is_switching:
		print("Channel switch already in progress")
		return false
	
	if not NetworkUtils.is_valid_port(new_port):
		print("Invalid port: %d" % new_port)
		return false
	
	return true

func _perform_channel_switch(new_port: int):
	"""Execute the channel switching process"""
	_is_switching = true
	_switch_start_time = Time.get_time_dict_from_system().hour * 3600 + Time.get_time_dict_from_system().minute * 60 + Time.get_time_dict_from_system().second
	switch_started.emit()
	
	print("Starting channel switch to port %d..." % new_port)
	NetworkUtils.log_network_event("CHANNEL_SWITCH_START", "Target port: %d" % new_port)
	
	# Test if new channel is reachable
	var can_connect = await _test_channel_connection(new_port)
	if not can_connect:
		print("Channel switch failed: cannot reach port %d" % new_port)
		NetworkUtils.log_network_event("CHANNEL_SWITCH_FAIL", "Cannot reach port %d" % new_port)
		switch_failed.emit()
		_is_switching = false
		return
	
	# Perform the actual switch
	var switch_successful = await _execute_channel_switch(new_port)
	
	if switch_successful:
		print("Channel switch successful to port %d!" % new_port)
		NetworkUtils.log_network_event("CHANNEL_SWITCH_SUCCESS", "Switched to port %d" % new_port)
		switch_success.emit()
	else:
		print("Channel switch failed during execution")
		NetworkUtils.log_network_event("CHANNEL_SWITCH_FAIL", "Execution failed for port %d" % new_port)
		switch_failed.emit()
		_handle_switch_failure()
	
	_is_switching = false

func _test_channel_connection(port: int) -> bool:
	"""Test if we can connect to the target channel"""
	print("Testing connection to port %d..." % port)
	
	var test_peer = ClientManager.create_new_peer(ClientManager.current_server_ip, port)
	if not test_peer:
		return false
	
	var time_waited = 0.0
	var can_connect = false
	
	while time_waited < SWITCH_TIMEOUT:
		test_peer.poll()
		var status = test_peer.get_connection_status()
		
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			can_connect = true
			print("Connection test successful")
			break
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED and time_waited > 0.2:
			# Server exists but may have rejected us - this is still a valid test
			can_connect = true
			print("Connection test completed (server responded)")
			break
		
		await get_tree().process_frame
		time_waited += get_process_delta_time()
	
	test_peer.close()
	await get_tree().process_frame  # Allow cleanup
	
	return can_connect

func _execute_channel_switch(new_port: int) -> bool:
	"""Execute the actual channel switch"""
	print("Executing channel switch to port %d..." % new_port)
	
	# Store old connection info
	var old_peer = multiplayer.multiplayer_peer
	var old_ip = ClientManager.current_server_ip
	
	# Step 2: Clean up game state
	print("Cleaning up game state...")
	PlayerManager.cleanup()
	await get_tree().process_frame
	
	# Step 3: Disconnect from old server
	print("Disconnecting from old server...")
	old_peer.close()
	multiplayer.multiplayer_peer = null
	
	# Step 4: Wait for proper cleanup
	await get_tree().create_timer(0.1).timeout
	
	# Step 5: Create new connection
	print("Creating new connection to port %d..." % new_port)
	var new_peer = ClientManager.create_new_peer(old_ip, new_port)
	if not new_peer:
		print("Failed to create new peer")
		return false
	
	multiplayer.multiplayer_peer = new_peer
	ClientManager.current_server_port = new_port
	
	# Step 6: Wait for connection to establish
	print("Waiting for connection to establish...")
	var time_waited = 0.0
	var connected = false
	
	while time_waited < CONNECTION_TIMEOUT:
		var status = new_peer.get_connection_status()
		
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			connected = true
			print("New connection established!")
			break
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED and time_waited > 0.5:
			print("New connection was rejected")
			break
		
		await get_tree().process_frame
		time_waited += get_process_delta_time()
	
	if connected:
		_update_ui_after_switch()
	
	return connected
	

func _update_ui_after_switch():
	"""Update UI elements after successful switch"""
	var menu_container = get_tree().get_current_scene().get_node_or_null("%MenuContainer")
	if menu_container and menu_container.has_method("setup_PID_label"):
		menu_container.setup_PID_label(false, multiplayer.get_unique_id())

func _handle_switch_failure():
	"""Handle complete failure of channel switch"""
	print("Handling channel switch failure...")
	ClientManager.cleanup()
	
	var menu_container = get_tree().get_current_scene().get_node_or_null("%MenuContainer")
	if menu_container:
		menu_container._connection_status_label.text = "Channel switch failed. Disconnected."
	
	# Return to main menu
	get_tree().change_scene_to_file("res://scenes/Levels/main_menu.tscn")

# === UTILITY FUNCTIONS ===
func get_available_channels() -> Array:
	"""Get list of potentially available channels (for UI)"""
	var base_port = ClientManager.current_server_port
	if base_port == 0:
		base_port = 8080
	
	var channels = []
	for i in range(-2, 3):  # Show 5 channels around current
		var port = base_port + i
		if port > 0 and port <= 65535 and port != ClientManager.current_server_port:
			channels.append({
				"port": port,
				"name": "Channel %d" % port,
				"current": false
			})
	
	return channels

func quick_test_channel(port: int) -> bool:
	"""Quick test if a channel is reachable (non-blocking, for UI)"""
	if port == ClientManager.current_server_port:
		return true
	
	# This would need to be implemented as a very quick, non-blocking test
	# For now, return true to indicate "potentially available"
	return NetworkUtils.is_valid_port(port)
