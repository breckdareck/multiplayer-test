extends Node

signal message_received(message, color)

var local_player_node: MultiplayerPlayerV2 = null

func _ready():
	pass

func register_local_player(player_node: MultiplayerPlayerV2):
	local_player_node = player_node

func send_chat_message(text: String):
	# Handle slash commands
	if text.begins_with("/"):
		var parts: PackedStringArray = text.split(" ", false, 2)
		var command: String = parts[0].to_lower()
		var args: String = text.substr(command.length()).strip_edges()

		match command:
			"/quest":
				_request_quest_command.rpc_id(1, args)
				return

	if local_player_node:
		broadcast_message.rpc(local_player_node.username, text)
	else:
		broadcast_message.rpc("Player", text)


@rpc("any_peer", "call_local", "reliable")
func _request_quest_command(args: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	QuestManager.handle_quest_command(args, sender_id)

@rpc("any_peer", "call_local", "reliable")
func add_system_message(text: String, color: Color = Color.WHITE):
	message_received.emit(text, color)

@rpc("any_peer", "call_local", "reliable")
func broadcast_message(sender_name: String, text: String):
	var message = "%s: %s" % [sender_name, text]
	message_received.emit(message, Color.WHITE)
