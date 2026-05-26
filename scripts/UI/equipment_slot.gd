extends Slot
class_name EquipmentSlot

@export var allowed_equipment_type: int = -1 # Sentinel for no specific equipment type
@export var allowed_armor_type: int = -1 # Sentinel for no specific armor type
@export var allowed_weapon_type: int = -1 # Sentinel for no specific weapon type


func can_accept_item(item_to_check: ItemData) -> bool:
	# First, run the parent class's validation (e.g., checking for ItemType.EQUIPMENT)
	if not super.can_accept_item(item_to_check):
		return false

	# If the parent check passes, then do the equipment-specific checks
	if not item_to_check:
		return true # Can always accept nothing

	# Check equipment type (ARMOR or WEAPON)
	if allowed_equipment_type != -1 and item_to_check.equipment_type != allowed_equipment_type:
		return false

	# Check armor type (HEAD, CHEST, etc.)
	if allowed_armor_type != -1 and item_to_check.armor_type != allowed_armor_type:
		return false

	return true
