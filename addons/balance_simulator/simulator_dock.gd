@tool
extends Control
##
## Read-only ability balance simulator. Reads .tres files under
## res://resources/Abilities/, runs each ability's AbilityScalingData formulas
## (the "Layer 1" numbers), and renders a per-level table. Layer 2
## (active_behavior.logic_script) and Layer 3 (proc handlers) are shown as
## breadcrumbs with "Open in editor" buttons — the actual behavior code can
## only be verified by running the game.

const ABILITIES_ROOT := "res://resources/Abilities/"
const CLASSES_ROOT := "res://resources/Player/Disciplines/"

# Stat-type names mirroring Constants.StatType keys we care about in passive
# bonuses. Discovered from level_data.stat_bonuses at render time, but having
# a known order makes column layout deterministic.
const LEVEL_COLUMNS := ["Lv", "MP", "CD", "Dmg%", "Targets", "Hits", "Cast", "Status%", "Bonuses", "Proc"]
const COMBAT_COLUMNS := ["Lv", "Stat", "Min", "Max", "Avg", "Hit%", "ExpAvg"]

# Combat formula constants, mirrored from CombatComponent so the simulator
# matches the game's damage calculation exactly.
const HIT_CHANCE_PER_LEVEL_DIFF := 2.0
const LEVEL_MOD_PER_LEVEL_DIFF := 0.05
const LEVEL_MOD_MIN := 0.5
const LEVEL_MOD_MAX := 1.5
const DEFENSE_DENOM := 500.0

var _editor_interface: EditorInterface = null

# Combat loadout state — bound to UI widgets via field_widgets below.
var _selected_ability: AbilityData = null
var _classes: Dictionary = {}  # class_type:int -> { name: String, primary: int, secondary: int }
var _loadout_widgets: Dictionary = {}  # name -> SpinBox / OptionButton

var _class_filter: OptionButton
var _refresh_btn: Button
var _abilities_list: ItemList
var _detail_root: VBoxContainer
var _header_label: RichTextLabel
var _meta_label: RichTextLabel
var _level_tree: Tree
var _breadcrumbs: VBoxContainer

# All loaded abilities, in display order. Each entry: { path, name, data, class }
var _abilities: Array = []


func _ready() -> void:
	_build_ui()
	# Defer refresh so the dock has time to size correctly the first time it's
	# shown (otherwise the Tree has zero width).
	call_deferred("_refresh_abilities")


func set_editor_interface(ed: EditorInterface) -> void:
	_editor_interface = ed


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	custom_minimum_size = Vector2(360, 480)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)

	# --- Top row: class filter + refresh ---
	var top := HBoxContainer.new()
	vb.add_child(top)

	var class_label := Label.new()
	class_label.text = "Class:"
	top.add_child(class_label)

	_class_filter = OptionButton.new()
	_class_filter.add_item("All")
	# Items beyond "All" are populated from the actual folder names under
	# resources/Abilities/ in _refresh_abilities() — the on-disk layout is the
	# source of truth, not Constants.ClassType (folders are e.g. "Sword" and the
	# enum has "SWORD" — they line up now post-rename).
	_class_filter.item_selected.connect(func(_i): _refresh_list())
	top.add_child(_class_filter)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Rescan"
	_refresh_btn.pressed.connect(_refresh_abilities)
	top.add_child(_refresh_btn)

	# --- Split: list (left) + detail (right). HSplitContainer keeps them
	# resizable inside the dock. ---
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(split)

	_abilities_list = ItemList.new()
	_abilities_list.custom_minimum_size = Vector2(160, 0)
	_abilities_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_abilities_list.item_selected.connect(_on_ability_selected)
	split.add_child(_abilities_list)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(detail_scroll)

	_detail_root = VBoxContainer.new()
	_detail_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_root.add_theme_constant_override("separation", 6)
	detail_scroll.add_child(_detail_root)

	_header_label = RichTextLabel.new()
	_header_label.bbcode_enabled = true
	_header_label.fit_content = true
	_header_label.scroll_active = false
	_header_label.text = "[i]Select an ability on the left.[/i]"
	_detail_root.add_child(_header_label)

	_meta_label = RichTextLabel.new()
	_meta_label.bbcode_enabled = true
	_meta_label.fit_content = true
	_meta_label.scroll_active = false
	_detail_root.add_child(_meta_label)

	_level_tree = Tree.new()
	_level_tree.columns = LEVEL_COLUMNS.size()
	_level_tree.column_titles_visible = true
	_level_tree.hide_root = true
	_level_tree.allow_search = false
	_level_tree.custom_minimum_size = Vector2(0, 220)
	_level_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for i in LEVEL_COLUMNS.size():
		_level_tree.set_column_title(i, LEVEL_COLUMNS[i])
		_level_tree.set_column_expand(i, i >= LEVEL_COLUMNS.size() - 2)
		_level_tree.set_column_clip_content(i, true)
	_detail_root.add_child(_level_tree)

	var breadcrumb_header := Label.new()
	breadcrumb_header.text = "Behavior layers"
	breadcrumb_header.add_theme_font_size_override("font_size", 12)
	_detail_root.add_child(breadcrumb_header)

	_breadcrumbs = VBoxContainer.new()
	_breadcrumbs.add_theme_constant_override("separation", 2)
	_detail_root.add_child(_breadcrumbs)

	_build_combat_section()


