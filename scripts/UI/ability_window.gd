extends PanelContainer
class_name AbilityWindow

## References to ability data classes
const ABILITYDATA = preload("res://scripts/Resources/AbilitySystem/AbilityData.gd")
const ABILITYLEVELDATA = preload("res://scripts/Resources/AbilitySystem/AbilityLevelData.gd")

## Unique Names from ability_window.tscn
## The left panel is a branching graph of the player's whole class ability tree.
@onready var ability_list_container: Control = %AbilityListContainer
@onready var ability_icon: TextureRect = %AbilityIcon
@onready var ability_name_label: Label = %AbilityName
@onready var ability_level_label: Label = %AbilityLevel
@onready var description_text: RichTextLabel = %DescriptionText
@onready var mana_cost_label: RichTextLabel = %ManaCost
@onready var cooldown_label: RichTextLabel = %Cooldown
@onready var cost_label: Label = %CostLabel
@onready var level_up_button: Button = %LevelUpButton
@onready var skill_points_label: Label = %SkillPointsLabel

var selected_ability_id: String = ""
var player: MultiplayerPlayerV2
var ability_component: AbilityComponent

var is_dragging = false
var drag_offset = Vector2()

const COLOR_NORMAL = "#FFFFFF"
const COLOR_UPGRADE = "#00FF00" # Green for stat increases
const COLOR_DOWNGRADE = "#FF0000" # Red for stat decreases (e.g., cooldown time)
const COLOR_BASE = "#B0B0B0" # Gray for base stats

## ── Ability tree graph ────────────────────────────────────────────────────────
## ability_id -> Button node, for the branching class-ability graph.
var _node_buttons: Dictionary = {}
## Cached prerequisite edges as [prereq_ability_id, ability_id] pairs.
var _connections: Array = []

# Graph layout: the tree flows top-to-bottom — row = prerequisite depth, and
# nodes within a depth are spread across columns, ordered to reduce edge
# crossings (by the average position of their prerequisites).
const GRAPH_MARGIN: float = 16.0
const COL_W: float = 128.0
const ROW_H: float = 124.0
const NODE_SIZE: Vector2 = Vector2(112, 94)
const ICON_SIZE: Vector2 = Vector2(46, 46)
const LABEL_FONT_SIZE: int = 9

# Node state colours.
const COLOR_MAXED: Color = Color(0.42, 0.85, 0.62)
const COLOR_LEARNED: Color = Color(0.30, 0.78, 0.36)
const COLOR_AVAILABLE: Color = Color(0.94, 0.78, 0.25)
const COLOR_LOCKED: Color = Color(0.30, 0.30, 0.34)
const COLOR_LINE_MET: Color = Color(0.45, 0.78, 0.45, 0.9)
const COLOR_LINE_UNMET: Color = Color(0.4, 0.4, 0.45, 0.55)

func _ready():
	# Add to ui_window group for drop detection
	add_to_group("ui_window")

	# The graph container draws its own prerequisite edges behind the nodes.
	ability_list_container.draw.connect(_draw_connections)

	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2
		ability_component = player.ability_component
		
		if not ability_component:
			push_error("AbilityWindow: Could not find AbilityComponent on player")
			return
	
	# Connect signals
	level_up_button.pressed.connect(on_level_up_button_pressed)
	
	# Connect to ability component signals
	if ability_component:
		ability_component.ability_leveled_up.connect(_on_ability_leveled_up)
		ability_component.ability_learned.connect(_on_ability_learned)
		ability_component.ability_points_changed.connect(_on_ability_points_changed)
		##print("AbilityWindow: Connected to ability component signals")
	
	# Load UI — load_ability_list() builds the graph and picks a default node.
	update_skill_points_display()
	load_ability_list()
	if not selected_ability_id.is_empty():
		select_ability(selected_ability_id)
	else:
		clear_details()


