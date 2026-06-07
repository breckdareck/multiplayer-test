@tool
class_name UpgradeTreeEditor
extends VBoxContainer

## Inline editor for an AbilityData's per-ability upgrade tree (PR 6).
## Renders the ability's `upgrades` grouped T1/T2/T3, lets you add/remove
## upgrades (managing the external .tres files + the parent's ext_resource
## refs), and edit each upgrade's fields with a code-scanned effect_key picker.
##
## Design locked in the 2026-06-06 grilling session; effect_key discovery is
## ADR 0010 (scan source, no central registry).
##
## File contract:
##  - Each upgrade is its own .tres under  <ability_dir>/Upgrades/  named
##    U_<ABBR>_<Slug>.tres, referenced from ability.upgrades.
##  - Add/Remove are STRUCTURAL: they write the upgrade file AND re-save the
##    parent ability immediately (so the ref array persists on disk).
##  - Field edits are deferred: they mark the upgrade dirty and emit
##    dirty_changed; the host calls save_all() from its main Save button.

signal dirty_changed   ## a field edit happened — host should show the ● marker
signal structure_changed  ## an upgrade was added/removed — host should rescan/refresh

const C_CARD   = Color(0.15, 0.16, 0.19)
const C_BORDER = Color(0.22, 0.24, 0.30)
const C_DIM    = Color(0.50, 0.53, 0.60)
const C_TEXT   = Color(0.88, 0.88, 0.90)
const C_OK     = Color(0.42, 0.85, 0.52)
const C_WARN   = Color(0.95, 0.75, 0.30)
const C_ERR    = Color(1.00, 0.35, 0.35)
const C_ACCENT = Color(0.55, 0.45, 0.85)

const TIER_COSTS := {1: 1, 2: 1, 3: 2}  # default point_cost per tier

var _ability: AbilityData = null
var _ability_path: String = ""
var _dirty_upgrades: Dictionary = {}  # AbilityUpgradeData -> true
var _rows_host: VBoxContainer
var _summary_label: Label
var _empty_note: Label


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_build_static_chrome()


func _build_static_chrome() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	add_child(header)

	var title := Label.new()
	title.text = "⬆  UPGRADE TREE"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", C_ACCENT)
	header.add_child(title)

	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 11)
	_summary_label.add_theme_color_override("font_color", C_DIM)
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_summary_label)

	_empty_note = Label.new()
	_empty_note.add_theme_font_size_override("font_size", 11)
	_empty_note.add_theme_color_override("font_color", C_DIM)
	_empty_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_empty_note)

	_rows_host = VBoxContainer.new()
	_rows_host.add_theme_constant_override("separation", 10)
	add_child(_rows_host)

	var add_bar := HBoxContainer.new()
	add_bar.add_theme_constant_override("separation", 6)
	add_child(add_bar)
	for tier in [1, 2, 3]:
		var b := Button.new()
		b.text = "+ Tier %d" % tier
		b.tooltip_text = "Add a new Tier %d upgrade (%d pt)" % [tier, TIER_COSTS[tier]]
		b.pressed.connect(_on_add_pressed.bind(tier))
		add_bar.add_child(b)


# ── Public API ───────────────────────────────────────────────────────────────

func set_ability(ability: AbilityData, ability_path: String) -> void:
	_ability = ability
	_ability_path = ability_path
	_dirty_upgrades.clear()
	_rebuild()


func clear() -> void:
	_ability = null
	_ability_path = ""
	_dirty_upgrades.clear()
	_rebuild()


## Writes every dirty upgrade .tres to disk. Called by the host on main Save.
func save_all() -> void:
	if _ability == null:
		return
	for up in _dirty_upgrades.keys():
		if up == null or not (up is AbilityUpgradeData):
			continue
		var path: String = up.resource_path
		if path.is_empty():
			path = _upgrade_path_for(up)
			if path.is_empty():
				continue
		ResourceSaver.save(up, path)
	_dirty_upgrades.clear()


