class_name SkillTreeWindow
extends Panel

## Draggable skill tree window.
##
## Renders the player's class skill tree as a graph of nodes positioned on a
## grid (each SkillTreeNodeData.ui_position). Prerequisite edges are drawn as
## connecting lines. Each node is colour-coded by its state:
##   unlocked   - bright green
##   available  - gold (prereqs + level + points all satisfied; clickable)
##   eligible   - blue (prereqs met but not enough points / level)
##   locked     - dark grey (prerequisites unmet)
##
## Clicking an "available" node sends an unlock intent to the server through
## the SkillTreeComponent, which validates authoritatively.

@onready var title_label: Label = %TitleLabel
@onready var close_button: Button = %CloseButton
@onready var skill_points_label: Label = %SkillPointsLabel
@onready var graph_container: Control = %GraphContainer
@onready var info_label: RichTextLabel = %InfoLabel

var player: MultiplayerPlayerV2
var skill_tree_component: SkillTreeComponent

var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

# Layout constants
const CELL_SIZE: Vector2 = Vector2(120, 96)
const NODE_SIZE: Vector2 = Vector2(96, 64)
const GRAPH_MARGIN: Vector2 = Vector2(24, 24)

# State colours
const COLOR_UNLOCKED := Color(0.30, 0.78, 0.36)
const COLOR_AVAILABLE := Color(0.94, 0.78, 0.25)
const COLOR_ELIGIBLE := Color(0.36, 0.55, 0.85)
const COLOR_LOCKED := Color(0.28, 0.28, 0.32)
const COLOR_LINE_MET := Color(0.45, 0.75, 0.45, 0.9)
const COLOR_LINE_UNMET := Color(0.4, 0.4, 0.45, 0.6)

# node_id -> Button
var _node_buttons: Dictionary = {}
var _selected_node_id: String = ""
# Cached connection list of [from_node_id, to_node_id] for the line drawer.
var _connections: Array = []


func _ready() -> void:
	add_to_group("ui_window")

	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2
		skill_tree_component = player.skill_tree_component

	close_button.pressed.connect(func(): visible = false)

	if skill_tree_component:
		skill_tree_component.tree_state_changed.connect(_refresh)
		skill_tree_component.skill_points_changed.connect(func(_p): _refresh())
		skill_tree_component.node_unlocked.connect(func(_n): _refresh())

	graph_container.draw.connect(_draw_connections)

	_build_tree()
	_refresh()


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return

	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenSkillTreeWindow"):
			if visible:
				visible = false
			elif not InputManager.is_locked():
				visible = true
				move_to_front()
				_build_tree()
				_refresh()

	if is_dragging:
		var new_pos := get_global_mouse_position() - drag_offset
		var vp := get_viewport_rect().size
		new_pos.x = clamp(new_pos.x, 0, vp.x - size.x)
		new_pos.y = clamp(new_pos.y, 0, vp.y - size.y)
		global_position = new_pos


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if title_label.get_global_rect().has_point(get_global_mouse_position()):
				is_dragging = true
				drag_offset = get_global_mouse_position() - global_position
				move_to_front()
		else:
			is_dragging = false


# ── Tree construction ─────────────────────────────────────────────────────────

## Builds the node buttons and connection list for the player's current class.
func _build_tree() -> void:
	for child in graph_container.get_children():
		child.queue_free()
	_node_buttons.clear()
	_connections.clear()

	var tree: SkillTreeData = skill_tree_component.get_tree_data() if skill_tree_component else null
	if not tree:
		title_label.text = "Skill Tree"
		info_label.text = "No skill tree is defined for this class yet."
		graph_container.custom_minimum_size = Vector2.ZERO
		return

	title_label.text = tree.tree_name if not tree.tree_name.is_empty() else "Skill Tree"

	# Determine the grid extent so the graph container sizes correctly.
	var max_col := 0
	var max_row := 0
	for node in tree.nodes:
		if not node:
			continue
		max_col = maxi(max_col, node.ui_position.x)
		max_row = maxi(max_row, node.ui_position.y)

	graph_container.custom_minimum_size = Vector2(
		GRAPH_MARGIN.x * 2 + (max_col + 1) * CELL_SIZE.x,
		GRAPH_MARGIN.y * 2 + (max_row + 1) * CELL_SIZE.y
	)

	for node in tree.nodes:
		if not node:
			continue
		_create_node_button(node)
		for prereq_id in node.prerequisite_node_ids:
			_connections.append([prereq_id, node.node_id])

	graph_container.queue_redraw()


func _create_node_button(node: SkillTreeNodeData) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = NODE_SIZE
	btn.size = NODE_SIZE
	btn.position = _node_top_left(node)
	btn.clip_text = true
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.focus_mode = Control.FOCUS_NONE

	# Show the ability icon when available.
	var ability: AbilityData = ResourceManager.get_ability_data(node.ability_name)
	if ability and ability.ability_icon:
		btn.icon = ability.ability_icon
		btn.expand_icon = true
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP

	btn.text = node.get_display_name()
	btn.pressed.connect(_on_node_pressed.bind(node.node_id))
	graph_container.add_child(btn)
	_node_buttons[node.node_id] = btn


## Top-left pixel position of a node given its grid cell.
func _node_top_left(node: SkillTreeNodeData) -> Vector2:
	var cell_origin := GRAPH_MARGIN + Vector2(node.ui_position) * CELL_SIZE
	return cell_origin + (CELL_SIZE - NODE_SIZE) * 0.5


