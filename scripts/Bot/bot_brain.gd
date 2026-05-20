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

var _combat_timer: float = 0.0
var _combat_last_enemy_hp: int = -1
var _blacklisted_enemies: Array[EnemyBase] = []
var _blacklist_clear_timer: float = 0.0
const COMBAT_DISENGAGE_TIME: float = 6.0
const BLACKLIST_DURATION: float = 15.0

var _respawn_timer: float = -1.0
const RESPAWN_DELAY: float = 3.0

var _equip_check_timer: float = 0.0
const EQUIP_CHECK_INTERVAL: float = 2.0

var _ability_check_timer: float = 0.0
const ABILITY_CHECK_INTERVAL: float = 5.0
var _buff_abilities: Array[String] = []
var _attack_abilities: Array[String] = []
var _attack_ability_index: int = 0

var _consumable_check_timer: float = 0.0
const CONSUMABLE_CHECK_INTERVAL: float = 1.0
const HEALTH_POTION_THRESHOLD: float = 0.4
const MANA_POTION_THRESHOLD: float = 0.3

var _shop_check_timer: float = 0.0
const SHOP_CHECK_INTERVAL: float = 10.0
const POTION_STOCK_TARGET: int = 20
const POTION_RESTOCK_THRESHOLD: int = 0
const TOWN_MAP_ID: String = "game"
var _needs_restock: bool = false

var allow_map_travel: bool = true

const FOLLOW_RANGE: float = 500.0
const FOLLOW_CLOSE_RANGE: float = 60.0

var patrol_route: Array = []
var patrol_index: int = 0
var target_portal: Node = null

# Cached reference to the bot's current map node — avoids resolving it through
# MapManager on every think tick. Refreshed lazily when the bot's map changes.
var _cached_map_node: Node = null
var _cached_map_id: String = ""
var _map_travel_timer: float = 0.0
var _map_stay_timer: float = 0.0
const MAP_TRAVEL_CHECK_INTERVAL: float = 15.0
const MAP_MIN_STAY_TIME: float = 120.0
const LEVEL_OVERRIDE_THRESHOLD: int = 5
const PORTAL_ARRIVE_DIST: float = 30.0

var _party_seek_timer: float = 0.0
const PARTY_SEEK_INTERVAL: float = 12.0
const PARTY_SEEK_RANGE: float = 300.0

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
	allow_map_travel = behavior_config.get("allow_map_travel", true)
	patrol_route = behavior_config.get("patrol_route", [])

	think_timer = randf() * think_interval
	_party_seek_timer = PARTY_SEEK_INTERVAL + randf() * PARTY_SEEK_INTERVAL


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

	if current_action == "fight" and is_instance_valid(target_enemy):
		var enemy_hp := -1
		if target_enemy.health_component:
			enemy_hp = target_enemy.health_component.current_health
		if _combat_last_enemy_hp != enemy_hp and enemy_hp >= 0:
			_combat_last_enemy_hp = enemy_hp
			_combat_timer = 0.0
		else:
			_combat_timer += delta

	_blacklist_clear_timer -= delta
	if _blacklist_clear_timer <= 0.0:
		_blacklist_clear_timer = BLACKLIST_DURATION
		_blacklisted_enemies.clear()

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

	_consumable_check_timer -= delta
	if _consumable_check_timer <= 0.0:
		_consumable_check_timer = CONSUMABLE_CHECK_INTERVAL
		_try_use_consumable()

	_shop_check_timer -= delta
	if _shop_check_timer <= 0.0:
		_shop_check_timer = SHOP_CHECK_INTERVAL
		_do_shop_maintenance()

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

	# Follow player party leader if in a player-led party
	if _should_follow_leader():
		var leader_id := _get_party_leader()
		var leader_map := MapManager.get_player_map(leader_id)
		var my_map := MapManager.get_player_map(bot_id)
		if leader_map != my_map and not leader_map.is_empty():
			MapManager.request_map_change(bot_id, leader_map)
			_map_stay_timer = MAP_MIN_STAY_TIME
			return
		var leader_node := PlayerManager.get_player_node(leader_id)
		if is_instance_valid(leader_node):
			var dist := player.global_position.distance_to(leader_node.global_position)
			if dist > FOLLOW_RANGE:
				current_action = "follow"
				return

	# Travel to town to restock potions if out and no merchant on current map
	if _needs_restock and not _should_follow_leader():
		var my_map := MapManager.get_player_map(bot_id)
		if my_map != TOWN_MAP_ID:
			if not is_instance_valid(target_portal):
				target_portal = _find_portal_to_map(TOWN_MAP_ID)
			if is_instance_valid(target_portal):
				target_enemy = null
				current_action = "travel"
				return

	# Check for nearby loot first — pick it up before chasing the next enemy
	var has_space := _has_inventory_space()
	if has_space:
		if not target_loot:
			target_loot = _find_best_loot()
		if target_loot:
			var loot_dist := player.global_position.distance_to(target_loot.global_position)
			if loot_dist <= loot_priority_range:
				current_action = "loot"
				return
	else:
		target_loot = null

	if not target_enemy:
		var new_enemy := _find_nearest_enemy()
		if new_enemy:
			target_enemy = new_enemy
			_combat_timer = 0.0
			_combat_last_enemy_hp = -1

	if target_enemy:
		current_action = "fight"
		return

	# Loot is available but farther away — go get it now since nothing else to do
	if has_space and target_loot:
		current_action = "loot"
		return

	if allow_map_travel and _is_squad_leader() and not _should_follow_leader():
		_map_stay_timer -= think_interval
		_map_travel_timer -= think_interval
		if _map_travel_timer <= 0.0:
			_map_travel_timer = MAP_TRAVEL_CHECK_INTERVAL
			target_portal = null
			if _should_change_map():
				var target_map := _get_target_map()
				if not target_map.is_empty():
					target_portal = _find_portal_to_map(target_map)
		if is_instance_valid(target_portal):
			current_action = "travel"
			return

	_try_party_seek()

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