# ── Rebuild ──────────────────────────────────────────────────────────────────

func _rebuild() -> void:
	for c in _rows_host.get_children():
		c.queue_free()

	if _ability == null:
		_summary_label.text = ""
		_empty_note.text = ""
		return

	var upgrades: Array = []
	if "upgrades" in _ability and _ability.upgrades != null:
		for u in _ability.upgrades:
			if u is AbilityUpgradeData:
				upgrades.append(u)

	# Summary chip.
	var total_pts := 0
	for u in upgrades:
		total_pts += int(u.point_cost)
	_summary_label.text = "%d upgrade%s • full-clear %d pt" % [
		upgrades.size(), ("" if upgrades.size() == 1 else "s"), total_pts]

	if _ability_path.is_empty():
		_empty_note.text = "Save the ability once before adding upgrades (the .tres files live in its Upgrades/ subfolder)."
	elif upgrades.is_empty():
		_empty_note.text = "No upgrades yet. Add a Tier 1 broad modifier to start the tree."
	else:
		_empty_note.text = ""

	# Group by tier.
	for tier in [1, 2, 3]:
		var in_tier: Array = []
		for u in upgrades:
			if int(u.tier) == tier:
				in_tier.append(u)
		if in_tier.is_empty():
			continue
		var tlabel := Label.new()
		tlabel.text = "Tier %d" % tier + ("  —  variants (pick 1)" if tier == 3 else "")
		tlabel.add_theme_font_size_override("font_size", 11)
		tlabel.add_theme_color_override("font_color", C_DIM)
		_rows_host.add_child(tlabel)
		for u in in_tier:
			_rows_host.add_child(_build_row(u))

	_validate_into_summary(upgrades)


