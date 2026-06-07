@tool
class_name ResourceEditor
extends EditorPlugin

## Weapon-content editor plugin. After the 2026-06 rewrite, per-resource editing
## lives in Godot's native Inspector (enhanced by WeaponContentInspector) and the
## cross-cutting tools live in one bottom panel (WeaponToolingPanel). The old
## custom dock (ResourceEditorGUI) has been retired.

## Native-Inspector enhancement for the weapon-content resource types.
var _inspector_plugin: EditorInspectorPlugin = null

## Bottom-panel home for the cross-cutting tools (Tree Board / Problems / Batch).
var _tooling_panel: Control = null


func _enter_tree():
	_inspector_plugin = WeaponContentInspector.new()
	add_inspector_plugin(_inspector_plugin)

	_tooling_panel = WeaponToolingPanel.new()
	add_control_to_bottom_panel(_tooling_panel, "Weapon Tooling")


func _exit_tree():
	if _inspector_plugin:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null

	if _tooling_panel:
		remove_control_from_bottom_panel(_tooling_panel)
		_tooling_panel.queue_free()
		_tooling_panel = null