func _process(_delta: float) -> void:
	if not ability_component:
		return
		
	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenAbilityWindow"):
			if self.visible:
				self.visible = false
			elif not InputManager.is_locked():
				self.visible = true
				if self.visible:
					# Refresh the display when opening
					update_skill_points_display()
					load_ability_list()
					if selected_ability_id:
						select_ability(selected_ability_id)
			
	if is_dragging:
		global_position = get_global_mouse_position() - drag_offset
		var new_position = get_global_mouse_position() - drag_offset
		var viewport_size = get_viewport_rect().size
		var window_size = size
		
		new_position.x = clamp(new_position.x, 0, viewport_size.x - window_size.x)
		new_position.y = clamp(new_position.y, 0, viewport_size.y - window_size.y)
			
		global_position = new_position

func _gui_input(event: InputEvent) -> void:
	# Check for a mouse button press (typically the left mouse button).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if self.get_global_rect().has_point(get_global_mouse_position()):
				is_dragging = true
				# Calculate the offset from the node's origin to the mouse position.
				drag_offset = get_global_mouse_position() - global_position
				self.move_to_front()
		else:
			is_dragging = false


## Rebuilds the branching ability-tree graph for the player's whole class.
## Shows every class ability — learned, learnable and still-locked — laid out
## by prerequisite depth, with edges connecting prerequisites to dependents.
func load_ability_list():
	if not ability_component:
		return

	for child in ability_list_container.get_children():
		child.queue_free()
	_node_buttons.clear()
	_connections.clear()

	var abilities := _get_class_abilities()
	if abilities.is_empty():
		ability_list_container.custom_minimum_size = Vector2.ZERO
		ability_list_container.queue_redraw()
		return

	# ability_id -> AbilityData, so prerequisite lookups stay within the class.
	var by_id: Dictionary = {}
	for ability in abilities:
		if ability:
			by_id[ability.ability_id] = ability

	# Column of each node = longest prerequisite chain leading to it.
	var depth_memo: Dictionary = {}
	for ability in abilities:
		if ability:
			_compute_depth(ability, by_id, depth_memo, {})

	# Group abilities into layers by prerequisite depth (layer 0 = no prereqs).
	var layers: Dictionary = {}
	var max_depth: int = 0
	for ability in abilities:
		if not ability:
			continue
		var depth: int = depth_memo.get(ability.ability_id, 0)
		if not layers.has(depth):
			layers[depth] = []
		(layers[depth] as Array).append(ability)
		max_depth = maxi(max_depth, depth)

	var max_layer_size: int = 0
	for d in layers:
		max_layer_size = maxi(max_layer_size, (layers[d] as Array).size())
	var total_width: float = float(max_layer_size) * COL_W

	# Place layer by layer, top-down. Within each layer, nodes are sorted by the
	# average horizontal position of their prerequisites so connecting edges
	# cross as little as possible; the layer is then centred horizontally.
	var x_center: Dictionary = {}
	for d in range(max_depth + 1):
		if not layers.has(d):
			continue
		var layer: Array = layers[d]
		if d > 0:
			var bary: Dictionary = {}
			for n in layer:
				bary[n.ability_id] = _barycenter(n, by_id, x_center)
			layer.sort_custom(func(a, b): return bary[a.ability_id] < bary[b.ability_id])
		var start_x: float = GRAPH_MARGIN + (total_width - float(layer.size()) * COL_W) * 0.5
		var node_y: float = GRAPH_MARGIN + float(d) * ROW_H
		for i in range(layer.size()):
			var ab: AbilityData = layer[i]
			var node_x: float = start_x + float(i) * COL_W
			x_center[ab.ability_id] = node_x + NODE_SIZE.x * 0.5
			_create_ability_node(ab, Vector2(node_x, node_y))

	ability_list_container.custom_minimum_size = Vector2(
		GRAPH_MARGIN * 2.0 + total_width,
		GRAPH_MARGIN * 2.0 + float(max_depth) * ROW_H + NODE_SIZE.y
	)

	for ability in abilities:
		if not ability:
			continue
		for prereq in ability.prerequisite_abilities:
			if prereq and by_id.has(prereq.ability_id):
				_connections.append([prereq.ability_id, ability.ability_id])

	# Keep a valid selection; default to the first node.
	if selected_ability_id.is_empty() or not by_id.has(selected_ability_id):
		selected_ability_id = abilities[0].ability_id if abilities[0] else ""

	_restyle_all_nodes()
	ability_list_container.queue_redraw()