func _build_row(up: AbilityUpgradeData) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.border_color = Color(C_ACCENT, 0.35)
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	card.add_child(col)

	# Row 1: name + tier + cost + remove
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 6)
	col.add_child(r1)

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Upgrade name"
	name_edit.text = up.upgrade_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.tooltip_text = "Display name. upgrade_id (%s) is kept stable on rename." % up.upgrade_id
	name_edit.text_changed.connect(func(t):
		up.upgrade_name = t
		_mark(up))
	r1.add_child(name_edit)

	var tier_lbl := Label.new()
	tier_lbl.text = "T"
	tier_lbl.add_theme_color_override("font_color", C_DIM)
	r1.add_child(tier_lbl)
	var tier_opt := OptionButton.new()
	for t in [1, 2, 3]:
		tier_opt.add_item(str(t), t)
	tier_opt.selected = clampi(int(up.tier) - 1, 0, 2)
	tier_opt.tooltip_text = "Tier band (gating + grouping)"
	tier_opt.item_selected.connect(func(idx):
		up.tier = idx + 1
		_mark(up)
		_rebuild())
	r1.add_child(tier_opt)

	var cost_lbl := Label.new()
	cost_lbl.text = "pt"
	cost_lbl.add_theme_color_override("font_color", C_DIM)
	r1.add_child(cost_lbl)
	var cost_spin := SpinBox.new()
	cost_spin.min_value = 0
	cost_spin.max_value = 10
	cost_spin.value = up.point_cost
	cost_spin.tooltip_text = "Ability points spent to buy this upgrade"
	cost_spin.value_changed.connect(func(v):
		up.point_cost = int(v)
		_mark(up)
		_rebuild())
	r1.add_child(cost_spin)

	var remove_btn := Button.new()
	remove_btn.text = "✕"
	remove_btn.tooltip_text = "Delete this upgrade (removes its .tres file)"
	remove_btn.add_theme_color_override("font_color", C_ERR)
	remove_btn.pressed.connect(_on_remove_pressed.bind(up))
	r1.add_child(remove_btn)

	# Row 2: effect_key (editable combo) + consumer chip + magnitude
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 6)
	col.add_child(r2)

	var key_lbl := Label.new()
	key_lbl.text = "effect_key"
	key_lbl.add_theme_color_override("font_color", C_DIM)
	r2.add_child(key_lbl)

	var key_edit := LineEdit.new()
	key_edit.text = up.effect_key
	key_edit.placeholder_text = "snake_case key"
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(key_edit)

	var key_menu := MenuButton.new()
	key_menu.text = "▾"
	key_menu.tooltip_text = "Pick a known effect_key (scanned from code)"
	_populate_key_menu(key_menu, key_edit, up)
	r2.add_child(key_menu)

	var chip := Label.new()
	chip.add_theme_font_size_override("font_size", 10)
	r2.add_child(chip)

	var mag_lbl := Label.new()
	mag_lbl.text = "mag"
	mag_lbl.add_theme_color_override("font_color", C_DIM)
	r2.add_child(mag_lbl)
	var mag_spin := SpinBox.new()
	mag_spin.min_value = -100000
	mag_spin.max_value = 100000
	mag_spin.step = 0.01
	mag_spin.value = up.magnitude
	mag_spin.tooltip_text = "Numeric parameter; meaning depends on effect_key"
	mag_spin.value_changed.connect(func(v):
		up.magnitude = v
		_mark(up))
	r2.add_child(mag_spin)

	# Magnitude hint (from `key → meaning` comments) + consumer chip refresh.
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", C_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	var refresh_key_feedback := func():
		var k: String = up.effect_key
		if k.is_empty():
			chip.text = "○ empty"
			chip.add_theme_color_override("font_color", C_DIM)
			hint.text = ""
		elif EffectKeyScanner.has_consumer(k):
			chip.text = "✓ consumed"
			chip.add_theme_color_override("font_color", C_OK)
			var d: String = EffectKeyScanner.describe_key(k)
			hint.text = ("↳ " + d) if not d.is_empty() else ""
		else:
			chip.text = "⚠ no consumer in code"
			chip.add_theme_color_override("font_color", C_WARN)
			hint.text = "↳ no AL_*.gd / component reads \"%s\" yet. Fine while authoring; wire a handler before shipping." % k
	key_edit.text_changed.connect(func(t):
		up.effect_key = t.strip_edges()
		_mark(up)
		refresh_key_feedback.call())
	refresh_key_feedback.call()

	# Row 3: variant_group (T3 only)
	if int(up.tier) == 3:
		var r3 := HBoxContainer.new()
		r3.add_theme_constant_override("separation", 6)
		col.add_child(r3)
		var vg_lbl := Label.new()
		vg_lbl.text = "variant_group"
		vg_lbl.add_theme_color_override("font_color", C_DIM)
		vg_lbl.tooltip_text = "Mutually-exclusive set. All T3 variants of this ability share one group; the purchase API blocks owning more than one."
		r3.add_child(vg_lbl)
		var vg_edit := LineEdit.new()
		vg_edit.text = up.variant_group
		vg_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vg_edit.placeholder_text = "e.g. %s_finisher" % _abbr(_ability.ability_name).to_lower()
		vg_edit.text_changed.connect(func(t):
			up.variant_group = t.strip_edges()
			_mark(up)
			_rebuild())
		r3.add_child(vg_edit)

	# Row 4: description
	var desc := TextEdit.new()
	desc.text = up.description
	desc.placeholder_text = "Tooltip description (BBCode allowed)"
	desc.custom_minimum_size = Vector2(0, 44)
	desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc.focus_exited.connect(func():
		if up.description != desc.text:
			up.description = desc.text
			_mark(up))
	col.add_child(desc)

	return card


