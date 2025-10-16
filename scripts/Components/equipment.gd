class_name EquipmentComponent
extends Node

signal on_equipment_changed

@export var head_slot: EquipmentSlot
@export var chest_slot: EquipmentSlot
@export var legs_slot: EquipmentSlot
@export var feet_slot: EquipmentSlot
@export var weapon_slot: EquipmentSlot

var equipment: Dictionary = {}
var _changed_in_frame: bool = false
var _silent_mode: bool = false

func _ready():
	# Configure the slots with their specific types and set their container to this component.
	var armor_slots = {
		Constants.ArmorType.HEAD: head_slot,
		Constants.ArmorType.CHEST: chest_slot,
		Constants.ArmorType.LEGS: legs_slot,
		Constants.ArmorType.FEET: feet_slot,
	}
	
	for armor_type in armor_slots:
		var slot = armor_slots[armor_type]
		if is_instance_valid(slot):
			equipment[armor_type] = slot
			slot.set_inventory(self)
			slot.allowed_item_type = Constants.ItemType.EQUIPMENT
			slot.allowed_equipment_type = Constants.EquipmentType.ARMOR
			slot.allowed_armor_type = armor_type

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


func set_silent_mode(enabled: bool) -> void:
	_silent_mode = enabled


# This function is called by the Slot's item setter whenever an item is changed.
func _update_item_tracking(_slot: Slot, _old_item: ItemData, _new_item: ItemData):
	if _changed_in_frame:
		return
	_changed_in_frame = true
	call_deferred("_emit_equipment_changed_deferred")


func _emit_equipment_changed_deferred():
	if _silent_mode:
		_changed_in_frame = false
		return
		
	on_equipment_changed.emit()
	_changed_in_frame = false


func get_slots() -> Array[EquipmentSlot]:
	var slots_array: Array[EquipmentSlot] = []
	if head_slot: slots_array.append(head_slot)
	if chest_slot: slots_array.append(chest_slot)
	if legs_slot: slots_array.append(legs_slot)
	if feet_slot: slots_array.append(feet_slot)
	if weapon_slot: slots_array.append(weapon_slot)
	return slots_array
