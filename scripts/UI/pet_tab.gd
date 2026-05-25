class_name PetTab
extends MarginContainer

## Pet management UI controller.
##
## The UI structure lives in pet_tab.tscn — tweak layout/colors/sizes there.
## This script binds data into the exported nodes and handles the signal
## callbacks (wired by editor connections, see pet_tab.tscn `[connection]`s).
##
## The 5 pet-inventory slots inside InventoryGrid are still instantiated here
## because their count/config is data-driven (PetManager constants).

@export var pet_list: ItemList
@export var detail_container: VBoxContainer
@export var empty_state_label: Label
@export var portrait: TextureRect
@export var name_edit: LineEdit
@export var hunger_bar: ProgressBar
@export var feed_button: Button
@export var summon_button: Button
@export var release_button: Button
@export var inventory_grid: HBoxContainer
@export var hp_threshold_slider: HSlider
@export var mp_threshold_slider: HSlider
@export var buff_dropdown: OptionButton
@export var learned_commands_label: Label
@export var confirm_dialog: ConfirmationDialog

const PET_SLOT_SCENE: PackedScene = preload("res://scenes/UI/pet_slot.tscn")

var player: MultiplayerPlayerV2 = null

# Runtime-built widget cache for the 5 inventory slots.
var _pet_slot_widgets: Array = []

var _selected_pet_uuid: String = ""


func _ready() -> void:
	_build_inventory_slots()
	_connect_pet_manager_signals()
	# Make sure "(none)" is in the buff dropdown until populated.
	if is_instance_valid(buff_dropdown) and buff_dropdown.item_count == 0:
		buff_dropdown.add_item("(none)")
	_refresh()


func set_owner_player(p: MultiplayerPlayerV2) -> void:
	player = p


# ═══════════════════════════════════════════════════════════════════════════
# DATA-DRIVEN INVENTORY SLOT BUILDOUT
# ═══════════════════════════════════════════════════════════════════════════

func _build_inventory_slots() -> void:
	if not is_instance_valid(inventory_grid):
		return
	# Clear any previous instances (handles hot-reload / re-entry).
	for child in inventory_grid.get_children():
		child.queue_free()
	_pet_slot_widgets.clear()

	var slot_configs := [
		{"key": PetManager.KEY_AUTOPOT_HP, "label": "HP", "kind": "pot"},
		{"key": PetManager.KEY_AUTOPOT_MP, "label": "MP", "kind": "pot"},
		{"key": PetManager.KEY_CMD_AUTO_POT, "label": "AutoPot", "kind": "book"},
		{"key": PetManager.KEY_CMD_BUFF, "label": "Buff", "kind": "book"},
		{"key": PetManager.KEY_CMD_MAGNET, "label": "Magnet", "kind": "book"},
	]
	for cfg in slot_configs:
		var slot: PetSlot = PET_SLOT_SCENE.instantiate()
		inventory_grid.add_child(slot)
		_pet_slot_widgets.append({
			"node": slot,
			"key": cfg.key,
			"label": cfg.label,
			"kind": cfg.kind,
		})


# ═══════════════════════════════════════════════════════════════════════════
# SIGNAL WIRING (PetManager → UI)
# ═══════════════════════════════════════════════════════════════════════════

func _connect_pet_manager_signals() -> void:
	if not PetManager:
		return
	if not PetManager.client_roster_updated.is_connected(_on_roster_updated):
		PetManager.client_roster_updated.connect(_on_roster_updated)
	if not PetManager.pet_hatched.is_connected(_on_pet_hatched):
		PetManager.pet_hatched.connect(_on_pet_hatched)


func _on_roster_updated() -> void:
	_refresh()


func _on_pet_hatched(pet_uuid: String, _pet_name: String, _pet_data_id: String) -> void:
	# Open this tab and select the new pet so the player can rename it.
	_selected_pet_uuid = pet_uuid
	_refresh()
	var equipment_window := _find_equipment_window()
	if equipment_window:
		equipment_window.visible = true
		if equipment_window.has_method("_show_pet_tab"):
			equipment_window._show_pet_tab()
	if is_instance_valid(name_edit):
		name_edit.grab_focus.call_deferred()
		name_edit.select_all.call_deferred()


func _find_equipment_window() -> Node:
	var parent: Node = self
	while is_instance_valid(parent):
		if parent is EquipmentWindow:
			return parent
		parent = parent.get_parent()
	return null


# ═══════════════════════════════════════════════════════════════════════════
# REFRESH (data -> UI)
# ═══════════════════════════════════════════════════════════════════════════

