extends Node

## GuildManager — Server-authoritative guild system.
##
## Guilds persist per-player through the save system. Server tracks all guilds
## in memory; each player's guild membership is saved/loaded with their data.
##
## Ranks: LEADER (0), OFFICER (1), MEMBER (2)
##
## Chat commands (routed through ChatManager):
##   /guild create <name>    — create a new guild
##   /guild invite <player>  — invite a player (leader/officer only)
##   /guild accept           — accept pending guild invite
##   /guild leave             — leave your guild
##   /guild kick <player>    — kick a member (leader/officer only, cannot kick equal/higher rank)
##   /guild promote <player> — promote to officer (leader only)
##   /guild demote <player>  — demote officer to member (leader only)
##   /guild info              — show guild info and member list
##   /guild chat <message>   — send a message to guild members only
##   /gc <message>           — shortcut for guild chat

# ── Constants ────────────────────────────────────────────────────────────────
enum GuildRank { LEADER = 0, OFFICER = 1, MEMBER = 2 }

const MAX_GUILD_MEMBERS: int = 50
const MAX_GUILD_NAME_LENGTH: int = 20
const MIN_GUILD_NAME_LENGTH: int = 3

# ── Signals ──────────────────────────────────────────────────────────────────
signal guild_created(guild_name: String, leader_username: String)
signal guild_disbanded(guild_name: String)
signal member_joined(guild_name: String, username: String)
signal member_left(guild_name: String, username: String)

# ── Data Structures (server only) ────────────────────────────────────────────
## _guilds: guild_name -> { "members": { username -> GuildRank }, "created_by": String }
var _guilds: Dictionary = {}

## _player_guild: username -> guild_name (quick lookup)
var _player_guild: Dictionary = {}

## _pending_invites: username -> guild_name (only one pending invite at a time)
var _pending_invites: Dictionary = {}


func _ready() -> void:
	print("GuildManager: Initialized.")


# ═══════════════════════════════════════════════════════════════════════════
# CHAT COMMAND HANDLER
# ═══════════════════════════════════════════════════════════════════════════

func handle_guild_command(args: String, sender_id: int) -> void:
	if not multiplayer.is_server():
		return

	var player_node = PlayerManager.get_player_node(sender_id)
	if not player_node:
		return
	var username: String = player_node.username

	var parts: PackedStringArray = args.strip_edges().split(" ", false, 2)
	if parts.is_empty():
		_send_message(sender_id, "[Guild] Usage: /guild create|invite|accept|leave|kick|promote|demote|info|chat", Color.YELLOW)
		return

	var subcmd: String = parts[0].to_lower()
	var subargs: String = args.substr(subcmd.length()).strip_edges()

	match subcmd:
		"create":
			_cmd_create(sender_id, username, subargs)
		"invite":
			_cmd_invite(sender_id, username, subargs)
		"accept":
			_cmd_accept(sender_id, username)
		"leave":
			_cmd_leave(sender_id, username)
		"kick":
			_cmd_kick(sender_id, username, subargs)
		"promote":
			_cmd_promote(sender_id, username, subargs)
		"demote":
			_cmd_demote(sender_id, username, subargs)
		"info":
			_cmd_info(sender_id, username)
		"chat":
			_cmd_chat(sender_id, username, subargs)
		_:
			_send_message(sender_id, "[Guild] Unknown subcommand '%s'." % subcmd, Color.YELLOW)


## Handle /gc shortcut for guild chat
func handle_guild_chat(message: String, sender_id: int) -> void:
	if not multiplayer.is_server():
		return
	var player_node = PlayerManager.get_player_node(sender_id)
	if not player_node:
		return
	_cmd_chat(sender_id, player_node.username, message)


# ═══════════════════════════════════════════════════════════════════════════
# COMMANDS
# ═══════════════════════════════════════════════════════════════════════════