## Returns the bot's current map node, resolving it through MapManager only
## when the bot has actually changed maps (cheap map_id string compare otherwise).
func _get_map_node() -> Node:
	var map_id := MapManager.get_player_map(bot_id)
	if map_id != _cached_map_id or not is_instance_valid(_cached_map_node):
		_cached_map_id = map_id
		_cached_map_node = MapManager.get_player_map_node(bot_id)
	return _cached_map_node


func _find_nearest_enemy() -> EnemyBase:
	var map_node := _get_map_node()
	if not is_instance_valid(map_node):
		return null

	var enemies := get_tree().get_nodes_in_group("Enemies")
	var best: EnemyBase = null
	var best_dist_sq := aggro_range * aggro_range

	for node in enemies:
		if node is not EnemyBase:
			continue
		if not is_instance_valid(node):
			continue
		# Skip enemies that live on a different map (the "Enemies" group is global).
		if not map_node.is_ancestor_of(node):
			continue
		if node.health_component and node.health_component.is_dead:
			continue
		if node in _blacklisted_enemies:
			continue

		var dist_sq := player.global_position.distance_squared_to(node.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = node

	return best


func _find_best_loot() -> DroppedItem:
	var map_node := _get_map_node()
	if not is_instance_valid(map_node):
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
		"follow":
			_do_follow()
		"travel":
			_do_navigate_to_portal()


func _do_wander() -> void:
	player.direction = wander_direction
	if player.direction != 0:
		player.facing_direction = player.direction

	if not player.is_on_floor():
		return

	if player.is_on_wall():
		if _wall_stuck_timer >= WALL_STUCK_JUMP_TIME:
			_try_jump()
		else:
			wander_direction *= -1
			player.direction = wander_direction
			if player.direction != 0:
				player.facing_direction = player.direction
		return

	if _is_near_ledge():
		wander_direction *= -1
		player.direction = wander_direction
		if player.direction != 0:
			player.facing_direction = player.direction


func _do_fight() -> void:
	if not is_instance_valid(target_enemy):
		_disengage()
		return

	if _combat_timer >= COMBAT_DISENGAGE_TIME:
		_blacklisted_enemies.append(target_enemy)
		_disengage()
		return

	if _is_in_attack_state():
		return

	var to_enemy := target_enemy.global_position - player.global_position
	var dx := absf(to_enemy.x)
	var dy := to_enemy.y
	var dir := 1 if to_enemy.x > 0 else -1

	if abs(dy) > 12.0:
		_navigate_toward(target_enemy.global_position)
		return

	player.facing_direction = dir

	if dx > attack_range:
		if _try_use_attack_ability(dx):
			player.direction = 0
			return
		_navigate_toward(target_enemy.global_position)
		return

	if _is_wall_between(player.global_position, target_enemy.global_position):
		player.direction = dir
		if player.is_on_wall() and player.is_on_floor():
			_try_jump()
		return

	player.direction = 0
	if not _try_use_buff():
		if not _try_use_attack_ability(dx):
			player.do_attack = true


func _disengage() -> void:
	target_enemy = null
	_combat_timer = 0.0
	_combat_last_enemy_hp = -1
	current_action = "idle"
	action_timer = 2.0


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
		_disengage()


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


func _do_follow() -> void:
	var leader_id := _get_party_leader()
	var leader_node := PlayerManager.get_player_node(leader_id)
	if not is_instance_valid(leader_node):
		current_action = "idle"
		return
	var dist := player.global_position.distance_to(leader_node.global_position)
	if dist <= FOLLOW_CLOSE_RANGE:
		player.direction = 0
		return
	_navigate_toward(leader_node.global_position)


func _get_party_leader() -> int:
	var party_id := PartyManager.get_player_party_id(bot_id)
	if party_id == -1:
		return 0
	return PartyManager.get_party_leader(party_id)


func _should_follow_leader() -> bool:
	var leader_id := _get_party_leader()
	if leader_id <= 0:
		return false
	# Only follow if the leader is a real player (not a bot)
	return not BotManager.is_bot(leader_id)


func _try_party_seek() -> void:
	_party_seek_timer -= think_interval
	if _party_seek_timer > 0.0:
		return
	_party_seek_timer = PARTY_SEEK_INTERVAL + randf() * 5.0

	var my_party_id := PartyManager.get_player_party_id(bot_id)
	if my_party_id != -1:
		return

	var my_map := MapManager.get_player_map(bot_id)
	var best_bot_id: int = 0
	var best_dist: float = PARTY_SEEK_RANGE

	for other_id in BotManager.active_bots:
		if other_id == bot_id:
			continue
		if PartyManager.get_player_party_id(other_id) != -1:
			continue
		if MapManager.get_player_map(other_id) != my_map:
			continue
		var other_node := PlayerManager.get_player_node(other_id)
		if not is_instance_valid(other_node):
			continue
		var dist := player.global_position.distance_to(other_node.global_position)
		if dist < best_dist:
			best_dist = dist
			best_bot_id = other_id

	if best_bot_id == 0:
		return

	var party_id := PartyManager.create_party(bot_id)
	if party_id == -1:
		return
	var accepted := PartyManager.send_invite(bot_id, best_bot_id)
	if not accepted:
		PartyManager.leave_party(bot_id)


func _is_squad_leader() -> bool:
	var party_id := PartyManager.get_player_party_id(bot_id)
	if party_id == -1:
		return true
	return PartyManager.get_party_leader(party_id) == bot_id


func _should_change_map() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(player.level_component):
		return false

	var my_map := MapManager.get_player_map(bot_id)
	var difficulty := BotManager.get_map_difficulty(my_map)
	if difficulty.is_empty():
		return not patrol_route.is_empty()

	var bot_level: int = player.level_component.level
	var max_level: int = difficulty.get("max_level", 999)
	var min_level: int = difficulty.get("min_level", 1)

	# Level override: always travel immediately if way out of range
	if bot_level >= max_level + LEVEL_OVERRIDE_THRESHOLD:
		return true
	if bot_level <= min_level - LEVEL_OVERRIDE_THRESHOLD:
		return true

	# Patrol route: only after stay timer expires, 30% chance per check
	if _map_stay_timer > 0.0:
		return false
	if not patrol_route.is_empty():
		return randf() < 0.3

	return false


func _get_target_map() -> String:
	if not is_instance_valid(player) or not is_instance_valid(player.level_component):
		return ""

	var bot_level: int = player.level_component.level
	var my_map := MapManager.get_player_map(bot_id)
	var difficulty := BotManager.get_map_difficulty(my_map)

	# Level override: find best-fit map
	if not difficulty.is_empty():
		var max_level: int = difficulty.get("max_level", 999)
		var min_level: int = difficulty.get("min_level", 1)

		if bot_level >= max_level + LEVEL_OVERRIDE_THRESHOLD or bot_level <= min_level - LEVEL_OVERRIDE_THRESHOLD:
			var best_map := ""
			var best_fit := 999
			var all_difficulties: Dictionary = BotManager.bot_config.get("map_difficulty", {})
			for map_id in all_difficulties:
				if map_id == my_map:
					continue
				var md: Dictionary = all_difficulties[map_id]
				var mid_level: int = (md.get("min_level", 1) + md.get("max_level", 60)) / 2
				var fit := absi(bot_level - mid_level)
				if fit < best_fit:
					best_fit = fit
					best_map = map_id
			if not best_map.is_empty():
				return best_map

	# Patrol route: pick the next level-appropriate map
	if patrol_route.is_empty():
		return ""
	var all_difficulties: Dictionary = BotManager.bot_config.get("map_difficulty", {})
	for i in patrol_route.size():
		var idx := (patrol_index + 1 + i) % patrol_route.size()
		var candidate: String = patrol_route[idx]
		if candidate == my_map:
			continue
		var md: Dictionary = all_difficulties.get(candidate, {})
		if md.is_empty():
			patrol_index = idx
			return candidate
		var min_lvl: int = md.get("min_level", 1)
		var max_lvl: int = md.get("max_level", 999)
		if bot_level >= min_lvl - LEVEL_OVERRIDE_THRESHOLD and bot_level <= max_lvl + LEVEL_OVERRIDE_THRESHOLD:
			patrol_index = idx
			return candidate
	return ""


func _find_portal_to_map(target_map_id: String) -> Node:
	var map_node := _get_map_node()
	if not is_instance_valid(map_node):
		return null
	return _search_for_portal(map_node, target_map_id)


func _search_for_portal(node: Node, target_map_id: String) -> Node:
	if "target_map_id" in node and node.target_map_id == target_map_id:
		return node
	for child in node.get_children():
		var result := _search_for_portal(child, target_map_id)
		if result:
			return result
	return null


func _do_navigate_to_portal() -> void:
	if not is_instance_valid(target_portal):
		target_portal = null
		current_action = "idle"
		return

	if is_instance_valid(player.current_portal):
		player.direction = 0
		player.do_portal_interact = true
		target_portal = null
		_map_stay_timer = MAP_MIN_STAY_TIME
		return

	# Keep walking toward the portal until body_entered fires
	_navigate_toward(target_portal.global_position)


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

	var class_type: Constants.ClassType = Constants.ClassType.BEGINNER
	if is_instance_valid(player.class_component):
		class_type = player.class_component.current_class

	for slot in player.inventory_component.get_slots():
		if slot.item == null:
			continue
		if slot.item is not EquipmentData:
			continue

		var target_slot := BotEquipmentLogic.get_target_slot(slot.item, player.equipment_component)
		if target_slot == null:
			continue

		if BotEquipmentLogic.should_equip(target_slot.item, slot.item, class_type):
			# UI-independent swap — moves the upgrade into equipment and the
			# old item back into this inventory slot, with tracking + stats.
			player.inventory_component.swap_slot_data(slot, target_slot)


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
		var level: int = ability_comp._ability_levels[ability_id]
		if level <= 0:
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
		var buff_ref: BuffData = ability_data.applies_buff
		if buff_comp.has_buff(buff_ref.buff_id) or buff_comp.has_buff(buff_ref.buff_name):
			continue
		if ability_comp.get_cooldown_remaining(ability_id) > 0.0:
			continue
		if not _has_enough_mana(ability_id):
			continue
		ability_comp.use_ability_server(ability_id)
		return true
	return false


func _try_use_attack_ability(distance_to_target: float = 0.0) -> bool:
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
		var ability_range := _get_ability_range(ability_id)
		if distance_to_target > ability_range:
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
	return mana_comp.current_mana >= mana_cost


func _try_use_consumable() -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.inventory_component):
		return

	var need_health := false
	var need_mana := false

	if is_instance_valid(player.health_component):
		var health_pct := float(player.health_component.current_health) / float(player.health_component.max_health)
		need_health = health_pct < HEALTH_POTION_THRESHOLD

	if is_instance_valid(player.mana_component):
		var mana_pct := float(player.mana_component.current_mana) / float(player.mana_component.max_mana)
		need_mana = mana_pct < MANA_POTION_THRESHOLD

	if not need_health and not need_mana:
		return

	for slot in player.inventory_component.get_slots():
		if not slot.item or slot.item is not ConsumableData:
			continue
		var consumable := slot.item as ConsumableData
		if not consumable.effect_script:
			continue

		var is_health_pot := consumable.effect_properties.has("heal_amount")
		var is_mana_pot := consumable.effect_properties.has("regain_amount")

		if (need_health and is_health_pot) or (need_mana and is_mana_pot):
			player.inventory_component.remove_item_from_stack(consumable, 1)
			var effect_instance = consumable.effect_script.new() as BaseItemEffect
			effect_instance.user = player
			effect_instance.source_item = consumable
			effect_instance.execute()
			return


