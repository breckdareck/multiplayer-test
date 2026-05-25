class_name PetTab
extends MarginContainer

## Pet management UI — Phase 3. Pet list on the left, detail on the right.
## Builds the UI programmatically to keep the .tscn footprint small.
##
## Functional in Phase 3: list pets, summon/unsummon, release (with confirm),
## rename. Inventory slots, autopot threshold sliders, and the buff dropdown
## are placeholder controls — they wire to RPCs in Phases 5-7.

var player: MultiplayerPlayerV2 = null

# Built nodes
var _pet_list: ItemList
var _detail_container: VBoxContainer
var _portrait: TextureRect
var _name_edit: LineEdit
var _hunger_bar: ProgressBar
var _feed_button: Button
var _summon_button: Button
var _release_button: Button
var _inventory_grid: HBoxContainer
var _pet_slot_widgets: Array = []  # PetSlot instances
var _hp_threshold_slider: HSlider
var _mp_threshold_slider: HSlider
var _buff_dropdown: OptionButton
var _learned_commands_label: Label
var _empty_state_label: Label

const PET_SLOT_SCENE: PackedScene = preload("res://scenes/UI/pet_slot.tscn")

var _selected_pet_uuid: String = ""
var _confirm_dialog: ConfirmationDialog


func _ready() -> void:
	_build_ui()
	_connect_pet_manager_signals()
	_refresh()


func set_owner_player(p: MultiplayerPlayerV2) -> void:
	player = p


# ═══════════════════════════════════════════════════════════════════════════
# UI CONSTRUCTION
# ═══════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	var root_hbox := HBoxContainer.new()
	root_hbox.add_theme_constant_override("separation", 8)
	root_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root_hbox)

	# ── Pet list (left) ──────────────────────────────────────────────
	var list_panel := PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(110, 0)
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_hbox.add_child(list_panel)

	var list_vbox := VBoxContainer.new()
	list_panel.add_child(list_vbox)

	var list_header := Label.new()
	list_header.text = "MY PETS"
	list_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_vbox.add_child(list_header)

	_pet_list = ItemList.new()
	_pet_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pet_list.allow_reselect = true
	_pet_list.item_selected.connect(_on_pet_list_selected)
	list_vbox.add_child(_pet_list)

	# ── Detail (right) ───────────────────────────────────────────────
	_detail_container = VBoxContainer.new()
	_detail_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_container.add_theme_constant_override("separation", 6)
	root_hbox.add_child(_detail_container)

	_empty_state_label = Label.new()
	_empty_state_label.text = "No pets yet.\nUse a Pet Egg to hatch one!"
	_empty_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_state_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_container.add_child(_empty_state_label)

	# Portrait + name row
	var portrait_row := HBoxContainer.new()
	portrait_row.add_theme_constant_override("separation", 8)
	_detail_container.add_child(portrait_row)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(48, 48)
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_row.add_child(_portrait)

	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_row.add_child(name_box)

	var name_label := Label.new()
	name_label.text = "Name:"
	name_box.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.max_length = 20
	_name_edit.placeholder_text = "Pet name"
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(_on_name_focus_exited)
	name_box.add_child(_name_edit)

	# Hunger row
	var hunger_row := HBoxContainer.new()
	_detail_container.add_child(hunger_row)

	var hunger_label := Label.new()
	hunger_label.text = "Hunger:"
	hunger_label.custom_minimum_size = Vector2(60, 0)
	hunger_row.add_child(hunger_label)

	_hunger_bar = ProgressBar.new()
	_hunger_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hunger_bar.min_value = 0.0
	_hunger_bar.max_value = 100.0
	_hunger_bar.value = 100.0
	hunger_row.add_child(_hunger_bar)

	_feed_button = Button.new()
	_feed_button.text = "Feed"
	_feed_button.pressed.connect(_on_feed_pressed)
	hunger_row.add_child(_feed_button)

	# Action buttons
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 4)
	_detail_container.add_child(button_row)

	_summon_button = Button.new()
	_summon_button.text = "Summon"
	_summon_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summon_button.pressed.connect(_on_summon_pressed)
	button_row.add_child(_summon_button)

	_release_button = Button.new()
	_release_button.text = "Release"
	_release_button.pressed.connect(_on_release_pressed)
	button_row.add_child(_release_button)

	# Inventory slots (visual only in Phase 3 — drag-drop wires up Phases 5+)
	var inv_label := Label.new()
	inv_label.text = "Pet Inventory"
	_detail_container.add_child(inv_label)

	_inventory_grid = HBoxContainer.new()
	_inventory_grid.add_theme_constant_override("separation", 4)
	_detail_container.add_child(_inventory_grid)
	_build_placeholder_inventory_slots()

	# Auto-pot thresholds (sliders are placeholder for Phase 6)
	var hp_row := HBoxContainer.new()
	_detail_container.add_child(hp_row)
	var hp_label := Label.new()
	hp_label.text = "HP %:"
	hp_label.custom_minimum_size = Vector2(60, 0)
	hp_row.add_child(hp_label)
	_hp_threshold_slider = HSlider.new()
	_hp_threshold_slider.min_value = 0.0
	_hp_threshold_slider.max_value = 1.0
	_hp_threshold_slider.step = 0.05
	_hp_threshold_slider.value = 0.5
	_hp_threshold_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_threshold_slider.drag_ended.connect(_on_hp_threshold_drag_ended)
	hp_row.add_child(_hp_threshold_slider)

	var mp_row := HBoxContainer.new()
	_detail_container.add_child(mp_row)
	var mp_label := Label.new()
	mp_label.text = "MP %:"
	mp_label.custom_minimum_size = Vector2(60, 0)
	mp_row.add_child(mp_label)
	_mp_threshold_slider = HSlider.new()
	_mp_threshold_slider.min_value = 0.0
	_mp_threshold_slider.max_value = 1.0
	_mp_threshold_slider.step = 0.05
	_mp_threshold_slider.value = 0.5
	_mp_threshold_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mp_threshold_slider.drag_ended.connect(_on_mp_threshold_drag_ended)
	mp_row.add_child(_mp_threshold_slider)

	# Active buff slot (dropdown wires up Phase 7)
	var buff_label := Label.new()
	buff_label.text = "Active Buff:"
	_detail_container.add_child(buff_label)
	_buff_dropdown = OptionButton.new()
	_buff_dropdown.add_item("(none)")
	_buff_dropdown.disabled = true
	_detail_container.add_child(_buff_dropdown)

	# Learned commands status
	_learned_commands_label = Label.new()
	_learned_commands_label.text = "Commands: —"
	_learned_commands_label.add_theme_font_size_override("font_size", 11)
	_detail_container.add_child(_learned_commands_label)

	# Confirmation dialog (for Release)
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.dialog_text = "Are you sure?"
	_confirm_dialog.confirmed.connect(_on_release_confirmed)
	add_child(_confirm_dialog)


