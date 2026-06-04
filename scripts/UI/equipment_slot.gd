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

	# Optional explicit weapon-type lock on a slot (sentinel -1 = any).
	if allowed_weapon_type != -1 and item_to_check is WeaponData \
			and item_to_check.weapon_type != allowed_weapon_type:
		return false

	# DUAL-WIELD RULE: the two weapon slots must hold DIFFERENT weapon types — you
	# can't run two swords / two staffs / etc. (the whole point is two distinct
	# disciplines, and passives/mastery would otherwise double-stack one weapon).
	# If this is a weapon slot and the OTHER weapon slot already holds the same
	# weapon_type, reject. item_container on an equipment slot is the
	# EquipmentComponent (set via set_inventory(self)). We identify which weapon
	# slot we are by our bound SlotData's key, not a view ref — ADR 0009 Stage A
	# removed the component's @export weapon_slot / secondary_weapon_slot paths.
	if allowed_equipment_type == Constants.EquipmentType.WEAPON and item_to_check is WeaponData:
		var eq = item_container
		if eq != null and eq.has_method("get_slot_data") and slot_data != null:
			var other_data: SlotData = null
			if slot_data.key == "WEAPON":
				other_data = eq.get_slot_data("SECONDARY_WEAPON")
			elif slot_data.key == "SECONDARY_WEAPON":
				other_data = eq.get_slot_data("WEAPON")
			if other_data != null and other_data.item is WeaponData \
					and other_data.item.weapon_type == item_to_check.weapon_type:
				return false

	return true
