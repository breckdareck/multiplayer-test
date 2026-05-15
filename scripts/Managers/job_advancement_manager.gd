extends Node
## JobAdvancementManager — Handles class evolution at level 30.
##
## Server-authoritative. Players use /advance to trigger class change
## when they meet the level requirement.

signal player_advanced(username: String, old_class: String, new_class: String)

const ADVANCEMENT_LEVEL: int = 30

# Maps base class -> advanced class
const ADVANCEMENT_MAP: Dictionary = {
	Constants.ClassType.SWORDSMAN: Constants.ClassType.CRUSADER,
	Constants.ClassType.ARCHER: Constants.ClassType.RANGER,
	Constants.ClassType.MAGE: Constants.ClassType.ARCHMAGE,
	Constants.ClassType.ROGUE: Constants.ClassType.ASSASSIN,
}

# Display names for advanced classes
const ADVANCED_CLASS_NAMES: Dictionary = {
	Constants.ClassType.CRUSADER: "Crusader",
	Constants.ClassType.RANGER: "Ranger",
	Constants.ClassType.ARCHMAGE: "Archmage",
	Constants.ClassType.ASSASSIN: "Assassin",
}


func can_advance(player: MultiplayerPlayerV2) -> bool:
	if not is_instance_valid(player):
		return false
	if not is_instance_valid(player.level_component) or not is_instance_valid(player.class_component):
		return false

	var current_class: Constants.ClassType = player.class_component.current_class
	if not ADVANCEMENT_MAP.has(current_class):
		return false  # Already advanced or invalid class

	return player.level_component.level >= ADVANCEMENT_LEVEL


func get_advanced_class(base_class: Constants.ClassType) -> Constants.ClassType:
	return ADVANCEMENT_MAP.get(base_class, base_class)


func get_advanced_class_name(base_class: Constants.ClassType) -> String:
	var advanced: Constants.ClassType = get_advanced_class(base_class)
	return ADVANCED_CLASS_NAMES.get(advanced, "Unknown")


## Attempt job advancement for a player
@rpc("any_peer", "call_remote", "reliable")
func request_advancement() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	var player: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(player):
		return

	if not can_advance(player):
		var current_class: Constants.ClassType = player.class_component.current_class
		if not ADVANCEMENT_MAP.has(current_class):
			_send_message.rpc_id(sender_id, "You have already advanced your class.", Color.GRAY)
		else:
			_send_message.rpc_id(sender_id, "You need to be level %d to advance. (Currently level %d)" % [ADVANCEMENT_LEVEL, player.level_component.level], Color.RED)
		return

	var old_class: Constants.ClassType = player.class_component.current_class
	var new_class: Constants.ClassType = ADVANCEMENT_MAP[old_class]
	var old_name: String = ResourceManager.get_class_name(old_class)
	var new_name: String = ADVANCED_CLASS_NAMES[new_class]

	# Perform the class change
	player.class_component.change_class_rpc.rpc(new_class)
	player._handle_sprite_change_on_server()

	_send_message.rpc_id(sender_id, "Congratulations! You have advanced from %s to %s!" % [old_name, new_name], Color.GOLD)

	# Server-wide announcement
	_server_announce.rpc("[ADVANCE] %s has advanced from %s to %s!" % [player.username, old_name, new_name])

	player_advanced.emit(player.username, old_name, new_name)
	print("JobAdvancement: %s advanced from %s to %s" % [player.username, old_name, new_name])


@rpc("authority", "call_local", "reliable")
func _send_message(text: String, color: Color) -> void:
	ChatManager.message_received.emit(text, color)


@rpc("authority", "call_local", "reliable")
func _server_announce(text: String) -> void:
	ChatManager.message_received.emit(text, Color.GOLD)
