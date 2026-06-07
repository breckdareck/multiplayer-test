@tool
class_name UpgradesProperty
extends EditorProperty

## Native-Inspector editor for AbilityData.upgrades — hosts the rich tier-row
## upgrade-tree widget (grouped T1/T2/T3, add/remove with external .tres
## management, effect_key picker, variant/tier validation) inside the real
## Inspector instead of the custom dock. Auto-saves the external upgrade files.

var _editor: UpgradeTreeEditor


func _init() -> void:
	_editor = UpgradeTreeEditor.new()
	_editor.auto_save = true
	_editor.dirty_changed.connect(_on_changed)
	_editor.structure_changed.connect(_on_changed)
	add_child(_editor)
	set_bottom_editor(_editor)  # span full width below the "upgrades" label


func _on_changed() -> void:
	var obj := get_edited_object()
	if obj:
		# Mark the AbilityData modified so the Inspector/undo stays in sync; the
		# external .tres writes are handled by the editor's own auto-save.
		emit_changed(get_edited_property(), obj.get(get_edited_property()))


func _update_property() -> void:
	var ab := get_edited_object() as AbilityData
	if ab:
		_editor.set_ability(ab, ab.resource_path)
