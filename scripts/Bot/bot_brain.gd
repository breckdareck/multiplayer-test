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
var loot_range: float = 80.0
var loot_priority_range: float = 50.0

var target_enemy: EnemyBase = null
var target_loot: DroppedItem = null

var _respawn_timer: float = -1.0
const RESPAWN_DELAY: float = 3.0

var _equip_check_timer: float = 0.0
const EQUIP_CHECK_INTERVAL: float = 2.0

var _ability_check_timer: float = 0.0
const ABILITY_CHECK_INTERVAL: float = 5.0
var _buff_abilities: Array[String] = []
var _attack_abilities: Array[String] = []
var _attack_ability_index: int = 0
const MANA_RESERVE_PCT: float = 0.2

const MAX_JUMP_HEIGHT: float = 40.0
const JUMP_COOLDOWN: float = 0.8
var _jump_cooldown_timer: float = 0.0

var _wall_stuck_timer: float = 0.0
const WALL_STUCK_JUMP_TIME: float = 0.4

# Collision masks: Layer 1 (World) = bit 0, Layer 3 (Platforms) = bit 2
const GROUND_MASK: int = 0b101  # World + Platforms
const SOLID_MASK: int = 0b001  # World only (not one-way platforms)


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
	loot_range = behavior_config.get("loot_range", 80.0)

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
	_jump_cooldown_timer -= delta
	action_timer -= delta
	think_timer -= delta

	if think_timer <= 0.0:
		think_timer = think_interval
		_think()

	_equip_check_timer -= delta
	if _equip_check_timer <= 0.0:
		_equip_check_timer = EQUIP_CHECK_INTERVAL
		_evaluate_and_equip()

	_ability_check_timer -= delta
	if _ability_check_timer <= 0.0:
		_ability_check_timer = ABILITY_CHECK_INTERVAL
		_build_ability_lists()

	# Track how long we've been stuck against a wall
	if player.is_on_wall() and player.is_on_floor() and player.direction != 0:
		_wall_stuck_timer += delta
	else:
		_wall_stuck_timer = 0.0

	_apply_current_action()


func _handle_dead(delta: float) -> void:
	if _respawn_timer < 0.0:
		_respawn_timer = RESPAWN_DELAY
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = -1.0
		player.respawn()


func _think() -> void:
	if is_instance_valid(target_enemy):
		if target_enemy.health_component and target_enemy.health_component.is_dead:
			target_enemy = null
	else:
		target_enemy = null

	if is_instance_valid(target_loot):
		if target_loot.current_state == DroppedItem.ItemState.COLLECTED:
			target_loot = null
	else:
		target_loot = null

	if _should_retreat():
		if target_enemy:
			current_action = "retreat"
			return

	# Check for nearby loot first — pick it up before chasing the next enemy
	if not target_loot:
		target_loot = _find_best_loot()
	if target_loot:
		var loot_dist := player.global_position.distance_to(target_loot.global_position)
		if loot_dist <= loot_priority_range:
			current_action = "loot"
			return

	if not target_enemy:
		target_enemy = _find_nearest_enemy()

	if target_enemy:
		current_action = "fight"
		return

	# Loot is available but farther away — go get it now since nothing else to do
	if target_loot:
		current_action = "loot"
		return

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


