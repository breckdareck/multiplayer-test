@tool
extends Node2D
class_name MapBase

# This script should be attached to the root node of every map scene.
# Maps now use manual spawning for both the map itself and players.
#
# @tool: the script also runs in the editor so the Camera Bounds can be drawn
# as a colored outline directly on the map. That preview is editor-only —
# none of the editor code paths fire at runtime.

## Path to the background music track for this map (e.g. "res://assets/music/gameplay.mp3").
## Leave empty to keep playing whatever is currently playing.
@export_file("*.mp3", "*.ogg", "*.wav") var bgm_path: String = ""

## Themed display name for this zone (e.g. "Maple Town", "Goblin Hollow").
## Surfaced by the ZoneBanner overlay when the local player enters the map.
## Leave empty to suppress the banner for this map.
@export var display_name: String = ""

@export_category("Camera Bounds")
## When true, the limits below are auto-computed from the "Mid" TileMapLayer
## on _ready (with the padding values below applied). Set to false and edit
## the four limit_* values manually to override.
@export var camera_bounds_auto: bool = true
## Padding applied when auto-computing bounds. The `Mid` tile layer captures
## only the ground; players need room to jump above it, and a bit of room
## below for fall/killzone. Horizontal padding is usually 0 (portals already
## sit at the map edges).
@export var camera_top_padding: int = 400
@export var camera_bottom_padding: int = 80
@export var camera_horizontal_padding: int = 0
## Camera2D limit_* values applied to the local player's camera on spawn.
## Defaults match Camera2D's own defaults (effectively unbounded). When
## `camera_bounds_auto` is true, the runtime `_ready()` overwrites these.
@export var camera_limit_left: int = -10000000
@export var camera_limit_top: int = -10000000
@export var camera_limit_right: int = 10000000
@export var camera_limit_bottom: int = 10000000

@export_category("Side Walls")
## When true, two invisible walls (a StaticBody2D with WorldBoundaryShape2D
## colliders on the "World" layer) are created at runtime at the left/right
## edges of the playable ground, so players and enemies can't walk or get
## knocked off the sides of the map. Computed from the same "Mid" tile layer
## as the camera bounds.
@export var side_walls_auto: bool = true
## Pushes the walls outward (+) or inward (-) from the ground edges, in pixels.
@export var side_wall_margin: float = 0.0

@export_category("Editor Preview")
## Draw a colored outline of the camera bounds directly on the map in the
## editor view. The preview live-updates as you edit the tilemap or padding.
@export var show_bounds_in_editor: bool = true
@export var bounds_outline_color: Color = Color(1.0, 0.85, 0.2, 0.9)


func _ready() -> void:
	if Engine.is_editor_hint():
		# Editor: don't write to exports, don't register in the runtime group.
		# The _draw() preview reads bounds via _compute_preview_bounds() so the
		# .tscn never gets dirtied by the auto-compute.
		queue_redraw()
		return
	set_process(false)  # no editor-preview work needed at runtime
	add_to_group("map_base")
	if camera_bounds_auto:
		_auto_compute_camera_bounds()
	if side_walls_auto:
		_create_side_walls()


func _process(_delta: float) -> void:
	# Editor-only: re-queue _draw each frame so the outline updates live as the
	# user edits the tilemap or tweaks padding values. Runtime _process is
	# disabled by `set_process(false)` in `_ready`.
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint() or not show_bounds_in_editor:
		return
	var bounds: Variant
	if camera_bounds_auto:
		bounds = _compute_preview_bounds()
		if bounds == null:
			return
	else:
		bounds = [camera_limit_left, camera_limit_top, camera_limit_right, camera_limit_bottom]
	var rect := Rect2(
		Vector2(bounds[0], bounds[1]),
		Vector2(bounds[2] - bounds[0], bounds[3] - bounds[1])
	)
	# Outer outline of the camera-reachable bounds.
	draw_rect(rect, bounds_outline_color, false, 4.0)
	# Numeric readout in the upper-left corner of the rect.
	var font: Font = ThemeDB.fallback_font
	if font:
		var label_text := "Camera Bounds  L:%d  T:%d  R:%d  B:%d  (%s)" % [
			int(bounds[0]), int(bounds[1]), int(bounds[2]), int(bounds[3]),
			"auto" if camera_bounds_auto else "manual",
		]
		draw_string(font, Vector2(bounds[0] + 8, bounds[1] + 22), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, bounds_outline_color)
	# Side-wall preview: vertical lines where the runtime walls will sit.
	if side_walls_auto:
		var extent: Variant = _compute_ground_extent_x()
		if extent != null:
			var wall_color := Color(1.0, 0.35, 0.2, 0.9)
			var left_x: float = extent[0] - side_wall_margin
			var right_x: float = extent[1] + side_wall_margin
			draw_line(Vector2(left_x, bounds[1]), Vector2(left_x, bounds[3]), wall_color, 3.0)
			draw_line(Vector2(right_x, bounds[1]), Vector2(right_x, bounds[3]), wall_color, 3.0)


