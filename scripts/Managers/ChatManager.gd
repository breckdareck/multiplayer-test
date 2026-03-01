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

func _ready():
	pass

func register_local_player(player_node: MultiplayerPlayerV2):
	local_player_node = player_node

func send_chat_message(text: String):
	# Handle slash commands
	if text.begins_with("/"):
		var command: String = text.strip_edges().split(" ", false)[0].to_lower()
		if EMOTES.has(command):
			_request_emote.rpc_id(1, command)
			return
		# Unknown command — just send as normal chat

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


## Client -> Server: request to play an emote
@rpc("any_peer", "call_remote", "reliable")
func _request_emote(emote_command: String) -> void:
	if not multiplayer.is_server():
		return
	if not EMOTES.has(emote_command):
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(player_node):
		return

	var emote_text: String = EMOTES[emote_command]
	var sender_name: String = player_node.username

	# Broadcast emote to all players on the same map
	var map_node = MapManager.get_player_map_node(sender_id)
	if map_node:
		var map_name: String = map_node.name.replace("Map_", "")
		var players_on_map: Array = MapManager.get_players_on_map(map_name)
		for peer_id in players_on_map:
			_show_emote.rpc_id(peer_id, sender_id, sender_name, emote_text)
		# Also show on server if host
		if multiplayer.get_unique_id() == 1:
			_show_emote(sender_id, sender_name, emote_text)
	else:
		# Fallback: broadcast to all
		_show_emote.rpc(sender_id, sender_name, emote_text)


## Server -> Client: display emote text bubble and chat message
@rpc("authority", "call_local", "reliable")
func _show_emote(player_id: int, sender_name: String, emote_text: String) -> void:
	# Show in chat
	var chat_msg: String = "%s %s" % [sender_name, emote_text]
	message_received.emit(chat_msg, Color.LIGHT_GOLDENROD)

	# Show text bubble above the player
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(player_id)
	if is_instance_valid(player_node):
		player_node.show_emote_bubble(emote_text)