func _refresh() -> void:
	if not PetManager or not is_instance_valid(pet_list):
		return
	var roster := PetManager.client_get_roster()
	pet_list.clear()
	for pet in roster:
		var name_text: String = pet.get(PetManager.KEY_NAME, "Pet")
		if PetManager.client_is_pet_summoned(pet.get(PetManager.KEY_ID, "")):
			name_text += " *"
		pet_list.add_item(name_text)

	if roster.is_empty():
		_set_detail_visible(false)
		return

	var idx := -1
	for i in roster.size():
		if roster[i].get(PetManager.KEY_ID, "") == _selected_pet_uuid:
			idx = i
			break
	if idx == -1:
		idx = 0
		_selected_pet_uuid = roster[0].get(PetManager.KEY_ID, "")
	pet_list.select(idx)
	_set_detail_visible(true)
	_refresh_detail()


func _set_detail_visible(detail_visible: bool) -> void:
	if is_instance_valid(empty_state_label):
		empty_state_label.visible = not detail_visible
	if not is_instance_valid(detail_container):
		return
	for child in detail_container.get_children():
		if child == empty_state_label:
			continue
		(child as Control).visible = detail_visible


func _refresh_detail() -> void:
	var record := PetManager.client_find_pet(_selected_pet_uuid)
	if record.is_empty():
		return

	# Portrait.
	var pet_data: PetData = null
	if PetManager:
		pet_data = PetManager.get_pet_data(record.get(PetManager.KEY_PET_DATA_ID, ""))
	if is_instance_valid(portrait):
		portrait.texture = pet_data.icon if pet_data else null

	# Name (don't overwrite while the user is typing).
	if is_instance_valid(name_edit) and not name_edit.has_focus():
		name_edit.text = record.get(PetManager.KEY_NAME, "")

	# Hunger.
	var hunger: float = record.get(PetManager.KEY_HUNGER, 100.0)
	var max_h := pet_data.max_hunger if pet_data else 100.0
	if is_instance_valid(hunger_bar):
		hunger_bar.max_value = max_h
		hunger_bar.value = hunger

	# Summon button.
	var is_summoned := PetManager.client_is_pet_summoned(_selected_pet_uuid)
	if is_instance_valid(summon_button):
		summon_button.text = "Unsummon" if is_summoned else "Summon"

	# Feed button.
	if is_instance_valid(feed_button):
		feed_button.disabled = not is_summoned or _find_first_pet_food_slot() == -1
		if not is_summoned:
			feed_button.tooltip_text = "Summon the pet first."
		elif feed_button.disabled:
			feed_button.tooltip_text = "No Pet Food in inventory."
		else:
			feed_button.tooltip_text = "Feed your pet a Pet Food item."

	# Autopot thresholds.
	var ap_cfg: Dictionary = record.get(PetManager.KEY_AUTOPOT_CONFIG, {})
	if is_instance_valid(hp_threshold_slider):
		hp_threshold_slider.value = ap_cfg.get(PetManager.KEY_HP_THRESHOLD, 0.5)
	if is_instance_valid(mp_threshold_slider):
		mp_threshold_slider.value = ap_cfg.get(PetManager.KEY_MP_THRESHOLD, 0.5)

	# Active commands (derived from which books are in command slots).
	if is_instance_valid(learned_commands_label):
		var active: Array = PetManager.get_active_commands(record)
		if active.is_empty():
			learned_commands_label.text = "Commands: (none — equip command books in the slots)"
		else:
			learned_commands_label.text = "Commands: " + ", ".join(active)

	# Pet inventory slots.
	for entry in _pet_slot_widgets:
		var slot_node: PetSlot = entry.node
		slot_node.setup(_selected_pet_uuid, entry.key, entry.label, entry.kind)

	# Active buff dropdown.
	_rebuild_buff_dropdown(record)


# ═══════════════════════════════════════════════════════════════════════════
# BUFF DROPDOWN
# ═══════════════════════════════════════════════════════════════════════════

func _rebuild_buff_dropdown(record: Dictionary) -> void:
	if not is_instance_valid(buff_dropdown):
		return
	buff_dropdown.set_block_signals(true)
	buff_dropdown.clear()
	buff_dropdown.add_item("(none)")
	buff_dropdown.set_item_metadata(0, "")

	var eligible := _get_eligible_buff_abilities()
	for i in eligible.size():
		var ability: AbilityData = eligible[i]
		buff_dropdown.add_item(ability.ability_name)
		buff_dropdown.set_item_metadata(i + 1, ability.ability_id)

	var current_id: String = record.get(PetManager.KEY_ACTIVE_BUFF, "")
	var selected_idx := 0
	for i in buff_dropdown.item_count:
		if str(buff_dropdown.get_item_metadata(i)) == current_id:
			selected_idx = i
			break
	buff_dropdown.select(selected_idx)

	var has_buff_cmd: bool = PetManager.is_command_active(record, PetManager.CMD_AUTOBUFF)
	buff_dropdown.disabled = not has_buff_cmd
	if buff_dropdown.disabled:
		buff_dropdown.tooltip_text = "Equip a Pet Buff Command book in the Buff slot."
	else:
		buff_dropdown.tooltip_text = "Pet will cast this buff on you periodically."
	buff_dropdown.set_block_signals(false)


