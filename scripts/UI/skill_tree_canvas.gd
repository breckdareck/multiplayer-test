extends Control

## Skill-tree v2 canvas — Layout A (one path at a time). For the active path it
## renders a free PASSIVES section (no gate) and a chained ACTIVES section, with
## every ability's UPGRADE tree (T1 -> T2 -> T3 variant fan) branching off it as
## D4-style nodes. A Vanguard|Berserker toggle swaps paths. Emits node_selected
## (kind = "ability" | "upgrade") so the window's right panel drives detail + the
## learn/level/buy action. Resolved by path (no class_name) to dodge cache staleness.

signal node_selected(kind: String, ability_id: String, upgrade_id: String)

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const NODE_SCRIPT := preload("res://scripts/UI/skill_tree_node.gd")

const PATH_NAMES := {
	"sword": ["Vanguard", "Berserker"], "bow": ["Marksman", "Skirmisher"],
	"staff": ["Elementalist", "Sage"], "dagger": ["Assassin", "Venomancer"],
}

# Layout (px)
const PAD := 14
const NODE_W := 186
const NODE_H := 48
const UPG_W := 102
const UPG_H := 28
const UPG_VGAP := 7
const X_T1 := 220   # PAD + NODE_W + 20
const X_T2 := 338
const X_T3 := 456
const PASS_ROW := 52
const ACT_ROW := 104
const TOP := 44

# Node states
const ST_LOCKED := 0
const ST_AVAIL := 1
const ST_OWNED := 2
const ST_MAX := 3

const C_OWNED := Color(0.36, 0.74, 1.0)
const C_MAX := Color(0.95, 0.80, 0.30)
const C_AVAIL := Color(0.82, 0.85, 0.92)
const C_LOCKED := Color(0.32, 0.32, 0.38)
const C_SELECT := Color(1.0, 0.95, 0.45)
const C_PASS := Color(0.42, 0.86, 0.62)
const C_UPG := Color(0.86, 0.70, 0.34)
const C_BG := Color(0.11, 0.11, 0.14, 0.97)
const C_BG_LOCKED := Color(0.07, 0.07, 0.09, 0.92)

var _comp
var _disc := ""
var _path := 0
var _abilities: Array = []
var _sel_ability := ""
var _sel_upgrade := ""
var _lines: Array = []   # [Vector2 from, Vector2 to, Color]


## abilities = ALL placed abilities for the discipline (both paths); the canvas
## shows only the active _path.
func populate(comp, abilities: Array, disc: String) -> void:
	_comp = comp
	_abilities = abilities
	_disc = disc
	_rebuild()


func set_path(p: int) -> void:
	if p == _path:
		return
	_path = clampi(p, 0, 1)
	_rebuild()


func get_active_path() -> int:
	return _path


## Called by the window to sync the highlight after it processes a selection.
## Also switches to the selected ability's path so the node is on screen.
func select_node(kind: String, ability_id: String, upgrade_id: String) -> void:
	_sel_ability = ability_id
	_sel_upgrade = upgrade_id if kind == "upgrade" else ""
	for a in _abilities:
		if a != null and a.ability_id == ability_id:
			_path = a.tree_path
			break
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_lines.clear()
	if _comp == null:
		return

	_build_toggle()

	var act: Array = []
	var pas: Array = []
	for a in _abilities:
		if a == null or a.tree_path != _path:
			continue
		if a.ability_type == Constants.AbilityType.PASSIVE:
			pas.append(a)
		else:
			act.append(a)
	act.sort_custom(func(x, b): return x.tree_depth < b.tree_depth)
	pas.sort_custom(func(x, b): return x.tree_depth < b.tree_depth)

	var y: int = TOP
	_section_label(y, "PASSIVES", C_PASS)
	y += 22
	for p in pas:
		_ability_row(p, y)
		y += PASS_ROW
	y += 10

	_section_label(y, "ACTIVES", C_AVAIL)
	y += 22
	var prev_cy: int = -1
	for i in act.size():
		@warning_ignore("integer_division")
		var cy: int = y + NODE_H / 2
		if prev_cy >= 0:
			var owned: bool = _comp.get_ability_level(act[i - 1].ability_id) >= 1
			@warning_ignore("integer_division")
			_lines.append([Vector2(PAD + 22, prev_cy + NODE_H / 2), Vector2(PAD + 22, cy - NODE_H / 2), C_OWNED if owned else C_LOCKED])
		_ability_row(act[i], y)
		prev_cy = cy
		y += ACT_ROW

	custom_minimum_size = Vector2(X_T3 + UPG_W + PAD + 6, y + 12)
	queue_redraw()