func _populate_key_menu(menu: MenuButton, key_edit: LineEdit, up: AbilityUpgradeData) -> void:
	var pop := menu.get_popup()
	pop.clear()
	var added := {}
	var add_section := func(header: String, keys: PackedStringArray):
		var any := false
		for k in keys:
			if added.has(k):
				continue
			if not any:
				pop.add_separator(header)
				any = true
			added[k] = true
			pop.add_item(k)

	# This ability's own logic-script keys first.
	var own := PackedStringArray()
	if _ability and _ability.active_behavior and _ability.active_behavior.logic_script:
		own = EffectKeyScanner.keys_for_script(_ability.active_behavior.logic_script.resource_path)
	add_section.call("This ability", own)
	add_section.call("Generic (any ability)", EffectKeyScanner.generic_keys())
	add_section.call("All other keys", EffectKeyScanner.all_keys())

	if not pop.id_pressed.is_connected(_on_key_menu_id):
		pop.id_pressed.connect(_on_key_menu_id.bind(pop, key_edit, up))


func _on_key_menu_id(id: int, pop: PopupMenu, key_edit: LineEdit, up: AbilityUpgradeData) -> void:
	var idx := pop.get_item_index(id)
	if idx < 0:
		return
	var k := pop.get_item_text(idx)
	if k.is_empty():
		return
	key_edit.text = k
	key_edit.text_changed.emit(k)


# ── Add / remove (structural — write files immediately) ───────────────────────

func _on_add_pressed(tier: int) -> void:
	if _ability == null:
		return
	if _ability_path.is_empty():
		structure_changed.emit()  # host shows "save ability first" via _rebuild note
		_rebuild()
		return

	var up := AbilityUpgradeData.new()
	up.tier = tier
	up.point_cost = TIER_COSTS.get(tier, 1)
	up.upgrade_name = "New Tier %d" % tier
	up.upgrade_id = _make_upgrade_id(up)
	if tier == 3:
		up.variant_group = "%s_t3" % _abbr(_ability.ability_name).to_lower()

	var path := _upgrade_path_for(up)
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(up, path)
	if err != OK:
		push_error("UpgradeTreeEditor: failed to save %s (err %d)" % [path, err])
		return
	up = load(path)  # reload so it carries resource_path as an ext_resource ref

	if _ability.upgrades == null:
		_ability.upgrades = []
	_ability.upgrades.append(up)
	ResourceSaver.save(_ability, _ability_path)  # persist the new ref array

	structure_changed.emit()
	_rebuild()


func _on_remove_pressed(up: AbilityUpgradeData) -> void:
	if _ability == null or up == null:
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete Upgrade"
	dialog.dialog_text = "Delete \"%s\" (%s)?\nThis removes its .tres file." % [up.upgrade_name, up.upgrade_id]
	dialog.ok_button_text = "Delete"
	add_child(dialog)
	dialog.confirmed.connect(func():
		var path: String = up.resource_path
		_dirty_upgrades.erase(up)
		var arr: Array = _ability.upgrades
		arr.erase(up)
		if not path.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			var uid := path + ".uid"
			if FileAccess.file_exists(uid):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(uid))
		ResourceSaver.save(_ability, _ability_path)
		dialog.queue_free()
		structure_changed.emit()
		_rebuild())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()


# ── Validation ────────────────────────────────────────────────────────────────