## All abilities defined for the player's class (learned or not).
func _get_class_abilities() -> Array[AbilityData]:
	if is_instance_valid(player) and player.class_component:
		return player.class_component.get_class_abilities()
	return []


## Longest prerequisite chain depth for an ability, memoised. The visiting set
## guards against a malformed cyclic prerequisite definition.
func _compute_depth(ability: AbilityData, by_id: Dictionary, memo: Dictionary, visiting: Dictionary) -> int:
	var aid: String = ability.ability_id
	if memo.has(aid):
		return memo[aid]
	if visiting.has(aid):
		return 0
	visiting[aid] = true
	var depth: int = 0
	for prereq in ability.prerequisite_abilities:
		if prereq and by_id.has(prereq.ability_id):
			depth = maxi(depth, 1 + _compute_depth(prereq, by_id, memo, visiting))
	visiting.erase(aid)
	memo[aid] = depth
	return depth


## Creates a positioned, clickable node for one ability: a large icon above a
## small wrapped name label, all inside a styled Button.
func _create_ability_node(ability: AbilityData, pos: Vector2) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = NODE_SIZE
	btn.size = NODE_SIZE
	btn.position = pos
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = true
	btn.tooltip_text = ability.ability_name

	# Icon + label stacked vertically; children ignore the mouse so the whole
	# node registers as a single button click.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 3)

	var icon_rect := TextureRect.new()
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.custom_minimum_size = ICON_SIZE
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ability.ability_icon:
		icon_rect.texture = ability.ability_icon
	vbox.add_child(icon_rect)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = ability.ability_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(label)

	btn.add_child(vbox)
	btn.pressed.connect(select_ability.bind(ability.ability_id))
	ability_list_container.add_child(btn)
	_node_buttons[ability.ability_id] = btn


## Average horizontal centre of an ability's already-placed prerequisites.
## Used to order a layer's nodes so prerequisite edges cross as little as possible.
func _barycenter(ability: AbilityData, by_id: Dictionary, x_center: Dictionary) -> float:
	var total: float = 0.0
	var count: int = 0
	for prereq in ability.prerequisite_abilities:
		if prereq and by_id.has(prereq.ability_id) and x_center.has(prereq.ability_id):
			total += x_center[prereq.ability_id]
			count += 1
	return total / float(count) if count > 0 else 0.0


## "maxed", "learned", "available" (prereqs met, not yet learned) or "locked".
func _get_ability_state(ability_id: String) -> String:
	var level: int = ability_component.get_ability_level(ability_id)
	var data: AbilityData = ResourceManager.get_ability_data(ability_id)
	if level >= 1:
		if data and level >= data.max_level:
			return "maxed"
		return "learned"
	if data:
		for prereq in data.prerequisite_abilities:
			var required_level: int = data.prerequisite_abilities[prereq]
			if prereq and ability_component.get_ability_level(prereq.ability_id) < required_level:
				return "locked"
	return "available"


## Applies state-coloured styleboxes to one node, highlighting it if selected.
func _style_ability_node(ability_id: String) -> void:
	var btn: Button = _node_buttons.get(ability_id)
	if not is_instance_valid(btn):
		return
	var state := _get_ability_state(ability_id)
	var base: Color
	match state:
		"maxed":     base = COLOR_MAXED
		"learned":   base = COLOR_LEARNED
		"available": base = COLOR_AVAILABLE
		_:           base = COLOR_LOCKED
	var selected: bool = ability_id == selected_ability_id
	for sb_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = base.darkened(0.2 if sb_name == "hover" else 0.4)
		sb.set_corner_radius_all(5)
		sb.set_border_width_all(3 if selected else 1)
		sb.border_color = Color.WHITE if selected else base
		sb.set_content_margin_all(4)
		btn.add_theme_stylebox_override(sb_name, sb)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.modulate = Color(1, 1, 1, 1) if state != "locked" else Color(1, 1, 1, 0.7)


