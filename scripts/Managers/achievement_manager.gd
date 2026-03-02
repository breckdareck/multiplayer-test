extends Node
## AchievementManager — Tracks milestones and awards titles.
##
## Server-authoritative. Stores progress in player save data.
## Players can set an active title displayed under their name.

signal achievement_unlocked(username: String, achievement_id: String)

# Achievement definitions: { id: { title, description, stat, threshold } }
const ACHIEVEMENTS: Dictionary = {
	"slime_slayer": {
		"title": "Slime Slayer",
		"description": "Defeat 100 slimes",
		"stat": "kills_slime",
		"threshold": 100,
	},
	"slime_master": {
		"title": "Slime Master",
		"description": "Defeat 1000 slimes",
		"stat": "kills_slime",
		"threshold": 1000,
	},
	"boar_hunter": {
		"title": "Boar Hunter",
		"description": "Defeat 100 boars",
		"stat": "kills_boar",
		"threshold": 100,
	},
	"veteran": {
		"title": "Veteran",
		"description": "Reach level 30",
		"stat": "level",
		"threshold": 30,
	},
	"elite": {
		"title": "Elite",
		"description": "Reach level 50",
		"stat": "level",
		"threshold": 50,
	},
	"first_blood": {
		"title": "First Blood",
		"description": "Defeat your first enemy",
		"stat": "kills_total",
		"threshold": 1,
	},
	"centurion": {
		"title": "Centurion",
		"description": "Defeat 100 enemies",
		"stat": "kills_total",
		"threshold": 100,
	},
	"millionaire": {
		"title": "Millionaire",
		"description": "Accumulate 1,000,000 coins",
		"stat": "monies_earned",
		"threshold": 1000000,
	},
}

# Per-player data: username -> { stats: {stat_key: value}, unlocked: [achievement_ids], active_title: String }
var _player_data: Dictionary = {}


func record_kill(username: String, enemy_name: String) -> void:
	if not multiplayer.is_server():
		return
	var stats: Dictionary = _get_stats(username)
	var kill_key: String = "kills_" + enemy_name.to_lower().replace(" ", "_")
	stats[kill_key] = stats.get(kill_key, 0) + 1
	stats["kills_total"] = stats.get("kills_total", 0) + 1
	_check_achievements(username)


func record_stat(username: String, stat_key: String, value: int) -> void:
	if not multiplayer.is_server():
		return
	var stats: Dictionary = _get_stats(username)
	stats[stat_key] = value
	_check_achievements(username)


func get_active_title(username: String) -> String:
	if not _player_data.has(username):
		return ""
	return _player_data[username].get("active_title", "")


func get_unlocked_achievements(username: String) -> Array:
	if not _player_data.has(username):
		return []
	return _player_data[username].get("unlocked", [])


func set_active_title(username: String, achievement_id: String) -> bool:
	if not multiplayer.is_server():
		return false
	if not _player_data.has(username):
		return false
	if achievement_id.is_empty():
		_player_data[username]["active_title"] = ""
		return true
	var unlocked: Array = _player_data[username].get("unlocked", [])
	if achievement_id not in unlocked:
		return false
	_player_data[username]["active_title"] = achievement_id
	return true


func get_save_data(username: String) -> Dictionary:
	if not _player_data.has(username):
		return {}
	return _player_data[username].duplicate(true)


func load_save_data(username: String, data: Dictionary) -> void:
	_player_data[username] = {
		"stats": data.get("stats", {}),
		"unlocked": data.get("unlocked", []),
		"active_title": data.get("active_title", ""),
	}


func _get_stats(username: String) -> Dictionary:
	if not _player_data.has(username):
		_player_data[username] = {"stats": {}, "unlocked": [], "active_title": ""}
	return _player_data[username]["stats"]


func _check_achievements(username: String) -> void:
	if not _player_data.has(username):
		return
	var stats: Dictionary = _player_data[username]["stats"]
	var unlocked: Array = _player_data[username]["unlocked"]

	for achievement_id in ACHIEVEMENTS:
		if achievement_id in unlocked:
			continue
		var achievement: Dictionary = ACHIEVEMENTS[achievement_id]
		var current_value: int = stats.get(achievement.stat, 0)
		if current_value >= achievement.threshold:
			unlocked.append(achievement_id)
			achievement_unlocked.emit(username, achievement_id)
			_notify_achievement(username, achievement_id)


func _notify_achievement(username: String, achievement_id: String) -> void:
	var achievement: Dictionary = ACHIEVEMENTS[achievement_id]
	var title: String = achievement.get("title", "")

	# Find the player and notify via chat
	for map_id in MapManager.active_maps.keys():
		var map_instance = MapManager.active_maps[map_id].scene_instance
		if not is_instance_valid(map_instance):
			continue
		var players_node = map_instance.get_node_or_null("Players")
		if not players_node:
			continue
		for child in players_node.get_children():
			if child is MultiplayerPlayerV2 and child.username == username:
				ChatManager.add_system_message.rpc_id(child.player_id,
					"Achievement Unlocked: %s — %s" % [title, achievement.description],
					Color.GOLD)
				return
