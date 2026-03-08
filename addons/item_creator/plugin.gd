@tool
extends EditorPlugin

var panel: Control

func _enter_tree() -> void:
	panel = preload("res://addons/item_creator/item_creator_panel.gd").new()
	panel.name = "ItemCreator"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, panel)


func _exit_tree() -> void:
	if panel:
		remove_control_from_docks(panel)
		panel.queue_free()
		panel = null