# --- Ability discovery ------------------------------------------------------

func _refresh_abilities() -> void:
	_abilities.clear()
	_scan_dir(ABILITIES_ROOT)
	_abilities.sort_custom(func(a, b):
		if a.class_name_str == b.class_name_str:
			return String(a.name).naturalnocasecmp_to(String(b.name)) < 0
		return String(a.class_name_str).naturalnocasecmp_to(String(b.class_name_str)) < 0)
	_populate_class_filter()
	_load_classes()
	_populate_class_dropdown()
	_refresh_list()


## Scans resources/Player/Disciplines/ for WeaponDisciplineData .tres so the combat dropdown
## knows each discipline's primary / secondary stat pairing without hardcoding.
func _load_classes() -> void:
	_classes.clear()
	var dir := DirAccess.open(CLASSES_ROOT)
	if dir == null: return
	for f in dir.get_files():
		if not (f.ends_with(".tres") or f.ends_with(".res")): continue
		var res := load(CLASSES_ROOT.path_join(f))
		if res is WeaponDisciplineData:
			_classes[res.class_type] = {
				"name": res._discipline_name if not res._discipline_name.is_empty() else f.get_basename(),
				"primary": res.primary_stat,
				"secondary": res.secondary_stat,
			}


func _populate_class_filter() -> void:
	# Preserve current selection by text so a rescan doesn't reset the user's
	# filter choice.
	var current_text: String = _class_filter.get_item_text(_class_filter.get_selected()) \
		if _class_filter.get_selected() >= 0 else "All"
	_class_filter.clear()
	_class_filter.add_item("All")
	var classes: Dictionary = {}
	for entry in _abilities:
		classes[entry.class_name_str] = true
	var keys: Array = classes.keys()
	keys.sort()
	for k in keys: _class_filter.add_item(k)
	# Restore selection.
	for i in _class_filter.item_count:
		if _class_filter.get_item_text(i) == current_text:
			_class_filter.select(i)
			return
	_class_filter.select(0)


## Recursive walk over a folder; loads every .tres that turns out to be an
## AbilityData. Subfolders under resources/Abilities/ map to class names
## (Archer/, Mage/, etc.) — we capture the immediate parent as `class_name_str`
## so the filter dropdown works without parsing the .tres.
func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	for f in dir.get_files():
		if not (f.ends_with(".tres") or f.ends_with(".res")): continue
		var full := path.path_join(f)
		var res := load(full)
		if res is AbilityData:
			var parent_folder := path.get_file()
			if parent_folder.is_empty() or path == ABILITIES_ROOT:
				parent_folder = "(root)"
			_abilities.append({
				"path": full,
				"name": res.ability_name if not res.ability_name.is_empty() else f.get_basename(),
				"data": res,
				"class_name_str": parent_folder,
			})
	for d in dir.get_directories():
		_scan_dir(path.path_join(d))