func _build_placeholder_inventory_slots() -> void:
	# 2 autopot slots + 3 generic storage slots — all real PetSlot widgets.
	var slot_configs := [
		{"key": PetManager.KEY_AUTOPOT_HP, "label": "HP", "require_consumable": true},
		{"key": PetManager.KEY_AUTOPOT_MP, "label": "MP", "require_consumable": true},
		{"key": "storage_0", "label": "1", "require_consumable": false},
		{"key": "storage_1", "label": "2", "require_consumable": false},
		{"key": "storage_2", "label": "3", "require_consumable": false},
	]
	for cfg in slot_configs:
		var slot: PetSlot = PET_SLOT_SCENE.instantiate()
		_inventory_grid.add_child(slot)
		_pet_slot_widgets.append({
			"node": slot,
			"key": cfg.key,
			"label": cfg.label,
			"require": cfg.require_consumable,
		})


# ═══════════════════════════════════════════════════════════════════════════
# SIGNAL WIRING
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
	# Try to open the equipment window if it's closed.
	var equipment_window := _find_equipment_window()
	if equipment_window:
		equipment_window.visible = true
		if equipment_window.has_method("_show_pet_tab"):
			equipment_window._show_pet_tab()
	# Focus name field so the player can rename immediately.
	if is_instance_valid(_name_edit):
		_name_edit.grab_focus.call_deferred()
		_name_edit.select_all.call_deferred()


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
	if not PetManager:
		return
	var roster := PetManager.client_get_roster()
	_pet_list.clear()
	for pet in roster:
		var name_text: String = pet.get(PetManager.KEY_NAME, "Pet")
		if PetManager.client_is_pet_summoned(pet.get(PetManager.KEY_ID, "")):
			name_text += " *"
		_pet_list.add_item(name_text)

	if roster.is_empty():
		_set_detail_visible(false)
		return

	# Re-select previously selected pet (or first if it's gone).
	var idx := -1
	for i in roster.size():
		if roster[i].get(PetManager.KEY_ID, "") == _selected_pet_uuid:
			idx = i
			break
	if idx == -1:
		idx = 0
		_selected_pet_uuid = roster[0].get(PetManager.KEY_ID, "")
	_pet_list.select(idx)
	_set_detail_visible(true)
	_refresh_detail()


func _set_detail_visible(detail_visible: bool) -> void:
	# Show either the empty-state label or the detail controls.
	if is_instance_valid(_empty_state_label):
		_empty_state_label.visible = not detail_visible
	for child in _detail_container.get_children():
		if child == _empty_state_label:
			continue
		(child as Control).visible = detail_visible


