class_name BotEquipmentLogic


static func score_item(item: ItemData) -> float:
	if item is not EquipmentData:
		return 0.0
	var eq := item as EquipmentData
	var score := 0.0
	for stat_type in eq.bonus_stats:
		var stat_data: StatData = eq.bonus_stats[stat_type]
		score += stat_data.flat_bonus_value
		score += stat_data.percent_bonus_value * 10.0
	score += float(eq.item_level) * 2.0
	return score


static func should_equip(current: ItemData, candidate: ItemData) -> bool:
	if candidate is not EquipmentData:
		return false
	if current == null:
		return true
	return score_item(candidate) > score_item(current)


static func get_target_slot(item: ItemData, equipment_component: EquipmentComponent) -> EquipmentSlot:
	if item is WeaponData:
		return equipment_component.weapon_slot
	elif item is ArmorData:
		var armor := item as ArmorData
		match armor.armor_type:
			Constants.ArmorType.HEAD:
				return equipment_component.head_slot
			Constants.ArmorType.CHEST:
				return equipment_component.chest_slot
			Constants.ArmorType.LEGS:
				return equipment_component.legs_slot
			Constants.ArmorType.FEET:
				return equipment_component.feet_slot
	return null