func _validate_into_summary(upgrades: Array) -> void:
	var warns: Array[String] = []

	# T3 variant-group mutex sanity.
	var groups: Dictionary = {}  # group -> [upgrades]
	for u in upgrades:
		if int(u.tier) == 3:
			if u.variant_group.is_empty():
				warns.append("T3 \"%s\" has no variant_group (won't be mutex-gated)." % u.upgrade_name)
			else:
				if not groups.has(u.variant_group):
					groups[u.variant_group] = []
				groups[u.variant_group].append(u)
	for g in groups:
		var members: Array = groups[g]
		if members.size() < 2:
			warns.append("variant_group \"%s\" has a lone variant (mutex needs ≥2)." % g)
		for u in members:
			if int(u.point_cost) != 2:
				warns.append("T3 variant \"%s\" costs %d pt (variants are conventionally 2)." % [u.upgrade_name, u.point_cost])

	# Tier-gate sanity: T2 needs a T1, T3 needs a T2.
	var has_tier := {1: false, 2: false, 3: false}
	for u in upgrades:
		has_tier[int(u.tier)] = true
	if has_tier[2] and not has_tier[1]:
		warns.append("Has T2 but no T1 — T2 unlocks once a T1 is owned.")
	if has_tier[3] and not has_tier[2]:
		warns.append("Has T3 but no T2 — T3 unlocks once a T2 is owned.")

	# Duplicate / missing effect_key.
	var key_seen := {}
	for u in upgrades:
		if u.effect_key.is_empty():
			warns.append("\"%s\" has an empty effect_key (no-op)." % u.upgrade_name)
		elif key_seen.has(u.effect_key):
			warns.append("effect_key \"%s\" used by multiple upgrades (they stack)." % u.effect_key)
		else:
			key_seen[u.effect_key] = true

	if warns.is_empty():
		return
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_WARN, 0.10)
	sb.border_color = Color(C_WARN, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	box.add_child(v)
	for w in warns:
		var l := Label.new()
		l.text = "⚠ " + w
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", C_WARN)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	_rows_host.add_child(box)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _mark(up: AbilityUpgradeData) -> void:
	_dirty_upgrades[up] = true
	dirty_changed.emit()


func _abbr(ability_name: String) -> String:
	var letters := ""
	for ch in ability_name:
		if ch.to_lower() != ch.to_upper():  # is a letter
			letters += ch
		if letters.length() >= 3:
			break
	if letters.is_empty():
		letters = "ABL"
	return letters.to_upper()


func _slugify(s: String) -> String:
	var out := ""
	var prev_us := false
	for ch in s.strip_edges():
		var lower := ch.to_lower()
		if (lower >= "a" and lower <= "z") or (ch >= "0" and ch <= "9"):
			out += lower
			prev_us = false
		elif not prev_us and not out.is_empty():
			out += "_"
			prev_us = true
	return out.trim_suffix("_")


func _make_upgrade_id(up: AbilityUpgradeData) -> String:
	var slug := _slugify(up.upgrade_name)
	if slug.is_empty():
		slug = "upgrade"
	# Disambiguate against existing ids on this ability.
	var base := "%s_t%d_%s" % [_abbr(_ability.ability_name).to_lower(), up.tier, slug]
	return _unique_id(base)


func _unique_id(base: String) -> String:
	var existing := {}
	if _ability and _ability.upgrades:
		for u in _ability.upgrades:
			if u is AbilityUpgradeData:
				existing[u.upgrade_id] = true
	if not existing.has(base):
		return base
	var n := 2
	while existing.has("%s_%d" % [base, n]):
		n += 1
	return "%s_%d" % [base, n]


func _upgrade_path_for(up: AbilityUpgradeData) -> String:
	if _ability_path.is_empty():
		return ""
	var dir := _ability_path.get_base_dir().path_join("Upgrades")
	var name_part := _slugify(up.upgrade_name)
	if name_part.is_empty():
		name_part = "upgrade"
	# CamelCase the slug for the filename to match the U_HEM_SerratedEdge style.
	var camel := ""
	for part in name_part.split("_"):
		if part.length() > 0:
			camel += part.substr(0, 1).to_upper() + part.substr(1)
	var fname := "U_%s_%s.tres" % [_abbr(_ability.ability_name), camel]
	return _unique_path(dir.path_join(fname))


func _unique_path(path: String) -> String:
	if not FileAccess.file_exists(path):
		return path
	var base := path.trim_suffix(".tres")
	var n := 2
	while FileAccess.file_exists("%s_%d.tres" % [base, n]):
		n += 1
	return "%s_%d.tres" % [base, n]
