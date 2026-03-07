extends Node
## FriendManager — Server-authoritative friend list with online status and whisper.
##
## Friends are stored per-username in player save data. Online status is tracked
## by cross-referencing active players in PlayerManager.

signal friend_added(username: String, friend_username: String)
signal friend_removed(username: String, friend_username: String)
signal friend_request_received(from_username: String)

# Server-side: username -> PackedStringArray of friend usernames
var _friend_lists: Dictionary = {}

# Server-side: pending requests — target_username -> [requester_usernames]
var _pending_requests: Dictionary = {}


# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API (server-side)
# ═══════════════════════════════════════════════════════════════════════════

func load_friends(username: String, friends: Array) -> void:
	_friend_lists[username] = friends.duplicate()


func get_friends(username: String) -> Array:
	return _friend_lists.get(username, [])


func save_friends(username: String) -> Array:
	return _friend_lists.get(username, [])


func unregister_player(username: String) -> void:
	# Notify online friends that this player went offline
	if not multiplayer.is_server():
		return
	var friends: Array = _friend_lists.get(username, [])
	for friend_name in friends:
		var friend_id: int = PlayerManager.get_player_id_from_name(friend_name)
		if friend_id > 0:
			_notify_friend_offline.rpc_id(friend_id, username)
	_pending_requests.erase(username)


# ═══════════════════════════════════════════════════════════════════════════
# CLIENT → SERVER RPCs
# ═══════════════════════════════════════════════════════════════════════════