func _do_shop_maintenance() -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.inventory_component):
		return
	if not is_instance_valid(player.player_inventory):
		return

	var merchant := _find_merchant_inventory()
	_sell_unwanted_items(merchant)
	_buy_potions(merchant)

	var health_count := _count_consumable("heal_amount")
	var mana_count := _count_consumable("regain_amount")
	var needs_health_pots := health_count <= POTION_RESTOCK_THRESHOLD
	var needs_mana_pots := mana_count <= POTION_RESTOCK_THRESHOLD and is_instance_valid(player.mana_component) and player.mana_component.max_mana > 0
	_needs_restock = (needs_health_pots or needs_mana_pots) and merchant == null


func _find_merchant_inventory() -> MerchantInventory:
	var map_node := _get_map_node()
	if not is_instance_valid(map_node):
		return null
	for child in map_node.get_children():
		var merchant := child.get_node_or_null("MerchantInventory") as MerchantInventory
		if merchant:
			return merchant
	return null


const SELL_FULLNESS_THRESHOLD: float = 0.85

func _sell_unwanted_items(merchant: MerchantInventory) -> void:
	var tab_counts := _count_slots_by_tab()
	var equip_full = tab_counts.equip_used >= int(tab_counts.equip_total * SELL_FULLNESS_THRESHOLD)
	var material_full = tab_counts.material_used >= int(tab_counts.material_total * SELL_FULLNESS_THRESHOLD)

	if not equip_full and not material_full:
		return

	var class_type: Constants.ClassType = Constants.ClassType.BEGINNER
	if is_instance_valid(player.class_component):
		class_type = player.class_component.current_class

	var equipped_scores: Dictionary = {}
	if is_instance_valid(player.equipment_component):
		for eq_slot in [player.equipment_component.weapon_slot_data, player.equipment_component.head_slot_data,
				player.equipment_component.chest_slot_data, player.equipment_component.legs_slot_data,
				player.equipment_component.feet_slot_data]:
			if eq_slot and eq_slot.item:
				var slot_key := _get_equip_slot_key(eq_slot.item)
				var score := BotEquipmentLogic.score_item(eq_slot.item, class_type)
				if not equipped_scores.has(slot_key) or score > equipped_scores[slot_key]:
					equipped_scores[slot_key] = score

	var best_inventory_scores: Dictionary = {}
	for slot in player.inventory_component.get_slots():
		if not slot.item or slot.item is not EquipmentData:
			continue
		var slot_key := _get_equip_slot_key(slot.item)
		var score := BotEquipmentLogic.score_item(slot.item, class_type)
		if not best_inventory_scores.has(slot_key) or score > best_inventory_scores[slot_key]:
			best_inventory_scores[slot_key] = score

	var items_to_sell: Array[ItemData] = []
	for slot in player.inventory_component.get_slots():
		if not slot.item:
			continue

		if slot.item is ConsumableData:
			continue

		if slot.item is EquipmentData:
			if not equip_full:
				continue
			var item := slot.item as EquipmentData
			var item_score := BotEquipmentLogic.score_item(item, class_type)

			if item is WeaponData and not BotEquipmentLogic.can_equip_weapon(item as WeaponData, class_type):
				items_to_sell.append(item)
				continue

			var slot_key := _get_equip_slot_key(item)
			var threshold: float = equipped_scores.get(slot_key, -1.0)

			if item_score <= threshold:
				items_to_sell.append(item)
			elif item_score < best_inventory_scores.get(slot_key, 0.0):
				items_to_sell.append(item)
		else:
			if material_full:
				items_to_sell.append(slot.item)

	for item in items_to_sell:
		var sell_price: int
		if merchant:
			sell_price = merchant.get_sell_price(item.item_id)
		else:
			sell_price = maxi(1, roundi(item.base_value * 0.5))
		player.player_inventory.monies_amount += sell_price
		player.inventory_component.remove_item(item)


