class_name EquipmentWindow
extends Control

@onready var equipment_window: Control = $"."
@onready var window_title_label: Label = $Label
@onready var equipment_panel: Control = $PanelContainer
@onready var pet_tab_content: Control = $PetTabContent
@onready var pet_tab: Node = $PetTabContent/PetTab
@onready var equipment_tab_button: Button = $TabButtons/EquipmentTabButton
@onready var pets_tab_button: Button = $TabButtons/PetsTabButton

var player: MultiplayerPlayerV2

var is_dragging = false
var drag_offset = Vector2()


func _ready() -> void:
	# Add to ui_window group for drop detection
	add_to_group("ui_window")

	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2
	else:
		# Nested inside the unified hub (game_window): owner is the hub root, not
		# the player. Walk ancestors to find the player so the pet wiring works.
		var n: Node = get_parent()
		while n != null and not (n is MultiplayerPlayerV2):
			n = n.get_parent()
		player = n as MultiplayerPlayerV2

	# The pet tab is embedded in equipment_window.tscn — wire its owner ref.
	if is_instance_valid(pet_tab) and pet_tab.has_method("set_owner_player"):
		pet_tab.set_owner_player(player)

	_show_equipment_tab()


func _process(_delta: float) -> void:
	if player != null and multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenEquipmentWindow"):
			if equipment_window.visible:
				equipment_window.visible = false
			elif not InputManager.is_locked():
				equipment_window.visible = true

	if is_dragging:
		var new_position = get_global_mouse_position() - drag_offset
		var viewport_size = get_viewport_rect().size
		var window_size = size

		new_position.x = clamp(new_position.x, 0, viewport_size.x - window_size.x)
		new_position.y = clamp(new_position.y, 0, viewport_size.y - window_size.y)

		global_position = new_position


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if window_title_label.get_global_rect().has_point(get_global_mouse_position()):
				is_dragging = true
				drag_offset = get_global_mouse_position() - global_position
				self.move_to_front()
		else:
			is_dragging = false


func _on_equipment_tab_pressed() -> void:
	_show_equipment_tab()


func _on_pets_tab_pressed() -> void:
	_show_pet_tab()


func _show_equipment_tab() -> void:
	if is_instance_valid(equipment_panel):
		equipment_panel.visible = true
	if is_instance_valid(pet_tab_content):
		pet_tab_content.visible = false
	if is_instance_valid(window_title_label):
		window_title_label.text = "Equipment"
	if is_instance_valid(equipment_tab_button):
		equipment_tab_button.disabled = true
	if is_instance_valid(pets_tab_button):
		pets_tab_button.disabled = false


func _show_pet_tab() -> void:
	if is_instance_valid(equipment_panel):
		equipment_panel.visible = false
	if is_instance_valid(pet_tab_content):
		pet_tab_content.visible = true
	if is_instance_valid(window_title_label):
		window_title_label.text = "Pets"
	if is_instance_valid(equipment_tab_button):
		equipment_tab_button.disabled = false
	if is_instance_valid(pets_tab_button):
		pets_tab_button.disabled = true