## Client requests to add a friend: /friend add <username>
@rpc("any_peer", "call_remote", "reliable")
func request_add_friend(target_username: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	var sender_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(sender_node):
		return

	var sender_username: String = sender_node.username

	if sender_username == target_username:
		_send_friend_message.rpc_id(sender_id, "You can't add yourself as a friend.", Color.RED)
		return

	# Check if already friends
	var friends: Array = _friend_lists.get(sender_username, [])
	if target_username in friends:
		_send_friend_message.rpc_id(sender_id, "%s is already your friend." % target_username, Color.GRAY)
		return

	# Check if target is online
	var target_id: int = PlayerManager.get_player_id_from_name(target_username)
	if target_id == -1:
		_send_friend_message.rpc_id(sender_id, "Player '%s' is not online." % target_username, Color.RED)
		return

	# Store pending request
	if not _pending_requests.has(target_username):
		_pending_requests[target_username] = []
	if sender_username in _pending_requests[target_username]:
		_send_friend_message.rpc_id(sender_id, "Friend request already pending.", Color.GRAY)
		return

	# Check if they already sent us a request — auto-accept
	if _pending_requests.has(sender_username) and target_username in _pending_requests[sender_username]:
		_accept_friend(sender_username, target_username)
		return

	_pending_requests[target_username].append(sender_username)
	_send_friend_message.rpc_id(sender_id, "Friend request sent to %s." % target_username, Color.YELLOW)
	_send_friend_message.rpc_id(target_id, "%s wants to be your friend! Type /friend accept %s" % [sender_username, sender_username], Color.YELLOW)
	friend_request_received.emit(sender_username)


## Client accepts a friend request
@rpc("any_peer", "call_remote", "reliable")
func request_accept_friend(requester_username: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	var sender_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(sender_node):
		return

	var sender_username: String = sender_node.username

	# Verify pending request exists
	if not _pending_requests.has(sender_username) or requester_username not in _pending_requests[sender_username]:
		_send_friend_message.rpc_id(sender_id, "No pending request from %s." % requester_username, Color.RED)
		return

	_accept_friend(requester_username, sender_username)


## Client removes a friend
@rpc("any_peer", "call_remote", "reliable")
func request_remove_friend(target_username: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	var sender_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(sender_node):
		return

	var sender_username: String = sender_node.username
	var friends: Array = _friend_lists.get(sender_username, [])

	if target_username not in friends:
		_send_friend_message.rpc_id(sender_id, "%s is not on your friend list." % target_username, Color.RED)
		return

	friends.erase(target_username)
	# Also remove from their list
	var target_friends: Array = _friend_lists.get(target_username, [])
	target_friends.erase(sender_username)

	_send_friend_message.rpc_id(sender_id, "Removed %s from your friend list." % target_username, Color.GRAY)

	var target_id: int = PlayerManager.get_player_id_from_name(target_username)
	if target_id > 0:
		_send_friend_message.rpc_id(target_id, "%s removed you from their friend list." % sender_username, Color.GRAY)

	friend_removed.emit(sender_username, target_username)


## Client requests friend list with online status
@rpc("any_peer", "call_remote", "reliable")
func request_friend_list() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	var sender_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(sender_node):
		return

	var friends: Array = _friend_lists.get(sender_node.username, [])
	if friends.is_empty():
		_send_friend_message.rpc_id(sender_id, "Your friend list is empty.", Color.GRAY)
		return

	var lines: String = "Friends:"
	for friend_name in friends:
		var friend_id: int = PlayerManager.get_player_id_from_name(friend_name)
		if friend_id > 0:
			var map_id: String = MapManager.get_player_map(friend_id)
			lines += "\n  %s — [color=green]Online[/color] (Map: %s)" % [friend_name, map_id]
		else:
			lines += "\n  %s — [color=gray]Offline[/color]" % friend_name

	_send_friend_message.rpc_id(sender_id, lines, Color.WHITE)


## Client sends a whisper/PM
@rpc("any_peer", "call_remote", "reliable")
func request_whisper(target_username: String, message: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	var sender_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(sender_node):
		return

	var target_id: int = PlayerManager.get_player_id_from_name(target_username)
	if target_id == -1:
		_send_friend_message.rpc_id(sender_id, "Player '%s' is not online." % target_username, Color.RED)
		return

	# Send whisper to target
	_receive_whisper.rpc_id(target_id, sender_node.username, message)
	# Echo to sender
	_send_friend_message.rpc_id(sender_id, "[To %s]: %s" % [target_username, message], Color.MAGENTA)


# ═══════════════════════════════════════════════════════════════════════════
# SERVER → CLIENT RPCs
# ═══════════════════════════════════════════════════════════════════════════

@rpc("authority", "call_local", "reliable")
func _send_friend_message(text: String, color: Color) -> void:
	ChatManager.message_received.emit(text, color)


@rpc("authority", "call_local", "reliable")
func _receive_whisper(from_username: String, message: String) -> void:
	ChatManager.message_received.emit("[From %s]: %s" % [from_username, message], Color.MAGENTA)


@rpc("authority", "call_local", "reliable")
func _notify_friend_online(friend_username: String, map_id: String) -> void:
	ChatManager.message_received.emit("%s is now online (Map: %s)." % [friend_username, map_id], Color.GREEN)


@rpc("authority", "call_local", "reliable")
func _notify_friend_offline(friend_username: String) -> void:
	ChatManager.message_received.emit("%s went offline." % friend_username, Color.GRAY)


# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL
# ═══════════════════════════════════════════════════════════════════════════

func _accept_friend(requester: String, accepter: String) -> void:
	# Add to both lists
	if not _friend_lists.has(requester):
		_friend_lists[requester] = []
	if not _friend_lists.has(accepter):
		_friend_lists[accepter] = []

	if accepter not in _friend_lists[requester]:
		_friend_lists[requester].append(accepter)
	if requester not in _friend_lists[accepter]:
		_friend_lists[accepter].append(requester)

	# Clear pending request
	if _pending_requests.has(accepter):
		_pending_requests[accepter].erase(requester)

	# Notify both
	var req_id: int = PlayerManager.get_player_id_from_name(requester)
	var acc_id: int = PlayerManager.get_player_id_from_name(accepter)

	if req_id > 0:
		_send_friend_message.rpc_id(req_id, "%s accepted your friend request!" % accepter, Color.GREEN)
	if acc_id > 0:
		_send_friend_message.rpc_id(acc_id, "You are now friends with %s!" % requester, Color.GREEN)

	friend_added.emit(requester, accepter)


## Called when a player finishes loading — notify their online friends.
func notify_player_online(username: String) -> void:
	if not multiplayer.is_server():
		return
	var friends: Array = _friend_lists.get(username, [])
	var player_id: int = PlayerManager.get_player_id_from_name(username)
	var map_id: String = MapManager.get_player_map(player_id) if player_id > 0 else ""

	for friend_name in friends:
		var friend_id: int = PlayerManager.get_player_id_from_name(friend_name)
		if friend_id > 0:
			_notify_friend_online.rpc_id(friend_id, username, map_id)
