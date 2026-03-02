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
		if command == "/title":
			_request_title.rpc_id(1, text.strip_edges())
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


# ═══════════════════════════════════════════════════════════════════════════
# TITLE COMMAND
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "call_remote", "reliable")
func _request_title(raw_text: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	var sender_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(sender_node):
		return

	var parts: PackedStringArray = raw_text.split(" ", false)

	# /title list — show unlocked achievements
	if parts.size() >= 2 and parts[1].to_lower() == "list":
		var unlocked: Array = AchievementManager.get_unlocked_achievements(sender_node.username)
		if unlocked.is_empty():
			_send_system_message.rpc_id(sender_id, "You have no unlocked titles yet.", Color.GRAY)
			return
		var lines: String = "Unlocked titles:"
		for aid in unlocked:
			if AchievementManager.ACHIEVEMENTS.has(aid):
				lines += "\n  %s — %s" % [aid, AchievementManager.ACHIEVEMENTS[aid].title]
		_send_system_message.rpc_id(sender_id, lines, Color.GOLD)
		return

	# /title clear — remove active title
	if parts.size() >= 2 and parts[1].to_lower() == "clear":
		AchievementManager.set_active_title(sender_node.username, "")
		# Sync to all peers on same map
		var map_id: String = MapManager.get_player_map(sender_id)
		if not map_id.is_empty():
			for pid in MapManager.get_players_on_map(map_id):
				sender_node._sync_title.rpc_id(pid, "")
		_send_system_message.rpc_id(sender_id, "Title cleared.", Color.GRAY)
		return

	# /title <achievement_id> — set active title
	if parts.size() >= 2:
		var title_id: String = parts[1]
		if AchievementManager.set_active_title(sender_node.username, title_id):
			var map_id: String = MapManager.get_player_map(sender_id)
			if not map_id.is_empty():
				for pid in MapManager.get_players_on_map(map_id):
					sender_node._sync_title.rpc_id(pid, title_id)
			var title_name: String = AchievementManager.ACHIEVEMENTS[title_id].title
			_send_system_message.rpc_id(sender_id, "Title set to: %s" % title_name, Color.GOLD)
		else:
			_send_system_message.rpc_id(sender_id, "Title not found or not unlocked. Use /title list to see your titles.", Color.RED)
		return

	# /title — show usage
	_send_system_message.rpc_id(sender_id, "Usage: /title list | /title <id> | /title clear", Color.GRAY)


@rpc("authority", "call_local", "reliable")
func _send_system_message(text: String, color: Color) -> void:
	message_received.emit(text, color)
