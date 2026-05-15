extends Node

## Ability logic for Mage's Teleport.
## Blinks the player in the direction they're holding. Server-authoritative.
## Supports horizontal (facing direction), up (W), and down (S) teleport.
## Validates destination against collision to prevent teleporting into walls,
## and snaps to nearby ledges when teleporting vertically.

const TELEPORT_RANGE: float = 100.0
const EDGE_SNAP_DISTANCE: float = 24.0
const GROUND_CHECK_DISTANCE: float = 200.0

func execute(owner_node: Node, _ability: AbilityData, level_stats: AbilityLevelData):
	var space_state: PhysicsDirectSpaceState2D = owner_node.get_world_2d().direct_space_state
	var collision_mask: int = owner_node.collision_mask
	var origin: Vector2 = owner_node.global_position

	var input_up: bool = owner_node.get("input_up") == true
	var input_down: bool = owner_node.get("input_down") == true

	var destination: Vector2
	if input_up:
		destination = _try_vertical_teleport(origin, -1, space_state, collision_mask, owner_node)
	elif input_down:
		destination = _try_vertical_teleport(origin, 1, space_state, collision_mask, owner_node)
	else:
		destination = _try_horizontal_teleport(origin, owner_node.facing_direction, space_state, collision_mask, owner_node)

	if destination == origin:
		print("%s teleport blocked — no valid destination (Level %d)" % [owner_node.name, level_stats.level])
		return

	owner_node.global_position = destination
	owner_node.velocity = Vector2.ZERO
	print("%s teleported to %s (Level %d)" % [owner_node.name, destination, level_stats.level])


func _try_horizontal_teleport(origin: Vector2, dir: int, space: PhysicsDirectSpaceState2D, mask: int, owner: Node) -> Vector2:
	var target := origin + Vector2(dir * TELEPORT_RANGE, 0.0)

	if _is_position_blocked(target, space, mask, owner):
		var clear := _find_furthest_clear_horizontal(origin, dir, space, mask, owner)
		if clear == origin:
			return origin
		target = clear

	# Snap down to ground if there is ground below
	var grounded := _find_ground_below(target, space, mask, owner)
	if grounded != Vector2.INF:
		target.y = grounded.y
	else:
		return origin

	# Try snapping up to a nearby ledge edge
	target = _try_edge_snap(target, space, mask, owner)

	if _is_position_blocked(target, space, mask, owner):
		return origin

	return target


func _try_vertical_teleport(origin: Vector2, y_dir: int, space: PhysicsDirectSpaceState2D, mask: int, owner: Node) -> Vector2:
	var target := origin + Vector2(0.0, y_dir * TELEPORT_RANGE)

	# For downward teleport, find ground below the target
	if y_dir > 0:
		var grounded := _find_ground_below(target, space, mask, owner)
		if grounded == Vector2.INF:
			return origin
		target.y = grounded.y
	else:
		# For upward teleport, find ground below target to land on
		var grounded := _find_ground_below(target, space, mask, owner)
		if grounded == Vector2.INF:
			return origin
		target.y = grounded.y

	if _is_position_blocked(target, space, mask, owner):
		return origin

	return target


func _is_position_blocked(pos: Vector2, space: PhysicsDirectSpaceState2D, mask: int, owner: Node) -> bool:
	var shape := owner.get_node("StandingCollisionShape").shape as Shape2D
	var offset: Vector2 = owner.get_node("StandingCollisionShape").position
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0, pos + offset)
	params.collision_mask = mask
	params.exclude = [owner.get_rid()]
	var results := space.intersect_shape(params, 1)
	return not results.is_empty()


func _find_ground_below(pos: Vector2, space: PhysicsDirectSpaceState2D, mask: int, owner: Node) -> Vector2:
	var ray_params := PhysicsRayQueryParameters2D.create(pos, pos + Vector2(0, GROUND_CHECK_DISTANCE), mask, [owner.get_rid()])
	var result := space.intersect_ray(ray_params)
	if result.is_empty():
		return Vector2.INF
	return result.position


func _find_furthest_clear_horizontal(origin: Vector2, dir: int, space: PhysicsDirectSpaceState2D, mask: int, owner: Node) -> Vector2:
	var step := 16.0
	var best := origin
	var dist := step
	while dist <= TELEPORT_RANGE:
		var test_pos := origin + Vector2(dir * dist, 0.0)
		if _is_position_blocked(test_pos, space, mask, owner):
			break
		best = test_pos
		dist += step
	return best


func _try_edge_snap(pos: Vector2, space: PhysicsDirectSpaceState2D, mask: int, owner: Node) -> Vector2:
	if _is_position_blocked(pos, space, mask, owner):
		# Try snapping upward in small increments
		for i in range(1, int(EDGE_SNAP_DISTANCE / 4.0) + 1):
			var snapped := pos + Vector2(0, -4.0 * i)
			if not _is_position_blocked(snapped, space, mask, owner):
				return snapped
	return pos
