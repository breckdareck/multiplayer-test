extends Node

signal message_received(message, color)

var local_player_node: MultiplayerPlayerV2 = null

const MAX_MESSAGE_LENGTH: int = 200
const RATE_LIMIT_INTERVAL: float = 2.0
const RATE_LIMIT_BURST: int = 3
var _rate_limits: Dictionary = {}

## Supported emotes: command -> display text
const EMOTES: Dictionary = {
	"/sit": "*sits down*",
	"/wave": "*waves*",
	"/laugh": "*laughs*",
	"/cry": "*cries*",
}

func _ready():
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func register_local_player(player_node: MultiplayerPlayerV2) -> void:
	local_player_node = player_node

func _send_system_message(text: String, color: Color = Color.YELLOW) -> void:
	message_received.emit(text, color)

func _check_rate_limit(peer_id: int) -> bool:
	var now = Time.get_ticks_msec() / 1000.0
	if not _rate_limits.has(peer_id):
		_rate_limits[peer_id] = { "last_time": now, "burst_count": 0 }
		return true
	var info = _rate_limits[peer_id]
	if now - info["last_time"] >= RATE_LIMIT_INTERVAL:
		info["burst_count"] = 0
		info["last_time"] = now
		return true
	info["burst_count"] += 1
	info["last_time"] = now
	return info["burst_count"] <= RATE_LIMIT_BURST

func _on_peer_disconnected(peer_id: int):
	_rate_limits.erase(peer_id)

func send_chat_message(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return

	if text.begins_with("/"):
		var command: String = text.split(" ", false)[0].to_lower()

		if EMOTES.has(command):
			_request_emote.rpc_id(1, command)
			return

		if command == "/quest":
			_request_quest_command.rpc_id(1, text)
			return

		if command == "/bot":
			_request_bot_command.rpc_id(1, text)
			return

		if command == "/trade":
			var parts := text.split(" ", false)
			if parts.size() < 2:
				_send_system_message("Usage: /trade <player_name>", Color.ORANGE)
			else:
				TradeManager.rpc_request_trade.rpc_id(1, parts[1])
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

	if text.length() > MAX_MESSAGE_LENGTH:
		text = text.substr(0, MAX_MESSAGE_LENGTH)

	if not _check_rate_limit(sender_id):
		add_system_message.rpc_id(sender_id, "You are sending messages too fast.", Color.ORANGE)
		return

	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(player_node):
		return

	var sender_map: String = MapManager.get_player_map(sender_id)
	if sender_map.is_empty():
		return

	# Use authoritative server-side username — never trust the client for this
	var sender_name: String = player_node.username
	var players_on_map: Array = MapManager.get_real_players_on_map(sender_map)
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
	if not _check_rate_limit(multiplayer.get_remote_sender_id()):
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
	var players_on_map: Array = MapManager.get_real_players_on_map(sender_map)
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


## Which client-side surface a server->peer notification lands on.
enum NotifySurface { CHAT, LOG }


## Canonical server->one-player notification seam. Routes a single message to a
## specific peer's CHAT (system message) or LOG (scrolling log) surface,
## reproducing the host-local-vs-rpc_id branch and the bot-peer skip in ONE
## place. Other managers (QuestManager, TradeManager, PetManager) delegate here
## so the routing rules live once.
##
## Must be called server-side. Bots have no client, so they are skipped.
func notify_peer(peer_id: int, text: String, color: Color = Color.WHITE, surface: NotifySurface = NotifySurface.CHAT) -> void:
	if peer_id == 0:
		return
	# Bots have no client/UI — nothing to deliver to.
	if BotManager.is_bot(peer_id):
		return
	if peer_id == multiplayer.get_unique_id():
		# Host is also a client — deliver locally.
		_notify_peer_local(text, color, surface)
	else:
		match surface:
			NotifySurface.LOG:
				_notify_peer_log_rpc.rpc_id(peer_id, text, color)
			_:
				add_system_message.rpc_id(peer_id, text, color)


## Local (host) side of notify_peer — emit on the chosen surface directly.
func _notify_peer_local(text: String, color: Color, surface: NotifySurface) -> void:
	match surface:
		NotifySurface.LOG:
			LogManager.add_scrolling_log(text, color)
		_:
			add_system_message(text, color)


## Server -> Client: deliver a notification to the LOG (scrolling log) surface.
@rpc("authority", "call_remote", "reliable")
func _notify_peer_log_rpc(text: String, color: Color) -> void:
	if multiplayer.is_server():
		return
	LogManager.add_scrolling_log(text, color)


## Client -> Server: quest command passthrough
@rpc("any_peer", "call_local", "reliable")
func _request_quest_command(args: String) -> void:
	if not multiplayer.is_server():
		return
	if not _check_rate_limit(multiplayer.get_remote_sender_id()):
		return
	QuestManager.handle_quest_command(args, multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_local", "reliable")
func _request_bot_command(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	# A local (host) call reports sender 0 — normalize to the server's peer id.
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if not _check_rate_limit(sender_id):
		add_system_message.rpc_id(sender_id, "You are sending commands too fast.", Color.ORANGE)
		return
	var parts := text.split(" ", false)
	parts.remove_at(0)
	var result := BotManager.handle_command(parts, sender_id)
	if sender_id == multiplayer.get_unique_id():
		add_system_message(result, Color.CYAN)
	else:
		add_system_message.rpc_id(sender_id, result, Color.CYAN)
