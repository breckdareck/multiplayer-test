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
var jump_chance: float = 0.15

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

	# Stagger think timer so bots don't all think on the same frame
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
	if action_timer > 0.0:
		return

	if randf() < wander_chance:
		_start_wander()
	else:
		_start_idle()


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
			player.direction = wander_direction
			if player.direction != 0:
				player.facing_direction = player.direction

			# Wall detection — turn around
			if player.is_on_wall():
				wander_direction *= -1
				player.direction = wander_direction
				if player.direction != 0:
					player.facing_direction = player.direction

			# Ledge detection — check if ground exists ahead before walking off
			if player.is_on_floor() and _is_near_ledge():
				wander_direction *= -1
				player.direction = wander_direction
				if player.direction != 0:
					player.facing_direction = player.direction


func _is_near_ledge() -> bool:
	var check_distance := 12.0
	var check_depth := 16.0
	var forward_offset := Vector2(wander_direction * check_distance, 0)
	var forward_transform := player.global_transform.translated(forward_offset)
	return not player.test_move(forward_transform, Vector2(0, check_depth))


func _clear_input() -> void:
	player.direction = 0
	player.do_attack = false
	player.do_jump = false
	player.do_drop = false
	player.do_pickup = false
	player.do_portal_interact = false
