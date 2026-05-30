extends Control

## Branching skill-tree renderer for the Ability Window. Lays a discipline's
## abilities into two vertical "path" columns by AbilityData.tree_path /
## tree_depth, draws connector lines between consecutive-depth nodes, and emits
## ability_selected when a node is clicked. Node state (locked / learnable /
## owned / maxed) is read from the AbilityComponent on each populate().
##
## The two paths per weapon are a display + climb-gate taxonomy authored on the
## AbilityData resources (tree_path 0 = left column, 1 = right). Discipline
## filtering happens in the window; this canvas only lays out what it's handed.

signal ability_selected(ability_id: String)

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const NODE_SCRIPT := preload("res://scripts/UI/skill_tree_node.gd")

## Path display names per discipline key (Path A = index 0, Path B = index 1).
const PATH_NAMES := {
	"sword": ["Vanguard", "Berserker"],
	"bow": ["Marksman", "Skirmisher"],
	"staff": ["Elementalist", "Sage"],
	"dagger": ["Assassin", "Venomancer"],
}

# Layout (px).
const NODE_W := 166
const NODE_H := 54
const COL_GAP := 24
const SIDE_PAD := 12
const NODES_TOP := 42
const ROW_PITCH := 82
const HEADER_Y := 10

# Node states.
const ST_LOCKED := 0
const ST_AVAIL := 1
const ST_OWNED := 2
const ST_MAX := 3

# State -> border color.
const C_OWNED := Color(0.36, 0.74, 1.0)    # learned, not max
const C_MAX := Color(0.95, 0.80, 0.30)     # maxed
const C_AVAIL := Color(0.82, 0.85, 0.92)   # unlocked, learnable
const C_LOCKED := Color(0.32, 0.32, 0.38)  # climb-locked
const C_SELECT := Color(1.0, 0.95, 0.45)   # selection highlight
const C_BG := Color(0.10, 0.10, 0.13, 0.96)
const C_BG_LOCKED := Color(0.07, 0.07, 0.09, 0.92)

var _ability_component
var _discipline_key: String = ""
var _selected_id: String = ""
# ability_id -> { node: Button, path: int, depth: int, state: int }
var _nodes: Dictionary = {}
# path index -> Array of ability_id sorted by depth (drives connector drawing)
var _path_order: Dictionary = {}


## Rebuilds the whole tree for `abilities` (already filtered to one discipline).
func populate(ability_component, abilities: Array, discipline_key: String, selected_id: String) -> void:
	_ability_component = ability_component
	_discipline_key = discipline_key
	_selected_id = selected_id
	for c in get_children():
		c.queue_free()
	_nodes.clear()
	_path_order.clear()
	if _ability_component == null:
		return

	# Bucket by path, sort each by depth.
	var by_path: Dictionary = {0: [], 1: []}
	for a in abilities:
		if a == null or a.tree_path < 0:
			continue
		if not by_path.has(a.tree_path):
			by_path[a.tree_path] = []
		by_path[a.tree_path].append(a)
	var max_depth: int = 0
	for p in by_path:
		by_path[p].sort_custom(func(x, y): return x.tree_depth < y.tree_depth)
		_path_order[p] = []
		for a in by_path[p]:
			_path_order[p].append(a.ability_id)
			max_depth = max(max_depth, a.tree_depth)

	# Path headers — name + points invested in the column (drives the tier gates).
	var names: Array = PATH_NAMES.get(discipline_key, ["Path A", "Path B"])
	for p in [0, 1]:
		var pts: int = 0
		if by_path.has(p):
			for a in by_path[p]:
				pts += _ability_component.get_ability_level(a.ability_id)
		var pname: String = str(names[p]) if p < names.size() else "Path %d" % (p + 1)
		var hdr := Label.new()
		hdr.text = "%s  (%d)" % [pname, pts]
		hdr.add_theme_font_override("font", FONT)
		hdr.add_theme_font_size_override("font_size", 13)
		hdr.add_theme_color_override("font_color", Color(0.91, 0.89, 0.35))
		hdr.position = Vector2(_col_x(p), HEADER_Y)
		hdr.size = Vector2(NODE_W, 20)
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hdr)

	# Nodes.
	for p in by_path:
		for a in by_path[p]:
			_make_node(a)

	var total_h: int = NODES_TOP + (max_depth + 1) * ROW_PITCH + 8
	var total_w: int = _col_x(1) + NODE_W + SIDE_PAD
	custom_minimum_size = Vector2(total_w, total_h)
	queue_redraw()


func _col_x(path_index: int) -> int:
	return SIDE_PAD + path_index * (NODE_W + COL_GAP)