## Build the runtime side walls: one StaticBody2D with two WorldBoundaryShape2D
## colliders (infinite vertical half-planes facing inward) at the horizontal
## edges of the playable ground. Runs on every peer — the walls are
## deterministic from the scene, not networked state.
func _create_side_walls() -> void:
	var extent: Variant = _compute_ground_extent_x()
	if extent == null:
		return
	var walls := StaticBody2D.new()
	walls.name = "SideWalls"
	walls.collision_layer = 1  # "World" — both players and enemies mask it
	walls.collision_mask = 0
	var sides: Array = [
		[extent[0] - side_wall_margin, Vector2.RIGHT],  # left wall, pushes right
		[extent[1] + side_wall_margin, Vector2.LEFT],   # right wall, pushes left
	]
	for side in sides:
		var shape := WorldBoundaryShape2D.new()
		shape.normal = side[1]
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = Vector2(side[0], 0)
		walls.add_child(collider)
	add_child(walls)


## Global min/max X of the playable ground ("Mid" layer used rect), as
## [min_x, max_x], or null if no usable tilemap is found.
func _compute_ground_extent_x() -> Variant:
	var layer: TileMapLayer = _find_playable_tilemap_layer(self)
	if not is_instance_valid(layer) or not layer.tile_set:
		return null
	var used: Rect2i = layer.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	var tile_size: Vector2 = Vector2(layer.tile_set.tile_size)
	return [
		layer.to_global(Vector2(used.position) * tile_size).x,
		layer.to_global(Vector2(used.end) * tile_size).x,
	]


## Compute what the auto-bounds would be without mutating any export. Returns
## an [left, top, right, bottom] Array, or null if no usable tilemap is found.
func _compute_preview_bounds() -> Variant:
	var layer: TileMapLayer = _find_playable_tilemap_layer(self)
	if not is_instance_valid(layer):
		return null
	var used: Rect2i = layer.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	if not layer.tile_set:
		return null
	var tile_size: Vector2 = Vector2(layer.tile_set.tile_size)
	var local_min: Vector2 = Vector2(used.position) * tile_size
	var local_max: Vector2 = Vector2(used.end) * tile_size
	var global_min: Vector2 = layer.to_global(local_min)
	var global_max: Vector2 = layer.to_global(local_max)
	return [
		int(global_min.x) - camera_horizontal_padding,
		int(global_min.y) - camera_top_padding,
		int(global_max.x) + camera_horizontal_padding,
		int(global_max.y) + camera_bottom_padding,
	]


## Runtime path: same computation but writes the result into the export vars
## so the player's Camera2D can read them in `_apply_map_camera_bounds`.
func _auto_compute_camera_bounds() -> void:
	var preview: Variant = _compute_preview_bounds()
	if preview == null:
		return
	camera_limit_left = preview[0]
	camera_limit_top = preview[1]
	camera_limit_right = preview[2]
	camera_limit_bottom = preview[3]


## Find the canonical playable-ground TileMapLayer. Prefers a layer named
## "Mid" (the project convention); falls back to the first TileMapLayer found.
func _find_playable_tilemap_layer(node: Node) -> TileMapLayer:
	var fallback: TileMapLayer = null
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is TileMapLayer:
			if current.name == "Mid":
				return current as TileMapLayer
			if fallback == null:
				fallback = current as TileMapLayer
		for child in current.get_children():
			stack.append(child)
	return fallback
