# client_manager.gd - AutoLoad singleton
extends Node

signal connection_succeeded
signal connection_failed

var _client_peer: ENetMultiplayerPeer
var current_server_ip: String = ""
var current_server_port: int = 0
var _connection_attempt_time: float = 0.0

func connect_to_server(ip: String, port: int):
	print("Connecting to %s:%d..." % [ip, port])
	NetworkUtils.log_connection_attempt(ip, port)
	
	_client_peer = ENetMultiplayerPeer.new()
	current_server_ip = ip
	current_server_port = port
	_connection_attempt_time = Time.get_time_dict_from_system().hour * 3600 + Time.get_time_dict_from_system().minute * 60 + Time.get_time_dict_from_system().second
	
	var error = _client_peer.create_client(ip, port)
	if error != OK:
		print("ERROR: Could not create client - Error code: %d" % error)
		connection_failed.emit()
		return
	
	multiplayer.multiplayer_peer = _client_peer

func _disconnect():
	if _client_peer:
		print("Disconnecting from %s:%d" % [current_server_ip, current_server_port])
		NetworkUtils.log_network_event("CLIENT_DISCONNECT", "From %s:%d" % [current_server_ip, current_server_port])
		_client_peer.close()
		_client_peer = null
	
	_reset_connection_state()

func cleanup():
	_disconnect()
	multiplayer.multiplayer_peer = null

func get_connection_info() -> Dictionary:
	return {
		"ip": current_server_ip,
		"port": current_server_port,
		"connected": _is_connected(),
		"connection_time": _connection_attempt_time
	}

func _is_connected() -> bool:
	return _client_peer != null and _client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func get_connection_status() -> String:
	if not _client_peer:
		return "Not Connected"
	
	match _client_peer.get_connection_status():
		MultiplayerPeer.CONNECTION_DISCONNECTED:
			return "Disconnected"
		MultiplayerPeer.CONNECTION_CONNECTING:
			return "Connecting"
		MultiplayerPeer.CONNECTION_CONNECTED:
			return "Connected"
		_:
			return "Unknown"

# Called by multiplayer manager when connection signals are received
func _on_connection_succeeded():
	print("Client connection succeeded to %s:%d" % [current_server_ip, current_server_port])
	NetworkUtils.log_connection_result(true, current_server_ip, current_server_port)
	connection_succeeded.emit()

func _on_connection_failed():
	print("Client connection failed to %s:%d" % [current_server_ip, current_server_port])
	NetworkUtils.log_connection_result(false, current_server_ip, current_server_port)
	cleanup()
	connection_failed.emit()

func _reset_connection_state():
	current_server_ip = ""
	current_server_port = 0
	_connection_attempt_time = 0.0

# Utility method for creating a new client peer (used by channel manager)
func create_new_peer(ip: String, port: int) -> ENetMultiplayerPeer:
	var new_peer = ENetMultiplayerPeer.new()
	var error = new_peer.create_client(ip, port)
	
	if error != OK:
		new_peer.close()
		return null
	
	return new_peer
