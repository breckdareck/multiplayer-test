extends Node

const TELEPORT_RANGE: float = 100.0
const EDGE_SNAP_DISTANCE: float = 33.0
const GROUND_CHECK_DISTANCE: float = 33.0
const LANDING_OFFSET: float = 1.0
const STEP_SIZE: float = 8.0
const HORIZONTAL_HEIGHT_TOLERANCE: float = 33.0
const DEBUG_DRAW: bool = true
const DEBUG_DURATION: float = 3.0

## Brief i-frame window after a successful blink — the mage's escape mirrors the
## bow's Disengage / sword's Vault Strike pattern (contact damage / knockback
## can't punish the reposition). Extendable via the "iframe_duration_bonus"
## upgrade (Phaseguard T3 variant).
const IFRAME_DURATION: float = 0.3

func execute(owner_node: Node, _ability: AbilityData, level_stats: AbilityLevelData):
	if not owner_node.multiplayer.is_server():
		return

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

	owner_node.velocity = Vector2.ZERO
	owner_node.global_position = destination
	owner_node.move_and_slide()
	print("%s teleported to %s (Level %d)" % [owner_node.name, destination, level_stats.level])

	_grant_iframes(owner_node, _ability)


## Grant a brief invulnerability window after the blink. Mirrors
## AL_Disengage / AL_VaultStrike: set is_invulnerable directly and schedule a
## one-shot clear, but only clear the flag if WE still own it (the
## invulnerability_timer is stopped) so a take_damage() during the window keeps
## its own (longer) invuln.
func _grant_iframes(owner_node: Node, ability: AbilityData) -> void:
	var health_comp = owner_node.get("health_component")
	if health_comp == null or not is_instance_valid(health_comp):
		return

	var duration: float = IFRAME_DURATION
	# Phase Step upgrade: "iframe_duration_bonus" (+s) extends the window.
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "iframe_duration_bonus")

	health_comp.is_invulnerable = true
	owner_node.get_tree().create_timer(duration).timeout.connect(
		func():
			if is_instance_valid(health_comp):
				if not health_comp.invulnerability_timer.is_stopped():
					return
				health_comp.is_invulnerable = false
	)


func _try_horizontal_teleport(origin: Vector2, dir: int, space: PhysicsDirectSpaceState2D, mask: int, actor: Node) -> Vector2:
	var best := origin

	if DEBUG_DRAW:
		_debug_draw_circle(actor, origin, 4.0, Color.WHITE)

	var dist := STEP_SIZE
	while dist <= TELEPORT_RANGE:
		var test_x := origin.x + dir * dist
		var ref := Vector2(test_x, origin.y)

		# Try to find ground first (handles slopes and normal terrain)
		var ground_y := _find_ground_in_range(ref, space, mask, actor)
		if ground_y == INF:
			# No ground below — check if we've hit a wall/obstacle
			if _is_position_blocked(ref, space, mask, actor):
				if DEBUG_DRAW:
					_debug_draw_circle(actor, ref, 2.0, Color.MAGENTA)
				var top_y := _find_ground_y_from_above(ref, space, mask, actor, HORIZONTAL_HEIGHT_TOLERANCE)
				if top_y != INF:
					var wall_top := Vector2(test_x, top_y - LANDING_OFFSET)
					if not _is_position_blocked(wall_top, space, mask, actor):
						if DEBUG_DRAW:
							_debug_draw_circle(actor, wall_top, 3.0, Color.GREEN)
						best = wall_top
						break
					else:
						var snapped_pos := _try_edge_snap(wall_top, space, mask, actor)
						if not _is_position_blocked(snapped_pos, space, mask, actor):
							if DEBUG_DRAW:
								_debug_draw_circle(actor, snapped_pos, 3.0, Color.YELLOW)
							best = snapped_pos
							break
			# No ground, no landable obstacle — keep stepping
			if DEBUG_DRAW:
				_debug_draw_circle(actor, ref, 2.0, Color.DARK_GRAY)
			dist += STEP_SIZE
			continue

		var landing := Vector2(test_x, ground_y - LANDING_OFFSET)

		if not _is_position_blocked(landing, space, mask, actor):
			if DEBUG_DRAW:
				_debug_draw_circle(actor, landing, 3.0, Color.GREEN)
			best = landing
		else:
			var snapped_pos := _try_edge_snap(landing, space, mask, actor)
			if not _is_position_blocked(snapped_pos, space, mask, actor):
				if DEBUG_DRAW:
					_debug_draw_circle(actor, snapped_pos, 3.0, Color.YELLOW)
				best = snapped_pos
			else:
				#print("Teleport: BLOCKED LANDING at %s, edge snap failed (dist=%.0f)" % [landing, dist])
				if DEBUG_DRAW:
					_debug_draw_circle(actor, landing, 3.0, Color.RED)
				break

		dist += STEP_SIZE

	if DEBUG_DRAW and best != origin:
		_debug_draw_circle(actor, best, 6.0, Color.CYAN)

	return best


