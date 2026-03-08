@tool
extends EditorPlugin

var panel: Control

func _enter_tree() -> void:
	panel = preload("res://addons/enemy_creator/enemy_creator_panel.gd").new()
	panel.name = "EnemyCreator"
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, panel)


func _exit_tree() -> void:
	if panel:
		remove_control_from_docks(panel)
		panel.queue_free()
		panel = null