## Re-applies styling to every node (after a selection or progression change).
func _restyle_all_nodes() -> void:
	for ability_id in _node_buttons:
		_style_ability_node(ability_id)
	ability_list_container.queue_redraw()


## Draw callback for the graph container — draws prerequisite edges behind the
## nodes as orthogonal (elbow) connectors flowing top-down: down out of the
## prerequisite, across, then down into the dependent ability.
func _draw_connections() -> void:
	for conn in _connections:
		var from_btn: Button = _node_buttons.get(conn[0])
		var to_btn: Button = _node_buttons.get(conn[1])
		if not is_instance_valid(from_btn) or not is_instance_valid(to_btn):
			continue
		var p_bottom: Vector2 = from_btn.position + Vector2(from_btn.size.x * 0.5, from_btn.size.y)
		var c_top: Vector2 = to_btn.position + Vector2(to_btn.size.x * 0.5, 0.0)
		var mid_y: float = (p_bottom.y + c_top.y) * 0.5
		var prereq_met: bool = ability_component.get_ability_level(conn[0]) >= 1
		var col: Color = COLOR_LINE_MET if prereq_met else COLOR_LINE_UNMET
		var points := PackedVector2Array([
			p_bottom,
			Vector2(p_bottom.x, mid_y),
			Vector2(c_top.x, mid_y),
			c_top,
		])
		ability_list_container.draw_polyline(points, col, 2.0, true)


## Selects an ability node, updates the details panel and highlights the node.
func select_ability(ability_id: String):
	if not ability_component:
		return

	selected_ability_id = ability_id

	# Get ability data from ResourceManager
	var selected_data: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not selected_data:
		clear_details()
		_restyle_all_nodes()
		return

	# Get current level from ability component
	var current_level: int = ability_component.get_ability_level(ability_id)

	_restyle_all_nodes()
	update_details(selected_data, current_level)


