@tool
extends EditorPlugin

var panel: Control

func _enter_tree() -> void:
	panel = preload("res://addons/class_editor/class_editor_panel.gd").new()
	panel.name = "ClassEditor"
	add_control_to_dock(DOCK_SLOT_LEFT_UL, panel)

func _exit_tree() -> void:
	if panel:
		remove_control_from_docks(panel)
		panel.queue_free()
		panel = null
