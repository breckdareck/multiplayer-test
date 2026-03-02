extends Node

signal message_received(message, color)

var local_player_node: MultiplayerPlayerV2 = null

# Megaphone: maps peer_id -> username for players with active megaphone
var _megaphone_active: Dictionary = {}

func _ready():
	pass

func register_local_player(player_node: MultiplayerPlayerV2):
	local_player_node = player_node

func send_chat_message(text: String):
	if local_player_node:
		broadcast_message.rpc(local_player_node.username, text)
	else:
		broadcast_message.rpc("Player", text)

func add_system_message(text: String, color: Color = Color.WHITE):
	message_received.emit(text, color)

## Called by Effect_MegaphoneChat on the server to flag the next message as megaphone.
func enable_megaphone(peer_id: int, username: String) -> void:
	if not multiplayer.is_server():
		return
	_megaphone_active[peer_id] = username
	# Notify the client that megaphone is ready
	_notify_megaphone_ready.rpc_id(peer_id)
	print("ChatManager: Megaphone enabled for '%s' (peer %d)." % [username, peer_id])

@rpc("authority", "call_local", "reliable")
func _notify_megaphone_ready() -> void:
	add_system_message("[MEGAPHONE] Your next message will be broadcast server-wide!", Color.YELLOW)

@rpc("any_peer", "call_local", "reliable")
func broadcast_message(sender_name: String, text: String):
	if multiplayer.is_server():
		var sender_id: int = multiplayer.get_remote_sender_id()
		if sender_id == 0:
			sender_id = 1  # Server itself

		# Check if this sender has megaphone active
		if _megaphone_active.has(sender_id):
			_megaphone_active.erase(sender_id)
			# Broadcast megaphone message to ALL connected peers
			_receive_megaphone_message.rpc("[MEGAPHONE] %s: %s" % [sender_name, text])
			return

	# Normal local display
	var message = "%s: %s" % [sender_name, text]
	message_received.emit(message, Color.WHITE)

@rpc("authority", "call_local", "reliable")
func _receive_megaphone_message(text: String) -> void:
	message_received.emit(text, Color.YELLOW)
