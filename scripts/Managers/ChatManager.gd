extends Node

signal message_received(message, color)

var local_player_node: MultiplayerPlayerV2 = null

func _ready():
	pass

func register_local_player(player_node: MultiplayerPlayerV2):
	local_player_node = player_node

func send_chat_message(text: String):
	# Handle slash commands locally before broadcasting
	if text.begins_with("/"):
		_handle_command(text)
		return

	if local_player_node:
		broadcast_message.rpc(local_player_node.username, text)
	else:
		broadcast_message.rpc("Player", text)

func add_system_message(text: String, color: Color = Color.WHITE):
	message_received.emit(text, color)

@rpc("any_peer", "call_local", "reliable")
func broadcast_message(sender_name: String, text: String):
	var message = "%s: %s" % [sender_name, text]
	message_received.emit(message, Color.WHITE)


func _handle_command(text: String) -> void:
	var parts: PackedStringArray = text.strip_edges().split(" ", false)
	if parts.is_empty():
		return

	var command: String = parts[0].to_lower()

	match command:
		"/fame", "/defame":
			if parts.size() < 2:
				add_system_message("Usage: %s <player_name>" % command, Color.YELLOW)
				return
			var target_name: String = parts[1]
			var is_defame: bool = command == "/defame"
			_request_fame.rpc_id(1, target_name, is_defame)
		_:
			add_system_message("Unknown command: %s" % command, Color.YELLOW)


@rpc("any_peer", "call_remote", "reliable")
func _request_fame(target_username: String, is_defame: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	FameManager.handle_fame_command(sender_id, target_username, is_defame)