func _refresh_list() -> void:
	_abilities_list.clear()
	var selected_class: String = _class_filter.get_item_text(_class_filter.get_selected())
	for entry in _abilities:
		if selected_class != "All" \
				and selected_class.to_lower() != entry.class_name_str.to_lower():
			continue
		var label := "%s  [%s]" % [entry.name, entry.class_name_str]
		_abilities_list.add_item(label)
		_abilities_list.set_item_metadata(_abilities_list.item_count - 1, entry)


# --- Selection -> detail rendering -----------------------------------------

func _on_ability_selected(idx: int) -> void:
	var entry: Dictionary = _abilities_list.get_item_metadata(idx)
	if entry.is_empty(): return
	var data: AbilityData = entry.data
	_selected_ability = data
	_render_detail(entry, data)
	_recompute_combat()


func _render_detail(entry: Dictionary, data: AbilityData) -> void:
	# Header.
	_header_label.text = "[b]%s[/b]   [color=#888]%s[/color]\n[color=#aaa]%s[/color]" % [
		_bb_escape(data.ability_name),
		_bb_escape(entry.path),
		_bb_escape(data.description),
	]

	# Meta line: type, max level, damage stat, required class/weapon.
	var meta_parts: PackedStringArray = []
	meta_parts.append("type: [b]%s[/b]" % _enum_name("AbilityType", data.ability_type))
	meta_parts.append("max_level: %d" % data.max_level)
	meta_parts.append("damage_stat: %s" % _enum_name("StatType", data.damage_stat))
	if not data.required_class.is_empty():
		var class_names: PackedStringArray = []
		for c in data.required_class:
			class_names.append(_enum_name("ClassType", c))
		meta_parts.append("class: %s" % ", ".join(class_names))
	if not data.required_weapon_types.is_empty():
		var weap_names: PackedStringArray = []
		for w in data.required_weapon_types:
			weap_names.append(_enum_name("WeaponType", w))
		meta_parts.append("weapon: %s" % ", ".join(weap_names))
	_meta_label.text = "[color=#9fd]%s[/color]" % "    ".join(meta_parts)

	_populate_level_tree(data)
	_populate_breadcrumbs(data)


func _populate_level_tree(data: AbilityData) -> void:
	_level_tree.clear()
	var root := _level_tree.create_item()
	if data.scaling_data == null:
		var no_data_row := _level_tree.create_item(root)
		no_data_row.set_text(0, "(no scaling_data — Layer 1 numbers unavailable)")
		return
	for lv in range(1, data.max_level + 1):
		var stats: AbilityLevelData = data.get_level_stats(lv)
		if stats == null: continue
		var row := _level_tree.create_item(root)
		row.set_text(0, str(lv))
		row.set_text(1, str(stats.mana_cost))
		row.set_text(2, "%.2f" % stats.cooldown_time)
		row.set_text(3, "%d%%" % stats.damage_percent)
		row.set_text(4, str(stats.max_targets))
		row.set_text(5, str(stats.max_hits))
		row.set_text(6, "%.2f" % stats.cast_time)
		row.set_text(7, "%.0f%%" % (stats.status_effect_chance * 100.0))
		row.set_text(8, _format_stat_bonuses(stats.stat_bonuses))
		row.set_text(9, _format_proc_summary(stats))


func _format_stat_bonuses(stat_bonuses: Dictionary) -> String:
	if stat_bonuses.is_empty(): return "—"
	var parts: PackedStringArray = []
	for stat_type in stat_bonuses:
		var sd: StatData = stat_bonuses[stat_type]
		if sd == null: continue
		var flat := int(sd.flat_bonus_value)
		var pct := int(sd.percent_bonus_value)
		var label := _enum_name("StatType", stat_type)
		if pct != 0 and flat != 0:
			parts.append("%s +%d/+%d%%" % [label, flat, pct])
		elif pct != 0:
			parts.append("%s +%d%%" % [label, pct])
		else:
			parts.append("%s +%d" % [label, flat])
	return ", ".join(parts)