func _count_slots_by_tab() -> Dictionary:
	var result := {
		"equip_used": 0, "equip_total": 0,
		"consumable_used": 0, "consumable_total": 0,
		"material_used": 0, "material_total": 0,
	}
	for slot in player.inventory_component.get_slots():
		match slot.allowed_item_type:
			Constants.ItemType.EQUIPMENT:
				result.equip_total += 1
				if slot.item:
					result.equip_used += 1
			Constants.ItemType.CONSUMABLE:
				result.consumable_total += 1
				if slot.item:
					result.consumable_used += 1
			Constants.ItemType.MATERIAL:
				result.material_total += 1
				if slot.item:
					result.material_used += 1
			Constants.ItemType.ANY:
				if slot.item:
					if slot.item is EquipmentData:
						result.equip_used += 1
					elif slot.item is ConsumableData:
						result.consumable_used += 1
					else:
						result.material_used += 1
				result.equip_total += 1
	return result


func _buy_potions(merchant: MerchantInventory) -> void:
	if not merchant:
		return

	var health_pot_id := _get_potion_item_id("heal_amount")
	var mana_pot_id := _get_potion_item_id("regain_amount")
	var health_count := _count_consumable("heal_amount")
	var mana_count := _count_consumable("regain_amount")

	while health_count < POTION_STOCK_TARGET and not health_pot_id.is_empty():
		var price := merchant.get_buy_price(health_pot_id)
		if price <= 0 or player.player_inventory.monies_amount < price:
			break
		if player.inventory_component.get_empty_slots().is_empty():
			break
		player.player_inventory.monies_amount -= price
		player.inventory_component.server_add_item(health_pot_id)
		health_count += 1

	while mana_count < POTION_STOCK_TARGET and not mana_pot_id.is_empty():
		var price := merchant.get_buy_price(mana_pot_id)
		if price <= 0 or player.player_inventory.monies_amount < price:
			break
		if player.inventory_component.get_empty_slots().is_empty():
			break
		player.player_inventory.monies_amount -= price
		player.inventory_component.server_add_item(mana_pot_id)
		mana_count += 1