func _cmd_create(sender_id: int, username: String, guild_name: String) -> void:
	guild_name = guild_name.strip_edges()
	if guild_name.is_empty():
		_send_message(sender_id, "[Guild] Usage: /guild create <name>", Color.YELLOW)
		return

	if guild_name.length() < MIN_GUILD_NAME_LENGTH or guild_name.length() > MAX_GUILD_NAME_LENGTH:
		_send_message(sender_id, "[Guild] Guild name must be %d-%d characters." % [MIN_GUILD_NAME_LENGTH, MAX_GUILD_NAME_LENGTH], Color.RED)
		return

	if _player_guild.has(username):
		_send_message(sender_id, "[Guild] You are already in a guild. Leave first.", Color.RED)
		return

	# Check for duplicate name (case-insensitive)
	for existing_name in _guilds:
		if existing_name.to_lower() == guild_name.to_lower():
			_send_message(sender_id, "[Guild] A guild with that name already exists.", Color.RED)
			return

	_guilds[guild_name] = {
		"members": { username: GuildRank.LEADER },
		"created_by": username,
	}
	_player_guild[username] = guild_name

	_send_message(sender_id, "[Guild] Created guild '%s'! You are the leader." % guild_name, Color.GREEN)
	guild_created.emit(guild_name, username)
	_save_guild_data(username)


func _cmd_invite(sender_id: int, username: String, target_name: String) -> void:
	target_name = target_name.strip_edges()
	if target_name.is_empty():
		_send_message(sender_id, "[Guild] Usage: /guild invite <player>", Color.YELLOW)
		return

	if not _player_guild.has(username):
		_send_message(sender_id, "[Guild] You are not in a guild.", Color.RED)
		return

	var guild_name: String = _player_guild[username]
	var guild: Dictionary = _guilds[guild_name]
	var rank: int = guild["members"].get(username, GuildRank.MEMBER)

	if rank > GuildRank.OFFICER:
		_send_message(sender_id, "[Guild] Only leaders and officers can invite.", Color.RED)
		return

	if guild["members"].size() >= MAX_GUILD_MEMBERS:
		_send_message(sender_id, "[Guild] Guild is full (%d members)." % MAX_GUILD_MEMBERS, Color.RED)
		return

	# Resolve target
	var target_id: int = PlayerManager.get_player_id_from_name(target_name)
	if target_id == -1:
		_send_message(sender_id, "[Guild] Player '%s' not found online." % target_name, Color.RED)
		return

	var target_node = PlayerManager.get_player_node(target_id)
	if not target_node:
		_send_message(sender_id, "[Guild] Player '%s' not found." % target_name, Color.RED)
		return

	if _player_guild.has(target_name):
		_send_message(sender_id, "[Guild] '%s' is already in a guild." % target_name, Color.RED)
		return

	_pending_invites[target_name] = guild_name
	_send_message(sender_id, "[Guild] Invited '%s' to join '%s'." % [target_name, guild_name], Color.GREEN)
	_send_message(target_id, "[Guild] You have been invited to join '%s' by %s. Type /guild accept to join." % [guild_name, username], Color.GOLD)


func _cmd_accept(sender_id: int, username: String) -> void:
	if not _pending_invites.has(username):
		_send_message(sender_id, "[Guild] You have no pending guild invite.", Color.RED)
		return

	if _player_guild.has(username):
		_send_message(sender_id, "[Guild] You are already in a guild. Leave first.", Color.RED)
		_pending_invites.erase(username)
		return

	var guild_name: String = _pending_invites[username]
	_pending_invites.erase(username)

	if not _guilds.has(guild_name):
		_send_message(sender_id, "[Guild] The guild '%s' no longer exists." % guild_name, Color.RED)
		return

	var guild: Dictionary = _guilds[guild_name]
	if guild["members"].size() >= MAX_GUILD_MEMBERS:
		_send_message(sender_id, "[Guild] Guild '%s' is full." % guild_name, Color.RED)
		return

	guild["members"][username] = GuildRank.MEMBER
	_player_guild[username] = guild_name

	_send_message(sender_id, "[Guild] You joined '%s'!" % guild_name, Color.GREEN)
	_broadcast_to_guild(guild_name, "[Guild] %s has joined the guild!" % username, Color.GREEN, username)
	member_joined.emit(guild_name, username)
	_save_guild_data(username)