func _format_proc_summary(stats: AbilityLevelData) -> String:
	var parts: PackedStringArray = []
	for pair in [
		["on_hit", stats.on_hit_proc],
		["on_crit", stats.on_crit_proc],
		["on_kill", stats.on_kill_proc],
		["on_damaged", stats.on_damaged_proc],
		["on_dodge", stats.on_dodge_proc],
		["on_ability_cast", stats.on_ability_cast_proc],
	]:
		var name: String = pair[0]
		var proc: ProcEffectData = pair[1]
		if proc == null: continue
		parts.append("%s@%d%%/%dd" % [name, int(proc.proc_chance * 100), proc.damage_percent])
	return ", ".join(parts) if not parts.is_empty() else "—"


func _populate_breadcrumbs(data: AbilityData) -> void:
	for child in _breadcrumbs.get_children():
		child.queue_free()

	# Layer 2: active behavior + its logic_script.
	if data.active_behavior:
		var ab := data.active_behavior
		var ab_path: String = ab.resource_path if not ab.resource_path.is_empty() else "(inline)"
		_breadcrumbs.add_child(_make_breadcrumb_label("Layer 2 — Active behavior", Color(0.85, 0.7, 0.4)))
		_breadcrumbs.add_child(_make_kv_row("target_type", _enum_name("TargetType", ab.target_type)))
		_breadcrumbs.add_child(_make_kv_row("animation", ab.animation_name))
		_breadcrumbs.add_child(_make_kv_row("sfx", ab.sfx_path))
		_breadcrumbs.add_child(_make_kv_row("active_behavior path", ab_path))
		if ab.logic_script != null:
			_breadcrumbs.add_child(_make_script_row("logic_script", ab.logic_script))
		else:
			_breadcrumbs.add_child(_make_kv_row("logic_script", "—"))
		if ab.is_projectile:
			_breadcrumbs.add_child(_make_kv_row("projectile", "yes (speed %.0f)" % ab.projectile_speed))
	else:
		_breadcrumbs.add_child(_make_breadcrumb_label("Layer 2 — Active behavior: (none)", Color(0.6, 0.6, 0.6)))

	# Layer 3: proc / passive logic scripts referenced by level-1 data (the
	# script slot doesn't change per level, but the proc *chance/damage* do).
	_breadcrumbs.add_child(_make_breadcrumb_label("Layer 3 — Proc / passive logic", Color(0.85, 0.7, 0.4)))
	var stats_l1: AbilityLevelData = data.get_level_stats(1)
	var any_proc_script := false
	if stats_l1:
		for pair in [
			["on_hit_proc", stats_l1.on_hit_proc],
			["on_crit_proc", stats_l1.on_crit_proc],
			["on_kill_proc", stats_l1.on_kill_proc],
			["on_damaged_proc", stats_l1.on_damaged_proc],
			["on_dodge_proc", stats_l1.on_dodge_proc],
			["on_ability_cast_proc", stats_l1.on_ability_cast_proc],
		]:
			var label: String = pair[0]
			var proc: ProcEffectData = pair[1]
			if proc == null: continue
			if proc.logic_script:
				_breadcrumbs.add_child(_make_script_row(label, proc.logic_script))
				any_proc_script = true
			elif proc.execute_ability:
				_breadcrumbs.add_child(_make_kv_row(label, "executes ability: %s" % proc.execute_ability.ability_name))
			elif proc.apply_buff:
				_breadcrumbs.add_child(_make_kv_row(label, "applies buff: %s" % proc.apply_buff.resource_path))
		if stats_l1.passive_logic_script:
			_breadcrumbs.add_child(_make_script_row("passive_logic_script", stats_l1.passive_logic_script))
			any_proc_script = true
	if not any_proc_script:
		_breadcrumbs.add_child(_make_kv_row("—", "no proc / passive scripts"))

	# Companion buffs/debuffs.
	_breadcrumbs.add_child(_make_breadcrumb_label("Auxiliary", Color(0.85, 0.7, 0.4)))
	if data.applies_buff:
		_breadcrumbs.add_child(_make_kv_row("applies_buff", data.applies_buff.resource_path))
	if data.applies_target_debuff:
		_breadcrumbs.add_child(_make_kv_row("applies_target_debuff", data.applies_target_debuff.resource_path))
	if data.applies_buff == null and data.applies_target_debuff == null:
		_breadcrumbs.add_child(_make_kv_row("—", "no aux buffs"))


