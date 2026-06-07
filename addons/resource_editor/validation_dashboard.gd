@tool
class_name ValidationDashboard
extends Control

## Live, in-editor "Problems" panel (grilled 2026-06-06). Scans every resource and
## surfaces authoring errors that otherwise only show up at runtime or in the
## offline ability-reference report: broken icon refs, orphan upgrade .tres,
## effect_keys with no code consumer, lone variant_groups, dead prerequisites,
## untreed abilities, empty names. Double-click a row to jump to it in the dock.

signal jump_requested(path: String)

const C_DARK = Color(0.11, 0.12, 0.15)
const C_DIM  = Color(0.50, 0.53, 0.60)
const C_TEXT = Color(0.88, 0.88, 0.90)
const C_OK   = Color(0.42, 0.85, 0.52)
const C_WARN = Color(0.95, 0.75, 0.30)
const C_ERR  = Color(1.00, 0.35, 0.35)

# severity: 0 = error, 1 = warning, 2 = info
const SEV_LABEL := {0: "ERRORS", 1: "WARNINGS", 2: "INFO"}
const SEV_COLOR := {0: C_ERR, 1: C_WARN, 2: C_DIM}

var _tree: Tree
var _summary: Label
var _problems: Array = []  # [{sev, msg, path}]


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
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

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	col.add_child(bar)
	_summary = Label.new()
	_summary.add_theme_color_override("font_color", C_DIM)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_summary)
	var rescan := Button.new()
	rescan.text = "Rescan"
	rescan.pressed.connect(rescan_and_show)
	bar.add_child(rescan)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.item_activated.connect(_on_item_activated)
	col.add_child(_tree)

	var hint := Label.new()
	hint.text = "Double-click a problem to open the resource."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", C_DIM)
	col.add_child(hint)


func refresh() -> void:
	rescan_and_show()


func rescan_and_show() -> void:
	EffectKeyScanner.invalidate()
	_problems.clear()
	_scan_abilities_and_upgrades()
	_scan_simple("res://resources/Items", "icon", ["name"])
	_scan_simple("res://resources/Buffs", "buff_icon", ["buff_name", "name"])
	_scan_simple("res://resources/Enemies", "", ["monster_name"])
	_rebuild_tree()


# ── Abilities + upgrades (the rich checks) ───────────────────────────────────
func _scan_abilities_and_upgrades() -> void:
	var abilities: Array = []      # [{res, path}]
	var all_upgrade_paths := {}    # path -> true (every AbilityUpgradeData on disk)
	var referenced_paths := {}     # path -> true (referenced by some ability)
	_collect_ability_dir("res://resources/Abilities", abilities, all_upgrade_paths)

	for entry in abilities:
		var a: AbilityData = entry.res
		var path: String = entry.path
		if a.ability_icon == null:
			_add(1, "Ability '%s' has no icon" % _nm(a.ability_name), path)
		if a.required_class == null or a.required_class.is_empty():
			_add(1, "Ability '%s' has no required_class (hidden from every discipline)" % _nm(a.ability_name), path)
		if int(a.tree_path) == -1:
			_add(2, "Ability '%s' is unplaced in the skill tree (tree_path = -1)" % _nm(a.ability_name), path)
		# prerequisites
		if a.prerequisite_abilities != null:
			for k in a.prerequisite_abilities:
				if k == null:
					_add(0, "Ability '%s' has a null prerequisite entry" % _nm(a.ability_name), path)
		# upgrades
		var tier3_groups := {}
		if a.upgrades != null:
			for u in a.upgrades:
				if u == null:
					_add(0, "Ability '%s' has a null upgrade ref" % _nm(a.ability_name), path)
					continue
				if not (u is AbilityUpgradeData):
					continue
				if not u.resource_path.is_empty():
					referenced_paths[u.resource_path] = true
				if u.effect_key.is_empty():
					_add(1, "Upgrade '%s' (%s) has an empty effect_key (no-op)" % [_nm(u.upgrade_name), _nm(a.ability_name)], path)
				elif not EffectKeyScanner.has_consumer(u.effect_key):
					_add(1, "Upgrade '%s' effect_key '%s' has no consumer in code" % [_nm(u.upgrade_name), u.effect_key], path)
				if int(u.tier) == 3:
					if u.variant_group.is_empty():
						_add(1, "T3 variant '%s' (%s) has no variant_group" % [_nm(u.upgrade_name), _nm(a.ability_name)], path)
					else:
						tier3_groups[u.variant_group] = tier3_groups.get(u.variant_group, 0) + 1
		for g in tier3_groups:
			if tier3_groups[g] < 2:
				_add(1, "Variant group '%s' (%s) has a lone variant (mutex needs ≥2)" % [g, _nm(a.ability_name)], path)

	# Orphan upgrade .tres (on disk but referenced by no ability).
	for up_path in all_upgrade_paths:
		if not referenced_paths.has(up_path):
			_add(1, "Orphan upgrade .tres (referenced by no ability)", up_path)