func _find_ground_in_range(reference: Vector2, space: PhysicsDirectSpaceState2D, mask: int, actor: Node) -> float:
	# Start slightly above origin to handle uphill slopes
	var scan_start := Vector2(reference.x, reference.y - STEP_SIZE * 2)
	var scan_end := Vector2(reference.x, reference.y + GROUND_CHECK_DISTANCE)
	var ray := PhysicsRayQueryParameters2D.create(scan_start, scan_end, mask, [actor.get_rid()])
	var result := space.intersect_ray(ray)
	if DEBUG_DRAW:
		_debug_draw_line(actor, scan_start, scan_end, Color(1, 0.5, 0, 0.4))
	if not result.is_empty():
		if DEBUG_DRAW:
			_debug_draw_circle(actor, result.position, 2.0, Color.ORANGE)
		return result.position.y
	return INF


func _try_teleport_up(origin: Vector2, space: PhysicsDirectSpaceState2D, mask: int, actor: Node) -> Vector2:
	var was_blocked := false

	var y := origin.y - STEP_SIZE
	while y >= origin.y - TELEPORT_RANGE:
		var pos := Vector2(origin.x, y)
		var blocked := _is_position_blocked(pos, space, mask, actor)

		if was_blocked and not blocked:
			return pos

		was_blocked = blocked
		y -= STEP_SIZE

	return origin


func _try_teleport_down(origin: Vector2, space: PhysicsDirectSpaceState2D, mask: int, actor: Node) -> Vector2:
	var scan_start := origin + Vector2(0, STEP_SIZE)
	var ray := PhysicsRayQueryParameters2D.create(
		scan_start, scan_start + Vector2(0, TELEPORT_RANGE), mask, [actor.get_rid()])
	var result := space.intersect_ray(ray)

	if result.is_empty():
		return origin

	var landing := Vector2(origin.x, result.position.y - LANDING_OFFSET)

	if landing.y <= origin.y + STEP_SIZE:
		return origin

	if _is_position_blocked(landing, space, mask, actor):
		return origin

	return landing


func _find_ground_y_from_above(reference: Vector2, space: PhysicsDirectSpaceState2D, mask: int, actor: Node, max_up: float = TELEPORT_RANGE) -> float:
	var scan_top := Vector2(reference.x, reference.y - max_up)
	var scan_bottom := Vector2(reference.x, reference.y + GROUND_CHECK_DISTANCE)
	var ray := PhysicsRayQueryParameters2D.create(scan_top, scan_bottom, mask, [actor.get_rid()])
	var result := space.intersect_ray(ray)
	if result.is_empty():
		return INF
	return result.position.y


func _is_position_blocked(pos: Vector2, space: PhysicsDirectSpaceState2D, mask: int, actor: Node) -> bool:
	var shape := actor.get_node("StandingCollisionShape").shape as Shape2D
	var offset: Vector2 = actor.get_node("StandingCollisionShape").position
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0, pos + offset)
	params.collision_mask = mask
	params.exclude = [actor.get_rid()]
	var results := space.intersect_shape(params, 1)
	return not results.is_empty()


func _try_edge_snap(pos: Vector2, space: PhysicsDirectSpaceState2D, mask: int, actor: Node) -> Vector2:
	if _is_position_blocked(pos, space, mask, actor):
		for i in range(1, int(EDGE_SNAP_DISTANCE / 4.0) + 1):
			var snapped_pos := pos + Vector2(0, -4.0 * i)
			if not _is_position_blocked(snapped_pos, space, mask, actor):
				return snapped_pos
	return pos


func _debug_draw_circle(actor: Node, pos: Vector2, radius: float, color: Color) -> void:
	var map = actor.get_parent().get_parent()
	if not is_instance_valid(map):
		return
	var line := Line2D.new()
	var points: PackedVector2Array = []
	for a in range(0, 17):
		var angle := a * TAU / 16.0
		points.append(pos - map.global_position + Vector2(cos(angle), sin(angle)) * radius)
	line.points = points
	line.default_color = color
	line.width = 1.5
	line.z_index = 100
	map.add_child(line)
	map.get_tree().create_timer(DEBUG_DURATION).timeout.connect(line.queue_free)


func _debug_draw_line(actor: Node, from: Vector2, to: Vector2, color: Color) -> void:
	var map = actor.get_parent().get_parent()
	if not is_instance_valid(map):
		return
	var line := Line2D.new()
	line.points = [from - map.global_position, to - map.global_position]
	line.default_color = color
	line.width = 1.0
	line.z_index = 100
	map.add_child(line)
	map.get_tree().create_timer(DEBUG_DURATION).timeout.connect(line.queue_free)
