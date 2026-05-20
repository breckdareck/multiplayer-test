class_name Effect_GrantExperience
extends BaseItemEffect

func execute():
	if not is_instance_valid(user) or not is_instance_valid(user.level_component):
		#print("Grant Experience Effect: Invalid user or level component.")
		return

	var exp_amount = source_item.effect_properties.get("exp_amount", 0)
	if exp_amount > 0:
		user.level_component.add_exp(exp_amount)
		#print("Player %d gained %d EXP." % [user.player_id, exp_amount])
