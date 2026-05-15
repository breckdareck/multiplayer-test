extends Node

const TELEPORT_RANGE: float = 100.0
const EDGE_SNAP_DISTANCE: float = 32.0
const GROUND_CHECK_DISTANCE: float = 300.0
const LANDING_OFFSET: float = 1.0
const STEP_SIZE: float = 8.0

func execute(owner_node: Node, _ability: AbilityData, level_stats: AbilityLevelData):
	var space_state: PhysicsDirectSpaceState2D = owner_node.get_world_2d().direct_space_state
	var collision_mask: int = owner_node.collision_mask
	var origin: Vector2 = owner_node.global_position

	var input_up: bool = owner_node.get("input_up") == true
	var input_down: bool = owner_node.get("input_down") == true

	var destination: Vector2
	if input_up:
		destination = _try_teleport_up(origin, space_state, collision_mask, owner_node)
	elif input_down:
		destination = _try_teleport_down(origin, space_state, collision_mask, owner_node)
	else:
		destination = _try_horizontal_teleport(origin, owner_node.facing_direction, space_state, collision_mask, owner_node)

	if destination == origin:
		return

	owner_node.global_position = destination
	owner_node.velocity = Vector2.ZERO
	print("%s teleported to %s (Level %d)" % [owner_node.name, destination, level_stats.level])


func _try_horizontal_teleport(origin: Vector2, dir: int, space: PhysicsDirectSpaceState2D, mask: int, owner: Node) -> Vector2:
	var best := origin

	var dist := STEP_SIZE
	while dist <= TELEPORT_RANGE:
		var test_x := origin.x + dir * dist

		var ground_y := _find_ground_y_from_above(Vector2(test_x, origin.y), space, mask, owner)
		if ground_y == INF:
			break

		var landing := Vector2(test_x, ground_y - LANDING_OFFSET)

		if not _is_position_blocked(landing, space, mask, owner):
			best = landing
		else:
			var snapped := _try_edge_snap(landing, space, mask, owner)
			if not _is_position_blocked(snapped, space, mask, owner):
				best = snapped
			else:
				break

		dist += STEP_SIZE

	return best


func _try_teleport_up(origin: Vector2, space: PhysicsDirectSpaceState2D, mask: int, owner: Node) -> Vector2:
	var was_blocked := false

	var y := origin.y - STEP_SIZE
	while y >= origin.y - TELEPORT_RANGE:
		var pos := Vector2(origin.x, y)
		var blocked := _is_position_blocked(pos, space, mask, owner)

		if was_blocked and not blocked:
			return pos

		was_blocked = blocked
		y -= STEP_SIZE

	return origin


func _try_teleport_down(origin: Vector2, space: PhysicsDirectSpaceState2D, mask: int, owner: Node) -> Vector2:
	var scan_start := origin + Vector2(0, STEP_SIZE)
	var ray := PhysicsRayQueryParameters2D.create(
		scan_start, scan_start + Vector2(0, GROUND_CHECK_DISTANCE), mask, [owner.get_rid()])
	var result := space.intersect_ray(ray)

	if result.is_empty():
		return origin

	var landing := Vector2(origin.x, result.position.y - LANDING_OFFSET)

	if landing.y <= origin.y + STEP_SIZE:
		return origin

	if _is_position_blocked(landing, space, mask, owner):
		return origin

	return landing


func _find_ground_y_from_above(reference: Vector2, space: PhysicsDirectSpaceState2D, mask: int, owner: Node) -> float:
	var scan_top := Vector2(reference.x, reference.y - TELEPORT_RANGE)
	var scan_bottom := scan_top + Vector2(0, TELEPORT_RANGE + GROUND_CHECK_DISTANCE)
	var ray := PhysicsRayQueryParameters2D.create(scan_top, scan_bottom, mask, [owner.get_rid()])
	var result := space.intersect_ray(ray)
	if result.is_empty():
		return INF
	return result.position.y


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


func _try_edge_snap(pos: Vector2, space: PhysicsDirectSpaceState2D, mask: int, owner: Node) -> Vector2:
	if _is_position_blocked(pos, space, mask, owner):
		for i in range(1, int(EDGE_SNAP_DISTANCE / 4.0) + 1):
			var snapped := pos + Vector2(0, -4.0 * i)
			if not _is_position_blocked(snapped, space, mask, owner):
				return snapped
	return pos
