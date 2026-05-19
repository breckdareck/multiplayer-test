class_name BotEquipmentLogic

const CLASS_WEAPON_TYPES: Dictionary = {
	Constants.ClassType.SWORDSMAN: [Constants.WeaponType.SWORD],
	Constants.ClassType.CRUSADER: [Constants.WeaponType.SWORD],
	Constants.ClassType.ARCHER: [Constants.WeaponType.BOW],
	Constants.ClassType.RANGER: [Constants.WeaponType.BOW],
	Constants.ClassType.MAGE: [Constants.WeaponType.STAFF],
	Constants.ClassType.ARCHMAGE: [Constants.WeaponType.STAFF],
	Constants.ClassType.ROGUE: [Constants.WeaponType.SWORD],
	Constants.ClassType.ASSASSIN: [Constants.WeaponType.SWORD],
	Constants.ClassType.BEGINNER: [Constants.WeaponType.SWORD],
}

const PRIMARY_STAT_WEIGHT: float = 3.0
const SECONDARY_STAT_WEIGHT: float = 2.0
const ATTACK_STAT_WEIGHT: float = 3.0
const DEFENSIVE_STAT_WEIGHT: float = 1.5
const OFF_ATTACK_STAT_WEIGHT: float = 0.2
const OTHER_STAT_WEIGHT: float = 0.5


static func can_equip_weapon(weapon: WeaponData, class_type: Constants.ClassType) -> bool:
	var allowed: Array = CLASS_WEAPON_TYPES.get(class_type, [])
	return weapon.weapon_type in allowed


static func _get_stat_weight(stat_type: Constants.StatType, primary_stat: Constants.StatType, secondary_stat: Constants.StatType, is_magic_class: bool) -> float:
	if stat_type == primary_stat:
		return PRIMARY_STAT_WEIGHT
	if stat_type == secondary_stat:
		return SECONDARY_STAT_WEIGHT
	match stat_type:
		Constants.StatType.WEAPONATTACK:
			return ATTACK_STAT_WEIGHT if not is_magic_class else OFF_ATTACK_STAT_WEIGHT
		Constants.StatType.MAGICATTACK:
			return ATTACK_STAT_WEIGHT if is_magic_class else OFF_ATTACK_STAT_WEIGHT
		Constants.StatType.HEALTH, Constants.StatType.DEFENSE, Constants.StatType.MAGICDEFENSE:
			return DEFENSIVE_STAT_WEIGHT
		Constants.StatType.CRITCHANCE, Constants.StatType.CRITDAMAGE:
			return SECONDARY_STAT_WEIGHT
		_:
			return OTHER_STAT_WEIGHT


static func score_item(item: ItemData, class_type: Constants.ClassType = Constants.ClassType.BEGINNER) -> float:
	if item is not EquipmentData:
		return 0.0

	if item is WeaponData and not can_equip_weapon(item as WeaponData, class_type):
		return -1.0

	var primary_stat: Constants.StatType = ResourceManager.get_primary_stat(class_type)
	var secondary_stat: Constants.StatType = ResourceManager.get_secondary_stat(class_type)
	var is_magic_class: bool = primary_stat == Constants.StatType.INTELLIGENCE

	var eq := item as EquipmentData
	var score := 0.0
	for stat_type in eq.bonus_stats:
		var stat_data: StatData = eq.bonus_stats[stat_type]
		var weight := _get_stat_weight(stat_type, primary_stat, secondary_stat, is_magic_class)
		score += stat_data.flat_bonus_value * weight
		score += stat_data.percent_bonus_value * weight * 10.0
	score += float(eq.item_level) * 2.0
	return score


static func should_equip(current: ItemData, candidate: ItemData, class_type: Constants.ClassType = Constants.ClassType.BEGINNER) -> bool:
	if candidate is not EquipmentData:
		return false
	var candidate_score := score_item(candidate, class_type)
	if candidate_score < 0.0:
		return false
	if current == null:
		return true
	return candidate_score > score_item(current, class_type)


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