func _collect_ability_dir(path: String, abilities: Array, all_upgrade_paths: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := path.path_join(f)
		if dir.current_is_dir():
			if not f.begins_with("."):
				_collect_ability_dir(full, abilities, all_upgrade_paths)
		elif f.ends_with(".tres"):
			var res = load(full)
			if res is AbilityData:
				abilities.append({"res": res, "path": full})
			elif res is AbilityUpgradeData:
				all_upgrade_paths[full] = true
		f = dir.get_next()
	dir.list_dir_end()


# ── Generic icon/name checks for other resource types ────────────────────────
func _scan_simple(root: String, icon_prop: String, name_props: Array) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := root.path_join(f)
		if dir.current_is_dir():
			if not f.begins_with("."):
				_scan_simple(full, icon_prop, name_props)
		elif f.ends_with(".tres"):
			var res = load(full)
			if res is Resource:
				_check_simple(res, full, icon_prop, name_props)
		f = dir.get_next()
	dir.list_dir_end()


func _check_simple(res: Resource, path: String, icon_prop: String, name_props: Array) -> void:
	var label := path.get_file()
	# name emptiness (first matching property that exists)
	for np in name_props:
		if np in res:
			var v = res.get(np)
			if v == null or str(v).strip_edges().is_empty():
				_add(1, "%s has an empty %s" % [label, np])
			else:
				label = str(v)
			break
	if not icon_prop.is_empty() and icon_prop in res:
		if res.get(icon_prop) == null:
			_add(1, "%s has no %s" % [label, icon_prop], path)


# ── Tree build ───────────────────────────────────────────────────────────────
func _rebuild_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var by_sev := {0: [], 1: [], 2: []}
	for p in _problems:
		by_sev[p.sev].append(p)
	var total_err: int = by_sev[0].size()
	var total_warn: int = by_sev[1].size()
	var total_info: int = by_sev[2].size()
	for sev in [0, 1, 2]:
		var group: Array = by_sev[sev]
		if group.is_empty():
			continue
		var ghead := _tree.create_item(root)
		ghead.set_text(0, "%s (%d)" % [SEV_LABEL[sev], group.size()])
		ghead.set_custom_color(0, SEV_COLOR[sev])
		ghead.set_selectable(0, false)
		for p in group:
			var it := _tree.create_item(ghead)
			var suffix := ""
			if not str(p.path).is_empty():
				suffix = "   [%s]" % str(p.path).get_file()
			it.set_text(0, p.msg + suffix)
			it.set_custom_color(0, C_TEXT if sev != 0 else C_ERR)
			it.set_metadata(0, p.path)

	if _problems.is_empty():
		var ok := _tree.create_item(root)
		ok.set_text(0, "✓ No problems found.")
		ok.set_custom_color(0, C_OK)
		ok.set_selectable(0, false)

	_summary.text = "%d error(s) • %d warning(s) • %d info" % [total_err, total_warn, total_info]


func _on_item_activated() -> void:
	var sel := _tree.get_selected()
	if sel == null:
		return
	var path = sel.get_metadata(0)
	if path is String and not path.is_empty():
		jump_requested.emit(path)


# ── Helpers ──────────────────────────────────────────────────────────────────
func _add(sev: int, msg: String, path: String = "") -> void:
	_problems.append({"sev": sev, "msg": msg, "path": path})


func _nm(s: String) -> String:
	return s if not s.strip_edges().is_empty() else "(unnamed)"