func _cmd_leave(sender_id: int, username: String) -> void:
	if not _player_guild.has(username):
		_send_message(sender_id, "[Guild] You are not in a guild.", Color.RED)
		return

	var guild_name: String = _player_guild[username]
	var guild: Dictionary = _guilds[guild_name]
	var rank: int = guild["members"].get(username, GuildRank.MEMBER)

	# Remove player
	guild["members"].erase(username)
	_player_guild.erase(username)

	_send_message(sender_id, "[Guild] You left '%s'." % guild_name, Color.YELLOW)

	if guild["members"].is_empty():
		# Guild disbanded
		_guilds.erase(guild_name)
		_send_message(sender_id, "[Guild] '%s' has been disbanded (no members left)." % guild_name, Color.YELLOW)
		guild_disbanded.emit(guild_name)
	else:
		# If leader left, promote the first officer, or first member
		if rank == GuildRank.LEADER:
			var new_leader: String = ""
			# Try to find an officer first
			for member_name in guild["members"]:
				if guild["members"][member_name] == GuildRank.OFFICER:
					new_leader = member_name
					break
			# Fall back to any member
			if new_leader.is_empty():
				new_leader = guild["members"].keys()[0]

			guild["members"][new_leader] = GuildRank.LEADER
			_broadcast_to_guild(guild_name, "[Guild] %s is now the guild leader." % new_leader, Color.GOLD)

		_broadcast_to_guild(guild_name, "[Guild] %s has left the guild." % username, Color.YELLOW)

	member_left.emit(guild_name, username)
	_save_guild_data(username)


func _cmd_kick(sender_id: int, username: String, target_name: String) -> void:
	target_name = target_name.strip_edges()
	if target_name.is_empty():
		_send_message(sender_id, "[Guild] Usage: /guild kick <player>", Color.YELLOW)
		return

	if not _player_guild.has(username):
		_send_message(sender_id, "[Guild] You are not in a guild.", Color.RED)
		return

	var guild_name: String = _player_guild[username]
	var guild: Dictionary = _guilds[guild_name]
	var my_rank: int = guild["members"].get(username, GuildRank.MEMBER)

	if my_rank > GuildRank.OFFICER:
		_send_message(sender_id, "[Guild] Only leaders and officers can kick members.", Color.RED)
		return

	if not guild["members"].has(target_name):
		_send_message(sender_id, "[Guild] '%s' is not in your guild." % target_name, Color.RED)
		return

	var target_rank: int = guild["members"].get(target_name, GuildRank.MEMBER)
	if target_rank <= my_rank:
		_send_message(sender_id, "[Guild] You cannot kick someone of equal or higher rank.", Color.RED)
		return

	guild["members"].erase(target_name)
	_player_guild.erase(target_name)

	_send_message(sender_id, "[Guild] Kicked '%s' from the guild." % target_name, Color.YELLOW)
	_broadcast_to_guild(guild_name, "[Guild] %s has been kicked from the guild." % target_name, Color.YELLOW)

	# Notify the kicked player if online
	var target_id: int = PlayerManager.get_player_id_from_name(target_name)
	if target_id != -1:
		_send_message(target_id, "[Guild] You have been kicked from '%s'." % guild_name, Color.RED)

	_save_guild_data(target_name)


