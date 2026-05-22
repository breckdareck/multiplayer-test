extends RefCounted
## Bot navigation: platform-aware routing across a map's nav graph, the
## ground/jump/climb/drop movement heuristics, and the raycast terrain probes.
## Owned by a BotBrain. The brain's _do_* action handlers call navigate_smart()
## to route toward a goal; try_jump / is_near_ledge / raycast_down /
## is_wall_between are shared terrain helpers used by the brain's retreat/wander
## code and the combat module. compute_jump_profile() derives jump reach from
## the player's real movement tuning.

const BotNavGraph = preload("res://scripts/Bot/bot_nav_graph.gd")

var brain                       ## The owning BotBrain node.

const JUMP_COOLDOWN: float = 0.8
var _jump_cooldown_timer: float = 0.0

# Jump reachability — derived from the player's real jump_velocity, move_speed
# and project gravity in compute_jump_profile(). Defaults match the stock
# player tuning so navigation still behaves sanely if derivation fails.
## Safety margin on the raw physics peak so the bot only commits to jumps it
## can comfortably clear.
const JUMP_HEIGHT_SAFETY: float = 0.88
## Max vertical distance (px) the bot will attempt to jump to reach a target.
var _max_jump_height: float = 40.0
## Horizontal stand-off (px) used when launching up to an elevated portal —
## roughly the bot's horizontal travel during a jump's rise, so the arc carries
## it from the launch point onto the portal.
var _jump_launch_offset: float = 40.0

var _wall_stuck_timer: float = 0.0
const WALL_STUCK_JUMP_TIME: float = 0.4

# --- Graph navigation: the map's platform-nav graph (bot_nav_graph.gd) routes
# the bot across terrain; per-waypoint movement reuses _navigate_toward /
# _climb_toward. Falls back to direct navigation when no graph/path exists. ---
var _nav_path: PackedInt64Array = PackedInt64Array()
var _nav_index: int = 0
var _nav_goal: Vector2 = Vector2.INF
var _nav_repath_timer: float = 0.0
const NAV_REPATH_INTERVAL: float = 2.0
## Within this distance of the goal, skip the graph and navigate directly.
const NAV_DIRECT_RANGE: float = 96.0
## Goal drifting this far from the planned path's goal forces a re-plan.
const NAV_GOAL_MOVED: float = 64.0
const NAV_WAYPOINT_X_TOL: float = 20.0
const NAV_WAYPOINT_Y_TOL: float = 22.0
## How far down to look for landing ground when deciding to walk off a ledge —
## generous so a bot will drop from a tall platform instead of freezing on it.
const DROP_SCAN_DEPTH: float = 400.0
## Committed direction while walking to a ledge to descend, so a wall in the way
## doesn't make the bot jitter (or jump). 0 when not currently seeking a drop.
var _descend_dir: int = 0

# Collision masks: Layer 1 (World) = bit 0, Layer 3 (Platforms) = bit 2
const GROUND_MASK: int = 0b101  # World + Platforms
const SOLID_MASK: int = 0b001  # World only (not one-way platforms)


func _init(owner_brain) -> void:
	brain = owner_brain


## Derives jump reachability limits from the player's real movement tuning so the
## navigation heuristics stay correct if jump_velocity / move_speed / gravity are
## ever retuned. Falls back to the defaults if the state machine is unavailable.
func compute_jump_profile() -> void:
	var grav: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	if grav <= 0.0:
		return

	var jump_velocity: float = -300.0
	var move_speed: float = 130.0
	var player: MultiplayerPlayerV2 = brain.player
	if is_instance_valid(player) and is_instance_valid(player.state_machine):
		var jump_state: Node = player.state_machine.get_node_or_null("jump")
		if jump_state and "jump_velocity" in jump_state:
			jump_velocity = jump_state.jump_velocity
		var move_state: Node = player.state_machine.get_node_or_null("move")
		if move_state and "move_speed" in move_state:
			move_speed = move_state.move_speed

	# Peak height of a jump is v^2 / 2g; keep a safety margin so the bot only
	# commits to jumps it can comfortably clear.
	var raw_height: float = (jump_velocity * jump_velocity) / (2.0 * grav)
	_max_jump_height = raw_height * JUMP_HEIGHT_SAFETY
	# Horizontal travel during the jump's rise = move_speed * time-to-apex.
	_jump_launch_offset = move_speed * (absf(jump_velocity) / grav)