# --- UI helpers -------------------------------------------------------------

func _make_breadcrumb_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 12)
	return l


func _make_kv_row(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var k := Label.new()
	k.text = "  " + key
	k.custom_minimum_size = Vector2(170, 0)
	k.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	row.add_child(k)
	var v := Label.new()
	v.text = value if not value.is_empty() else "—"
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	return row


## Like _make_kv_row but with an "Open" button that opens the script in the
## editor — turns the Layer 2/3 breadcrumb into an actionable link.
func _make_script_row(key: String, script: Script) -> Control:
	var row := HBoxContainer.new()
	var k := Label.new()
	k.text = "  " + key
	k.custom_minimum_size = Vector2(170, 0)
	k.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	row.add_child(k)
	var v := Label.new()
	v.text = script.resource_path if not script.resource_path.is_empty() else "(inline script)"
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var btn := Button.new()
	btn.text = "Open"
	btn.disabled = script.resource_path.is_empty() or _editor_interface == null
	btn.pressed.connect(func(): _open_script(script))
	row.add_child(btn)
	return row


func _open_script(script: Script) -> void:
	if _editor_interface == null: return
	if script.resource_path.is_empty(): return
	_editor_interface.edit_resource(script)


# --- Misc helpers -----------------------------------------------------------

const _ConstantsScript := preload("res://scripts/Core/Enums/constants.gd")

func _enum_name(enum_key: String, value: int) -> String:
	# Look up by enum name. GDScript enums compile to script-level Dictionary
	# constants, so .find_key() does the int -> name reverse lookup. Direct
	# match keeps this robust against tool-context autoload weirdness.
	var enum_dict: Dictionary = {}
	match enum_key:
		"AbilityType": enum_dict = _ConstantsScript.AbilityType
		"StatType": enum_dict = _ConstantsScript.StatType
		"ClassType": enum_dict = _ConstantsScript.ClassType
		"WeaponType": enum_dict = _ConstantsScript.WeaponType
		"TargetType": enum_dict = _ConstantsScript.TargetType
		_: return str(value)
	var key = enum_dict.find_key(value)
	return String(key) if key != null else str(value)


func _bb_escape(text: String) -> String:
	return text.replace("[", "[lb]")


# --- Combat simulation ------------------------------------------------------

var _combat_tree: Tree = null
var _combat_class_dropdown: OptionButton = null
var _combat_class_hint: Label = null


func _build_combat_section() -> void:
	_detail_root.add_child(HSeparator.new())

	var header := Label.new()
	header.text = "Combat simulation"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.95, 0.88, 0.6))
	_detail_root.add_child(header)

	# Quick-level preset — sets player + target level together so the user can
	# walk the matchup up the ladder (1, 10, 20, ...) without typing into two
	# SpinBoxes each time.
	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 4)
	var quick_lab := Label.new()
	quick_lab.text = "Quick level:"
	quick_row.add_child(quick_lab)
	var quick := OptionButton.new()
	quick.add_item("(custom)", -1)
	for lv in [1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]:
		quick.add_item("Lv %d  vs  Lv %d" % [lv, lv], lv)
	quick.item_selected.connect(_on_quick_level_selected.bind(quick))
	quick_row.add_child(quick)
	_detail_root.add_child(quick_row)

	# Side-by-side panels for player vs target loadout, so the two sides of the
	# damage formula are visually distinct.
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 6)
	sides.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_root.add_child(sides)

	var ps := _make_section_panel("Player",
		Color(0.55, 0.75, 1.0), Color(0.16, 0.18, 0.24, 0.92))
	sides.add_child(ps.panel)
	var player_body: VBoxContainer = ps.body

	# --- Player: class row ---
	var class_row := HBoxContainer.new()
	class_row.add_theme_constant_override("separation", 4)
	var cl_lab := _stat_label("Class", 80)
	class_row.add_child(cl_lab)
	_combat_class_dropdown = OptionButton.new()
	_combat_class_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_combat_class_dropdown.item_selected.connect(func(_i): _on_class_changed())
	class_row.add_child(_combat_class_dropdown)
	player_body.add_child(class_row)

	_combat_class_hint = Label.new()
	_combat_class_hint.text = "primary/secondary: —"
	_combat_class_hint.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9))
	_combat_class_hint.add_theme_font_size_override("font_size", 11)
	player_body.add_child(_combat_class_hint)

	var player_grid := _make_input_grid()
	player_body.add_child(player_grid)

	# Defaults: a fresh level-1 character — base WeaponDisciplineData stats (4 each),
	# no equipment, no crit. Adjust upward to test gear / progression.
	_add_spinbox(player_grid, "player_level",     "Level",      1,     999,     1, 1)
	_add_spinbox(player_grid, "primary_stat",     "Primary",    0,    9999,     4, 1)
	_add_spinbox(player_grid, "secondary_stat",   "Secondary",  0,    9999,     4, 1)
	_add_spinbox(player_grid, "weapon_attack",    "WeaponAtk",  0,   99999,     0, 1)
	_add_spinbox(player_grid, "magic_attack",     "MagicAtk",   0,   99999,     0, 1)
	_add_spinbox(player_grid, "weapon_multiplier","Wpn Mult",   0.1,   3.0,   1.5, 0.05)
	_add_spinbox(player_grid, "mastery",          "Mastery",    0.0,   1.0,   0.2, 0.05)
	_add_spinbox(player_grid, "crit_chance",      "Crit %",     0.0, 100.0,   0.0, 1.0)
	_add_spinbox(player_grid, "crit_damage",      "CritDmg %",  0.0, 500.0,   0.0, 1.0)

	# --- Target panel ---
	var ts := _make_section_panel("Target",
		Color(1.0, 0.6, 0.55), Color(0.22, 0.16, 0.18, 0.92))
	sides.add_child(ts.panel)
	var target_body: VBoxContainer = ts.body

	var target_grid := _make_input_grid()
	target_body.add_child(target_grid)

	# Defaults: a level-1 enemy with no defense — the lowest-end matchup.
	_add_spinbox(target_grid, "target_level",   "Level",   1,     999,     1, 1)
	_add_spinbox(target_grid, "target_defense", "Defense", 0,  999999,     0, 1)

	# A bit of context inside the target panel so the difference is obvious at
	# a glance — these are the only two enemy-side inputs the combat formula
	# uses (see CombatComponent._execute_hit).
	var note := Label.new()
	note.text = "Hit% and level mod come from Player Lv − Target Lv.\nDefense reduction: 1 − DEF / (DEF + 500)."
	note.add_theme_color_override("font_color", Color(0.75, 0.7, 0.7))
	note.add_theme_font_size_override("font_size", 10)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target_body.add_child(note)

	# --- Results table ---
	var results_header := Label.new()
	results_header.text = "Per-level expected damage"
	results_header.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	_detail_root.add_child(results_header)

	_combat_tree = Tree.new()
	_combat_tree.columns = COMBAT_COLUMNS.size()
	_combat_tree.column_titles_visible = true
	_combat_tree.hide_root = true
	_combat_tree.allow_search = false
	_combat_tree.custom_minimum_size = Vector2(0, 200)
	_combat_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in COMBAT_COLUMNS.size():
		_combat_tree.set_column_title(i, COMBAT_COLUMNS[i])
		_combat_tree.set_column_clip_content(i, true)
	_detail_root.add_child(_combat_tree)


