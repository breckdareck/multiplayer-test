extends Node

signal message_received(message, color)

var local_player_node: MultiplayerPlayerV2 = null

## Supported emotes: command -> display text
const EMOTES: Dictionary = {
	"/sit": "*sits down*",
	"/wave": "*waves*",
	"/laugh": "*laughs*",
	"/cry": "*cries*",
}

func register_local_player(player_node: MultiplayerPlayerV2) -> void:
	local_player_node = player_node

	if text.begins_with("/"):
		var command: String = text.split(" ", false)[0].to_lower()

		if EMOTES.has(command):
			_request_emote.rpc_id(1, command)
			return

		if command == "/quest":
			_request_quest_command.rpc_id(1, text)
			return

		if command == "/advance":
			JobAdvancementManager.request_advancement.rpc_id(1)
			return

		_send_system_message("Unknown command: %s" % command, Color.ORANGE)
		return

	_broadcast_message.rpc_id(1, text)


## Client -> Server: send raw message text only (server resolves the sender name)
@rpc("any_peer", "call_local", "reliable")
func _broadcast_message(text: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(player_node):
		return

	var sender_map: String = MapManager.get_player_map(sender_id)
	if sender_map.is_empty():
		return

	# Use authoritative server-side username — never trust the client for this
	var sender_name: String = player_node.username
	var players_on_map: Array = MapManager.get_players_on_map(sender_map)
	var server_id: int = multiplayer.get_unique_id()

	for peer_id in players_on_map:
		if peer_id != server_id:
			_show_chat_message.rpc_id(peer_id, sender_id, sender_name, text)

	if server_id in players_on_map:
		_show_chat_message(sender_id, sender_name, text)


## Server -> Client: display chat message and bubble
## - Chat box shows "Name: text"
## - Bubble shows only "text" (no name)
@rpc("authority", "call_local", "reliable")
func _show_chat_message(player_id: int, sender_name: String, text: String) -> void:
	message_received.emit("%s: %s" % [sender_name, text], Color.WHITE)

	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(player_id)
	if is_instance_valid(player_node):
		player_node.show_chat_bubble(text)


## Client -> Server: request to play an emote
@rpc("any_peer", "call_local", "reliable")
func _request_emote(emote_command: String) -> void:
	if not multiplayer.is_server():
		return
	if not EMOTES.has(emote_command):
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(player_node):
		return

	var sender_map: String = MapManager.get_player_map(sender_id)
	if sender_map.is_empty():
		return

	var sender_name: String = player_node.username
	var emote_text: String = EMOTES[emote_command]
	var players_on_map: Array = MapManager.get_players_on_map(sender_map)
	var server_id: int = multiplayer.get_unique_id()

	for peer_id in players_on_map:
		if peer_id != server_id:
			_show_emote.rpc_id(peer_id, sender_id, sender_name, emote_text)

	if server_id in players_on_map:
		_show_emote(sender_id, sender_name, emote_text)


## Server -> Client: display emote in chat and bubble (bubble has no name)
@rpc("authority", "call_local", "reliable")
func _show_emote(player_id: int, sender_name: String, emote_text: String) -> void:
	message_received.emit("%s %s" % [sender_name, emote_text], Color.LIGHT_GOLDENROD)

	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(player_id)
	if is_instance_valid(player_node):
		player_node.show_emote_bubble(emote_text)


## Server -> Client: system message (called by other managers like QuestManager)
@rpc("authority", "call_local", "reliable")
func add_system_message(text: String, color: Color = Color.WHITE) -> void:
	message_received.emit(text, color)


## Client -> Server: quest command passthrough
@rpc("any_peer", "call_local", "reliable")
func _request_quest_command(args: String) -> void:
	if not multiplayer.is_server():
		return
	QuestManager.handle_quest_command(args, multiplayer.get_remote_sender_id())
