@tool
class_name EffectKeyProperty
extends EditorProperty

## Native-Inspector editor for AbilityUpgradeData.effect_key. Replaces the plain
## text field with a code-scanned combo + live "consumed / no-consumer" chip and
## a magnitude-meaning hint (ADR 0010). Used via WeaponContentInspector.
##
## Lives in the real Inspector, so it inherits the editor theme and Godot handles
## undo/redo + dirty state through emit_changed().

var _line: LineEdit
var _menu: MenuButton
var _chip: Label
var _hint: Label
var _updating := false


func _init() -> void:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(row)

	_line = LineEdit.new()
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.placeholder_text = "snake_case key"
	_line.text_changed.connect(_on_text_changed)
	row.add_child(_line)

	_menu = MenuButton.new()
	_menu.text = "▾"
	_menu.tooltip_text = "Pick a known effect_key (scanned from code)"
	_menu.about_to_popup.connect(_populate_menu)
	_menu.get_popup().id_pressed.connect(_on_menu_pick)
	row.add_child(_menu)

	_chip = Label.new()
	_chip.add_theme_font_size_override("font_size", 10)
	row.add_child(_chip)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(_hint)

	add_child(vb)
	add_focusable(_line)
	set_bottom_editor(vb)  # span full width under the property label


func _populate_menu() -> void:
	var pop := _menu.get_popup()
	pop.clear()
	var seen := {}
	var section := func(header: String, keys: PackedStringArray) -> void:
		var any := false
		for k in keys:
			if seen.has(k):
				continue
			if not any:
				pop.add_separator(header)
				any = true
			seen[k] = true
			pop.add_item(k)
	section.call("Generic (any ability)", EffectKeyScanner.generic_keys())
	section.call("All keys in code", EffectKeyScanner.all_keys())


func _on_menu_pick(id: int) -> void:
	var pop := _menu.get_popup()
	var idx := pop.get_item_index(id)
	if idx < 0 or pop.is_item_separator(idx):
		return
	var k := pop.get_item_text(idx)
	if k.is_empty():
		return
	_line.text = k
	_on_text_changed(k)


func _on_text_changed(t: String) -> void:
	if _updating:
		return
	var k := t.strip_edges()
	emit_changed(get_edited_property(), k)
	_refresh_feedback(k)


func _update_property() -> void:
	var v: String = str(get_edited_object().get(get_edited_property()))
	_updating = true
	_line.text = v
	_updating = false
	_refresh_feedback(v)


func _refresh_feedback(k: String) -> void:
	if k.is_empty():
		_chip.text = "○ empty"
		_chip.modulate = Color(0.6, 0.6, 0.65)
		_hint.text = ""
	elif EffectKeyScanner.has_consumer(k):
		_chip.text = "✓ consumed"
		_chip.modulate = Color(0.42, 0.85, 0.52)
		var d := EffectKeyScanner.describe_key(k)
		_hint.text = ("↳ " + d) if not d.is_empty() else ""
	else:
		_chip.text = "⚠ no consumer"
		_chip.modulate = Color(0.95, 0.75, 0.30)
		_hint.text = "No AL_*.gd / component reads \"%s\" yet. Fine while authoring; wire a handler before shipping." % k