## Builds a titled section panel and returns refs to its outer PanelContainer
## and the inner body VBox where callers should add their inputs.
## Returns: { panel: PanelContainer, body: VBoxContainer }
func _make_section_panel(title: String, title_color: Color, bg_color: Color) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = title_color.darkened(0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	panel.add_child(outer)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", title_color)
	outer.add_child(title_label)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	outer.add_child(body)

	return {"panel": panel, "body": body}


func _make_input_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	return grid


func _stat_label(text: String, min_w: int = 72) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(min_w, 0)
	return l


func _add_spinbox(parent: GridContainer, key: String, label: String,
		min_v: float, max_v: float, default_v: float, step: float) -> void:
	var lab := Label.new()
	lab.text = label
	lab.custom_minimum_size = Vector2(80, 0)
	parent.add_child(lab)
	var sb := SpinBox.new()
	# Order matters: SpinBox's default step is 1, which can snap a fractional
	# default (e.g. mastery=0.2) down to 0 if value is set before step.
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = step
	sb.value = default_v
	sb.allow_greater = false
	sb.allow_lesser = false
	sb.custom_minimum_size = Vector2(70, 0)
	sb.value_changed.connect(func(_v): _recompute_combat())
	parent.add_child(sb)
	_loadout_widgets[key] = sb


func _populate_class_dropdown() -> void:
	if _combat_class_dropdown == null: return
	var prev_idx: int = _combat_class_dropdown.get_selected()
	var prev_text: String = _combat_class_dropdown.get_item_text(prev_idx) if prev_idx >= 0 else ""
	_combat_class_dropdown.clear()
	var class_types: Array = _classes.keys()
	class_types.sort()
	for ct in class_types:
		var c: Dictionary = _classes[ct]
		_combat_class_dropdown.add_item(c.name, ct)
	# Restore prior selection.
	for i in _combat_class_dropdown.item_count:
		if _combat_class_dropdown.get_item_text(i) == prev_text:
			_combat_class_dropdown.select(i)
			break
	_on_class_changed()


## Quick-level preset: sets player + target SpinBoxes to the same level. The
## SpinBox.value_changed signals fire _recompute_combat() automatically.
func _on_quick_level_selected(idx: int, dropdown: OptionButton) -> void:
	var lv: int = dropdown.get_item_id(idx)
	if lv <= 0: return
	if _loadout_widgets.has("player_level"):
		_loadout_widgets.player_level.value = lv
	if _loadout_widgets.has("target_level"):
		_loadout_widgets.target_level.value = lv


func _on_class_changed() -> void:
	if _combat_class_dropdown == null: return
	if _combat_class_dropdown.item_count == 0:
		_combat_class_hint.text = "  (no WeaponDisciplineData found in %s)" % CLASSES_ROOT
		return
	var ct: int = _combat_class_dropdown.get_item_id(_combat_class_dropdown.get_selected())
	var c: Dictionary = _classes.get(ct, {})
	if c.is_empty():
		_combat_class_hint.text = "  primary/secondary: —"
	else:
		_combat_class_hint.text = "  primary: %s   secondary: %s" % [
			_enum_name("StatType", c.primary),
			_enum_name("StatType", c.secondary),
		]
	_recompute_combat()


## Re-runs the damage formula for the currently selected ability against the
## currently configured loadout/target, filling _combat_tree row-by-row. No
## ability or class data -> renders an explanatory row.
func _recompute_combat() -> void:
	if _combat_tree == null: return
	_combat_tree.clear()
	var root := _combat_tree.create_item()
	if _selected_ability == null:
		var r := _combat_tree.create_item(root)
		r.set_text(0, "(select an ability above)")
		return
	if _selected_ability.scaling_data == null:
		var r := _combat_tree.create_item(root)
		r.set_text(0, "(no scaling_data on this ability)")
		return
	if _selected_ability.ability_type == _ConstantsScript.AbilityType.PASSIVE:
		var r := _combat_tree.create_item(root)
		r.set_text(0, "(passive — no direct damage; see Layer-1 table for stat bonuses)")
		return

	# Pull loadout values.
	var player_level: int = int(_loadout_widgets.player_level.value)
	var target_level: int = int(_loadout_widgets.target_level.value)
	var primary: int = int(_loadout_widgets.primary_stat.value)
	var secondary: int = int(_loadout_widgets.secondary_stat.value)
	var weapon_attack: int = int(_loadout_widgets.weapon_attack.value)
	var magic_attack: int = int(_loadout_widgets.magic_attack.value)
	var weapon_mult: float = _loadout_widgets.weapon_multiplier.value
	var mastery: float = _loadout_widgets.mastery.value
	var crit_chance: float = _loadout_widgets.crit_chance.value
	var crit_damage_pct: float = _loadout_widgets.crit_damage.value
	var target_defense: int = int(_loadout_widgets.target_defense.value)

	# Damage stat for THIS ability (Layer-1 value; CombatComponent uses this in
	# _calculate_max_range for ability damage).
	var dmg_stat: int = _selected_ability.damage_stat
	var attack_power: int = magic_attack if dmg_stat == _ConstantsScript.StatType.MAGICATTACK \
		else weapon_attack

	# Mirror the combat formula at each level.
	var level_diff: int = player_level - target_level
	var hit_chance: float = clampf(95.0 + (level_diff * HIT_CHANCE_PER_LEVEL_DIFF), 5.0, 100.0)
	var level_mod: float = clampf(1.0 + (level_diff * LEVEL_MOD_PER_LEVEL_DIFF), LEVEL_MOD_MIN, LEVEL_MOD_MAX)
	var defense_mult: float = 1.0 - (float(target_defense) / (target_defense + DEFENSE_DENOM))
	# Average crit multiplier = mid of randf_range(1.2, 1.5) + critDamage%/100.
	var avg_crit_mult: float = 1.35 + (crit_damage_pct / 100.0)
	var crit_p: float = clampf(crit_chance / 100.0, 0.0, 1.0)

	# _calculate_max_range (without per-level damage_percent yet).
	var stat_mult: float = (primary * 4 + secondary)
	var max_range_base: float = weapon_mult * stat_mult * attack_power / 100.0

	for lv in range(1, _selected_ability.max_level + 1):
		var stats: AbilityLevelData = _selected_ability.get_level_stats(lv)
		if stats == null: continue
		# Apply ability damage_percent.
		var max_dmg_raw: float = max_range_base * (stats.damage_percent / 100.0)
		var min_dmg_raw: float = max_dmg_raw * mastery
		# Apply level + defense multipliers (CombatComponent applies these post-roll).
		var min_dmg_eff: float = min_dmg_raw * level_mod * defense_mult
		var max_dmg_eff: float = max_dmg_raw * level_mod * defense_mult
		# Expected damage per hit, factoring crit chance.
		var avg_dmg_no_crit: float = (min_dmg_eff + max_dmg_eff) * 0.5
		var avg_dmg_with_crit: float = avg_dmg_no_crit * (1.0 - crit_p) + avg_dmg_no_crit * avg_crit_mult * crit_p
		# Expected outcome accounting for hit chance.
		var expected_avg: float = avg_dmg_with_crit * (hit_chance / 100.0)
		# Multiply by max_hits — the ability hits the same target multiple times.
		var max_hits: int = max(1, stats.max_hits)

		var row := _combat_tree.create_item(root)
		row.set_text(0, str(lv))
		row.set_text(1, _enum_name("StatType", dmg_stat))
		row.set_text(2, "%d" % int(min_dmg_eff * max_hits))
		row.set_text(3, "%d" % int(max_dmg_eff * max_hits))
		row.set_text(4, "%d" % int(avg_dmg_with_crit * max_hits))
		row.set_text(5, "%.0f%%" % hit_chance)
		row.set_text(6, "%d" % int(expected_avg * max_hits))
