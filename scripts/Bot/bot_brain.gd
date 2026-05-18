extends Node

var player: MultiplayerPlayerV2
var bot_id: int

var think_timer: float = 0.0
var think_interval: float = 0.3

var current_action: String = "idle"
var action_timer: float = 0.0

var wander_direction: int = 0
var idle_duration_min: float = 1.0
var idle_duration_max: float = 4.0
var wander_duration_min: float = 2.0
var wander_duration_max: float = 6.0
var wander_chance: float = 0.6

var aggro_range: float = 200.0
var attack_range: float = 25.0
var retreat_health_pct: float = 0.2

var target_enemy: EnemyBase = null

var _respawn_timer: float = -1.0
const RESPAWN_DELAY: float = 3.0


func init(player_node: MultiplayerPlayerV2, id: int, behavior_config: Dictionary = {}) -> void:
	player = player_node
	bot_id = id

	think_interval = behavior_config.get("think_interval", 0.3)
	wander_chance = behavior_config.get("wander_chance", 0.6)
	idle_duration_min = behavior_config.get("idle_duration_min", 1.0)
	idle_duration_max = behavior_config.get("idle_duration_max", 4.0)
	wander_duration_min = behavior_config.get("wander_duration_min", 2.0)
	wander_duration_max = behavior_config.get("wander_duration_max", 6.0)
	aggro_range = behavior_config.get("aggro_range", 200.0)

	think_timer = randf() * think_interval


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	if player._is_being_cleaned_up:
		return

	if is_instance_valid(player.health_component) and player.health_component.is_dead:
		_clear_input()
		_handle_dead(delta)
		return

	_respawn_timer = -1.0
	action_timer -= delta
	think_timer -= delta

	if think_timer <= 0.0:
		think_timer = think_interval
		_think()

	_apply_current_action()


func _handle_dead(delta: float) -> void:
	if _respawn_timer < 0.0:
		_respawn_timer = RESPAWN_DELAY
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = -1.0
		player.respawn()


func _think() -> void:
	# Validate current target
	if is_instance_valid(target_enemy):
		if target_enemy.health_component and target_enemy.health_component.is_dead:
			target_enemy = null
	else:
		target_enemy = null

	# Check health for retreat
	if _should_retreat():
		if target_enemy:
			current_action = "retreat"
			return

	# Look for enemies
	if not target_enemy:
		target_enemy = _find_nearest_enemy()

	if target_enemy:
		current_action = "fight"
		return

	# No enemies — wander or idle
	if action_timer > 0.0:
		return

	if randf() < wander_chance:
		_start_wander()
	else:
		_start_idle()


func _should_retreat() -> bool:
	if not is_instance_valid(player.health_component):
		return false
	var health_pct := float(player.health_component.current_health) / float(player.health_component.max_health)
	return health_pct < retreat_health_pct


func _find_nearest_enemy() -> EnemyBase:
	var enemies := get_tree().get_nodes_in_group("Enemies")
	var best: EnemyBase = null
	var best_dist_sq := aggro_range * aggro_range

	for node in enemies:
		if node is not EnemyBase:
			continue
		if not is_instance_valid(node):
			continue
		if node.health_component and node.health_component.is_dead:
			continue

		var dist_sq := player.global_position.distance_squared_to(node.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = node

	return best


func _start_idle() -> void:
	current_action = "idle"
	action_timer = randf_range(idle_duration_min, idle_duration_max)
	wander_direction = 0


func _start_wander() -> void:
	current_action = "wander"
	action_timer = randf_range(wander_duration_min, wander_duration_max)
	wander_direction = 1 if randf() > 0.5 else -1


func _apply_current_action() -> void:
	match current_action:
		"idle":
			player.direction = 0
		"wander":
			_do_wander()
		"fight":
			_do_fight()
		"retreat":
			_do_retreat()


func _do_wander() -> void:
	player.direction = wander_direction
	if player.direction != 0:
		player.facing_direction = player.direction

	if player.is_on_wall():
		wander_direction *= -1
		player.direction = wander_direction
		if player.direction != 0:
			player.facing_direction = player.direction

	if player.is_on_floor() and _is_near_ledge():
		wander_direction *= -1
		player.direction = wander_direction
		if player.direction != 0:
			player.facing_direction = player.direction


func _do_fight() -> void:
	if not is_instance_valid(target_enemy):
		current_action = "idle"
		return

	var to_enemy := target_enemy.global_position - player.global_position
	var dist :int= abs(to_enemy.x)

	if dist <= attack_range:
		# In range — stop and attack
		player.direction = 0
		player.facing_direction = 1 if to_enemy.x > 0 else -1
		player.do_attack = true
	else:
		# Move toward enemy
		var dir := 1 if to_enemy.x > 0 else -1
		player.direction = dir
		player.facing_direction = dir

		# Don't walk off ledges while chasing
		if player.is_on_floor() and _is_near_ledge():
			player.direction = 0


func _do_retreat() -> void:
	if not is_instance_valid(target_enemy):
		current_action = "idle"
		return

	var to_enemy := target_enemy.global_position - player.global_position
	# Move away from enemy
	var dir := -1 if to_enemy.x > 0 else 1
	player.direction = dir
	player.facing_direction = dir

	if player.is_on_floor() and _is_near_ledge():
		player.direction = 0

	# Stop retreating if health recovers or enemy is far away
	if not _should_retreat() or abs(to_enemy.x) > aggro_range:
		target_enemy = null
		current_action = "idle"
		action_timer = 1.0


func _is_near_ledge() -> bool:
	var check_distance := 12.0
	var check_depth := 16.0
	var dir := player.direction if player.direction != 0 else player.facing_direction
	var forward_offset := Vector2(dir * check_distance, 0)
	var forward_transform := player.global_transform.translated(forward_offset)
	return not player.test_move(forward_transform, Vector2(0, check_depth))


func _clear_input() -> void:
	player.direction = 0
	player.do_attack = false
	player.do_jump = false
	player.do_drop = false
	player.do_pickup = false
	player.do_portal_interact = false