func _make_node(a) -> void:
	var level: int = _ability_component.get_ability_level(a.ability_id)
	var unlocked: bool = _ability_component.is_tree_node_unlocked(a.ability_id)
	var state: int = ST_LOCKED
	if level >= a.max_level and level > 0:
		state = ST_MAX
	elif level > 0:
		state = ST_OWNED
	elif unlocked:
		state = ST_AVAIL

	# Use the node script (extends Button) so the node can be dragged to the hotbar.
	var btn: Button = NODE_SCRIPT.new()
	btn.ability_data = a
	btn.current_level = level
	btn.position = Vector2(_col_x(a.tree_path), NODES_TOP + a.tree_depth * ROW_PITCH)
	btn.custom_minimum_size = Vector2(NODE_W, NODE_H)
	btn.size = Vector2(NODE_W, NODE_H)
	btn.focus_mode = Control.FOCUS_NONE
	btn.modulate = Color(1, 1, 1, 0.55) if state == ST_LOCKED else Color(1, 1, 1, 1)
	_apply_node_style(btn, state, a.ability_id == _selected_id)
	var aid: String = a.ability_id
	btn.pressed.connect(func(): ability_selected.emit(aid))
	add_child(btn)

	var icon := TextureRect.new()
	icon.texture = a.ability_icon
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(6, 7)
	icon.size = Vector2(40, 40)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = a.ability_name
	name_lbl.add_theme_font_override("font", FONT)
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	name_lbl.position = Vector2(48, 7)
	name_lbl.size = Vector2(NODE_W - 54, 18)
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(name_lbl)

	var status := Label.new()
	status.add_theme_font_override("font", FONT)
	status.add_theme_font_size_override("font_size", 10)
	status.position = Vector2(48, 29)
	status.size = Vector2(NODE_W - 54, 16)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var txt: String = "Locked"
	var col: Color = Color(0.6, 0.6, 0.65)
	match state:
		ST_MAX:
			txt = "MAX %d/%d" % [level, a.max_level]
			col = C_MAX
		ST_OWNED:
			txt = "Lv %d/%d" % [level, a.max_level]
			col = C_OWNED
		ST_AVAIL:
			txt = "Learn"
			col = Color(0.45, 0.95, 0.45)
		ST_LOCKED:
			# Points-in-path gate: show how many more points this column needs.
			var need: int = _ability_component.path_points_to_unlock(a.ability_id)
			txt = "Need +%d" % need if need > 0 else "Locked"
			col = Color(0.72, 0.6, 0.4)
	status.text = txt
	status.add_theme_color_override("font_color", col)
	btn.add_child(status)

	var tag := Label.new()
	tag.add_theme_font_override("font", FONT)
	tag.add_theme_font_size_override("font_size", 9)
	var is_passive: bool = a.ability_type == Constants.AbilityType.PASSIVE
	tag.text = "P" if is_passive else "A"
	tag.add_theme_color_override("font_color", Color(0.55, 0.7, 1.0) if is_passive else Color(1.0, 0.65, 0.4))
	tag.position = Vector2(NODE_W - 16, 3)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(tag)

	var total_ups: int = a.upgrades.size() if a.upgrades != null else 0
	if total_ups > 0:
		var owned_ups: int = _ability_component.get_learned_upgrades(a.ability_id).size()
		var ub := Label.new()
		ub.add_theme_font_override("font", FONT)
		ub.add_theme_font_size_override("font_size", 9)
		ub.text = "◆%d/%d" % [owned_ups, total_ups]
		ub.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
		ub.position = Vector2(NODE_W - 46, NODE_H - 16)
		ub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(ub)

	_nodes[a.ability_id] = {"node": btn, "path": a.tree_path, "depth": a.tree_depth, "state": state}


func _apply_node_style(btn: Button, state: int, selected: bool) -> void:
	var border: Color = C_SELECT if selected else _state_color(state)
	var bw: int = 3 if selected else 2
	var bg: Color = C_BG_LOCKED if state == ST_LOCKED else C_BG
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(2)
	for s in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(s, sb)


func _state_color(state: int) -> Color:
	match state:
		ST_MAX: return C_MAX
		ST_OWNED: return C_OWNED
		ST_AVAIL: return C_AVAIL
		_: return C_LOCKED


## Re-highlights the selected node without a full rebuild.
func set_selected(ability_id: String) -> void:
	if ability_id == _selected_id:
		return
	_selected_id = ability_id
	for id in _nodes:
		var info: Dictionary = _nodes[id]
		_apply_node_style(info.node, info.state, id == _selected_id)


func _draw() -> void:
	for p in _path_order:
		var ids: Array = _path_order[p]
		var cx: float = _col_x(p) + NODE_W / 2.0
		for i in range(ids.size() - 1):
			var top_id: String = ids[i]
			var bot_id: String = ids[i + 1]
			if not _nodes.has(top_id) or not _nodes.has(bot_id):
				continue
			var top: Dictionary = _nodes[top_id]
			var bot: Dictionary = _nodes[bot_id]
			var y0: float = NODES_TOP + top.depth * ROW_PITCH + NODE_H
			var y1: float = NODES_TOP + bot.depth * ROW_PITCH
			var col: Color = Color(0.25, 0.25, 0.3)
			match bot.state:
				ST_MAX, ST_OWNED:
					col = C_OWNED
				ST_AVAIL:
					col = Color(0.6, 0.6, 0.66)
			draw_line(Vector2(cx, y0), Vector2(cx, y1), col, 3.0)