func _cmd_promote(sender_id: int, username: String, target_name: String) -> void:
	target_name = target_name.strip_edges()
	if target_name.is_empty():
		_send_message(sender_id, "[Guild] Usage: /guild promote <player>", Color.YELLOW)
		return

	if not _player_guild.has(username):
		_send_message(sender_id, "[Guild] You are not in a guild.", Color.RED)
		return

	var guild_name: String = _player_guild[username]
	var guild: Dictionary = _guilds[guild_name]
	var my_rank: int = guild["members"].get(username, GuildRank.MEMBER)

	if my_rank != GuildRank.LEADER:
		_send_message(sender_id, "[Guild] Only the leader can promote members.", Color.RED)
		return

	if not guild["members"].has(target_name):
		_send_message(sender_id, "[Guild] '%s' is not in your guild." % target_name, Color.RED)
		return

	var target_rank: int = guild["members"][target_name]
	if target_rank == GuildRank.OFFICER:
		_send_message(sender_id, "[Guild] '%s' is already an officer." % target_name, Color.YELLOW)
		return
	if target_rank == GuildRank.LEADER:
		_send_message(sender_id, "[Guild] Cannot promote the leader.", Color.RED)
		return

	guild["members"][target_name] = GuildRank.OFFICER
	_broadcast_to_guild(guild_name, "[Guild] %s has been promoted to Officer!" % target_name, Color.GREEN)
	_save_guild_data(target_name)


func _cmd_demote(sender_id: int, username: String, target_name: String) -> void:
	target_name = target_name.strip_edges()
	if target_name.is_empty():
		_send_message(sender_id, "[Guild] Usage: /guild demote <player>", Color.YELLOW)
		return

	if not _player_guild.has(username):
		_send_message(sender_id, "[Guild] You are not in a guild.", Color.RED)
		return

	var guild_name: String = _player_guild[username]
	var guild: Dictionary = _guilds[guild_name]
	var my_rank: int = guild["members"].get(username, GuildRank.MEMBER)

	if my_rank != GuildRank.LEADER:
		_send_message(sender_id, "[Guild] Only the leader can demote members.", Color.RED)
		return

	if not guild["members"].has(target_name):
		_send_message(sender_id, "[Guild] '%s' is not in your guild." % target_name, Color.RED)
		return

	var target_rank: int = guild["members"][target_name]
	if target_rank != GuildRank.OFFICER:
		_send_message(sender_id, "[Guild] '%s' is not an officer." % target_name, Color.YELLOW)
		return

	guild["members"][target_name] = GuildRank.MEMBER
	_broadcast_to_guild(guild_name, "[Guild] %s has been demoted to Member." % target_name, Color.ORANGE_RED)
	_save_guild_data(target_name)


func _cmd_info(sender_id: int, username: String) -> void:
	if not _player_guild.has(username):
		_send_message(sender_id, "[Guild] You are not in a guild.", Color.RED)
		return

	var guild_name: String = _player_guild[username]
	var guild: Dictionary = _guilds[guild_name]

	_send_message(sender_id, "[Guild] === %s ===" % guild_name, Color.GOLD)
	_send_message(sender_id, "[Guild] Members (%d/%d):" % [guild["members"].size(), MAX_GUILD_MEMBERS], Color.GOLD)

	# Sort by rank for display
	var leaders: Array = []
	var officers: Array = []
	var members: Array = []
	for member_name in guild["members"]:
		var rank: int = guild["members"][member_name]
		match rank:
			GuildRank.LEADER:
				leaders.append(member_name)
			GuildRank.OFFICER:
				officers.append(member_name)
			_:
				members.append(member_name)

	for name in leaders:
		var online_str: String = " (online)" if PlayerManager.get_player_id_from_name(name) != -1 else ""
		_send_message(sender_id, "  [Leader] %s%s" % [name, online_str], Color.GOLD)
	for name in officers:
		var online_str: String = " (online)" if PlayerManager.get_player_id_from_name(name) != -1 else ""
		_send_message(sender_id, "  [Officer] %s%s" % [name, online_str], Color.CYAN)
	for name in members:
		var online_str: String = " (online)" if PlayerManager.get_player_id_from_name(name) != -1 else ""
		_send_message(sender_id, "  [Member] %s%s" % [name, online_str], Color.WHITE)


func _cmd_chat(sender_id: int, username: String, message: String) -> void:
	if message.strip_edges().is_empty():
		_send_message(sender_id, "[Guild] Usage: /guild chat <message> or /gc <message>", Color.YELLOW)
		return

	if not _player_guild.has(username):
		_send_message(sender_id, "[Guild] You are not in a guild.", Color.RED)
		return

	var guild_name: String = _player_guild[username]
	var chat_msg: String = "[Guild] %s: %s" % [username, message]
	_broadcast_to_guild(guild_name, chat_msg, Color.MEDIUM_SPRING_GREEN)