func _build_toggle() -> void:
	var names: Array = PATH_NAMES.get(_disc, ["Path A", "Path B"])
	for p in [0, 1]:
		var on: bool = (p == _path)
		var btn := Button.new()
		btn.position = Vector2(PAD + p * 128, 8)
		btn.custom_minimum_size = Vector2(124, 26)
		btn.size = Vector2(124, 26)
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = str(names[p]) if p < names.size() else "Path %d" % (p + 1)
		btn.add_theme_font_override("font", FONT)
		btn.add_theme_font_size_override("font_size", 12)
		var sb := _sbox(Color(0.2, 0.18, 0.08) if on else C_BG_LOCKED, C_MAX if on else C_LOCKED, 2)
		for s in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(s, sb)
		btn.add_theme_color_override("font_color", C_MAX if on else Color(0.6, 0.6, 0.65))
		var pi: int = p
		btn.pressed.connect(func(): set_path(pi))
		add_child(btn)


func _section_label(y: int, txt: String, col: Color) -> void:
	var l := Label.new()
	l.position = Vector2(PAD, y)
	l.size = Vector2(360, 20)
	l.text = txt
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


func _ability_row(a, y: int) -> void:
	var level: int = _comp.get_ability_level(a.ability_id)
	var unlocked: bool = _comp.is_tree_node_unlocked(a.ability_id)
	var state: int = ST_LOCKED
	if level >= a.max_level and level > 0:
		state = ST_MAX
	elif level > 0:
		state = ST_OWNED
	elif unlocked:
		state = ST_AVAIL

	var node: Button = NODE_SCRIPT.new()
	node.ability_data = a
	node.current_level = level
	node.position = Vector2(PAD, y)
	node.custom_minimum_size = Vector2(NODE_W, NODE_H)
	node.size = Vector2(NODE_W, NODE_H)
	node.focus_mode = Control.FOCUS_NONE
	node.modulate = Color(1, 1, 1, 0.6) if state == ST_LOCKED else Color(1, 1, 1, 1)
	_style(node, _state_color(state), state == ST_LOCKED, _sel_ability == a.ability_id and _sel_upgrade == "")
	var aid: String = a.ability_id
	node.pressed.connect(func(): node_selected.emit("ability", aid, ""))
	add_child(node)

	var icon := TextureRect.new()
	icon.texture = a.ability_icon
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(6, 8)
	icon.size = Vector2(32, 32)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(icon)
	_text(node, 44, 5, NODE_W - 48, a.ability_name, 10, Color(1, 1, 1))
	var sub := "Lv %d/%d" % [level, a.max_level]
	var scol := _state_color(state)
	match state:
		ST_MAX: sub = "MAX %d/%d" % [level, a.max_level]
		ST_AVAIL: sub = "Learn"; scol = Color(0.45, 0.95, 0.45)
		ST_LOCKED:
			var pr: String = _comp.active_chain_prereq_name(a.ability_id) if _comp.has_method("active_chain_prereq_name") else ""
			sub = "Needs %s" % pr if pr != "" else "Locked"
			scol = Color(0.66, 0.6, 0.55)
	_text(node, 44, NODE_H - 16, NODE_W - 48, sub, 9, scol)

	@warning_ignore("integer_division")
	_upgrade_branch(a, y + NODE_H / 2, state == ST_MAX)