## Updates the right-side detail panel with the selected ability's info
func update_details(data: AbilityData, current_level: int):
	if not ability_component:
		return
		
	ability_icon.texture = data.ability_icon
	ability_name_label.text = data.ability_name
	ability_level_label.text = "LEVEL: %d / %d" % [current_level, data.max_level]
	
	var is_max_level = current_level >= data.max_level
	var next_level = current_level + 1
	
	var current_stats: AbilityLevelData = data.get_level_stats(current_level)
	var next_stats: AbilityLevelData = data.get_level_stats(next_level)
	
	# Check prerequisites
	var prereq_met = true
	var prereq_text = ""
	if current_level <= 0 and data.prerequisite_abilities and not data.prerequisite_abilities.is_empty():
		prereq_text = "\n[color=%s]PREREQUISITES:[/color]\n" % COLOR_BASE
		for prereq_ability in data.prerequisite_abilities:
			var required_level = data.prerequisite_abilities[prereq_ability]
			var current_prereq_level = ability_component.get_ability_level(prereq_ability.ability_id)
			var is_met = current_prereq_level >= required_level
			
			if not is_met:
				prereq_met = false
			
			var check_mark = "[color=%s]✓[/color]" if is_met else "[color=%s]✗[/color]"
			var color = COLOR_UPGRADE if is_met else COLOR_DOWNGRADE
			prereq_text += "%s %s: [color=%s]Level %d[/color] (Current: %d)\n" % [
				check_mark % color,
				prereq_ability.ability_name,
				color,
				required_level,
				current_prereq_level
			]
	
	# --- Description and Stats Update ---
	var desc: String
	var mana_cost_text: String
	var cooldown_text: String

	# --- Max Level Display ---
	if is_max_level:
		desc = create_description_text(data, current_stats)
		
		mana_cost_text = str(current_stats.mana_cost) if current_stats else "N/A"
		cooldown_text = "%.1fs" % current_stats.cooldown_time if current_stats and data.ability_type == Constants.AbilityType.ACTIVE else "N/A"
		
		cost_label.text = "Max Level Reached!"
		level_up_button.text = "MAXED"
		level_up_button.disabled = true
		cost_label.add_theme_color_override("font_color", Color(COLOR_NORMAL))

	# --- Level Up Comparison Display ---
	elif next_stats:
		desc = create_description_comparison_text(data, current_stats, next_stats)
		
		# Add prerequisite info to description
		if prereq_text:
			desc += "\n" + prereq_text
		
		# Mana Cost Comparison
		mana_cost_text = format_comparison_text(current_stats.mana_cost, next_stats.mana_cost, false) if current_stats else str(next_stats.mana_cost)
		
		# Cooldown Comparison
		if data.ability_type == Constants.AbilityType.ACTIVE:
			cooldown_text = format_comparison_text(current_stats.cooldown_time, next_stats.cooldown_time, true) if current_stats else "%.1fs" % next_stats.cooldown_time
		else:
			cooldown_text = "N/A"

		# Level Up Cost/Button Logic
		var cost = 1
		var available_points = ability_component.get_available_ability_points()
		var can_level_up = ability_component.can_level_up_ability(data.ability_id)
		
		# Update button text based on current level
		if current_level <= 0:
			level_up_button.text = "LEARN"
		else:
			level_up_button.text = "LEVEL UP"
		
		# Determine why leveling up is blocked
		if not prereq_met:
			cost_label.text = "Prerequisites Not Met!"
			cost_label.add_theme_color_override("font_color", Color(COLOR_DOWNGRADE))
		elif available_points < cost:
			cost_label.text = "Not Enough SP (Need: %d)" % cost
			cost_label.add_theme_color_override("font_color", Color(COLOR_DOWNGRADE))
		elif current_level <= 0:
			cost_label.text = "Cost to Learn: %d SP" % cost
			cost_label.add_theme_color_override("font_color", Color(COLOR_UPGRADE) if can_level_up else Color(COLOR_DOWNGRADE))
		else:
			cost_label.text = "Cost to Upgrade: %d SP" % cost
			cost_label.add_theme_color_override("font_color", Color(COLOR_UPGRADE) if can_level_up else Color(COLOR_DOWNGRADE))
		
		level_up_button.disabled = not can_level_up
		
	else:
		clear_details()
		return
		
	# Apply final text values to UI
	description_text.text = desc
	mana_cost_label.text = mana_cost_text
	cooldown_label.text = cooldown_text
	
	# Passive abilities often don't have mana/cooldown
	if data.ability_type == Constants.AbilityType.PASSIVE:
		mana_cost_label.text = "N/A"
		cooldown_label.text = "N/A"