## Routes the bot toward a distant goal using the map's platform-nav graph,
## falling back to direct navigation when the graph is unavailable or the goal
## is near. The graph picks the route; _navigate_toward / _climb_toward execute
## each hop.
func navigate_smart(goal: Vector2) -> void:
	var player: MultiplayerPlayerV2 = brain.player
	# Close in — the graph adds nothing, and its waypoints are coarser than the
	# direct heuristics for the final approach (e.g. entering a portal Area2D).
	if player.global_position.distance_to(goal) < NAV_DIRECT_RANGE:
		_nav_path = PackedInt64Array()
		_navigate_toward_or_climb(goal)
		return

	_ensure_nav_path(goal)
	if _nav_path.is_empty():
		_navigate_toward_or_climb(goal)
		return

	_steer_along_nav_path(goal)


## (Re)plans the waypoint path when none exists, the goal has drifted, or the
## repath interval has elapsed.
func _ensure_nav_path(goal: Vector2) -> void:
	var player: MultiplayerPlayerV2 = brain.player
	var need := _nav_path.is_empty()
	if not need and _nav_goal.distance_to(goal) > NAV_GOAL_MOVED:
		need = true
	if not need and _nav_repath_timer <= 0.0:
		need = true
	if not need:
		return

	_nav_repath_timer = NAV_REPATH_INTERVAL
	_nav_goal = goal
	_nav_index = 0
	_nav_path = PackedInt64Array()
	var graph := _get_nav_graph()
	if graph != null:
		_nav_path = graph.find_id_path(player.global_position, goal)


## The platform-nav graph for the bot's current map, or null.
func _get_nav_graph() -> BotNavGraph:
	var map_node: Node = brain._get_map_node()
	if not is_instance_valid(map_node):
		return null
	var map_id: String = MapManager.get_player_map(brain.bot_id)
	return BotManager.get_nav_graph(map_id, map_node, _max_jump_height, _jump_launch_offset)


## Advances past reached waypoints and steers toward the next one. When the path
## is consumed, finishes with direct navigation to the real goal.
func _steer_along_nav_path(goal: Vector2) -> void:
	var player: MultiplayerPlayerV2 = brain.player
	var graph := _get_nav_graph()
	if graph == null:
		_nav_path = PackedInt64Array()
		_navigate_toward_or_climb(goal)
		return

	while _nav_index < _nav_path.size():
		var id: int = _nav_path[_nav_index]
		if not graph.has_point(id):
			# Stale path (graph changed under us) — drop it and re-plan later.
			_nav_path = PackedInt64Array()
			_navigate_toward_or_climb(goal)
			return
		var wp := graph.point_position(id)
		var reached := player.is_on_floor() \
			and absf(wp.x - player.global_position.x) <= NAV_WAYPOINT_X_TOL \
			and absf(wp.y - player.global_position.y) <= NAV_WAYPOINT_Y_TOL
		if reached:
			_nav_index += 1
		else:
			break

	if _nav_index >= _nav_path.size():
		_nav_path = PackedInt64Array()
		_navigate_toward_or_climb(goal)
		return

	_navigate_toward_or_climb(graph.point_position(_nav_path[_nav_index]))


## Single-hop movement toward a target: climb logic if it sits above jump range,
## otherwise the standard ground/jump heuristic.
func _navigate_toward_or_climb(target: Vector2) -> void:
	var player: MultiplayerPlayerV2 = brain.player
	if target.y - player.global_position.y < -_max_jump_height:
		_climb_toward(target)
	else:
		_navigate_toward(target)


## Climbs the bot up to a target that sits above its current floor (e.g. a
## portal on a block). Walks to a horizontal launch point offset from the
## target, then jumps so the rising arc carries the bot onto it.
func _climb_toward(portal_pos: Vector2) -> void:
	var player: MultiplayerPlayerV2 = brain.player
	var bot_pos := player.global_position

	# Steer toward the target itself while airborne or mounting a wall.
	var portal_dir := 1 if portal_pos.x > bot_pos.x else -1

	if not player.is_on_floor():
		player.direction = portal_dir
		player.facing_direction = portal_dir
		return

	# Blocked by the platform's side — jump to mount it.
	if player.is_on_wall():
		player.direction = portal_dir
		player.facing_direction = portal_dir
		if _wall_stuck_timer >= WALL_STUCK_JUMP_TIME:
			try_jump()
		return

	# Approach from whichever side of the portal the bot is already on, so it
	# never tries to jump straight up into the underside of the platform.
	var side := -1 if bot_pos.x <= portal_pos.x else 1
	var launch_x := portal_pos.x + side * _jump_launch_offset
	var to_launch := launch_x - bot_pos.x

	# At the launch point: jump and steer toward the portal. Wait in place if
	# the jump is still on cooldown rather than drifting off the mark.
	if absf(to_launch) <= 4.0:
		if _jump_cooldown_timer <= 0.0:
			player.direction = portal_dir
			player.facing_direction = portal_dir
			try_jump()
		else:
			player.direction = 0
		return

	# Walk toward the launch point, stopping short of any unsafe ledge.
	var dir := 1 if to_launch > 0 else -1
	player.direction = dir
	player.facing_direction = dir
	if is_near_ledge() and not _has_ground_across_gap(dir):
		if not raycast_down(bot_pos + Vector2(dir * 18.0, 0), 200.0):
			player.direction = 0


