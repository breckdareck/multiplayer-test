extends Node

signal message_received(message, color)

var local_player_node: MultiplayerPlayerV2 = null

# Level milestones that trigger server-wide announcements
const LEVEL_MILESTONES: Array[int] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

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

@rpc("any_peer", "call_local", "reliable")
func broadcast_message(sender_name: String, text: String):
	var message = "%s: %s" % [sender_name, text]
	message_received.emit(message, Color.WHITE)


# ═══════════════════════════════════════════════════════════════════════════
# SERVER-WIDE ANNOUNCEMENTS
# ═══════════════════════════════════════════════════════════════════════════

## Broadcast a server-wide announcement to ALL connected players.
## Called only on the server.
func server_announce(text: String, color: Color = Color.GOLD) -> void:
	if not multiplayer.is_server():
		return
	_receive_announcement.rpc(text, color)

@rpc("authority", "call_local", "reliable")
func _receive_announcement(text: String, color: Color) -> void:
	message_received.emit(text, color)

## Called by player controller when a level milestone is reached.
func announce_level_up(username: String, new_level: int) -> void:
	if not multiplayer.is_server():
		return
	if new_level in LEVEL_MILESTONES:
		server_announce("[ANNOUNCE] %s has reached level %d!" % [username, new_level])

## Called when a rare item drops.
func announce_rare_drop(username: String, item_name: String, rarity_name: String) -> void:
	if not multiplayer.is_server():
		return
	server_announce("[ANNOUNCE] %s obtained a %s %s!" % [username, rarity_name, item_name])
