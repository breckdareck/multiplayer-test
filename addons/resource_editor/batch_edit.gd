@tool
class_name BatchEditWindow
extends Window

## Batch / bulk field editor (grilled 2026-06-06). Multi-select resources of one
## type and set a scalar field across all of them at once, with a mandatory
## dry-run preview (old → new per resource) and a confirm dialog before anything
## is written. Editable fields are discovered from the resource's own script
## variables (int / float / bool / String), so it works for every type without
## a hand-maintained field map.
##
## Note on undo: each apply writes .tres files directly. Godot's
## EditorUndoRedoManager can't cleanly revert file writes, so safety comes from
## the preview + confirm step rather than an undo entry. Resources aren't backed
## up; review the preview before applying.

signal applied  ## emitted after a successful apply so the host can rescan

const C_DARK = Color(0.11, 0.12, 0.15)
const C_DIM  = Color(0.50, 0.53, 0.60)
const C_TEXT = Color(0.88, 0.88, 0.90)
const C_OK   = Color(0.42, 0.85, 0.52)
const C_WARN = Color(0.95, 0.75, 0.30)
const C_ERR  = Color(1.00, 0.35, 0.35)
const C_ACCENT = Color(0.75, 0.48, 1.00)

var _type_name := ""
var _entries: Array = []   # [{res, path, check}]
var _fields: Array = []    # [{name, type}]

var _header: Label
var _list_host: VBoxContainer
var _field_option: OptionButton
var _value_edit: LineEdit
var _preview: RichTextLabel
var _status: Label
var _confirm: ConfirmationDialog


func _init() -> void:
	title = "Batch Edit"
	size = Vector2i(760, 640)
	min_size = Vector2i(520, 420)
	close_requested.connect(hide)
	_build_chrome()


func _build_chrome() -> void:
	var root := PanelContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_DARK
	root.add_theme_stylebox_override("panel", sb)
	add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	root.add_child(col)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 12)
	_header.add_theme_color_override("font_color", C_ACCENT)
	col.add_child(_header)

	# Selection list
	var sel_bar := HBoxContainer.new()
	col.add_child(sel_bar)
	var sel_lbl := Label.new()
	sel_lbl.text = "Select resources"
	sel_lbl.add_theme_color_override("font_color", C_DIM)
	sel_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_bar.add_child(sel_lbl)
	var all_btn := Button.new()
	all_btn.text = "All"
	all_btn.pressed.connect(func(): _set_all_checks(true))
	sel_bar.add_child(all_btn)
	var none_btn := Button.new()
	none_btn.text = "None"
	none_btn.pressed.connect(func(): _set_all_checks(false))
	sel_bar.add_child(none_btn)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_list_host = VBoxContainer.new()
	_list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_host)

	# Field + value
	var edit_bar := HBoxContainer.new()
	edit_bar.add_theme_constant_override("separation", 6)
	col.add_child(edit_bar)
	var fl := Label.new(); fl.text = "Set field"; fl.add_theme_color_override("font_color", C_DIM)
	edit_bar.add_child(fl)
	_field_option = OptionButton.new()
	_field_option.custom_minimum_size = Vector2(220, 0)
	_field_option.item_selected.connect(func(_i): _refresh_preview())
	edit_bar.add_child(_field_option)
	var vl := Label.new(); vl.text = "to"; vl.add_theme_color_override("font_color", C_DIM)
	edit_bar.add_child(vl)
	_value_edit = LineEdit.new()
	_value_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_edit.placeholder_text = "value"
	_value_edit.text_changed.connect(func(_t): _refresh_preview())
	edit_bar.add_child(_value_edit)

	# Preview
	var pl := Label.new()
	pl.text = "PREVIEW"
	pl.add_theme_font_size_override("font_size", 11)
	pl.add_theme_color_override("font_color", C_DIM)
	col.add_child(pl)
	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = true
	_preview.fit_content = true
	_preview.scroll_active = true
	_preview.custom_minimum_size = Vector2(0, 140)
	col.add_child(_preview)

	# Footer
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	col.add_child(foot)
	_status = Label.new()
	_status.add_theme_color_override("font_color", C_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_status)
	var apply_btn := Button.new()
	apply_btn.text = "Apply…"
	apply_btn.pressed.connect(_on_apply_pressed)
	foot.add_child(apply_btn)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Confirm Batch Edit"
	_confirm.ok_button_text = "Write Files"
	_confirm.confirmed.connect(_do_apply)
	add_child(_confirm)


# ── Public ───────────────────────────────────────────────────────────────────
func open_for(type_name: String, script_path: String, base_folder: String) -> void:
	_type_name = type_name
	_header.text = "⚙  BATCH EDIT — %s" % type_name
	_scan(script_path, base_folder)
	_build_list()
	_build_field_options()
	_refresh_preview()
	popup_centered()