## Navigates the bot toward a target position, handling platform traversal.
func _navigate_toward(target_pos: Vector2) -> void:
	var player: MultiplayerPlayerV2 = brain.player
	var to_target := target_pos - player.global_position
	var dir := 1 if to_target.x > 0 else -1
	player.direction = dir
	player.facing_direction = dir

	if not player.is_on_floor():
		return

	var dy := to_target.y  # positive = target below, negative = target above

	# --- Target is below us: descend by dropping/walking off a ledge. Handled
	# before the wall check because jumping can never take the bot downward. ---
	if dy > 20.0:
		if player.can_drop_through_platform():
			_descend_dir = 0
			player.do_drop = true
			return
		# Commit to a direction toward a ledge so a wall in the way doesn't make
		# the bot jitter; if it stays walled, flip to seek a ledge the other way.
		if _descend_dir == 0:
			_descend_dir = dir
		if player.is_on_wall() and _wall_stuck_timer >= WALL_STUCK_JUMP_TIME:
			_descend_dir = -_descend_dir
		player.direction = _descend_dir
		player.facing_direction = _descend_dir
		# At a ledge — walk off it only when there is ground below to land on.
		if is_near_ledge():
			_descend_dir = 0
			if not raycast_down(player.global_position + Vector2(player.direction * 18.0, 0), DROP_SCAN_DEPTH):
				player.direction = 0  # ledge over a pit / map edge — hold
		return
	_descend_dir = 0

	# --- Stuck against a wall (target at or above us): jump to get over it ---
	if player.is_on_wall():
		if _wall_stuck_timer >= WALL_STUCK_JUMP_TIME:
			try_jump()
		return

	# --- Target is above us ---
	if dy < -10.0:
		if abs(dy) <= _max_jump_height:
			try_jump()
			return
		if is_near_ledge():
			player.direction = 0
		return

	# --- Target is roughly same level ---
	if is_near_ledge():
		if _has_ground_across_gap(dir):
			return  # safe to walk off — will land on ground ahead
		if dy > 5.0 and raycast_down(player.global_position + Vector2(dir * 18.0, 0), DROP_SCAN_DEPTH):
			return
		player.direction = 0


func try_jump() -> void:
	var player: MultiplayerPlayerV2 = brain.player
	if _jump_cooldown_timer <= 0.0 and player.is_on_floor():
		player.do_jump = true
		_jump_cooldown_timer = JUMP_COOLDOWN


# --- Raycast helpers ---
# All rays extend 2px past tile boundaries (16px tiles) to ensure hits.

func _get_space_state() -> PhysicsDirectSpaceState2D:
	var player: MultiplayerPlayerV2 = brain.player
	return player.get_world_2d().direct_space_state


## Cast a ray downward from a position. Returns true if ground is found within max_depth.
func raycast_down(from: Vector2, max_depth: float) -> bool:
	var player: MultiplayerPlayerV2 = brain.player
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, max_depth), GROUND_MASK)
	query.exclude = [player.get_rid()]
	var result := _get_space_state().intersect_ray(query)
	return not result.is_empty()


## Check if there's ground on the other side of a gap (within ~3 tiles ahead).
func _has_ground_across_gap(dir: int) -> bool:
	var player: MultiplayerPlayerV2 = brain.player
	for offset_x in [34, 50]:
		var from := player.global_position + Vector2(dir * offset_x, -2.0)
		var to := from + Vector2(0, 34.0)
		var query := PhysicsRayQueryParameters2D.create(from, to, GROUND_MASK)
		query.exclude = [player.get_rid()]
		var result := _get_space_state().intersect_ray(query)
		if not result.is_empty():
			return true
	return false


## Check if there's a solid wall between two positions (horizontal ray on World layer only).
func is_wall_between(from: Vector2, to: Vector2) -> bool:
	var player: MultiplayerPlayerV2 = brain.player
	var query := PhysicsRayQueryParameters2D.create(from, to, SOLID_MASK)
	query.exclude = [player.get_rid()]
	var result := _get_space_state().intersect_ray(query)
	return not result.is_empty()


func is_near_ledge() -> bool:
	var player: MultiplayerPlayerV2 = brain.player
	var check_distance := 12.0
	var check_depth := 18.0  # 16px tile + 2px buffer
	var dir := player.direction if player.direction != 0 else player.facing_direction
	var forward_offset := Vector2(dir * check_distance, 0)
	var forward_transform := player.global_transform.translated(forward_offset)
	return not player.test_move(forward_transform, Vector2(0, check_depth))
