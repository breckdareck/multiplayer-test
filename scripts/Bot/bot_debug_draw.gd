extends Node2D
## Host-side visual debug overlay for bot navigation.
##
## Draws the platform-nav graph (surfaces, points, jump/drop/gap edges) and each
## bot's planned waypoint path, current action and nav goal, for whichever map
## the host is currently viewing. Toggle with `/bot debugdraw`.
##
## Host view only: the nav graph and bot brains live on the server, so this
## renders meaningfully only in the host's process.

const BotNavGraph = preload("res://scripts/Bot/bot_nav_graph.gd")

var enabled: bool = false

## Indexed by BotNavGraph.EdgeKind (WALK, JUMP, DROP, GAP).
const EDGE_COLORS: Array[Color] = [
	Color(0.4, 0.9, 0.4, 0.35),   # WALK  — green (mostly redundant with surfaces)
	Color(0.3, 0.8, 1.0, 0.75),   # JUMP  — cyan
	Color(1.0, 0.6, 0.2, 0.75),   # DROP  — orange
	Color(1.0, 0.9, 0.2, 0.75),   # GAP   — yellow
]
const SURFACE_COLOR := Color(1, 1, 1, 0.55)
const ONEWAY_SURFACE_COLOR := Color(0.5, 1.0, 0.7, 0.7)  ## One-way platforms.
const POINT_COLOR := Color(1, 1, 1, 0.9)
const PATH_COLOR := Color(1.0, 0.25, 0.85, 0.95)
const GOAL_COLOR := Color(1.0, 0.25, 0.85, 0.4)


func _ready() -> void:
	top_level = true                 # draw in world space, ignore parent transform
	global_position = Vector2.ZERO
	z_index = 4096


func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var map_id: String = MapManager.get_player_map(1)
	if map_id.is_empty():
		return
	var graph: BotNavGraph = BotManager.debug_nav_graph(map_id)
	if graph == null:
		return
	if graph.is_building():
		_draw_status("nav graph: building…", Color.YELLOW)
		return
	_draw_graph(graph)
	_draw_bots(map_id, graph)


func _draw_graph(graph: BotNavGraph) -> void:
	for seg in graph.segments:
		var surface_color: Color = ONEWAY_SURFACE_COLOR if seg.one_way else SURFACE_COLOR
		draw_line(Vector2(seg.x_min, seg.y), Vector2(seg.x_max, seg.y), surface_color, 1.5)

	for key in graph.edges:
		var kind: int = graph.edges[key]
		if kind < 0 or kind >= EDGE_COLORS.size():
			continue
		draw_line(graph.point_position(key.x), graph.point_position(key.y),
			EDGE_COLORS[kind], 1.0)

	for i in graph.points.size():
		draw_circle(graph.points[i], 2.0, POINT_COLOR)


func _draw_bots(map_id: String, graph: BotNavGraph) -> void:
	for bot_id in BotManager.active_bots:
		var brain = BotManager.get_bot_brain(bot_id)
		if brain == null or not is_instance_valid(brain.player):
			continue
		if MapManager.get_player_map(bot_id) != map_id:
			continue

		var pos: Vector2 = brain.player.global_position
		_label(pos + Vector2(-18, -26), str(brain.current_action), Color.WHITE)

		# Straight line to the nav goal, then the resolved waypoint path.
		var goal: Vector2 = brain._nav_goal
		if goal.is_finite():
			draw_line(pos, goal, GOAL_COLOR, 1.0)

		var path: PackedInt64Array = brain._nav_path
		var prev := pos
		for idx in range(brain._nav_index, path.size()):
			var id: int = path[idx]
			if not graph.has_point(id):
				break
			var wp := graph.point_position(id)
			draw_line(prev, wp, PATH_COLOR, 2.0)
			draw_circle(wp, 3.5, PATH_COLOR)
			prev = wp


func _draw_status(text: String, color: Color) -> void:
	var host = PlayerManager.get_player_node(1)
	if is_instance_valid(host):
		_label(host.global_position + Vector2(-40, -40), text, color)


func _label(pos: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)
