@tool
class_name DisciplineBoard
extends Window

## Discipline-wide skill-tree placement board (grilled 2026-06-06). Shows every
## ability of one weapon discipline arranged on a 2-path grid (Path A / Path B)
## by tree_path/tree_depth, mirroring the in-game skill-tree window. Drag a node
## to set its placement; the board flags collisions + climb-gate gaps and shows
## a point-economy budget panel (full-clear cost vs the 100-pt mastery cap).
##
## Discipline membership = required_class[0] mapped to a discipline key, matching
## ability_window.gd._ability_discipline_key so the board groups exactly like the
## live tree.

const MASTERY_POOL_CAP := 100  # WeaponMasteryComponent.MASTERY_CAP * 1 pt/level
const BUILD_TARGET_PCT := 70   # progression target: build completes ~70% to cap

const C_DARK   = Color(0.11, 0.12, 0.15)
const C_CARD   = Color(0.15, 0.16, 0.19)
const C_BORDER = Color(0.22, 0.24, 0.30)
const C_DIM    = Color(0.50, 0.53, 0.60)
const C_TEXT   = Color(0.88, 0.88, 0.90)
const C_OK     = Color(0.42, 0.85, 0.52)
const C_WARN   = Color(0.95, 0.75, 0.30)
const C_ERR    = Color(1.00, 0.35, 0.35)
const C_ACCENT = Color(0.75, 0.48, 1.00)

const NODE_W := 150.0
const NODE_H := 46.0
const ROW_H := 64.0
const COL_GAP := 40.0
const TOP_MARGIN := 16.0
const LEFT_MARGIN := 20.0

# Column index: 0 = Unplaced (-1), 1 = Path A (0), 2 = Path B (1)
const COL_FOR_PATH := {-1: 0, 0: 1, 1: 2}
const PATH_FOR_COL := {0: -1, 1: 0, 2: 1}

var _disc_option: OptionButton
var _canvas: Control
var _budget_label: RichTextLabel
var _warn_label: RichTextLabel
var _status: Label
var _save_btn: Button

var _all: Array = []        # [{res, path, disc}]
var _node_panels: Array = []  # [{panel, res}]
var _changed: Dictionary = {} # AbilityData -> true (needs save)

var _drag_panel: Panel = null
var _drag_offset := Vector2.ZERO

# discipline key -> ClassType ids that belong to it
const DISC_KEYS := ["sword", "bow", "staff", "dagger"]


func _init() -> void:
	title = "Discipline Tree Board"
	size = Vector2i(900, 680)
	min_size = Vector2i(640, 480)
	close_requested.connect(hide)
	_build_chrome()


func _build_chrome() -> void:
	var root := PanelContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	var root_sb := StyleBoxFlat.new()
	root_sb.bg_color = C_DARK
	root.add_theme_stylebox_override("panel", root_sb)
	add_child(root)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	root.add_child(outer)

	# Toolbar
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	outer.add_child(bar)
	var dl := Label.new()
	dl.text = "Discipline"
	dl.add_theme_color_override("font_color", C_DIM)
	bar.add_child(dl)
	_disc_option = OptionButton.new()
	for k in DISC_KEYS:
		_disc_option.add_item(k.capitalize())
	_disc_option.item_selected.connect(func(_i): _populate())
	bar.add_child(_disc_option)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_status = Label.new()
	_status.add_theme_color_override("font_color", C_DIM)
	_status.add_theme_font_size_override("font_size", 11)
	bar.add_child(_status)
	_save_btn = Button.new()
	_save_btn.text = "Save Placements"
	_save_btn.pressed.connect(_on_save_pressed)
	bar.add_child(_save_btn)
	var rescan := Button.new()
	rescan.text = "Rescan"
	rescan.pressed.connect(func(): _scan(); _populate())
	bar.add_child(rescan)

	# Body: canvas (left) + budget/warn panel (right)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 600
	outer.add_child(split)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(560, 1200)
	_canvas.draw.connect(_on_canvas_draw)
	scroll.add_child(_canvas)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(260, 0)
	side.add_theme_constant_override("separation", 10)
	split.add_child(side)

	var bt := Label.new()
	bt.text = "POINT ECONOMY"
	bt.add_theme_font_size_override("font_size", 11)
	bt.add_theme_color_override("font_color", C_ACCENT)
	side.add_child(bt)
	_budget_label = RichTextLabel.new()
	_budget_label.bbcode_enabled = true
	_budget_label.fit_content = true
	_budget_label.custom_minimum_size = Vector2(0, 160)
	side.add_child(_budget_label)

	var wt := Label.new()
	wt.text = "PLACEMENT ISSUES"
	wt.add_theme_font_size_override("font_size", 11)
	wt.add_theme_color_override("font_color", C_WARN)
	side.add_child(wt)
	_warn_label = RichTextLabel.new()
	_warn_label.bbcode_enabled = true
	_warn_label.fit_content = true
	_warn_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_warn_label)