# ── Scan / list ──────────────────────────────────────────────────────────────
func _scan(script_path: String, base_folder: String) -> void:
	_entries.clear()
	var script = load(script_path)
	if script == null:
		return
	_scan_dir(base_folder, script)
	_entries.sort_custom(func(a, b): return str(a.path) < str(b.path))


func _scan_dir(path: String, script: Script) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := path.path_join(f)
		if dir.current_is_dir():
			if not f.begins_with("."):
				_scan_dir(full, script)
		elif f.ends_with(".tres"):
			var res = load(full)
			if res != null and _matches(res.get_script(), script):
				_entries.append({"res": res, "path": full, "check": null})
		f = dir.get_next()
	dir.list_dir_end()


func _matches(res_script, target: Script) -> bool:
	var s = res_script
	while s != null:
		if s == target:
			return true
		s = s.get_base_script()
	return false


func _build_list() -> void:
	for c in _list_host.get_children():
		c.queue_free()
	for e in _entries:
		var cb := CheckBox.new()
		cb.text = str(e.path).get_file()
		cb.tooltip_text = e.path
		cb.button_pressed = false
		cb.toggled.connect(func(_p): _refresh_preview())
		_list_host.add_child(cb)
		e.check = cb


func _set_all_checks(v: bool) -> void:
	for e in _entries:
		if is_instance_valid(e.check):
			e.check.button_pressed = v
	_refresh_preview()


# ── Fields ───────────────────────────────────────────────────────────────────
func _build_field_options() -> void:
	_field_option.clear()
	_fields.clear()
	if _entries.is_empty():
		return
	var sample: Resource = _entries[0].res
	for p in sample.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var t: int = p.type
		if t in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING]:
			var n: String = p.name
			if n.begins_with("_") or n in ["resource_name", "resource_local_to_scene"]:
				continue
			_field_option.add_item("%s  (%s)" % [n, _type_str(t)], _fields.size())
			_fields.append({"name": n, "type": t})


func _type_str(t: int) -> String:
	match t:
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_BOOL: return "bool"
		TYPE_STRING: return "String"
	return "?"


func _selected_field() -> Dictionary:
	var i := _field_option.get_selected_id()
	if i < 0 or i >= _fields.size():
		return {}
	return _fields[i]


func _parse_value(field: Dictionary):
	var raw := _value_edit.text.strip_edges()
	match int(field.type):
		TYPE_INT: return int(raw) if raw.is_valid_int() else (0 if raw.is_empty() else null)
		TYPE_FLOAT: return float(raw) if raw.is_valid_float() else (0.0 if raw.is_empty() else null)
		TYPE_BOOL: return raw.to_lower() in ["true", "1", "yes", "on"]
		TYPE_STRING: return raw
	return null


func _checked_entries() -> Array:
	return _entries.filter(func(e): return is_instance_valid(e.check) and e.check.button_pressed)


# ── Preview / apply ──────────────────────────────────────────────────────────
func _refresh_preview() -> void:
	var field := _selected_field()
	var checked := _checked_entries()
	if field.is_empty():
		_preview.text = "[color=#7d8088]Pick a field.[/color]"
		_status.text = ""
		return
	var new_val = _parse_value(field)
	if new_val == null:
		_preview.text = "[color=#f2bf4d]Value '%s' isn't a valid %s.[/color]" % [_value_edit.text, _type_str(field.type)]
		_status.text = ""
		return
	if checked.is_empty():
		_preview.text = "[color=#7d8088]No resources selected.[/color]"
		_status.text = ""
		return
	var lines := ""
	var changes := 0
	for e in checked:
		var old = e.res.get(field.name)
		var marker := "[color=#6bd97f]→[/color]"
		if str(old) == str(new_val):
			marker = "[color=#7d8088]= (unchanged)[/color]"
		else:
			changes += 1
		lines += "[color=#cfd2da]%s[/color]: %s %s %s\n" % [str(e.path).get_file(), str(old), marker, str(new_val)]
	_preview.text = lines
	_status.text = "%d selected • %d will change" % [checked.size(), changes]


func _on_apply_pressed() -> void:
	var field := _selected_field()
	var checked := _checked_entries()
	if field.is_empty() or checked.is_empty() or _parse_value(field) == null:
		_status.text = "Nothing to apply."
		return
	_confirm.dialog_text = "Set %s = %s on %d resource(s)?\nThis writes the .tres files (no undo)." % [
		field.name, str(_parse_value(field)), checked.size()]
	_confirm.popup_centered()


func _do_apply() -> void:
	var field := _selected_field()
	var new_val = _parse_value(field)
	if field.is_empty() or new_val == null:
		return
	var written := 0
	for e in _checked_entries():
		e.res.set(field.name, new_val)
		if ResourceSaver.save(e.res, e.path) == OK:
			written += 1
	_status.text = "Wrote %d file(s)." % written
	_refresh_preview()
	applied.emit()