# ═══════════════════════════════════════════════════════════════════════════
# SAVE / LOAD
# ═══════════════════════════════════════════════════════════════════════════

## Returns the guild data to include in a player's save.
func save_guild(username: String) -> Dictionary:
	if not _player_guild.has(username):
		return {}

	var guild_name: String = _player_guild[username]
	if not _guilds.has(guild_name):
		return {}

	var guild: Dictionary = _guilds[guild_name]
	return {
		"guild_name": guild_name,
		"rank": guild["members"].get(username, GuildRank.MEMBER),
		"members": guild["members"].duplicate(),
		"created_by": guild.get("created_by", ""),
	}


## Loads guild data from a player's save. Reconstructs guild state on server.
func load_guild(username: String, data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if data.is_empty():
		return

	var guild_name: String = data.get("guild_name", "")
	if guild_name.is_empty():
		return

	var rank: int = data.get("rank", GuildRank.MEMBER)

	# If the guild doesn't exist yet in memory, reconstruct it from save data
	if not _guilds.has(guild_name):
		var saved_members: Dictionary = data.get("members", {})
		if saved_members.is_empty():
			saved_members = { username: rank }
		_guilds[guild_name] = {
			"members": saved_members,
			"created_by": data.get("created_by", username),
		}
		print("GuildManager: Reconstructed guild '%s' from save data for '%s'." % [guild_name, username])
	else:
		# Guild already exists — ensure this player is tracked with correct rank
		var guild: Dictionary = _guilds[guild_name]
		if not guild["members"].has(username):
			guild["members"][username] = rank

	_player_guild[username] = guild_name
	print("GuildManager: Loaded guild data for '%s' — guild '%s', rank %d." % [username, guild_name, rank])


func unregister_player(username: String) -> void:
	# Player disconnected — keep guild data in memory (persisted through saves)
	pass


func handle_player_disconnect(username: String) -> void:
	# Notify guild members that someone went offline
	if not _player_guild.has(username):
		return
	var guild_name: String = _player_guild[username]
	_broadcast_to_guild(guild_name, "[Guild] %s went offline." % username, Color.GRAY, username)


# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _send_message(peer_id: int, text: String, color: Color) -> void:
	_client_receive_guild_message.rpc_id(peer_id, text, color)


@rpc("authority", "call_local", "reliable")
func _client_receive_guild_message(text: String, color: Color) -> void:
	ChatManager.add_system_message(text, color)


func _broadcast_to_guild(guild_name: String, text: String, color: Color, exclude_username: String = "") -> void:
	if not _guilds.has(guild_name):
		return
	var guild: Dictionary = _guilds[guild_name]
	for member_name in guild["members"]:
		if member_name == exclude_username:
			continue
		var pid: int = PlayerManager.get_player_id_from_name(member_name)
		if pid != -1:
			_send_message(pid, text, color)


func _save_guild_data(username: String) -> void:
	var pid: int = PlayerManager.get_player_id_from_name(username)
	if pid != -1:
		var pn = PlayerManager.get_player_node(pid)
		if pn and SaveManager:
			SaveManager.queue_save(username, "all", pn)


func _rank_name(rank: int) -> String:
	match rank:
		GuildRank.LEADER: return "Leader"
		GuildRank.OFFICER: return "Officer"
		GuildRank.MEMBER: return "Member"
		_: return "Unknown"


## Get a player's guild name (or empty string).
func get_player_guild(username: String) -> String:
	return _player_guild.get(username, "")


## Get a player's rank in their guild (or -1 if not in a guild).
func get_player_rank(username: String) -> int:
	if not _player_guild.has(username):
		return -1
	var guild_name: String = _player_guild[username]
	if not _guilds.has(guild_name):
		return -1
	return _guilds[guild_name]["members"].get(username, -1)