func _find_best_loot() -> DroppedItem:
	var map_node = MapManager.get_player_map_node(bot_id)
	if not map_node:
		return null

	var drops_node = map_node.get_node_or_null("ItemDrops")
	if not drops_node:
		return null

	var best: DroppedItem = null
	var best_dist_sq := loot_range * loot_range

	for child in drops_node.get_children():
		if child is not DroppedItem:
			continue
		if not is_instance_valid(child):
			continue
		if child.current_state != DroppedItem.ItemState.SETTLED:
			continue
		if not child._can_player_pickup(player):
			continue

		var dist_sq := player.global_position.distance_squared_to(child.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = child

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
			player.do_pickup = false
		"wander":
			player.do_pickup = false
			_do_wander()
		"fight":
			player.do_pickup = false
			_do_fight()
		"retreat":
			player.do_pickup = false
			_do_retreat()
		"loot":
			_do_loot()


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
	var dx :int= abs(to_enemy.x)
	var dy := to_enemy.y
	var dir := 1 if to_enemy.x > 0 else -1

	# Enemy is on a different Y level — navigate to them first
	if abs(dy) > 12.0:
		_navigate_toward(target_enemy.global_position)
		return

	# Same level: check X range and line of sight
	if dx <= attack_range:
		if _is_wall_between(player.global_position, target_enemy.global_position):
			player.direction = dir
			player.facing_direction = dir
			if player.is_on_wall() and player.is_on_floor():
				_try_jump()
		else:
			player.direction = 0
			player.facing_direction = dir
			if not _try_use_buff():
				if not _try_use_attack_ability():
					player.do_attack = true
	else:
		_navigate_toward(target_enemy.global_position)


func _do_retreat() -> void:
	if not is_instance_valid(target_enemy):
		current_action = "idle"
		return

	var to_enemy := target_enemy.global_position - player.global_position
	var dir := -1 if to_enemy.x > 0 else 1
	player.direction = dir
	player.facing_direction = dir

	if player.is_on_floor():
		# Jump over walls when fleeing
		if player.is_on_wall():
			if _wall_stuck_timer >= WALL_STUCK_JUMP_TIME:
				_try_jump()
		elif _is_near_ledge():
			# Check if there's ground to land on in the escape direction
			if _raycast_down(player.global_position + Vector2(dir * 18.0, 0), 200.0):
				pass  # safe to walk off
			else:
				# Cornered at edge — jump up to escape
				_try_jump()

	if not _should_retreat() or abs(to_enemy.x) > aggro_range:
		target_enemy = null
		current_action = "idle"
		action_timer = 1.0


func _do_loot() -> void:
	if not is_instance_valid(target_loot) or target_loot.current_state == DroppedItem.ItemState.COLLECTED:
		target_loot = null
		current_action = "idle"
		player.do_pickup = false
		return

	var to_loot := target_loot.global_position - player.global_position
	var dx = abs(to_loot.x)

	# Use horizontal distance for "am I on top of the item" since Y can differ
	# due to player origin vs item ground position
	if dx <= 10.0:
		player.direction = 0
		player.do_pickup = true
	else:
		player.do_pickup = true  # keep trying while approaching
		_navigate_toward(target_loot.global_position)


## Navigates the bot toward a target position, handling platform traversal.
func _navigate_toward(target_pos: Vector2) -> void:
	var to_target := target_pos - player.global_position
	var dir := 1 if to_target.x > 0 else -1
	player.direction = dir
	player.facing_direction = dir

	if not player.is_on_floor():
		return

	var dy := to_target.y  # positive = target below, negative = target above

	# --- Stuck against a wall: jump to get over it ---
	if player.is_on_wall():
		if _wall_stuck_timer >= WALL_STUCK_JUMP_TIME:
			_try_jump()
		return

	# --- Target is below us ---
	if dy > 20.0:
		if player.can_drop_through_platform():
			player.do_drop = true
			return
		if _is_near_ledge():
			if _raycast_down(player.global_position + Vector2(dir * 18.0, 0), 200.0):
				return  # safe to walk off — ground below
			player.direction = 0
			return
		return

	# --- Target is above us ---
	if dy < -10.0:
		if abs(dy) <= MAX_JUMP_HEIGHT:
			_try_jump()
			return
		if _is_near_ledge():
			player.direction = 0
		return

	# --- Target is roughly same level ---
	if _is_near_ledge():
		if _has_ground_across_gap(dir):
			return  # safe to walk off — will land on ground ahead
		if dy > 5.0 and _raycast_down(player.global_position + Vector2(dir * 18.0, 0), 200.0):
			return
		player.direction = 0


func _try_jump() -> void:
	if _jump_cooldown_timer <= 0.0 and player.is_on_floor():
		player.do_jump = true
		_jump_cooldown_timer = JUMP_COOLDOWN


# --- Raycast helpers ---
# All rays extend 2px past tile boundaries (16px tiles) to ensure hits.

func _get_space_state() -> PhysicsDirectSpaceState2D:
	return player.get_world_2d().direct_space_state


## Cast a ray downward from a position. Returns true if ground is found within max_depth.
func _raycast_down(from: Vector2, max_depth: float) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, max_depth), GROUND_MASK)
	query.exclude = [player.get_rid()]
	var result := _get_space_state().intersect_ray(query)
	return not result.is_empty()