func _refresh_detail() -> void:
	var record := PetManager.client_find_pet(_selected_pet_uuid)
	if record.is_empty():
		return

	# Portrait — use the PetData icon if defined, fall back to nothing.
	var pet_data: PetData = null
	if PetManager:
		pet_data = PetManager.get_pet_data(record.get(PetManager.KEY_PET_DATA_ID, ""))
	_portrait.texture = pet_data.icon if pet_data else null

	# Name (only refresh if the field isn't being edited).
	if not _name_edit.has_focus():
		_name_edit.text = record.get(PetManager.KEY_NAME, "")

	# Hunger
	var hunger: float = record.get(PetManager.KEY_HUNGER, 100.0)
	var max_h := pet_data.max_hunger if pet_data else 100.0
	_hunger_bar.max_value = max_h
	_hunger_bar.value = hunger

	# Summon button
	var is_summoned := PetManager.client_is_pet_summoned(_selected_pet_uuid)
	_summon_button.text = "Unsummon" if is_summoned else "Summon"

	# Feed button — disabled when pet not summoned (MapleStory parity) or no food.
	_feed_button.disabled = not is_summoned or _find_first_pet_food_slot() == -1
	if not is_summoned:
		_feed_button.tooltip_text = "Summon the pet first."
	elif _feed_button.disabled:
		_feed_button.tooltip_text = "No Pet Food in inventory."
	else:
		_feed_button.tooltip_text = "Feed your pet a Pet Food item."

	# Autopot thresholds
	var ap_cfg: Dictionary = record.get(PetManager.KEY_AUTOPOT_CONFIG, {})
	_hp_threshold_slider.value = ap_cfg.get(PetManager.KEY_HP_THRESHOLD, 0.5)
	_mp_threshold_slider.value = ap_cfg.get(PetManager.KEY_MP_THRESHOLD, 0.5)

	# Learned commands
	var learned: Array = record.get(PetManager.KEY_LEARNED, [])
	if learned.is_empty():
		_learned_commands_label.text = "Commands: (none — find skill books!)"
	else:
		_learned_commands_label.text = "Commands: " + ", ".join(learned)

	# Pet inventory slots
	for entry in _pet_slot_widgets:
		var slot_node: PetSlot = entry.node
		slot_node.setup(_selected_pet_uuid, entry.key, entry.label, entry.require)


# ═══════════════════════════════════════════════════════════════════════════
# UI EVENT HANDLERS
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


func _on_feed_pressed() -> void:
	if _selected_pet_uuid.is_empty():
		return
	var slot_idx := _find_first_pet_food_slot()
	if slot_idx == -1:
		return
	PetManager.request_feed_pet_server.rpc_id(1, _selected_pet_uuid, slot_idx)


func _on_hp_threshold_drag_ended(_value_changed: bool) -> void:
	if _selected_pet_uuid.is_empty():
		return
	PetManager.request_set_autopot_threshold_server.rpc_id(1, _selected_pet_uuid, "hp", _hp_threshold_slider.value)


func _on_mp_threshold_drag_ended(_value_changed: bool) -> void:
	if _selected_pet_uuid.is_empty():
		return
	PetManager.request_set_autopot_threshold_server.rpc_id(1, _selected_pet_uuid, "mp", _mp_threshold_slider.value)


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


func _on_release_pressed() -> void:
	if _selected_pet_uuid.is_empty():
		return
	var record := PetManager.client_find_pet(_selected_pet_uuid)
	if record.is_empty():
		return
	_confirm_dialog.dialog_text = "Permanently release %s?" % record.get(PetManager.KEY_NAME, "this pet")
	_confirm_dialog.popup_centered()


func _on_release_confirmed() -> void:
	if _selected_pet_uuid.is_empty():
		return
	PetManager.request_release_pet_server.rpc_id(1, _selected_pet_uuid)
	_selected_pet_uuid = ""


func _on_name_submitted(new_text: String) -> void:
	_commit_rename(new_text)
	_name_edit.release_focus()


func _on_name_focus_exited() -> void:
	_commit_rename(_name_edit.text)


func _commit_rename(new_text: String) -> void:
	if _selected_pet_uuid.is_empty():
		return
	var trimmed := new_text.strip_edges()
	if trimmed.is_empty():
		# Restore the original name in the field if blank.
		var record := PetManager.client_find_pet(_selected_pet_uuid)
		_name_edit.text = record.get(PetManager.KEY_NAME, "") if not record.is_empty() else ""
		return
	var current := PetManager.client_find_pet(_selected_pet_uuid)
	if current.get(PetManager.KEY_NAME, "") == trimmed:
		return  # no change
	PetManager.request_rename_pet_server.rpc_id(1, _selected_pet_uuid, trimmed)
