@tool
extends EditorPlugin

const BossAttackDockScript := preload("res://addons/boss_attack_designer/boss_attack_dock.gd")

var _dock: Control = null


func _enter_tree() -> void:
	_dock = BossAttackDockScript.new()
	_dock.name = "Boss Attacks"
	# Bottom-left dock slot keeps it alongside Scene/FileSystem, out of the
	# inspector's way (mirrors the Balance Simulator plugin).
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_BR, _dock)
	if _dock.has_method("set_editor_interface"):
		_dock.set_editor_interface(get_editor_interface())


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
