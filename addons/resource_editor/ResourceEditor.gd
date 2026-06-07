@tool
class_name ResourceEditor
extends EditorPlugin

# Path to the main GUI scene for the editor
const EDITOR_SCENE = "res://addons/resource_editor/ResourceEditorGUI.tscn"

var resource_editor_gui: Control = null

## Native-Inspector enhancement (the rewrite target — see WeaponContentInspector).
## Registered alongside the legacy dock during the staged migration; the dock is
## removed in the final stage once all editing has moved to the Inspector + the
## bottom-panel tools.
var _inspector_plugin: EditorInspectorPlugin = null

## Bottom-panel home for the cross-cutting tools (Tree Board / Problems / Batch),
## replacing the three popup Windows.
var _tooling_panel: Control = null

func _enter_tree():
	# Native Inspector enhancement for the weapon-content resource types.
	_inspector_plugin = WeaponContentInspector.new()
	add_inspector_plugin(_inspector_plugin)

	# Cross-cutting tools in one bottom panel.
	_tooling_panel = WeaponToolingPanel.new()
	add_control_to_bottom_panel(_tooling_panel, "Weapon Tooling")

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
	if _inspector_plugin:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null

	if _tooling_panel:
		remove_control_from_bottom_panel(_tooling_panel)
		_tooling_panel.queue_free()
		_tooling_panel = null

	if resource_editor_gui:
		# Remove the control from the dock area.
		remove_control_from_docks(resource_editor_gui)

		# Free the control from memory.
		resource_editor_gui.queue_free()
		resource_editor_gui = null

# The `_run()` function from your original script is no longer needed
# because the functionality is now handled by _enter_tree() and _exit_tree().
