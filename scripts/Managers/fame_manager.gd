extends Node
## FameManager — Server-authoritative fame/reputation system.
##
## Players can give +1 or -1 fame to another player once per day (per target).
## Fame is persisted as part of the player's save data.
##
## Usage (via chat commands):
##   /fame <player>    — Give +1 fame
##   /defame <player>  — Give -1 fame

signal fame_changed(username: String, new_fame: int)

## Tracks daily fame cooldowns: "giver:target" -> unix timestamp of last fame action
var _fame_cooldowns: Dictionary = {}

const FAME_COOLDOWN_SECONDS: int = 86400  # 24 hours
const FAME_PROXIMITY_RANGE: float = 100.0  # Must be within range to give fame


## Give fame to a target player. Called on the server.
## Returns an error message string, or empty string on success.
func give_fame(giver_node: MultiplayerPlayerV2, target_username: String, amount: int) -> String:
	if not multiplayer.is_server():
		return "Only the server can process fame."

	if amount != 1 and amount != -1:
		return "Invalid fame amount."

	var giver_username: String = giver_node.username
	if giver_username == target_username:
		return "You cannot give fame to yourself."

	# Find target player node
	var target_node: MultiplayerPlayerV2 = _find_player_by_username(target_username)
	if not is_instance_valid(target_node):
		return "Player '%s' not found." % target_username

	# Check proximity
	var distance: float = giver_node.global_position.distance_to(target_node.global_position)
	if distance > FAME_PROXIMITY_RANGE:
		return "You need to be closer to %s." % target_username

	# Check daily cooldown
	var cooldown_key: String = "%s:%s" % [giver_username, target_username]
	if _fame_cooldowns.has(cooldown_key):
		var last_time: float = _fame_cooldowns[cooldown_key]
		var now: float = Time.get_unix_time_from_system()
		if now - last_time < FAME_COOLDOWN_SECONDS:
			var remaining: int = int(FAME_COOLDOWN_SECONDS - (now - last_time))
			var hours: int = remaining / 3600
			var minutes: int = (remaining % 3600) / 60
			return "You can give fame to %s again in %dh %dm." % [target_username, hours, minutes]

	# Apply fame
	target_node.fame += amount
	_fame_cooldowns[cooldown_key] = Time.get_unix_time_from_system()

	# Sync to target client
	_sync_fame_to_client.rpc_id(target_node.player_id, target_node.fame)

	# Emit signal for any listeners
	fame_changed.emit(target_username, target_node.fame)

	# Notify both players via chat
	var action_word: String = "raised" if amount > 0 else "lowered"
	var giver_msg: String = "You %s %s's fame to %d." % [action_word, target_username, target_node.fame]
	var target_msg: String = "%s %s your fame to %d." % [giver_username, action_word, target_node.fame]

	_send_system_message.rpc_id(giver_node.player_id, giver_msg)
	_send_system_message.rpc_id(target_node.player_id, target_msg)

	# Also show on server console
	print("FameManager: %s %s %s's fame to %d" % [giver_username, action_word, target_username, target_node.fame])

	return ""


## Handle a /fame or /defame chat command from a client.
func handle_fame_command(sender_peer_id: int, target_username: String, is_defame: bool) -> void:
	if not multiplayer.is_server():
		return

	var giver_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_peer_id)
	if not is_instance_valid(giver_node):
		return

	var amount: int = -1 if is_defame else 1
	var error: String = give_fame(giver_node, target_username, amount)

	if not error.is_empty():
		_send_system_message.rpc_id(sender_peer_id, error)


func _find_player_by_username(target_username: String) -> MultiplayerPlayerV2:
	for node in get_tree().get_nodes_in_group("Players"):
		if is_instance_valid(node) and node is MultiplayerPlayerV2:
			if node.username == target_username:
				return node
	return null


@rpc("authority", "call_local", "reliable")
func _sync_fame_to_client(new_fame: int) -> void:
	# Client receives their updated fame — find local player and update
	var local_id: int = multiplayer.get_unique_id()
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(local_id)
	if is_instance_valid(player_node):
		player_node.fame = new_fame


@rpc("authority", "call_local", "reliable")
func _send_system_message(text: String) -> void:
	ChatManager.add_system_message(text, Color.GOLD)