## Helper function to create the final description text for comparison
func create_description_comparison_text(data: AbilityData, current: AbilityLevelData, next: AbilityLevelData) -> String:
	var desc_template = data.description
	var output = ""
	
	if current == null: # Level 0 / Unlearned
		output += "[color=%s]Unlearned[/color]\n\n" % COLOR_DOWNGRADE
		output += "[color=%s]NEXT LEVEL (%d) STATS:[/color]\n" % [COLOR_UPGRADE, next.level]
		output += format_ability_description(data, next, COLOR_UPGRADE)
		
		# Show stat bonuses if any exist
		if not next.stat_bonuses.is_empty():
			output += "\n\n[color=%s]Stat Bonuses:[/color]\n" % COLOR_UPGRADE
			output += format_stat_bonuses(next, COLOR_UPGRADE)
			
	else: # Level 1 to Max-1
		output += "[color=%s]Current Level (%d) Stats:[/color]\n" % [COLOR_BASE, current.level]
		output += format_ability_description(data, current, COLOR_NORMAL)
		
		# Show current stat bonuses if any exist
		if not current.stat_bonuses.is_empty():
			output += "\n\n[color=%s]Stat Bonuses:[/color]\n" % COLOR_BASE
			output += format_stat_bonuses(current, COLOR_NORMAL)
		
		output += "\n\n[color=%s]NEXT LEVEL (%d) UPGRADE:[/color]\n" % [COLOR_UPGRADE, next.level]
		
		# Show damage/target/hit upgrades for active abilities
		if data.ability_type == Constants.AbilityType.ACTIVE:
			var current_damage = current.damage_percent
			var next_damage = next.damage_percent
			
			if next_damage != current_damage:
				var color = COLOR_UPGRADE if next_damage > current_damage else COLOR_DOWNGRADE
				output += "Damage: [color=%s]%d%%[/color] [color=%s](%+d%%)[/color]\n" % [COLOR_BASE, current_damage, color, next_damage - current_damage]
			
			if data.scaling_data.max_targets_formula:
				var current_target_count = data.scaling_data.max_targets_formula.calculate(current.level)
				var next_target_count = data.scaling_data.max_targets_formula.calculate(next.level)
				if next_target_count != current_target_count:
					var color = COLOR_UPGRADE
					output += "Target Count: [color=%s]%d[/color] [color=%s](%+d)[/color]\n" % [COLOR_BASE, current_target_count, color, next_target_count - current_target_count]
			
			if data.scaling_data.max_hits_formula:
				var current_hit_count = data.scaling_data.max_hits_formula.calculate(current.level)
				var next_hit_count = data.scaling_data.max_hits_formula.calculate(next.level)
				if next_hit_count != current_hit_count:
					var color = COLOR_UPGRADE
					output += "Hit Count: [color=%s]%d[/color] [color=%s](%+d)[/color]\n" % [COLOR_BASE, current_hit_count, color, next_hit_count - current_hit_count]
		
		# NEW: Show buff duration upgrade
		var buff_duration_diff = format_buff_duration_comparison(data, current, next)
		if not buff_duration_diff.is_empty():
			output += buff_duration_diff
		
		# Show stat bonus upgrades
		if not next.stat_bonuses.is_empty():
			output += format_stat_bonus_comparison(current, next)
			
	return output


## Helper function to create the final description text for MAX level
func create_description_text(data: AbilityData, current: AbilityLevelData) -> String:
	var output = "[color=%s]MAX LEVEL STATS:[/color]\n" % COLOR_UPGRADE
	output += format_ability_description(data, current, COLOR_NORMAL)
	
	# Show stat bonuses if any exist
	if not current.stat_bonuses.is_empty():
		output += "\n\n[color=%s]Stat Bonuses:[/color]\n" % COLOR_NORMAL
		output += format_stat_bonuses(current, COLOR_NORMAL)
		
	return output


## Formats the ability description with damage/target/hit counts
func format_ability_description(data: AbilityData, level_data: AbilityLevelData, color: String) -> String:
	var desc_template = data.description
	var output = ""
	
	if data.ability_type == Constants.AbilityType.ACTIVE:
		var damage_text = desc_template.replace("$[damage_percent]", "[color=%s]%d%%[/color]" % [color, level_data.damage_percent])
		var target_text = damage_text.replace("$[target_count]", "[color=%s]%d[/color]" % [color, data.scaling_data.max_targets_formula.calculate(level_data.level)])
		var hit_text = target_text.replace("$[hit_count]", "[color=%s]%d[/color]" % [color, data.scaling_data.max_hits_formula.calculate(level_data.level)])
		
		# NEW: Handle buff duration placeholder
		if data.applies_buff and data.buff_duration_formula:
			var duration = data.buff_duration_formula.calculate(level_data.level)
			hit_text = hit_text.replace("$[buff_duration]", "[color=%s]%.0fs[/color]" % [color, duration])
			
			var stat_key = level_data.stat_bonuses.keys()[0] if not level_data.stat_bonuses.is_empty() else null
			if stat_key != null:
				var stat_value = level_data.stat_bonuses.get(stat_key).total_value if level_data.stat_bonuses.get(stat_key).total_value > 0 else level_data.stat_bonuses.get(stat_key).percent_bonus_value
				hit_text = hit_text.replace("$[stat_bonus]", "[color=%s]%d[/color]" % [color, stat_value])
		
		output += hit_text
	elif data.ability_type == Constants.AbilityType.PASSIVE:
		# For passive abilities, use the first stat bonus in the description
		var stat_key = level_data.stat_bonuses.keys()[0] if not level_data.stat_bonuses.is_empty() else null
		if stat_key != null:
			var stat_value = level_data.stat_bonuses.get(stat_key).total_value if level_data.stat_bonuses.get(stat_key).total_value > 0 else level_data.stat_bonuses.get(stat_key).percent_bonus_value
			var stat_text = desc_template.replace("$[stat_bonus]", "[color=%s]%d[/color]" % [color, stat_value])
			output += stat_text
		else:
			output += desc_template
	else:
		output += desc_template
		
	return output