func _get_potion_item_id(effect_key: String) -> String:
	for item_id in ResourceManager.item_data:
		var item: ItemData = ResourceManager.item_data[item_id]
		if item is ConsumableData:
			var consumable := item as ConsumableData
			if consumable.effect_properties.has(effect_key):
				return item_id
	return ""


func _count_consumable(effect_key: String) -> int:
	var count := 0
	for slot in player.inventory_component.get_slots():
		if not slot.item or slot.item is not ConsumableData:
			continue
		var consumable := slot.item as ConsumableData
		if consumable.effect_properties.has(effect_key):
			count += slot.item.current_stack_amount
	return count


func _has_inventory_space() -> bool:
	for slot in player.inventory_component.get_slots():
		if slot.item == null and slot.allowed_item_type in [Constants.ItemType.ANY, Constants.ItemType.EQUIPMENT]:
			return true
	return false


func _get_equip_slot_key(item: ItemData) -> String:
	if item is WeaponData:
		return "weapon"
	if item is ArmorData:
		var armor := item as ArmorData
		match armor.armor_type:
			Constants.ArmorType.HEAD: return "head"
			Constants.ArmorType.CHEST: return "chest"
			Constants.ArmorType.LEGS: return "legs"
			Constants.ArmorType.FEET: return "feet"
	return "unknown"


func _get_ability_range(ability_id: String) -> float:
	var ability_data: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability_data or not ability_data.active_behavior:
		return attack_range

	var behavior: ActiveBehaviorData = ability_data.active_behavior
	var hitbox_x := absf(behavior.hit_box_position_data.x)
	if behavior.hit_box_shape_data is RectangleShape2D:
		hitbox_x += behavior.hit_box_shape_data.size.x * 0.5
	elif behavior.hit_box_shape_data is CircleShape2D:
		hitbox_x += behavior.hit_box_shape_data.radius
	return maxf(hitbox_x * 0.85, attack_range)


func _is_in_attack_state() -> bool:
	var state_machine = player.get_node_or_null("StateMachine")
	if not state_machine or not "current_state" in state_machine:
		return false
	var attack_state = state_machine.get_node_or_null("attack")
	return attack_state and state_machine.current_state == attack_state


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
