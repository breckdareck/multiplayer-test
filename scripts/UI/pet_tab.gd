class_name PetTab
extends MarginContainer

## Pet management UI controller.
##
## The full layout — including the 6 pet-inventory slots under PotsGrid and
## CommandsGrid — lives in pet_tab.tscn. This script binds data into the
## exported nodes, configures each slot's key/kind, and handles the signal
## callbacks wired by the scene.

@export var pet_list: ItemList
@export var detail_container: VBoxContainer
@export var empty_state_label: Label
@export var portrait: TextureRect
@export var name_edit: LineEdit
@export var summon_button: Button
@export var release_button: Button
@export var hunger_bar: ProgressBar
@export var feed_button: Button
@export var pots_grid: HBoxContainer       # HP / MP / Active-Buff slots
@export var commands_grid: HBoxContainer   # AutoPot / Buff Cmd / Magnet slots
@export var hp_threshold_slider: HSlider
@export var hp_threshold_value_label: Label
@export var mp_threshold_slider: HSlider
@export var mp_threshold_value_label: Label
@export var confirm_dialog: ConfirmationDialog

# Pet inventory slots — pre-instanced in pet_tab.tscn under PotsGrid / CommandsGrid.
@export var slot_autopot_hp: PetSlot
@export var slot_autopot_mp: PetSlot
@export var slot_ability_buff: PetSlot
@export var slot_cmd_auto_pot: PetSlot
@export var slot_cmd_buff: PetSlot
@export var slot_cmd_magnet: PetSlot

var player: MultiplayerPlayerV2 = null

# Slot config cache. Each entry: { node, key, label, kind }.
var _pet_slot_widgets: Array = []

var _selected_pet_uuid: String = ""


func _ready() -> void:
	_init_inventory_slots()
	_connect_pet_manager_signals()
	_refresh()


func set_owner_player(p: MultiplayerPlayerV2) -> void:
	player = p


# ═══════════════════════════════════════════════════════════════════════════
# SLOT BUILDOUT (slot nodes live in pet_tab.tscn; this assigns key/kind/label)
# ═══════════════════════════════════════════════════════════════════════════

func _init_inventory_slots() -> void:
	_pet_slot_widgets.clear()
	# Row 1: triggers — HP pot, MP pot, the active buff ability.
	# Row 2: enabler books — AutoPot, Buff Command, Magnet.
	var configs := [
		{"node": slot_autopot_hp, "key": PetManager.KEY_AUTOPOT_HP, "label": "HP", "kind": "pot"},
		{"node": slot_autopot_mp, "key": PetManager.KEY_AUTOPOT_MP, "label": "MP", "kind": "pot"},
		{"node": slot_ability_buff, "key": "", "label": "Buff", "kind": "ability_buff"},
		{"node": slot_cmd_auto_pot, "key": PetManager.KEY_CMD_AUTO_POT, "label": "Auto Pot", "kind": "book"},
		{"node": slot_cmd_buff, "key": PetManager.KEY_CMD_BUFF, "label": "Buff Cmd", "kind": "book"},
		{"node": slot_cmd_magnet, "key": PetManager.KEY_CMD_MAGNET, "label": "Magnet", "kind": "book"},
	]
	for cfg in configs:
		if not is_instance_valid(cfg.node):
			continue
		# Set kind/key immediately so the slot's drop filter works even
		# before a pet is selected. pet_uuid stays empty until _refresh_detail
		# runs with a selected pet, at which point setup is called again.
		cfg.node.setup("", cfg.key, cfg.label, cfg.kind)
		_pet_slot_widgets.append(cfg)


# ═══════════════════════════════════════════════════════════════════════════
# PetManager → UI WIRING
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
	_selected_pet_uuid = pet_uuid
	_refresh()


# ═══════════════════════════════════════════════════════════════════════════
# REFRESH
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

	# Name.
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

	# Feed button is ALWAYS pressable — feeding works summoned or not, and the
	# food check is deferred to press time (see _on_feed_pressed). Gating
	# `disabled` on _find_first_pet_food_slot() here was fragile on the client:
	# this refresh can run before the player ref / inventory finish wiring (the
	# child's _ready beats the parent's set_owner_player, and inventory can lag
	# the roster sync at login), which left the button stuck disabled until an
	# unsummon/resummon.
	if is_instance_valid(feed_button):
		feed_button.disabled = false
		feed_button.tooltip_text = "Feed your pet a Pet Food item."

	# Autopot thresholds.
	var ap_cfg: Dictionary = record.get(PetManager.KEY_AUTOPOT_CONFIG, {})
	var hp_t: float = ap_cfg.get(PetManager.KEY_HP_THRESHOLD, 0.5)
	var mp_t: float = ap_cfg.get(PetManager.KEY_MP_THRESHOLD, 0.5)
	if is_instance_valid(hp_threshold_slider):
		hp_threshold_slider.set_value_no_signal(hp_t)
	if is_instance_valid(mp_threshold_slider):
		mp_threshold_slider.set_value_no_signal(mp_t)
	_update_threshold_label(hp_threshold_value_label, hp_t)
	_update_threshold_label(mp_threshold_value_label, mp_t)

	# Pet inventory slots.
	for entry in _pet_slot_widgets:
		var slot_node: PetSlot = entry.node
		slot_node.setup(_selected_pet_uuid, entry.key, entry.label, entry.kind)


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
		if LogManager:
			LogManager.add_scrolling_log("No Pet Food in inventory.", Color(1.0, 0.85, 0.3))
		return
	PetManager.request_feed_pet_server.rpc_id(1, _selected_pet_uuid, slot_idx)


# ── Threshold sliders ─────────────────────────────────────────────────────

func _on_hp_threshold_value_changed(value: float) -> void:
	_update_threshold_label(hp_threshold_value_label, value)


func _on_mp_threshold_value_changed(value: float) -> void:
	_update_threshold_label(mp_threshold_value_label, value)


func _on_hp_threshold_drag_ended(_value_changed: bool) -> void:
	if _selected_pet_uuid.is_empty() or not is_instance_valid(hp_threshold_slider):
		return
	PetManager.request_set_autopot_threshold_server.rpc_id(1, _selected_pet_uuid, "hp", hp_threshold_slider.value)


func _on_mp_threshold_drag_ended(_value_changed: bool) -> void:
	if _selected_pet_uuid.is_empty() or not is_instance_valid(mp_threshold_slider):
		return
	PetManager.request_set_autopot_threshold_server.rpc_id(1, _selected_pet_uuid, "mp", mp_threshold_slider.value)


static func _update_threshold_label(label: Label, value: float) -> void:
	if not is_instance_valid(label):
		return
	label.text = "%d%%" % roundi(value * 100.0)


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