func _get_eligible_buff_abilities() -> Array:
	var result: Array = []
	if not is_instance_valid(player) or not is_instance_valid(player.ability_component):
		return result
	var levels: Dictionary = player.ability_component._ability_levels
	for ability_id in levels.keys():
		var level: int = int(levels[ability_id])
		if level <= 0:
			continue
		var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
		if not ability or not ability.applies_buff:
			continue
		if not ability.active_behavior or ability.active_behavior.target_type != Constants.TargetType.SELF:
			continue
		result.append(ability)
	return result


# ═══════════════════════════════════════════════════════════════════════════
# UI EVENT CALLBACKS (wired in pet_tab.tscn [connection]s)
# ═══════════════════════════════════════════════════════════════════════════

func _on_pet_list_selected(idx: int) -> void:
	var roster := PetManager.client_get_roster()
	if idx < 0 or idx >= roster.size():
		return
	_selected_pet_uuid = roster[idx].get(PetManager.KEY_ID, "")
	_refresh_detail()


func _on_summon_pressed() -> void:
	if _selected_pet_uuid.is_empty():
		return
	if PetManager.client_is_pet_summoned(_selected_pet_uuid):
		PetManager.request_unsummon_pet_server.rpc_id(1, _selected_pet_uuid)
	else:
		PetManager.request_summon_pet_server.rpc_id(1, _selected_pet_uuid)


func _on_release_pressed() -> void:
	if _selected_pet_uuid.is_empty():
		return
	var record := PetManager.client_find_pet(_selected_pet_uuid)
	if record.is_empty():
		return
	if not is_instance_valid(confirm_dialog):
		return
	confirm_dialog.dialog_text = "Permanently release %s?" % record.get(PetManager.KEY_NAME, "this pet")
	confirm_dialog.popup_centered()


func _on_release_confirmed() -> void:
	if _selected_pet_uuid.is_empty():
		return
	PetManager.request_release_pet_server.rpc_id(1, _selected_pet_uuid)
	_selected_pet_uuid = ""


func _on_name_submitted(new_text: String) -> void:
	_commit_rename(new_text)
	if is_instance_valid(name_edit):
		name_edit.release_focus()


func _on_name_focus_exited() -> void:
	if is_instance_valid(name_edit):
		_commit_rename(name_edit.text)


func _commit_rename(new_text: String) -> void:
	if _selected_pet_uuid.is_empty() or not is_instance_valid(name_edit):
		return
	var trimmed := new_text.strip_edges()
	if trimmed.is_empty():
		var record := PetManager.client_find_pet(_selected_pet_uuid)
		name_edit.text = record.get(PetManager.KEY_NAME, "") if not record.is_empty() else ""
		return
	var current := PetManager.client_find_pet(_selected_pet_uuid)
	if current.get(PetManager.KEY_NAME, "") == trimmed:
		return
	PetManager.request_rename_pet_server.rpc_id(1, _selected_pet_uuid, trimmed)


func _on_feed_pressed() -> void:
	if _selected_pet_uuid.is_empty():
		return
	var slot_idx := _find_first_pet_food_slot()
	if slot_idx == -1:
		return
	PetManager.request_feed_pet_server.rpc_id(1, _selected_pet_uuid, slot_idx)


func _on_buff_dropdown_selected(idx: int) -> void:
	if _selected_pet_uuid.is_empty() or not is_instance_valid(buff_dropdown):
		return
	var ability_id: String = str(buff_dropdown.get_item_metadata(idx))
	PetManager.request_set_active_buff_ability_server.rpc_id(1, _selected_pet_uuid, ability_id)


func _on_hp_threshold_drag_ended(_value_changed: bool) -> void:
	if _selected_pet_uuid.is_empty() or not is_instance_valid(hp_threshold_slider):
		return
	PetManager.request_set_autopot_threshold_server.rpc_id(1, _selected_pet_uuid, "hp", hp_threshold_slider.value)


func _on_mp_threshold_drag_ended(_value_changed: bool) -> void:
	if _selected_pet_uuid.is_empty() or not is_instance_valid(mp_threshold_slider):
		return
	PetManager.request_set_autopot_threshold_server.rpc_id(1, _selected_pet_uuid, "mp", mp_threshold_slider.value)


## Returns the index of the first inventory slot holding PetFoodData, or -1.
func _find_first_pet_food_slot() -> int:
	if not is_instance_valid(player) or not is_instance_valid(player.inventory_component):
		return -1
	var slots := player.inventory_component.slots_data
	for i in slots.size():
		var sd = slots[i]
		if sd and sd.item and sd.item is PetFoodData:
			return i
	return -1
