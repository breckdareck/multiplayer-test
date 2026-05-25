class_name PetSlot
extends PanelContainer

## A pet inventory slot. Three kinds:
##
##   "pot"          — accepts non-pet ConsumableData (HP/MP potions).
##   "book"         — accepts only the PetSkillBookData matching this slot's command.
##   "ability_buff" — accepts an AbilityData (drag from the ability window) that
##                    is self-target + applies a buff. Stored separately from
##                    pet_inventory (in record.active_buff_ability_id).
##
## Owns no game state itself — reads from PetManager whenever asked to refresh.

@export var slot_label: Label
@export var icon_rect: TextureRect
@export var count_label: Label

var pet_uuid: String = ""
## PetManager.KEY_AUTOPOT_HP / KEY_AUTOPOT_MP / KEY_CMD_AUTO_POT / KEY_CMD_BUFF
## / KEY_CMD_MAGNET. For ability_buff kind this is unused (data lives on the
## record directly).
var slot_key: String = ""
## "pot" / "book" / "ability_buff".
var slot_kind: String = "pot"


func setup(pet_uuid_in: String, slot_key_in: String, label_text: String, kind: String) -> void:
	pet_uuid = pet_uuid_in
	slot_key = slot_key_in
	slot_kind = kind
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

	if slot_kind == "ability_buff":
		_refresh_ability_buff(record)
		return
	_refresh_item_slot(record)


func _refresh_item_slot(record: Dictionary) -> void:
	var inv: Dictionary = record.get(PetManager.KEY_INVENTORY, {})
	var slot_data := inv.get(slot_key, {}) as Dictionary
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


func _refresh_ability_buff(record: Dictionary) -> void:
	var ability_id: String = record.get(PetManager.KEY_ACTIVE_BUFF, "")
	if ability_id.is_empty():
		_clear_display()
		return
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability:
		_clear_display()
		return
	if is_instance_valid(icon_rect):
		icon_rect.texture = ability.ability_icon
		icon_rect.visible = ability.ability_icon != null
	if is_instance_valid(count_label):
		count_label.visible = false
	if is_instance_valid(slot_label):
		slot_label.visible = ability.ability_icon == null


func _clear_display() -> void:
	if is_instance_valid(icon_rect):
		icon_rect.texture = null
		icon_rect.visible = false
	if is_instance_valid(count_label):
		count_label.visible = false
	if is_instance_valid(slot_label):
		slot_label.visible = true


# ── Drag-drop ────────────────────────────────────────────────────────────

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if slot_kind == "ability_buff":
		return _is_buff_ability_drag(data)
	if not (data is Slot):
		return false
	var s: Slot = data
	if not s.drag_item:
		return false
	if slot_kind == "pot":
		if not (s.drag_item is ConsumableData):
			return false
		if s.drag_item is PetSkillBookData or s.drag_item is PetFoodData:
			return false
		return true
	if slot_kind == "book":
		if not (s.drag_item is PetSkillBookData):
			print("[PetSlot] reject: kind=book but drag_item is not PetSkillBookData (got %s)" % s.drag_item.get_class())
			return false
		var expected := PetManager.book_id_for_slot(slot_key)
		var accept: bool = s.drag_item.item_id == expected
		if not accept:
			print("[PetSlot] reject: kind=book slot_key=%s expected=%s got_id=%s" % [slot_key, expected, s.drag_item.item_id])
		return accept
	print("[PetSlot] reject: unknown slot_kind=%s for slot_key=%s" % [slot_kind, slot_key])
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if slot_kind == "ability_buff":
		if not _is_buff_ability_drag(data):
			return
		var ability: AbilityData = data.get("ability_data")
		PetManager.request_set_active_buff_ability_server.rpc_id(1, pet_uuid, ability.ability_id)
		return

	if not (data is Slot):
		return
	var source_slot: Slot = data
	if not source_slot.drag_item:
		return
	if not (source_slot.item_container is InventoryComponent):
		source_slot.cancel_drag()
		return
	var source_inv: InventoryComponent = source_slot.item_container
	# Find the slot's index via the Slot node array — works even when the
	# slot is in legacy mode (slot_data == null), unlike slots_data.find().
	var idx: int = source_inv.slots.find(source_slot)
	if idx == -1:
		push_warning("PetSlot: drop source slot not found in inventory.slots")
		source_slot.cancel_drag()
		return
	if pet_uuid.is_empty():
		print("[PetSlot] drop accepted client-side but pet_uuid is empty — server will reject. Select a pet first.")
	print("[PetSlot] sending transfer RPC: pet=%s slot=%s inv_idx=%d item=%s" % [pet_uuid, slot_key, idx, source_slot.drag_item.item_id])
	PetManager.request_transfer_to_pet_slot_server.rpc_id(1, pet_uuid, slot_key, idx)
	source_slot.cancel_drag()


## Right-click clears the slot.
##   - Item slots return the held stack to main inventory.
##   - Ability-buff slot clears active_buff_ability_id.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_RIGHT or not event.pressed:
		return
	if pet_uuid.is_empty():
		return
	if slot_kind == "ability_buff":
		PetManager.request_set_active_buff_ability_server.rpc_id(1, pet_uuid, "")
		return
	PetManager.request_transfer_from_pet_slot_server.rpc_id(1, pet_uuid, slot_key)


# ── Helpers ──────────────────────────────────────────────────────────────

## Ability drags from AbilitySlot are Dictionaries: {"ability_data": AbilityData}.
## A valid buff drop must be a self-target ability that applies a BuffData.
static func _is_buff_ability_drag(data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var ability_data = data.get("ability_data")
	if not (ability_data is AbilityData):
		return false
	if not ability_data.applies_buff:
		return false
	if not ability_data.active_behavior:
		return false
	return ability_data.active_behavior.target_type == Constants.TargetType.SELF
