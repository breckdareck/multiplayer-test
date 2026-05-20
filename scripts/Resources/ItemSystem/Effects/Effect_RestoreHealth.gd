class_name Effect_RestoreHealth
extends BaseItemEffect

func execute():
	if not is_instance_valid(user) or not is_instance_valid(user.health_component):
		#print("Restore Health Effect: Invalid user or health component.")
		return

	var heal_amount = source_item.effect_properties.get("heal_amount", 0)
	if heal_amount > 0:
		user.health_component.heal_damage(heal_amount)
		#print("Player %d healed for %d HP." % [user.player_id, heal_amount])
