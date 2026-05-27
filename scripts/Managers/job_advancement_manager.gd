extends Node
## JobAdvancementManager — Handles class evolution at level 30.
##
## Server-authoritative. Players use /advance to trigger class change
## when they meet the level requirement.

signal player_advanced(username: String, old_class: String, new_class: String)

const ADVANCEMENT_LEVEL: int = 30

# Maps base discipline -> advanced discipline
const ADVANCEMENT_MAP: Dictionary = {
	Constants.ClassType.SWORD: Constants.ClassType.CRUSADER,
	Constants.ClassType.BOW: Constants.ClassType.RANGER,
	Constants.ClassType.STAFF: Constants.ClassType.ARCHMAGE,
	Constants.ClassType.DAGGER: Constants.ClassType.ASSASSIN,
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
@rpc("any_peer", "call_local", "reliable")
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

	# Personal showcase VFX (flash + class-name banner) on the advancing
	# player's local screen. Sent to that player only — the server-wide
	# chat broadcast below is what other peers see.
	_show_advancement_vfx.rpc_id(sender_id, new_name)

	# Server-wide announcement
	_server_announce.rpc("[ADVANCE] %s has advanced from %s to %s!" % [player.username, old_name, new_name])

	player_advanced.emit(player.username, old_name, new_name)
	#print("JobAdvancement: %s advanced from %s to %s" % [player.username, old_name, new_name])


@rpc("authority", "call_local", "reliable")
func _send_message(text: String, color: Color) -> void:
	ChatManager.message_received.emit(text, color)


@rpc("authority", "call_local", "reliable")
func _server_announce(text: String) -> void:
	ChatManager.message_received.emit(text, Color.GOLD)


## Server-triggered, client-rendered: spawn the AdvancementVFX overlay (flash
## + class-name banner) on the local player's HUD. `call_local` so the host
## sees the VFX when its own character advances.
@rpc("authority", "call_local", "reliable")
func _show_advancement_vfx(class_text: String) -> void:
	var local_id: int = multiplayer.get_unique_id()
	for p in get_tree().get_nodes_in_group("Players"):
		if p.player_id != local_id:
			continue
		if not is_instance_valid(p.player_HUD):
			return
		# Avoid stacking if a previous VFX is still mid-animation.
		for child in p.player_HUD.get_children():
			if child is AdvancementVFX:
				return
		var vfx := AdvancementVFX.new()
		vfx.setup(class_text)
		p.player_HUD.add_child(vfx)
		return