## Formats all stat bonuses for display
func format_stat_bonuses(level_data: AbilityLevelData, color: String) -> String:
	var output = ""
	
	for stat_type in level_data.stat_bonuses:
		var stat_data: StatData = level_data.stat_bonuses[stat_type]
		var stat_name = Constants.StatType.keys()[stat_type]
		
		# Show flat bonus if it exists
		if stat_data.flat_bonus_value > 0:
			output += "  %s: [color=%s]+%d[/color]\n" % [stat_name, color, stat_data.flat_bonus_value]
		
		# Show percent bonus if it exists
		if stat_data.percent_bonus_value > 0:
			output += "  %s: [color=%s]+%d%%[/color]\n" % [stat_name, color, stat_data.percent_bonus_value]
	
	return output


## Formats stat bonus comparison between current and next level
func format_stat_bonus_comparison(current: AbilityLevelData, next: AbilityLevelData) -> String:
	var output = ""
	var has_changes = false
	
	# Get all stat types from both levels
	var all_stat_types = {}
	if current and not current.stat_bonuses.is_empty():
		for stat_type in current.stat_bonuses:
			all_stat_types[stat_type] = true
	
	for stat_type in next.stat_bonuses:
		all_stat_types[stat_type] = true
	
	# Compare each stat type
	for stat_type in all_stat_types:
		var current_stat: StatData = current.stat_bonuses.get(stat_type) if current else null
		var next_stat: StatData = next.stat_bonuses.get(stat_type)
		
		if not next_stat:
			continue
			
		var stat_name = Constants.StatType.keys()[stat_type]
		var current_flat = current_stat.flat_bonus_value if current_stat else 0
		var next_flat = next_stat.flat_bonus_value
		var current_percent = current_stat.percent_bonus_value if current_stat else 0.0
		var next_percent = next_stat.percent_bonus_value
		
		# Show flat bonus changes
		if next_flat != current_flat:
			has_changes = true
			var diff = next_flat - current_flat
			var color = COLOR_UPGRADE if diff > 0 else COLOR_DOWNGRADE
			output += "%s: [color=%s]+%d[/color] [color=%s](%+d)[/color]\n" % [stat_name, COLOR_BASE, current_flat, color, diff]
		
		# Show percent bonus changes
		if next_percent != current_percent:
			has_changes = true
			var diff = next_percent - current_percent
			var color = COLOR_UPGRADE if diff > 0 else COLOR_DOWNGRADE
			output += "%s: [color=%s]+%d%%[/color] [color=%s](%+d%%)[/color]\n" % [stat_name, COLOR_BASE, current_percent, color, diff]
	
	return output if has_changes else ""