# ── Public ───────────────────────────────────────────────────────────────────
func open() -> void:
	_scan()
	if _disc_option.selected < 0:
		_disc_option.selected = 0
	_populate()
	popup_centered()


# ── Scan ─────────────────────────────────────────────────────────────────────
func _scan() -> void:
	_all.clear()
	_scan_dir("res://resources/Abilities")


func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := path.path_join(f)
		if dir.current_is_dir():
			if not f.begins_with("."):
				_scan_dir(full)
		elif f.ends_with(".tres"):
			var res = load(full)
			if res is AbilityData:
				_all.append({"res": res, "path": full, "disc": _disc_key(res)})
		f = dir.get_next()
	dir.list_dir_end()


func _disc_key(ability: AbilityData) -> String:
	if ability.required_class == null or ability.required_class.is_empty():
		return ""
	match ability.required_class[0]:
		Constants.ClassType.SWORD, Constants.ClassType.CRUSADER: return "sword"
		Constants.ClassType.BOW, Constants.ClassType.RANGER: return "bow"
		Constants.ClassType.STAFF, Constants.ClassType.ARCHMAGE: return "staff"
		Constants.ClassType.DAGGER, Constants.ClassType.ASSASSIN: return "dagger"
	return ""


# ── Populate / layout ────────────────────────────────────────────────────────
func _current_key() -> String:
	var i := _disc_option.selected
	return DISC_KEYS[i] if i >= 0 and i < DISC_KEYS.size() else "sword"


func _populate() -> void:
	for n in _node_panels:
		if is_instance_valid(n.panel):
			n.panel.queue_free()
	_node_panels.clear()

	var key := _current_key()
	for entry in _all:
		if entry.disc != key:
			continue
		_make_node(entry.res)

	_relayout()
	_recompute()
	_status.text = "%d abilities" % _node_panels.size()


func _make_node(res: AbilityData) -> void:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(NODE_W, NODE_H)
	panel.size = Vector2(NODE_W, NODE_H)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.set_border_width_all(1)
	sb.border_color = C_BORDER
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_meta("res", res)
	panel.set_meta("sb", sb)

	var vb := VBoxContainer.new()
	vb.anchor_right = 1.0
	vb.offset_left = 8
	vb.offset_top = 5
	vb.offset_right = -8
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)
	var nm := Label.new()
	nm.text = res.ability_name if not res.ability_name.is_empty() else "(unnamed)"
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", C_TEXT)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)
	var sub := Label.new()
	var up_count: int = res.upgrades.size() if res.upgrades != null else 0
	sub.text = "Lv %d • %d upg" % [res.max_level, up_count]
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", C_DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sub)

	panel.gui_input.connect(_on_node_input.bind(panel))
	_canvas.add_child(panel)
	_node_panels.append({"panel": panel, "res": res})


func _col_x(col: int) -> float:
	return LEFT_MARGIN + col * (NODE_W + COL_GAP)


func _relayout() -> void:
	# Track occupancy per (col, depth) to fan out collisions visually.
	var slot_count := {}
	# Stable order: by depth so stacking is deterministic.
	var ordered := _node_panels.duplicate()
	ordered.sort_custom(func(a, b): return int(a.res.tree_depth) < int(b.res.tree_depth))
	for n in ordered:
		var res: AbilityData = n.res
		var col: int = COL_FOR_PATH.get(res.tree_path, 0)
		var depth: int = maxi(0, int(res.tree_depth))
		var slot_key := "%d:%d" % [col, depth]
		var dup_idx: int = slot_count.get(slot_key, 0)
		slot_count[slot_key] = dup_idx + 1
		var x := _col_x(col) + dup_idx * 16.0
		var y := TOP_MARGIN + depth * ROW_H + dup_idx * 16.0
		n.panel.position = Vector2(x, y)
	_canvas.queue_redraw()


func _on_canvas_draw() -> void:
	var font := ThemeDB.fallback_font
	var titles := ["Unplaced", "Path A", "Path B"]
	for col in range(3):
		var x := _col_x(col)
		var color := C_DIM if col == 0 else C_ACCENT
		_canvas.draw_string(font, Vector2(x, 12), titles[col], HORIZONTAL_ALIGNMENT_LEFT, NODE_W, 13, color)
		# subtle column guide
		if col > 0:
			_canvas.draw_line(Vector2(x - COL_GAP / 2, 20), Vector2(x - COL_GAP / 2, 1180), Color(C_BORDER, 0.4), 1.0)


# ── Drag ─────────────────────────────────────────────────────────────────────
func _on_node_input(event: InputEvent, panel: Panel) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_panel = panel
			_drag_offset = panel.get_local_mouse_position()
			panel.move_to_front()
		elif _drag_panel == panel:
			_commit_drag(panel)
			_drag_panel = null
	elif event is InputEventMouseMotion and _drag_panel == panel:
		panel.position += event.relative