## Check if there's ground on the other side of a gap (within ~3 tiles ahead).
func _has_ground_across_gap(dir: int) -> bool:
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
func _is_wall_between(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, SOLID_MASK)
	query.exclude = [player.get_rid()]
	var result := _get_space_state().intersect_ray(query)
	return not result.is_empty()


func _evaluate_and_equip() -> void:
	if not is_instance_valid(player):
		return
	if not is_instance_valid(player.inventory_component):
		return
	if not is_instance_valid(player.equipment_component):
		return

	for slot in player.inventory_component.slots:
		if slot.item == null:
			continue
		if slot.item is not EquipmentData:
			continue

		var target_slot := BotEquipmentLogic.get_target_slot(slot.item, player.equipment_component)
		if target_slot == null:
			continue

		if BotEquipmentLogic.should_equip(target_slot.item, slot.item):
			var old_item = target_slot.item
			target_slot.item = slot.item
			slot.item = old_item
			slot.update_display()
			target_slot.update_display()


func _build_ability_lists() -> void:
	_buff_abilities.clear()
	_attack_abilities.clear()

	if not is_instance_valid(player):
		return
	var ability_comp: AbilityComponent = player.ability_component
	if not is_instance_valid(ability_comp):
		return

	_auto_spend_ability_points(ability_comp)

	for ability_id in ability_comp._ability_levels:
		if ability_comp._ability_levels[ability_id] <= 0:
			continue
		var ability_data: AbilityData = ResourceManager.get_ability_data(ability_id)
		if not ability_data or ability_data.ability_type != Constants.AbilityType.ACTIVE:
			continue
		if ability_data.applies_buff:
			_buff_abilities.append(ability_id)
		else:
			_attack_abilities.append(ability_id)


func _auto_spend_ability_points(ability_comp: AbilityComponent) -> void:
	while ability_comp.get_available_ability_points() > 0:
		var leveled_any := false
		for ability_id in ability_comp._ability_levels:
			if ability_comp.can_level_up_ability(ability_id):
				ability_comp.level_up_ability(ability_id)
				leveled_any = true
				break
		if not leveled_any:
			break


func _try_use_buff() -> bool:
	if _buff_abilities.is_empty():
		return false
	var ability_comp: AbilityComponent = player.ability_component
	var buff_comp: BuffComponent = player.buff_component
	if not is_instance_valid(ability_comp) or not is_instance_valid(buff_comp):
		return false

	for ability_id in _buff_abilities:
		var ability_data: AbilityData = ResourceManager.get_ability_data(ability_id)
		if not ability_data or not ability_data.applies_buff:
			continue
		if buff_comp.has_buff(ability_data.applies_buff.buff_id):
			continue
		if ability_comp.get_cooldown_remaining(ability_id) > 0.0:
			continue
		if not _has_enough_mana(ability_id):
			continue
		ability_comp.use_ability_server(ability_id)
		return true
	return false


func _try_use_attack_ability() -> bool:
	if _attack_abilities.is_empty():
		return false
	var ability_comp: AbilityComponent = player.ability_component
	if not is_instance_valid(ability_comp):
		return false

	var count := _attack_abilities.size()
	for i in count:
		var idx := (_attack_ability_index + i) % count
		var ability_id: String = _attack_abilities[idx]
		if ability_comp.get_cooldown_remaining(ability_id) > 0.0:
			continue
		if not _has_enough_mana(ability_id):
			continue
		ability_comp.use_ability_server(ability_id)
		_attack_ability_index = (idx + 1) % count
		return true
	return false


func _has_enough_mana(ability_id: String) -> bool:
	var ability_comp: AbilityComponent = player.ability_component
	var mana_comp: ManaComponent = player.mana_component
	if not is_instance_valid(ability_comp) or not is_instance_valid(mana_comp):
		return false
	var ability_data: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability_data:
		return false
	var level := ability_comp.get_ability_level(ability_id)
	var level_stats: AbilityLevelData = ability_data.get_level_stats(level)
	if not level_stats:
		return false
	var mana_cost: float = level_stats.mana_cost * ability_comp.get_ability_mana_modifier(ability_id)
	var mana_after := mana_comp.current_mana - mana_cost
	return mana_after >= mana_comp.max_mana * MANA_RESERVE_PCT


func _is_near_ledge() -> bool:
	var check_distance := 12.0
	var check_depth := 18.0  # 16px tile + 2px buffer
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
