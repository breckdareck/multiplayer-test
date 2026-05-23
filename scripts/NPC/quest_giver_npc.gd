class_name QuestGiverNPC
extends Node2D

## Reusable quest-giver NPC. Right-click opens a QuestGiverDialog listing the
## subset of QuestManager quests this NPC is configured to offer
## (`offered_quest_ids`), filtered by the local player's current state.
##
## Generalizes the JobAdvancementNPC pattern: same scene layout (sprite +
## clickable overlay + tooltip Label + CanvasLayer-mounted dialog), different
## payload. Multiple instances can exist per zone with different `npc_name`
## and `offered_quest_ids` so each one feels like a distinct character with
## their own slate of work.

@export var npc_name: String = "Quest-Giver"
## Quest IDs this NPC offers, in the order they should appear in the dialog.
## Must match keys registered in QuestManager._define_quests().
@export var offered_quest_ids: PackedStringArray = PackedStringArray()

@export var clickable_overlay: TextureButton
@export var prompt_label: Label = null
@export var dialog_window: QuestGiverDialog


func _ready() -> void:
	if not clickable_overlay:
		push_error("QuestGiverNPC: clickable_overlay (TextureButton) missing!")
		return
	if not dialog_window:
		push_error("QuestGiverNPC: dialog_window missing!")
		return

	dialog_window.configure(npc_name, offered_quest_ids)

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
