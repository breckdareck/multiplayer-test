class_name Effect_TownPotion
extends BaseItemEffect

func execute():
	if not is_instance_valid(user):
		print("Town Potion Effect: Invalid user.")
		return

	var target_map: String = source_item.effect_properties.get("target_map", MapManager.DEFAULT_MAP)
	print("Town Potion: Target Map %s - Default Map %s" % [target_map, MapManager.DEFAULT_MAP])
	var current_map: String = MapManager.get_player_map(user.player_id)
	if current_map == target_map:
		print("Town Potion: Player '%s' is already on map '%s'." % [user.username, target_map])
		return

	print("Town Potion: Teleporting '%s' to '%s'." % [user.username, target_map])
	MapManager.request_map_change(user.player_id, target_map)
