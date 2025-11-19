@tool
class_name ResourceEditor
extends EditorPlugin

# Path to the main GUI scene for the editor
const EDITOR_SCENE = "res://addons/resource_editor/ResourceEditorGUI.tscn"

var resource_editor_gui: Control = null

func _enter_tree():
	# Load and instantiate the custom GUI scene.
	var scene = load(EDITOR_SCENE)
	if scene:
		resource_editor_gui = scene.instantiate()
		
		# Add the control to a dock in the editor.
		# DOCK_SLOT_LEFT_UR places it in the top-left dock area.
		# Other common slots are DOCK_SLOT_RIGHT_UL, DOCK_SLOT_BOTTOM_LEFT, etc.
		add_control_to_dock(DOCK_SLOT_LEFT_UR, resource_editor_gui)
		
		# Set the title that appears in the dock tab.
		resource_editor_gui.name = "Resources"

func _exit_tree():
	if resource_editor_gui:
		# Remove the control from the dock area.
		remove_control_from_docks(resource_editor_gui)
		
		# Free the control from memory.
		resource_editor_gui.queue_free()
		resource_editor_gui = null

# The `_run()` function from your original script is no longer needed
# because the functionality is now handled by _enter_tree() and _exit_tree().