## Centre pixel position of a node, used for drawing connection lines.
func _node_center(node_id: String) -> Vector2:
	var tree: SkillTreeData = skill_tree_component.get_tree_data()
	if not tree:
		return Vector2.ZERO
	var node := tree.get_node_by_id(node_id)
	if not node:
		return Vector2.ZERO
	return _node_top_left(node) + NODE_SIZE * 0.5


# ── Rendering ─────────────────────────────────────────────────────────────────

## Refreshes node colours, the skill point counter and the info panel.
func _refresh() -> void:
	if not skill_tree_component:
		return

	skill_points_label.text = "Skill Points: %d" % skill_tree_component.get_available_skill_points()

	var tree: SkillTreeData = skill_tree_component.get_tree_data()
	if not tree:
		return

	# Rebuild buttons if the class changed and the graph is now stale.
	for node in tree.nodes:
		if node and not _node_buttons.has(node.node_id):
			_build_tree()
			break

	for node_id in _node_buttons:
		var btn: Button = _node_buttons[node_id]
		if not is_instance_valid(btn):
			continue
		var state := skill_tree_component.get_node_state(node_id)
		_style_node_button(btn, state, node_id == _selected_node_id)

	graph_container.queue_redraw()

	if not _selected_node_id.is_empty():
		_show_node_info(_selected_node_id)
	else:
		info_label.text = "Select a node to see its details. Click an unlocked-eligible node to spend a skill point."


func _style_node_button(btn: Button, state: String, selected: bool) -> void:
	var base: Color
	match state:
		"unlocked":  base = COLOR_UNLOCKED
		"available": base = COLOR_AVAILABLE
		"eligible":  base = COLOR_ELIGIBLE
		_:           base = COLOR_LOCKED

	for sb_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = base.darkened(0.35) if sb_name != "hover" else base.darkened(0.2)
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(3 if selected else 2)
		sb.border_color = Color.WHITE if selected else base
		sb.set_content_margin_all(4)
		btn.add_theme_stylebox_override(sb_name, sb)

	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.modulate = Color(1, 1, 1, 1) if state != "locked" else Color(1, 1, 1, 0.75)


## Custom draw callback for graph_container — draws prerequisite edges.
func _draw_connections() -> void:
	if not skill_tree_component:
		return
	for conn in _connections:
		var from_id: String = conn[0]
		var to_id: String = conn[1]
		var from_pos := _node_center(from_id)
		var to_pos := _node_center(to_id)
		if from_pos == Vector2.ZERO or to_pos == Vector2.ZERO:
			continue
		var prereq_met := skill_tree_component.is_node_unlocked(from_id)
		var col := COLOR_LINE_MET if prereq_met else COLOR_LINE_UNMET
		graph_container.draw_line(from_pos, to_pos, col, 3.0, true)


# ── Info panel ────────────────────────────────────────────────────────────────

func _show_node_info(node_id: String) -> void:
	var tree: SkillTreeData = skill_tree_component.get_tree_data()
	if not tree:
		return
	var node := tree.get_node_by_id(node_id)
	if not node:
		return

	var state := skill_tree_component.get_node_state(node_id)
	var ability: AbilityData = ResourceManager.get_ability_data(node.ability_name)

	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % node.get_display_name())

	var desc := node.description
	if desc.is_empty() and ability:
		desc = ability.description
	if not desc.is_empty():
		lines.append(desc)

	lines.append("")
	lines.append("Cost: [color=#f0c840]%d SP[/color]" % node.skill_point_cost)
	if node.required_level > 0:
		var lvl_ok := true
		if is_instance_valid(player) and player.level_component:
			lvl_ok = player.level_component.level >= node.required_level
		var lvl_col := "#4ed64e" if lvl_ok else "#d64e4e"
		lines.append("Required Level: [color=%s]%d[/color]" % [lvl_col, node.required_level])

	if node.prerequisite_node_ids.size() > 0:
		lines.append("Prerequisites:")
		for prereq_id in node.prerequisite_node_ids:
			var prereq := tree.get_node_by_id(prereq_id)
			var prereq_name := prereq.get_display_name() if prereq else prereq_id
			var met := skill_tree_component.is_node_unlocked(prereq_id)
			var mark := "[color=#4ed64e]OK[/color]" if met else "[color=#d64e4e]X[/color]"
			lines.append("  %s %s" % [mark, prereq_name])

	lines.append("")
	match state:
		"unlocked":
			lines.append("[color=#4ed64e]Unlocked[/color]")
		"available":
			lines.append("[color=#f0c840]Click again to unlock[/color]")
		"eligible":
			lines.append("[color=#d64e4e]Not enough skill points or level[/color]")
		_:
			lines.append("[color=#888888]Prerequisites not met[/color]")

	info_label.text = "\n".join(lines)


# ── Interaction ───────────────────────────────────────────────────────────────

func _on_node_pressed(node_id: String) -> void:
	if not skill_tree_component:
		return

	# First click selects the node; clicking an already-selected available
	# node confirms the unlock. This prevents accidental point spending.
	if _selected_node_id != node_id:
		_selected_node_id = node_id
		_refresh()
		return

	if skill_tree_component.can_unlock_node(node_id):
		skill_tree_component.unlock_node(node_id)
	_refresh()