func _commit_drag(panel: Panel) -> void:
	var res: AbilityData = panel.get_meta("res")
	var center := panel.position + Vector2(NODE_W, NODE_H) / 2.0
	# Nearest column.
	var best_col := 0
	var best_dx := INF
	for col in range(3):
		var cx := _col_x(col) + NODE_W / 2.0
		var dx: float = absf(center.x - cx)
		if dx < best_dx:
			best_dx = dx
			best_col = col
	var new_path: int = PATH_FOR_COL[best_col]
	var new_depth: int = maxi(0, int(round((center.y - TOP_MARGIN - NODE_H / 2.0) / ROW_H)))
	if int(res.tree_path) != new_path or int(res.tree_depth) != new_depth:
		res.tree_path = new_path
		res.tree_depth = new_depth
		_changed[res] = true
	_relayout()
	_recompute()


# ── Budget + warnings ────────────────────────────────────────────────────────
func _recompute() -> void:
	var leveling := 0
	var upgrades := 0
	for n in _node_panels:
		var res: AbilityData = n.res
		leveling += int(res.max_level)
		if res.upgrades != null:
			for u in res.upgrades:
				if u is AbilityUpgradeData:
					upgrades += int(u.point_cost)
	var full_clear := leveling + upgrades
	var coverage := 100 if full_clear == 0 else mini(100, int(round(100.0 * MASTERY_POOL_CAP / float(full_clear))))

	var b := ""
	b += "[color=#cfd2da]Abilities:[/color] %d\n" % _node_panels.size()
	b += "[color=#cfd2da]Leveling cost:[/color] %d pt\n" % leveling
	b += "[color=#cfd2da]Upgrades cost:[/color] %d pt\n" % upgrades
	b += "[color=#ffffff]Full-clear:[/color] [b]%d pt[/b]\n" % full_clear
	b += "[color=#cfd2da]Mastery pool (cap):[/color] %d pt\n" % MASTERY_POOL_CAP
	b += "[color=#cfd2da]Coverage at cap:[/color] %d%%\n" % coverage
	var target := int(round(MASTERY_POOL_CAP * BUILD_TARGET_PCT / 100.0))
	b += "[color=#7d8088]Build target ≈%d pt (%d%%); refine %d→%d[/color]" % [target, BUILD_TARGET_PCT, target, MASTERY_POOL_CAP]
	_budget_label.text = b

	var warns: Array[String] = []
	if full_clear <= MASTERY_POOL_CAP and full_clear > 0:
		warns.append("[color=#f2bf4d]⚠ A maxed character can buy 100%% of this discipline (full-clear %d ≤ %d) — no build opportunity cost.[/color]" % [full_clear, MASTERY_POOL_CAP])
	if full_clear > MASTERY_POOL_CAP * 3:
		warns.append("[color=#f2bf4d]⚠ Full-clear is %.1f× the pool — content may feel unreachable.[/color]" % (full_clear / float(MASTERY_POOL_CAP)))

	# Placement: collisions + climb-gate gaps.
	var occ := {}             # "path:depth" -> [names]
	var depths_by_path := {0: {}, 1: {}}
	for n in _node_panels:
		var res: AbilityData = n.res
		if res.tree_path != 0 and res.tree_path != 1:
			continue
		var slot := "%d:%d" % [res.tree_path, res.tree_depth]
		if not occ.has(slot):
			occ[slot] = []
		occ[slot].append(res.ability_name)
		depths_by_path[res.tree_path][int(res.tree_depth)] = true
	for slot in occ:
		if occ[slot].size() > 1:
			warns.append("[color=#ff5959]✕ Collision @ %s: %s[/color]" % [slot, ", ".join(occ[slot])])
	for p in [0, 1]:
		var depths: Array = depths_by_path[p].keys()
		depths.sort()
		for d in depths:
			if d > 0 and not depths_by_path[p].has(d - 1):
				warns.append("[color=#f2bf4d]⚠ Path %s depth %d has no depth %d above it (climb-gate gap).[/color]" % ["A" if p == 0 else "B", d, d - 1])

	var unplaced := 0
	for n in _node_panels:
		if int(n.res.tree_path) == -1:
			unplaced += 1
	if unplaced > 0:
		warns.append("[color=#7d8088]%d ability(ies) unplaced (hidden from the in-game tree).[/color]" % unplaced)

	_warn_label.text = "\n".join(warns) if not warns.is_empty() else "[color=#6bd97f]✓ No placement issues.[/color]"
	_save_btn.text = "Save Placements (%d)" % _changed.size() if not _changed.is_empty() else "Save Placements"


func _on_save_pressed() -> void:
	var saved := 0
	for res in _changed.keys():
		var ability := res as AbilityData
		if ability == null:
			continue
		var path: String = ability.resource_path
		if path.is_empty():
			continue
		if ResourceSaver.save(ability, path) == OK:
			saved += 1
	_changed.clear()
	_status.text = "Saved %d placement(s)" % saved
	_recompute()
