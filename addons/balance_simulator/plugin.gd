@tool
extends EditorPlugin

const SimulatorDockScene := preload("res://addons/balance_simulator/simulator_dock.gd")

var _dock: Control = null


func _enter_tree() -> void:
	_dock = SimulatorDockScene.new()
	_dock.name = "Balance Sim"
	# Bottom-left dock slot keeps it out of the way of the inspector but
	# visible alongside Scene/FileSystem.
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_BR, _dock)
	if _dock.has_method("set_editor_interface"):
		_dock.set_editor_interface(get_editor_interface())


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
