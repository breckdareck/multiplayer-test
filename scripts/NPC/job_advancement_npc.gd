class_name JobAdvancementNPC
extends Node2D

## NPC that opens the Job Advancement dialog on right-click. Mirrors the
## NPCInteraction pattern used by the merchant, but routed to a dialog that
## advances the player's class instead of a shop.

@export var clickable_overlay: TextureButton
@export var prompt_label: Label = null
@export var dialog_window: JobAdvancementDialog


func _ready() -> void:
	if not clickable_overlay:
		push_error("JobAdvancementNPC: clickable_overlay (TextureButton) missing!")
		return
	if not dialog_window:
		push_error("JobAdvancementNPC: dialog_window missing!")
		return

	clickable_overlay.gui_input.connect(_on_gui_input)
	clickable_overlay.mouse_entered.connect(_on_mouse_entered)
	clickable_overlay.mouse_exited.connect(_on_mouse_exited)

	if prompt_label:
		prompt_label.visible = false


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_open_dialog()
			get_viewport().set_input_as_handled()


func _on_mouse_entered() -> void:
	if prompt_label:
		prompt_label.visible = true


func _on_mouse_exited() -> void:
	if prompt_label:
		prompt_label.visible = false


func _open_dialog() -> void:
	if not dialog_window:
		return
	dialog_window.refresh_for_local_player()
	dialog_window.visible = true
