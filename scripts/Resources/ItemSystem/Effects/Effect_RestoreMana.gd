class_name Effect_RestoreMana
extends BaseItemEffect

func execute():
	if not is_instance_valid(user) or not is_instance_valid(user.mana_component):
		print("Restore Mana Effect: Invalid user or mana component.")
		return

	var regain_amount = source_item.effect_properties.get("regain_amount", 0)
	if regain_amount > 0:
		user.mana_component.regain_mana(regain_amount)
		print("Player %d healed for %d MP." % [user.player_id, regain_amount])
