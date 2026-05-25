class_name PetSlot
extends PanelContainer

## A pet inventory slot. Holds 1 item type at a time (with stack).
## Accepts drops from main-inventory Slot nodes by sending a transfer RPC
## through PetManager. Used for the 2 autopot slots and the 3 storage slots.
##
## Owns no game state itself — reads from PetManager.client_find_pet
## whenever asked to refresh.

@export var slot_label: Label
@export var icon_rect: TextureRect
@export var count_label: Label

## The pet whose inventory this slot belongs to.
var pet_uuid: String = ""
## Which sub-slot — "autopot_hp_slot", "autopot_mp_slot", or "storage_<i>".
var slot_key: String = ""
## Which item types are allowed in this slot — kept loose for v1 so the player
## can experiment. The server validates by command anyway.
var require_consumable: bool = false


func setup(pet_uuid_in: String, slot_key_in: String, label_text: String, require_consumable_in: bool) -> void:
	pet_uuid = pet_uuid_in
	slot_key = slot_key_in
	require_consumable = require_consumable_in
	if is_instance_valid(slot_label):
		slot_label.text = label_text
	refresh()


func refresh() -> void:
	if pet_uuid.is_empty():
		_clear_display()
		return
	var record := PetManager.client_find_pet(pet_uuid)
	if record.is_empty():
		_clear_display()
		return
	var inv: Dictionary = record.get(PetManager.KEY_INVENTORY, {})
	var slot_data := _read_slot_data(inv)
	if slot_data.is_empty():
		_clear_display()
		return

	var item_id: String = slot_data.get("item_id", "")
	var stack: int = int(slot_data.get("stack", 0))
	if item_id.is_empty() or stack <= 0:
		_clear_display()
		return

	var item: ItemData = ResourceManager.get_item_data(item_id)
	if is_instance_valid(icon_rect):
		icon_rect.texture = item.icon if item else null
		icon_rect.visible = item != null
	if is_instance_valid(count_label):
		count_label.text = "x%d" % stack
		count_label.visible = stack > 1
	if is_instance_valid(slot_label):
		slot_label.visible = false


func _read_slot_data(inv: Dictionary) -> Dictionary:
	if slot_key.begins_with("storage_"):
		var idx_str := slot_key.substr("storage_".length())
		var idx := int(idx_str)
		var storage: Array = inv.get(PetManager.KEY_STORAGE, [])
		if idx >= 0 and idx < storage.size():
			return storage[idx]
		return {}
	return inv.get(slot_key, {})


func _clear_display() -> void:
	if is_instance_valid(icon_rect):
		icon_rect.texture = null
		icon_rect.visible = false
	if is_instance_valid(count_label):
		count_label.visible = false
	if is_instance_valid(slot_label):
		slot_label.visible = true


# ── Drag-drop (drops from main-inventory Slot) ───────────────────────────

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Slot):
		return false
	var s: Slot = data
	if not s.drag_item:
		return false
	if require_consumable and not (s.drag_item is ConsumableData):
		return false
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not (data is Slot):
		return
	var source_slot: Slot = data
	if not source_slot.drag_item:
		return
	if not (source_slot.item_container is InventoryComponent):
		source_slot.cancel_drag()
		return
	var source_inv: InventoryComponent = source_slot.item_container
	var idx := -1
	for i in source_inv.slots_data.size():
		if source_inv.slots_data[i] == source_slot.slot_data:
			idx = i
			break
	if idx == -1:
		source_slot.cancel_drag()
		return
	PetManager.request_transfer_to_pet_slot_server.rpc_id(1, pet_uuid, slot_key, idx)
	source_slot.cancel_drag()


# ── Click-to-remove (returns the held item to main inventory) ────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if pet_uuid.is_empty():
			return
		PetManager.request_transfer_from_pet_slot_server.rpc_id(1, pet_uuid, slot_key)
