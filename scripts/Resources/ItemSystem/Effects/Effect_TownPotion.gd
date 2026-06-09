class_name Effect_TownPotion
extends BaseItemEffect

func execute():
	if not is_instance_valid(user):
		print("Town Potion Effect: Invalid user.")
		return

	# Town-Scroll behaviour: a specific "target_map" property goes straight there
	# (e.g. a Lantern's Rest Scroll). With no target_map, this is a generic
	# Hearthstone — teleport to the NEAREST hearth from where the player is now.
	var current_map: String = MapManager.get_player_map(user.player_id)
	var target_map: String = source_item.effect_properties.get("target_map", "")
	if target_map.is_empty():
		target_map = MapManager.get_nearest_hearth(current_map)

	if current_map == target_map:
		print("Hearthstone: '%s' is already at hearth '%s'." % [user.username, target_map])
		return

	print("Hearthstone: Teleporting '%s' to '%s'." % [user.username, target_map])
	MapManager.request_map_change(user.player_id, target_map)