## Helper function for formatting a stat comparison string
func format_comparison_text(current_value, next_value, is_cooldown: bool) -> String:
	var difference = next_value - current_value
	
	if difference == 0:
		return "[color=%s]%s[/color]" % [COLOR_NORMAL, str(current_value)]
	
	# For Cooldown: negative difference (decrease) is an UPGRADE
	var is_upgrade = (is_cooldown and difference < 0) or (not is_cooldown and difference > 0)
	var color = COLOR_UPGRADE if is_upgrade else COLOR_DOWNGRADE
	
	var operator = "-" if is_cooldown and difference < 0 else "+"
	if not is_cooldown and difference < 0:
		operator = "-"

	var diff_string = " ( %s%s )" % [operator, abs(difference)]
	if is_cooldown:
		diff_string = " ( %s%.1fs )" % [operator, abs(difference)]
	
	var current_string = "%.1fs" if is_cooldown else "%s"
	
	return "[color=%s]%s[/color] [color=%s]%s[/color]" % [COLOR_BASE, current_string % current_value, color, diff_string]


func format_buff_info(data: AbilityData, level_data: AbilityLevelData, color: String) -> String:
	if not data.applies_buff:
		return ""
	
	var output = "\n\n[color=%s]Buff Details:[/color]\n" % COLOR_BASE
	var buff: BuffData = data.applies_buff
	
	# Show buff duration
	if data.buff_duration_formula:
		var duration = data.buff_duration_formula.calculate(level_data.level)
		output += "  Duration: [color=%s]%.0fs[/color]\n" % [color, duration]
	elif buff.duration > 0:
		output += "  Duration: [color=%s]%.0fs[/color]\n" % [color, buff.duration]
	else:
		output += "  Duration: [color=%s]Permanent[/color]\n" % color

	return output


func format_buff_duration_comparison(data: AbilityData, current: AbilityLevelData, next: AbilityLevelData) -> String:
	if not data.applies_buff or not data.buff_duration_formula:
		return ""
	
	var current_duration = data.buff_duration_formula.calculate(current.level)
	var next_duration = data.buff_duration_formula.calculate(next.level)
	
	if next_duration == current_duration:
		return ""
	
	var diff = next_duration - current_duration
	var color = COLOR_UPGRADE if diff > 0 else COLOR_DOWNGRADE
	
	return "Buff Duration: [color=%s]%.0fs[/color] [color=%s](%+.0fs)[/color]\n" % [COLOR_BASE, current_duration, color, diff]


## Clears the details panel when no ability is selected
func clear_details():
	selected_ability_id = ""
	ability_icon.texture = null
	ability_name_label.text = "No Ability Selected"
	ability_level_label.text = "LEVEL: 0 / 0"
	description_text.text = "Select an ability from the list on the left to view its details and upgrade it."
	mana_cost_label.text = "N/A"
	cooldown_label.text = "N/A"
	cost_label.text = "No cost"
	level_up_button.text = "LEVEL UP"
	level_up_button.disabled = true


## Handles the Level Up button press
func on_level_up_button_pressed():
	if not ability_component or selected_ability_id.is_empty():
		return
	
	# Level up (or learn, at level 0) the selected ability. The UI refreshes
	# via the ability_leveled_up / ability_learned signal callbacks.
	ability_component.level_up_ability(selected_ability_id)


## Updates the SP display in the header
func update_skill_points_display():
	if not ability_component:
		skill_points_label.text = "SP: 0"
		return
		
	var points = ability_component.get_available_ability_points()
	skill_points_label.text = "SP: %d" % points


## Signal callback when ability levels up
func _on_ability_leveled_up(ability_id: String, new_level: int):
	update_skill_points_display()
	load_ability_list()
	if not selected_ability_id.is_empty():
		select_ability(selected_ability_id)


## Signal callback when ability is learned
func _on_ability_learned(ability_id: String):
	update_skill_points_display()
	load_ability_list()
	if not selected_ability_id.is_empty():
		select_ability(selected_ability_id)


## Signal callback when ability points change
func _on_ability_points_changed(new_total: int):
	update_skill_points_display()
	_restyle_all_nodes()

	# Refresh the details panel to update the level-up button state.
	if not selected_ability_id.is_empty():
		var selected_data = ResourceManager.get_ability_data(selected_ability_id)
		if selected_data:
			var current_level = ability_component.get_ability_level(selected_ability_id)
			update_details(selected_data, current_level)
