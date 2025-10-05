class_name EquipmentComponent
extends Node

signal on_equipment_changed

@export var head_slot: EquipmentSlot
@export var chest_slot: EquipmentSlot
@export var legs_slot: EquipmentSlot
@export var feet_slot: EquipmentSlot
@export var weapon_slot: EquipmentSlot

var equipment: Dictionary = {}

func _ready():
	# Configure the slots with their specific types and set their container to this component.
	if head_slot:
		equipment[Constants.ArmorType.HEAD] = head_slot
		head_slot.set_inventory(self)
		head_slot.allowed_item_type = Constants.ItemType.EQUIPMENT
		head_slot.allowed_equipment_type = Constants.EquipmentType.ARMOR
		head_slot.allowed_armor_type = Constants.ArmorType.HEAD

	if chest_slot:
		equipment[Constants.ArmorType.CHEST] = chest_slot
		chest_slot.set_inventory(self)
		chest_slot.allowed_item_type = Constants.ItemType.EQUIPMENT
		chest_slot.allowed_equipment_type = Constants.EquipmentType.ARMOR
		chest_slot.allowed_armor_type = Constants.ArmorType.CHEST

	if legs_slot:
		equipment[Constants.ArmorType.LEGS] = legs_slot
		legs_slot.set_inventory(self)
		legs_slot.allowed_item_type = Constants.ItemType.EQUIPMENT
		legs_slot.allowed_equipment_type = Constants.EquipmentType.ARMOR
		legs_slot.allowed_armor_type = Constants.ArmorType.LEGS

	if feet_slot:
		equipment[Constants.ArmorType.FEET] = feet_slot
		feet_slot.set_inventory(self)
		feet_slot.allowed_item_type = Constants.ItemType.EQUIPMENT
		feet_slot.allowed_equipment_type = Constants.EquipmentType.ARMOR
		feet_slot.allowed_armor_type = Constants.ArmorType.FEET

	if weapon_slot:
		equipment["WEAPON"] = weapon_slot
		weapon_slot.set_inventory(self)
		weapon_slot.allowed_item_type = Constants.ItemType.EQUIPMENT
		weapon_slot.allowed_equipment_type = Constants.EquipmentType.WEAPON

	# When equipment changes on the server, persist the player's data
	if multiplayer.is_server():
		on_equipment_changed.connect(func():
			var owner_player := owner as MultiplayerPlayerV2
			if owner_player and owner_player.has_method("_data_changed"):
				owner_player._data_changed()
		)


# This function is called by the Slot's item setter whenever an item is changed.
func _update_item_tracking(_slot: Slot, _old_item: ItemData, _new_item: ItemData):
	# When equipment changes, we just emit a signal.
	# Other systems (like a character stats manager) can connect to this signal.
	#print("Equipment changed: %s" % _new_item.name)
	on_equipment_changed.emit()


func get_slots() -> Array[EquipmentSlot]:
	var slots_array: Array[EquipmentSlot] = []
	if head_slot: slots_array.append(head_slot)
	if chest_slot: slots_array.append(chest_slot)
	if legs_slot: slots_array.append(legs_slot)
	if feet_slot: slots_array.append(feet_slot)
	if weapon_slot: slots_array.append(weapon_slot)
	return slots_array


# These functions can still be useful for programmatic equipping (e.g., from a script).
func equip_item(item: ItemData) -> bool:
	if not item or item.item_type != Constants.ItemType.EQUIPMENT:
		return false

	var target_slot: EquipmentSlot = null
	if item.equipment_type == Constants.EquipmentType.ARMOR:
		if equipment.has(item.armor_type):
			target_slot = equipment[item.armor_type]
	elif item.equipment_type == Constants.EquipmentType.WEAPON:
		target_slot = equipment.get("WEAPON")

	if target_slot and not target_slot.item:
		# The slot's item setter will trigger the _update_item_tracking function.
		target_slot.item = item
		return true
	
	return false


func unequip_item(slot: EquipmentSlot) -> ItemData:
	if not slot or not slot.item:
		return null
	
	var item_to_return = slot.item
	# The slot's item setter will trigger the _update_item_tracking function.
	slot.item = null
	return item_to_return
