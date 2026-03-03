@tool
@abstract
class_name EquipmentData
extends ItemData

@export var equipment_type: Constants.EquipmentType

@export var bonus_stats: Dictionary[Constants.StatType, StatData] = {}

func _init():
	super ()

func to_dictionary() -> Dictionary:
	var dict = super.to_dictionary()
	
	var serialized_bonus_stats = {}
	for stat_type in bonus_stats:
		var stat_data: StatData = bonus_stats[stat_type]
		serialized_bonus_stats[stat_type] = stat_data.to_dictionary()
	dict["bonus_stats"] = serialized_bonus_stats
	
	dict["equipment_type"] = equipment_type
	
	if self is ArmorData:
		dict["armor_type"] = (self as ArmorData).armor_type
	elif self is WeaponData:
		dict["weapon_type"] = (self as WeaponData).weapon_type
		dict["weapon_attack_speed"] = (self as WeaponData).weapon_attack_speed
		
	return dict


func get_save_data() -> Dictionary:
	var dict = super.get_save_data()
	
	var serialized_bonus_stats = {}
	for stat_type in bonus_stats:
		var stat_data: StatData = bonus_stats[stat_type]
		serialized_bonus_stats[str(stat_type)] = stat_data.to_dictionary()
	dict["bonus_stats"] = serialized_bonus_stats
	
	dict["equipment_type"] = equipment_type
	
	if self is ArmorData:
		dict["armor_type"] = (self as ArmorData).armor_type
	elif self is WeaponData:
		dict["weapon_type"] = (self as WeaponData).weapon_type
		dict["weapon_attack_speed"] = (self as WeaponData).weapon_attack_speed
		
	return dict


static func from_dictionary(dict: Dictionary) -> ItemData:
	var item_instance: EquipmentData
	var equipment_type_enum = int(dict.get("equipment_type", -1))
	
	match equipment_type_enum:
		Constants.EquipmentType.ARMOR:
			item_instance = ArmorData.new()
		Constants.EquipmentType.WEAPON:
			item_instance = WeaponData.new()
		_:
			print("Error: Attempted to deserialize abstract EquipmentData without concrete type.")
			return null

	# Populate ItemData properties (manually, as ItemData.from_dictionary is static)
	item_instance.item_id = dict.get("item_id", ItemData.new().generate_uuid())
	item_instance.name = dict.get("name", "")
	item_instance.rarity = dict.get("rarity", Constants.ItemRarity.COMMON)
	var icon_path = dict.get("icon_path", "")
	if not icon_path.is_empty():
		item_instance.icon = load(icon_path)
	item_instance.description = dict.get("description", "")
	item_instance.item_type = dict.get("item_type", Constants.ItemType.EQUIPMENT) # Ensure it's EQUIPMENT
	item_instance.item_level = dict.get("item_level", 0)
	item_instance.custom_item_value = dict.get("custom_item_value", 0)
	item_instance.can_stack = dict.get("can_stack", false)
	item_instance.max_stack_amount = dict.get("max_stack_amount", 0)
	item_instance.current_stack_amount = dict.get("current_stack_amount", 1)
	item_instance.original_resource_path = dict.get("original_resource_path", "")

	# Populate EquipmentData specific properties
	item_instance.equipment_type = equipment_type_enum
	if item_instance is ArmorData:
		(item_instance as ArmorData).armor_type = dict.get("armor_type", -1)
	elif item_instance is WeaponData:
		(item_instance as WeaponData).weapon_type = dict.get("weapon_type", -1)
		(item_instance as WeaponData).weapon_attack_speed = dict.get("weapon_attack_speed", 4)

	# Initialize bonus_stats if it's null or not a dictionary
	if not item_instance.bonus_stats is Dictionary:
		item_instance.bonus_stats = {}

	# Deserialize bonus_stats
	var serialized_bonus_stats = dict.get("bonus_stats", {})
	for stat_type_str in serialized_bonus_stats:
		var stat_type = int(stat_type_str)
		item_instance.bonus_stats[stat_type] = StatData.from_dictionary(serialized_bonus_stats[stat_type_str])
	
	return item_instance