func _upgrade_branch(a, cy: int, ability_maxed: bool) -> void:
	if a.upgrades == null or a.upgrades.is_empty():
		return
	var t1: Array = []
	var t2: Array = []
	var t3: Array = []
	for up in a.upgrades:
		match up.tier:
			1: t1.append(up)
			2: t2.append(up)
			_: t3.append(up)
	var line_col := C_UPG if ability_maxed else C_LOCKED
	# ability -> T1
	_lines.append([Vector2(PAD + NODE_W, cy), Vector2(X_T1, cy), line_col])
	_tier_single(a, t1, X_T1, cy)
	if not t2.is_empty():
		_lines.append([Vector2(X_T1 + UPG_W, cy), Vector2(X_T2, cy), line_col])
		_tier_single(a, t2, X_T2, cy)
	if not t3.is_empty():
		var n: int = t3.size()
		var total_h: int = n * UPG_H + (n - 1) * UPG_VGAP
		@warning_ignore("integer_division")
		var sy: int = cy - total_h / 2
		_lines.append([Vector2(X_T2 + UPG_W, cy), Vector2(X_T3 - 8, cy), line_col])
		@warning_ignore("integer_division")
		_lines.append([Vector2(X_T3 - 8, sy + UPG_H / 2), Vector2(X_T3 - 8, sy + total_h - UPG_H / 2), line_col])
		for i in n:
			var uy: int = sy + i * (UPG_H + UPG_VGAP)
			@warning_ignore("integer_division")
			_lines.append([Vector2(X_T3 - 8, uy + UPG_H / 2), Vector2(X_T3, uy + UPG_H / 2), line_col])
			_upg_node(a, t3[i], X_T3, uy)


func _tier_single(a, ups: Array, x: int, cy: int) -> void:
	for up in ups:
		@warning_ignore("integer_division")
		_upg_node(a, up, x, cy - UPG_H / 2)


func _upg_node(a, up, x: int, y: int) -> void:
	var owned: bool = _comp.has_upgrade(a.ability_id, up.upgrade_id)
	var buyable: bool = false
	if not owned:
		var can = _comp.can_purchase_upgrade(a.ability_id, up.upgrade_id)
		buyable = can is Dictionary and can.get("ok", false)
	var border := C_UPG if owned else (C_AVAIL if buyable else C_LOCKED)
	var dim: bool = not owned and not buyable
	var btn := Button.new()
	btn.position = Vector2(x, y)
	btn.custom_minimum_size = Vector2(UPG_W, UPG_H)
	btn.size = Vector2(UPG_W, UPG_H)
	btn.focus_mode = Control.FOCUS_NONE
	btn.modulate = Color(1, 1, 1, 0.7) if dim else Color(1, 1, 1, 1)
	_style(btn, border, dim, _sel_upgrade == up.upgrade_id)
	var aid: String = a.ability_id
	var uid: String = up.upgrade_id
	btn.pressed.connect(func(): node_selected.emit("upgrade", aid, uid))
	add_child(btn)
	var nm: String = up.upgrade_name
	if owned:
		nm = "✓ " + nm
	@warning_ignore("integer_division")
	_text_c(btn, 2, (UPG_H - 11) / 2, UPG_W - 4, nm, 9, Color(0.62, 0.62, 0.67) if dim else border)


# ---- styling helpers ----
func _state_color(state: int) -> Color:
	match state:
		ST_MAX: return C_MAX
		ST_OWNED: return C_OWNED
		ST_AVAIL: return C_AVAIL
		_: return C_LOCKED


func _sbox(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(2)
	return sb


func _style(btn: Button, border: Color, locked: bool, selected: bool) -> void:
	var b := C_SELECT if selected else border
	var sb := _sbox(C_BG_LOCKED if locked else C_BG, b, 3 if selected else 2)
	for s in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(s, sb)


func _text(parent, x: int, y: int, w: int, txt: String, sz: int, col: Color) -> void:
	var l := Label.new()
	l.position = Vector2(x, y)
	l.size = Vector2(w, sz + 6)
	l.text = txt
	l.clip_text = true
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)


func _text_c(parent, x: int, y: int, w: int, txt: String, sz: int, col: Color) -> void:
	var l := Label.new()
	l.position = Vector2(x, y)
	l.size = Vector2(w, sz + 6)
	l.text = txt
	l.clip_text = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)


func _draw() -> void:
	for seg in _lines:
		draw_line(seg[0], seg[1], seg[2], 3.0)
