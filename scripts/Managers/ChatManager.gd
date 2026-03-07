extends Node

signal message_received(message, color)

var local_player_node: MultiplayerPlayerV2 = null

func _ready():
	pass

func register_local_player(player_node: MultiplayerPlayerV2):
	local_player_node = player_node

func send_chat_message(text: String):
	if text.begins_with("/"):
		var parts: PackedStringArray = text.strip_edges().split(" ", false)
		var command: String = parts[0].to_lower()

		# /friend add|accept|remove|list <username>
		if command == "/friend":
			_handle_friend_command(parts)
			return

		# /w <username> <message> or /whisper <username> <message>
		if command == "/w" or command == "/whisper":
			if parts.size() >= 3:
				var target: String = parts[1]
				var msg: String = text.substr(text.find(parts[1]) + parts[1].length()).strip_edges()
				FriendManager.request_whisper.rpc_id(1, target, msg)
			else:
				add_system_message("Usage: /w <username> <message>", Color.GRAY)
			return

	if local_player_node:
		broadcast_message.rpc(local_player_node.username, text)
	else:
		broadcast_message.rpc("Player", text)


func _handle_friend_command(parts: PackedStringArray) -> void:
	if parts.size() < 2:
		add_system_message("Usage: /friend add|accept|remove|list [username]", Color.GRAY)
		return

	var action: String = parts[1].to_lower()
	match action:
		"add":
			if parts.size() >= 3:
				FriendManager.request_add_friend.rpc_id(1, parts[2])
			else:
				add_system_message("Usage: /friend add <username>", Color.GRAY)
		"accept":
			if parts.size() >= 3:
				FriendManager.request_accept_friend.rpc_id(1, parts[2])
			else:
				add_system_message("Usage: /friend accept <username>", Color.GRAY)
		"remove":
			if parts.size() >= 3:
				FriendManager.request_remove_friend.rpc_id(1, parts[2])
			else:
				add_system_message("Usage: /friend remove <username>", Color.GRAY)
		"list":
			FriendManager.request_friend_list.rpc_id(1)
		_:
			add_system_message("Usage: /friend add|accept|remove|list [username]", Color.GRAY)

func add_system_message(text: String, color: Color = Color.WHITE):
	message_received.emit(text, color)

@rpc("any_peer", "call_local", "reliable")
func broadcast_message(sender_name: String, text: String):
	var message = "%s: %s" % [sender_name, text]
	message_received.emit(message, Color.WHITE)
