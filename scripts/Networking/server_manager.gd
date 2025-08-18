# server_manager.gd - AutoLoad singleton
extends Node

signal server_started
signal server_failed

const MAX_PORT_ATTEMPTS = 10

var _server_peer: ENetMultiplayerPeer
var _current_port: int = 0
var _is_dedicated: bool = false

func start_dedicated_server(port: int) -> bool:
	print("--- Starting Dedicated Server ---")
	print("Process ID: %d" % OS.get_process_id())
	
	_is_dedicated = true
	_server_peer = ENetMultiplayerPeer.new()
	
	for i in range(MAX_PORT_ATTEMPTS):
		var current_port = port + i
		var error = _server_peer.create_server(current_port)
		
		if error == OK:
			_finalize_server_setup(current_port)
			return true
		
		print("Port %d failed, trying next..." % current_port)
	
	print("ERROR: Could not start dedicated server after %d attempts" % MAX_PORT_ATTEMPTS)
	get_tree().quit(1)
	return false

func start_listen_server(port: int) -> bool:
	print("--- Starting Listen Server ---")
	_is_dedicated = false
	_server_peer = ENetMultiplayerPeer.new()
	
	var error = _server_peer.create_server(port)
	if error == OK:
		_finalize_server_setup(port)
		return true
	
	print("ERROR: Could not start listen server on port %d" % port)
	server_failed.emit()
	return false

func stop_server():
	if _server_peer:
		print("Stopping server on port %d" % _current_port)
		_server_peer.close()
		_server_peer = null
	_current_port = 0
	_is_dedicated = false

func get_current_port() -> int:
	return _current_port

func is_server_running() -> bool:
	return _server_peer != null and _current_port > 0

func is_dedicated_server() -> bool:
	return _is_dedicated

func get_server_info() -> Dictionary:
	return {
		"running": is_server_running(),
		"dedicated": _is_dedicated,
		"port": _current_port,
		"ip": NetworkUtils.get_public_ip_address() if is_server_running() else ""
	}

func _finalize_server_setup(port: int):
	_current_port = port
	multiplayer.multiplayer_peer = _server_peer
	
	var ip_address = NetworkUtils.get_public_ip_address() if _is_dedicated else "localhost"
	var server_type = "Dedicated" if _is_dedicated else "Listen"
	print("%s Server started successfully!" % server_type)
	print("IP: %s, Port: %d" % [ip_address, port])
	
	NetworkUtils.log_network_event("SERVER_START", "%s server on %s:%d" % [server_type, ip_address, port])
	
	server_started.emit()
