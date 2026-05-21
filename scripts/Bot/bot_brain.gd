extends Node

const BotNavGraph = preload("res://scripts/Bot/bot_nav_graph.gd")

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
## When retreating, the bot flees to safety and waits until HP regenerates to
## this fraction before re-engaging — hysteresis well above retreat_health_pct
## so it doesn't yo-yo straight back into a fight at 1 HP over the threshold.
const RECOVER_TARGET_PCT: float = 0.7
## A retreating bot considers itself safe once no enemy is within this distance.
const SAFE_DISTANCE: float = 260.0
var _recovering: bool = false
var loot_range: float = 80.0
var loot_priority_range: float = 50.0
## Periodic loot sweep: when this elapses the bot collects every reachable
## drop in range even mid-combat, so forever-spawning enemies don't starve it
## of loot before drops despawn (~2m10s). Reset once no loot remains in range.
var _loot_sweep_timer: float = 0.0
const LOOT_SWEEP_INTERVAL: float = 14.0

var target_enemy: EnemyBase = null
var target_loot: DroppedItem = null

var _combat_timer: float = 0.0
var _combat_last_enemy_hp: int = -1
var _blacklisted_enemies: Array[EnemyBase] = []
var _blacklisted_loot: Array[DroppedItem] = []
var _blacklist_clear_timer: float = 0.0
const COMBAT_DISENGAGE_TIME: float = 6.0
const BLACKLIST_DURATION: float = 15.0
## While fighting, switch to a different enemy only when it is this much closer
## (fraction of the current target's squared distance) — hysteresis so the bot
## doesn't flip-flop between similar-distance foes.
const RETARGET_FACTOR: float = 0.36
## A ranged bot gives ground only when an enemy closes inside this distance;
## beyond it the bot holds and attacks. Kept tight so the bot actually fights
## instead of fleeing.
const KITE_DANGER_RANGE: float = 60.0
## Projectile lifetime in seconds — mirrors the despawn timer in projectile.gd.
## A projectile's real reach is projectile_speed * this.
const PROJECTILE_LIFETIME: float = 1.0
## Fraction of a projectile's max travel the bot will actually fire at, so the
## shot connects instead of expiring just short of the target.
const PROJECTILE_RANGE_MARGIN: float = 0.85
## Enemies within this radius of the target count as a cluster, biasing the
## bot's ability choice toward AoE skills.
const AOE_CLUSTER_RADIUS: float = 72.0

var _respawn_timer: float = -1.0
const RESPAWN_DELAY: float = 3.0

var _equip_check_timer: float = 0.0
const EQUIP_CHECK_INTERVAL: float = 2.0

var _ability_check_timer: float = 0.0
const ABILITY_CHECK_INTERVAL: float = 5.0
var _buff_abilities: Array[String] = []
var _attack_abilities: Array[String] = []
# Combat profile, refreshed in _build_ability_lists. A bot kites only when it
# is a ranged class AND actually has a projectile attack ability.
var _combat_range: float = 25.0       ## Longest attack reach (abilities or melee).
var _is_ranged_class: bool = false
var _has_ranged_ability: bool = false

var _consumable_check_timer: float = 0.0
const CONSUMABLE_CHECK_INTERVAL: float = 1.0
const HEALTH_POTION_THRESHOLD: float = 0.4
const MANA_POTION_THRESHOLD: float = 0.3

var _shop_check_timer: float = 0.0
const SHOP_CHECK_INTERVAL: float = 10.0
const POTION_STOCK_TARGET: int = 20
const POTION_RESTOCK_THRESHOLD: int = 0
const TOWN_MAP_ID: String = "town"
var _needs_restock: bool = false
## Set when the bag is full and no merchant is on this map — routes to town to sell.
var _needs_sell: bool = false
## Potion buy prices learned at a merchant (effect_key -> price). Lets the
## affordability gate use the real price on maps with no merchant to query.
var _merchant_pot_cache: Dictionary = {}

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

const JUMP_COOLDOWN: float = 0.8
var _jump_cooldown_timer: float = 0.0

# Jump reachability — derived from the player's real jump_velocity, move_speed
# and project gravity in _compute_jump_profile(). Defaults match the stock
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

# --- Stuck detection: catches a bot that intends to move but makes no
# progress (bad terrain, an unreachable target) and escalates to recovery. ---
var _stuck_sample_pos: Vector2 = Vector2.ZERO
var _stuck_sample_timer: float = 0.0
var _stuck_timer: float = 0.0
const STUCK_SAMPLE_INTERVAL: float = 0.5
## Min px of progress expected per sample while actively walking.
const STUCK_MIN_PROGRESS: float = 6.0
## Stuck this long -> attempt a recovery jump.
const STUCK_JUMP_TIME: float = 1.0
## Stuck this long -> abandon the current target so the think loop re-plans.
const STUCK_ABANDON_TIME: float = 4.0

# --- Travel watchdog: a hard cap per portal hop, since an oscillating failed
# climb keeps "moving" and would slip past the stuck detector. ---
var _travel_timed_portal: Node = null
var _travel_timeout_timer: float = 0.0
const TRAVEL_TIMEOUT: float = 35.0

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

# --- Lifetime metrics, surfaced by `/bot stats` and the debug panel. ---
var _metrics := {
	"kills": 0,
	"deaths": 0,
	"deaths_to_enemy": 0,
	"deaths_to_hazard": 0,
	"stuck_recoveries": 0,
	"travel_abandons": 0,
	"loot_collected": 0,
	"gold_from_sales": 0,
}


## Lifetime behaviour counters for this bot (see _metrics).
func get_metrics() -> Dictionary:
	return _metrics


## Connects to the character's death signal for death-cause metrics. Safe to
## call repeatedly (e.g. after a map change re-bodies the bot).
func _connect_health_signals() -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.health_component):
		return
	if not player.health_component.died.is_connected(_on_player_died):
		player.health_component.died.connect(_on_player_died)


func _on_player_died(killer: Node) -> void:
	_metrics.deaths += 1
	if killer is EnemyBase:
		_metrics.deaths_to_enemy += 1
	else:
		_metrics.deaths_to_hazard += 1


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

	_compute_jump_profile()
	_connect_health_signals()


## Derives jump reachability limits from the player's real movement tuning so the
## navigation heuristics stay correct if jump_velocity / move_speed / gravity are
## ever retuned. Falls back to the defaults if the state machine is unavailable.
func _compute_jump_profile() -> void:
	var grav: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	if grav <= 0.0:
		return

	var jump_velocity: float = -300.0
	var move_speed: float = 130.0
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


## Re-points the brain at a freshly spawned character body after a map change.
## The brain is parented to BotManager, not the character (see
## BotManager._on_bot_spawned), so it persists across the despawn/respawn a map
## change performs — keeping travel timers, patrol progress and cooldowns. Only
## references into the old, now-freed map are cleared.
func attach_to_player(player_node: MultiplayerPlayerV2) -> void:
	player = player_node
	current_action = "idle"
	action_timer = 0.0
	target_enemy = null
	target_loot = null
	target_portal = null
	_combat_timer = 0.0
	_combat_last_enemy_hp = -1
	_recovering = false
	_blacklisted_enemies.clear()
	_cached_map_node = null
	_cached_map_id = ""
	_respawn_timer = -1.0
	# The new map has its own nav graph — point IDs from the old graph are
	# meaningless here, so drop any planned path.
	_nav_path = PackedInt64Array()
	_nav_goal = Vector2.INF
	_descend_dir = 0
	_connect_health_signals()


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
	_nav_repath_timer -= delta
	_loot_sweep_timer -= delta
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
		_blacklisted_loot.clear()

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

	# Stuck detection runs after the action set player.direction this frame.
	_update_stuck_detection(delta)
	_update_travel_watchdog(delta)


## Detects a bot that intends to move but is making no progress, and escalates:
## a recovery jump first, then abandoning the wedged target.
func _update_stuck_detection(delta: float) -> void:
	# Only meaningful while actively trying to walk on the ground. Airborne
	# frames (jump arcs) and deliberate stops reset the tracker.
	if player.direction == 0 or not player.is_on_floor():
		_stuck_timer = 0.0
		_stuck_sample_timer = STUCK_SAMPLE_INTERVAL
		_stuck_sample_pos = player.global_position
		return

	_stuck_sample_timer -= delta
	if _stuck_sample_timer > 0.0:
		return
	_stuck_sample_timer = STUCK_SAMPLE_INTERVAL

	var progress := player.global_position.distance_to(_stuck_sample_pos)
	_stuck_sample_pos = player.global_position
	if progress >= STUCK_MIN_PROGRESS:
		_stuck_timer = 0.0
		return

	_stuck_timer += STUCK_SAMPLE_INTERVAL
	if _stuck_timer >= STUCK_ABANDON_TIME:
		_stuck_timer = 0.0
		_recover_from_stuck()
	elif _stuck_timer >= STUCK_JUMP_TIME:
		_try_jump()


## Hard cap on a single portal hop. An oscillating failed climb keeps "moving"
## and would slip past the stuck detector, so time the hop directly.
func _update_travel_watchdog(delta: float) -> void:
	if current_action != "travel" or not is_instance_valid(target_portal):
		_travel_timed_portal = null
		_travel_timeout_timer = 0.0
		return

	if target_portal != _travel_timed_portal:
		_travel_timed_portal = target_portal
		_travel_timeout_timer = 0.0

	_travel_timeout_timer += delta
	if _travel_timeout_timer >= TRAVEL_TIMEOUT:
		_travel_timed_portal = null
		_travel_timeout_timer = 0.0
		_abandon_travel()


## Abandons the current travel target and defers the next travel attempt so the
## bot doesn't immediately re-wedge on the same unreachable route.
func _abandon_travel() -> void:
	target_portal = null
	current_action = "idle"
	action_timer = 2.0
	_map_travel_timer = MAP_TRAVEL_CHECK_INTERVAL
	_nav_path = PackedInt64Array()
	_metrics.travel_abandons += 1
	player.direction = 0


## Last-resort recovery when the bot is wedged against terrain it can't pass —
## drops whatever target caused it so the think loop can re-plan.
func _recover_from_stuck() -> void:
	_metrics.stuck_recoveries += 1
	match current_action:
		"fight":
			if is_instance_valid(target_enemy) and not _blacklisted_enemies.has(target_enemy):
				_blacklisted_enemies.append(target_enemy)
			_disengage()
		"loot":
			# Loot we can't reach — blacklist it so the sweep moves on rather
			# than re-targeting the same unreachable drop forever.
			if is_instance_valid(target_loot) and not _blacklisted_loot.has(target_loot):
				_blacklisted_loot.append(target_loot)
			target_loot = null
			current_action = "idle"
			action_timer = 1.0
			player.do_pickup = false
		"travel":
			_abandon_travel()
		"follow":
			current_action = "idle"
			action_timer = 1.0
		"wander":
			wander_direction *= -1
		_:
			player.direction = 0


func _handle_dead(delta: float) -> void:
	if _respawn_timer < 0.0:
		_respawn_timer = RESPAWN_DELAY
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = -1.0
		player.respawn()


## The bot's decision step. Each consideration is checked in strict priority
## order; the first that commits an action stops the cascade. Survival outranks
## errands, errands outrank combat, combat outranks chores, chores outrank idle.
func _think() -> void:
	_refresh_targets()

	if _consider_retreat(): return
	if _consider_restock_trip(): return
	if _consider_follow_leader(): return
	if _consider_priority_loot(): return
	if _consider_fight(): return
	if _consider_pending_loot(): return
	if _consider_map_travel(): return
	_consider_idle()


## Clears a dead enemy or collected drop from the current targets.
func _refresh_targets() -> void:
	if is_instance_valid(target_enemy):
		if target_enemy.health_component and target_enemy.health_component.is_dead:
			_metrics.kills += 1
			target_enemy = null
	else:
		target_enemy = null

	if is_instance_valid(target_loot):
		if target_loot.current_state == DroppedItem.ItemState.COLLECTED:
			_metrics.loot_collected += 1
			target_loot = null
	else:
		target_loot = null


## Survival: when critically low on HP, retreat to safety and regenerate. Stays
## in recovery until HP is comfortably back up — without this hysteresis the bot
## pops out of retreat 1 HP over the threshold and dives straight back in.
func _consider_retreat() -> bool:
	if _recovering:
		if _health_fraction() >= RECOVER_TARGET_PCT:
			_recovering = false
		else:
			current_action = "retreat"
			return true
	elif _should_retreat():
		_recovering = true
		current_action = "retreat"
		return true
	return false


## Visit town when out of potions, or when the bag is full with no merchant here
## to sell to. Routes hop-by-hop (town may not be directly portal-connected).
## The affordability gate in _do_shop_maintenance keeps a broke bot from looping
## here instead of fighting to earn the gold it needs.
func _consider_restock_trip() -> bool:
	if not (_needs_restock or _needs_sell):
		return false
	var my_map := MapManager.get_player_map(bot_id)
	if my_map == TOWN_MAP_ID:
		return false
	var hop := MapManager.get_next_map_toward(my_map, TOWN_MAP_ID)
	if hop.is_empty():
		return false
	if not is_instance_valid(target_portal) or target_portal.target_map_id != hop:
		target_portal = _find_portal_to_map(hop)
	if not is_instance_valid(target_portal):
		return false
	target_enemy = null
	current_action = "travel"
	return true


## Squad members follow their party leader across maps — but never into town.
## The leader visits town only to restock; members keep farming and rejoin when
## the leader heads back out.
func _consider_follow_leader() -> bool:
	if not _should_follow_leader():
		return false
	var leader_id := _get_party_leader()
	var leader_map := MapManager.get_player_map(leader_id)
	var my_map := MapManager.get_player_map(bot_id)
	if leader_map != my_map:
		if not leader_map.is_empty() and leader_map != TOWN_MAP_ID:
			MapManager.request_map_change(bot_id, leader_map)
			_map_stay_timer = MAP_MIN_STAY_TIME
			return true
		return false
	var leader_node := PlayerManager.get_player_node(leader_id)
	if is_instance_valid(leader_node):
		if player.global_position.distance_to(leader_node.global_position) > FOLLOW_RANGE:
			current_action = "follow"
			return true
	return false


## Grab loot before chasing the next enemy when it's close, and on a periodic
## sweep clear every reachable drop even mid-combat — otherwise forever-spawning
## enemies keep the bot fighting until the loot despawns. Also keeps target_loot
## current for the lower-priority pending-loot check.
func _consider_priority_loot() -> bool:
	if not _has_inventory_space():
		target_loot = null
		return false
	if not target_loot:
		target_loot = _find_best_loot()
	if target_loot:
		var loot_dist := player.global_position.distance_to(target_loot.global_position)
		if loot_dist <= loot_priority_range or _loot_sweep_timer <= 0.0:
			current_action = "loot"
			return true
	elif _loot_sweep_timer <= 0.0:
		# Sweep done — nothing reachable left in range; wait for the next one.
		_loot_sweep_timer = LOOT_SWEEP_INTERVAL
	return false


## Acquire a combat target, or — if already fighting — switch to a much closer
## enemy so the bot doesn't tunnel-vision a distant foe while one is on top of
## it. Prefers an enemy a party member is already on (focus fire).
func _consider_fight() -> bool:
	if not target_enemy:
		var new_enemy := _party_focus_target()
		if not is_instance_valid(new_enemy):
			new_enemy = _find_best_enemy()
		if new_enemy:
			_set_target_enemy(new_enemy)
	else:
		var closer := _find_best_enemy()
		if is_instance_valid(closer) and closer != target_enemy:
			var cur_sq := player.global_position.distance_squared_to(target_enemy.global_position)
			var new_sq := player.global_position.distance_squared_to(closer.global_position)
			if new_sq < cur_sq * RETARGET_FACTOR:
				_set_target_enemy(closer)
	if target_enemy:
		current_action = "fight"
		return true
	return false


## Known loot that was farther than the priority range — collect it now since
## nothing more urgent is pending.
func _consider_pending_loot() -> bool:
	if target_loot and _has_inventory_space():
		current_action = "loot"
		return true
	return false


## Squad leaders periodically travel toward a level-appropriate map.
func _consider_map_travel() -> bool:
	if not (allow_map_travel and _is_squad_leader() and not _should_follow_leader()):
		return false
	_map_stay_timer -= think_interval
	_map_travel_timer -= think_interval
	if _map_travel_timer <= 0.0:
		_map_travel_timer = MAP_TRAVEL_CHECK_INTERVAL
		target_portal = null
		if _should_change_map():
			var dest_map := _get_target_map()
			if not dest_map.is_empty():
				# Step toward the destination via the next reachable map — the
				# destination is often not directly portal-connected.
				var hop := MapManager.get_next_map_toward(MapManager.get_player_map(bot_id), dest_map)
				if not hop.is_empty():
					target_portal = _find_portal_to_map(hop)
	if is_instance_valid(target_portal):
		current_action = "travel"
		return true
	return false


## Nothing pressing — seek a party, then idle or wander.
func _consider_idle() -> void:
	_try_party_seek()
	if action_timer > 0.0:
		return
	if randf() < wander_chance:
		_start_wander()
	else:
		_start_idle()


func _should_retreat() -> bool:
	return _health_fraction() < retreat_health_pct


## Current HP as a 0..1 fraction (1.0 when there is no health component).
func _health_fraction() -> float:
	if not is_instance_valid(player.health_component):
		return 1.0
	var max_hp: int = player.health_component.max_health
	if max_hp <= 0:
		return 1.0
	return float(player.health_component.current_health) / float(max_hp)


## Returns the bot's current map node, resolving it through MapManager only
## when the bot has actually changed maps (cheap map_id string compare otherwise).
func _get_map_node() -> Node:
	var map_id := MapManager.get_player_map(bot_id)
	if map_id != _cached_map_id or not is_instance_valid(_cached_map_node):
		_cached_map_id = map_id
		_cached_map_node = MapManager.get_player_map_node(bot_id)
	return _cached_map_node


## Picks the nearest live, non-blacklisted enemy within aggro range.
func _find_best_enemy() -> EnemyBase:
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


## Sets the combat target and resets the per-fight disengage tracking.
func _set_target_enemy(enemy: EnemyBase) -> void:
	target_enemy = enemy
	_combat_timer = 0.0
	_combat_last_enemy_hp = -1


## An enemy a party member is already fighting and that's within this bot's
## aggro range — so a squad focus-fires one target instead of scattering.
## Returns the nearest such enemy, or null when not useful.
func _party_focus_target() -> EnemyBase:
	var members := PartyManager.get_party_members(bot_id)
	if members.size() <= 1:
		return null
	var map_node := _get_map_node()
	if not is_instance_valid(map_node):
		return null

	var best: EnemyBase = null
	var best_sq := aggro_range * aggro_range
	for member_id in members:
		if member_id == bot_id:
			continue
		var mate = BotManager.get_bot_brain(member_id)
		if mate == null:
			continue  # human party members expose no target
		var foe: EnemyBase = mate.target_enemy
		if not is_instance_valid(foe):
			continue
		if foe.health_component and foe.health_component.is_dead:
			continue
		if foe in _blacklisted_enemies:
			continue
		if not map_node.is_ancestor_of(foe):
			continue
		var d := player.global_position.distance_squared_to(foe.global_position)
		if d < best_sq:
			best_sq = d
			best = foe
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
		if child in _blacklisted_loot:
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
		# Enemy on another level — route across terrain via the nav graph.
		_navigate_smart(target_enemy.global_position)
		return

	player.facing_direction = dir

	# Keep combat buffs up before positioning — placed here so ranged bots,
	# which never reach the melee branch, also buff. A cast takes the tick.
	if _try_use_buff():
		player.direction = 0
		return

	# A bot kites only if it is a ranged class wielding an actual projectile
	# ability — Rogues and other melee classes always close in and fight.
	var is_ranged := _is_ranged_class and _has_ranged_ability

	# A caster with no mana for any ability is dead weight at range — pull back
	# to safety and let mana regenerate rather than idling in melee reach.
	if is_ranged and not _has_mana_for_any_attack():
		if dx < KITE_DANGER_RANGE:
			if dx <= attack_range:
				player.do_attack = true
			_kite_away(dir)
		else:
			player.direction = 0
		return

	# Enemy inside melee-threat range — give ground, but keep attacking so the
	# bot is fighting on the way out, not just fleeing.
	if is_ranged and dx < KITE_DANGER_RANGE:
		if not _try_use_attack_ability(dx) and dx <= attack_range:
			player.do_attack = true
		_kite_away(dir)
		return

	if dx > attack_range:
		if _try_use_attack_ability(dx):
			player.direction = 0
			return
		# A ranged bot already within ability reach holds its ground while
		# abilities cool down, instead of charging into melee.
		if is_ranged and dx <= _combat_range:
			player.direction = 0
			return
		_navigate_smart(target_enemy.global_position)
		return

	if _is_wall_between(player.global_position, target_enemy.global_position):
		player.direction = dir
		if player.is_on_wall() and player.is_on_floor():
			_try_jump()
		return

	player.direction = 0
	if not _try_use_attack_ability(dx):
		player.do_attack = true


## Steps a ranged bot away from an enemy to re-open attack distance while
## keeping it facing the enemy. Holds position rather than backing off a ledge
## or into a wall.
func _kite_away(enemy_dir: int) -> void:
	var dir := -enemy_dir
	player.direction = dir
	player.facing_direction = enemy_dir
	if not player.is_on_floor():
		return
	if player.is_on_wall():
		player.direction = 0
		return
	if _is_near_ledge() and not _raycast_down(player.global_position + Vector2(dir * 18.0, 0), 200.0):
		player.direction = 0


func _disengage() -> void:
	target_enemy = null
	_combat_timer = 0.0
	_combat_last_enemy_hp = -1
	current_action = "idle"
	action_timer = 2.0


## Retreats from danger and waits to regenerate. Moves away from the nearest
## threat; once no enemy is within SAFE_DISTANCE it holds still and lets HP (and
## any potion _try_use_consumable can drink) bring it back up. The think loop
## keeps the bot in this action until _recovering clears.
func _do_retreat() -> void:
	var threat := _nearest_enemy(SAFE_DISTANCE)
	if not is_instance_valid(threat):
		# Clear of every enemy — stand still and recover.
		player.direction = 0
		return

	var to_threat := threat.global_position - player.global_position
	var dir := -1 if to_threat.x > 0 else 1
	player.direction = dir
	player.facing_direction = dir

	if player.is_on_floor():
		# Jump over a wall in the escape direction.
		if player.is_on_wall():
			if _wall_stuck_timer >= WALL_STUCK_JUMP_TIME:
				_try_jump()
		elif _is_near_ledge():
			# Drop down only when there is safe ground below. At a pit or the
			# map edge, stop at the ledge — never jump or walk off into the
			# void (jumping while fleeing toward the edge launches the bot off).
			if not _raycast_down(player.global_position + Vector2(dir * 18.0, 0), 200.0):
				player.direction = 0


## Nearest live enemy on the bot's map within max_dist, or null. Unlike
## _find_best_enemy this is used for retreat safety checks, not target picking.
func _nearest_enemy(max_dist: float) -> EnemyBase:
	var map_node := _get_map_node()
	if not is_instance_valid(map_node):
		return null
	var best: EnemyBase = null
	var best_sq := max_dist * max_dist
	for node in get_tree().get_nodes_in_group("Enemies"):
		if node is not EnemyBase or not is_instance_valid(node):
			continue
		if not map_node.is_ancestor_of(node):
			continue
		if node.health_component and node.health_component.is_dead:
			continue
		var d := player.global_position.distance_squared_to(node.global_position)
		if d < best_sq:
			best_sq = d
			best = node
	return best


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
		_navigate_smart(target_loot.global_position)


func _do_follow() -> void:
	var leader_id := _get_party_leader()
	var leader_node := PlayerManager.get_player_node(leader_id)
	if not is_instance_valid(leader_node):
		current_action = "idle"
		return
	# Aim at a per-bot slot beside the leader so squad members spread out
	# instead of stacking on a single tile.
	var target := leader_node.global_position + _follow_slot_offset()
	var dist := player.global_position.distance_to(target)
	if dist <= FOLLOW_CLOSE_RANGE:
		player.direction = 0
		return
	_navigate_smart(target)


## A small, stable per-bot horizontal offset used to fan squad members out
## around their leader.
func _follow_slot_offset() -> Vector2:
	var slot := absi(bot_id) % 4
	return Vector2((float(slot) - 1.5) * 36.0, 0.0)


func _get_party_leader() -> int:
	var party_id := PartyManager.get_player_party_id(bot_id)
	if party_id == -1:
		return 0
	return PartyManager.get_party_leader(party_id)


func _should_follow_leader() -> bool:
	var leader_id := _get_party_leader()
	if leader_id == 0:
		return false  # not in a party
	# Follow whoever leads the party — bot or player — unless that is this bot.
	# Only the squad leader makes its own travel decisions; members follow it.
	return leader_id != bot_id


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

	# Route to the portal via the platform-nav graph; it handles terrain the
	# greedy heuristics can't, and falls back to direct navigation itself.
	_navigate_smart(target_portal.global_position)


## Routes the bot toward a distant goal using the map's platform-nav graph,
## falling back to direct navigation when the graph is unavailable or the goal
## is near. The graph picks the route; _navigate_toward / _climb_toward execute
## each hop.
func _navigate_smart(goal: Vector2) -> void:
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
	var map_node := _get_map_node()
	if not is_instance_valid(map_node):
		return null
	var map_id := MapManager.get_player_map(bot_id)
	return BotManager.get_nav_graph(map_id, map_node, _max_jump_height, _jump_launch_offset)


## Advances past reached waypoints and steers toward the next one. When the path
## is consumed, finishes with direct navigation to the real goal.
func _steer_along_nav_path(goal: Vector2) -> void:
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
	if target.y - player.global_position.y < -_max_jump_height:
		_climb_toward(target)
	else:
		_navigate_toward(target)


## Climbs the bot up to a target that sits above its current floor (e.g. a
## portal on a block). Walks to a horizontal launch point offset from the
## target, then jumps so the rising arc carries the bot onto it.
func _climb_toward(portal_pos: Vector2) -> void:
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
			_try_jump()
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
			_try_jump()
		else:
			player.direction = 0
		return

	# Walk toward the launch point, stopping short of any unsafe ledge.
	var dir := 1 if to_launch > 0 else -1
	player.direction = dir
	player.facing_direction = dir
	if _is_near_ledge() and not _has_ground_across_gap(dir):
		if not _raycast_down(bot_pos + Vector2(dir * 18.0, 0), 200.0):
			player.direction = 0


## Navigates the bot toward a target position, handling platform traversal.
func _navigate_toward(target_pos: Vector2) -> void:
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
		if _is_near_ledge():
			_descend_dir = 0
			if not _raycast_down(player.global_position + Vector2(player.direction * 18.0, 0), DROP_SCAN_DEPTH):
				player.direction = 0  # ledge over a pit / map edge — hold
		return
	_descend_dir = 0

	# --- Stuck against a wall (target at or above us): jump to get over it ---
	if player.is_on_wall():
		if _wall_stuck_timer >= WALL_STUCK_JUMP_TIME:
			_try_jump()
		return

	# --- Target is above us ---
	if dy < -10.0:
		if abs(dy) <= _max_jump_height:
			_try_jump()
			return
		if _is_near_ledge():
			player.direction = 0
		return

	# --- Target is roughly same level ---
	if _is_near_ledge():
		if _has_ground_across_gap(dir):
			return  # safe to walk off — will land on ground ahead
		if dy > 5.0 and _raycast_down(player.global_position + Vector2(dir * 18.0, 0), DROP_SCAN_DEPTH):
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

	_refresh_combat_profile()


## Recomputes the kiting inputs after the ability list (or class) changes.
func _refresh_combat_profile() -> void:
	_combat_range = attack_range
	_has_ranged_ability = false
	for ability_id in _attack_abilities:
		_combat_range = maxf(_combat_range, _get_ability_range(ability_id))
		var adata: AbilityData = ResourceManager.get_ability_data(ability_id)
		if adata and adata.active_behavior and adata.active_behavior.is_projectile:
			_has_ranged_ability = true

	_is_ranged_class = false
	if is_instance_valid(player) and is_instance_valid(player.class_component):
		match player.class_component.current_class:
			Constants.ClassType.ARCHER, Constants.ClassType.MAGE, \
			Constants.ClassType.RANGER, Constants.ClassType.ARCHMAGE:
				_is_ranged_class = true


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


## Picks and casts the best usable attack ability for the situation — highest
## damage potential, biased toward AoE skills when enemies are clustered.
func _try_use_attack_ability(distance_to_target: float = 0.0) -> bool:
	if _attack_abilities.is_empty():
		return false
	var ability_comp: AbilityComponent = player.ability_component
	if not is_instance_valid(ability_comp):
		return false

	# How many enemies are bunched on the target — drives AoE preference.
	var cluster := 1
	if is_instance_valid(target_enemy):
		cluster = _count_enemies_near(target_enemy.global_position, AOE_CLUSTER_RADIUS)

	var best_id := ""
	var best_score := -1.0
	for ability_id in _attack_abilities:
		if ability_comp.get_cooldown_remaining(ability_id) > 0.0:
			continue
		if not _has_enough_mana(ability_id):
			continue
		if distance_to_target > _get_ability_range(ability_id):
			continue
		var score := _score_attack_ability(ability_id, cluster)
		if score > best_score:
			best_score = score
			best_id = ability_id

	if best_id.is_empty():
		return false
	ability_comp.use_ability_server(best_id)
	return true


## Rates an attack ability for the current situation: base damage potential,
## boosted when it is an AoE skill and several enemies are clustered.
func _score_attack_ability(ability_id: String, cluster: int) -> float:
	var data: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not data:
		return 0.0
	var level := 1
	if is_instance_valid(player.ability_component):
		level = player.ability_component._ability_levels.get(ability_id, 1)
	var stats: AbilityLevelData = data.get_level_stats(level)
	if not stats:
		return 1.0
	var score := float(stats.damage_percent) * float(maxi(stats.max_hits, 1))
	if stats.max_targets > 1 and cluster >= 2:
		# Reward hitting the pack, capped at how many the ability can hit.
		score *= 1.0 + 0.4 * float(mini(cluster, stats.max_targets) - 1)
	return score


## Counts live enemies on the bot's map within `radius` of a point.
func _count_enemies_near(pos: Vector2, radius: float) -> int:
	var map_node := _get_map_node()
	if not is_instance_valid(map_node):
		return 0
	var r_sq := radius * radius
	var count := 0
	for node in get_tree().get_nodes_in_group("Enemies"):
		if node is not EnemyBase or not is_instance_valid(node):
			continue
		if not map_node.is_ancestor_of(node):
			continue
		if node.health_component and node.health_component.is_dead:
			continue
		if pos.distance_squared_to(node.global_position) <= r_sq:
			count += 1
	return count


## True if the bot can currently afford at least one attack ability. A caster
## that can't is effectively out of the fight until mana regenerates.
func _has_mana_for_any_attack() -> bool:
	if _attack_abilities.is_empty():
		return true  # melee-only — basic attacks cost no mana
	for ability_id in _attack_abilities:
		if _has_enough_mana(ability_id):
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
			player.inventory_component.remove_item_from_stack(consumable, 1, "used")
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

	var health_count := _count_consumable("heal_amount")
	var mana_count := _count_consumable("regain_amount")
	var needs_health_pots := health_count <= POTION_RESTOCK_THRESHOLD
	var needs_mana_pots := mana_count <= POTION_RESTOCK_THRESHOLD \
		and is_instance_valid(player.mana_component) and player.mana_component.max_mana > 0

	var gold: int = player.player_inventory.monies_amount
	var can_afford_health := _can_afford_potion("heal_amount", gold)
	var can_afford_mana := _can_afford_potion("regain_amount", gold)

	# Out of potions and too broke to buy them: if the bot is carrying items
	# worth selling, liquidate them for the gold instead of going without.
	var broke_for_potions := (needs_health_pots and not can_afford_health) \
		or (needs_mana_pots and not can_afford_mana)
	var liquidate := broke_for_potions and not _collect_items_to_sell(true).is_empty()

	var bag_full := _inventory_is_full()
	_sell_unwanted_items(merchant, bag_full or liquidate)
	_buy_potions(merchant)

	# Route to a town merchant when the bag needs offloading, or when the bot
	# must sell to afford potions.
	_needs_sell = merchant == null and (bag_full or liquidate)
	# Flag a restock run only if the bot can pay for it — it has the gold now,
	# or the liquidation sale will cover it. A broke bot with nothing to sell
	# skips the trip and keeps fighting to earn gold instead.
	var want_health := needs_health_pots and (can_afford_health or liquidate)
	var want_mana := needs_mana_pots and (can_afford_mana or liquidate)
	_needs_restock = merchant == null and (want_health or want_mana)


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

## Items the bot should offload to a merchant: junk equipment (unusable, or no
## better than what it already has) and materials. With `force` the per-tab
## fullness gates are ignored — used when the bot must raise gold for potions.
func _collect_items_to_sell(force: bool) -> Array[ItemData]:
	var items_to_sell: Array[ItemData] = []
	if not is_instance_valid(player) or not is_instance_valid(player.inventory_component):
		return items_to_sell

	var tab_counts := _count_slots_by_tab()
	var sell_equip: bool = force \
		or tab_counts.equip_used >= int(tab_counts.equip_total * SELL_FULLNESS_THRESHOLD)
	var sell_material: bool = force \
		or tab_counts.material_used >= int(tab_counts.material_total * SELL_FULLNESS_THRESHOLD)

	if not sell_equip and not sell_material:
		return items_to_sell

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

	for slot in player.inventory_component.get_slots():
		if not slot.item:
			continue

		if slot.item is ConsumableData:
			continue

		if slot.item is EquipmentData:
			if not sell_equip:
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
		elif sell_material:
			items_to_sell.append(slot.item)

	return items_to_sell


## Sells the bot's unwanted items to a merchant. `force` ignores the bag-
## fullness gates so a broke bot can liquidate gear/materials for potion money.
func _sell_unwanted_items(merchant: MerchantInventory, force: bool) -> void:
	# Selling requires a merchant — a bot never offloads gear out in the field.
	if not merchant:
		return
	for item in _collect_items_to_sell(force):
		var sell_price: int = merchant.get_sell_price(item.item_id)
		player.player_inventory.monies_amount += sell_price
		_metrics.gold_from_sales += sell_price
		player.inventory_component.remove_item(item, "sold")


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


## True when the equipment or material tab has crossed the sell threshold —
## the same fullness gate _sell_unwanted_items uses to decide it's time to sell.
func _inventory_is_full() -> bool:
	var tab_counts := _count_slots_by_tab()
	var equip_full: bool = tab_counts.equip_used >= int(tab_counts.equip_total * SELL_FULLNESS_THRESHOLD)
	var material_full: bool = tab_counts.material_used >= int(tab_counts.material_total * SELL_FULLNESS_THRESHOLD)
	return equip_full or material_full


func _buy_potions(merchant: MerchantInventory) -> void:
	if not merchant:
		return
	# Buy only what this merchant actually stocks — never an arbitrary potion
	# pulled from the global item table.
	var stock: Array = merchant.get_stock_data(bot_id)
	_buy_potion_type(merchant, stock, "heal_amount")
	_buy_potion_type(merchant, stock, "regain_amount")


## Buys, up to POTION_STOCK_TARGET, the best-sized potion of the given effect
## type from the merchant's own base stock: the largest heal/regain that does
## not exceed the bot's max stat (or, if every option exceeds it, the smallest).
## Caches the price so the affordability gate can use it on merchant-less maps.
func _buy_potion_type(merchant: MerchantInventory, stock: Array, effect_key: String) -> void:
	var cap := _potion_effect_cap(effect_key)

	var pot_id := ""
	var pot_name := ""
	var pot_price := 0
	var best_score := 0.0
	for entry in stock:
		if entry.get("is_buyback", false):
			continue
		var item = ResourceManager.get_item_data(entry.get("item_id", ""))
		if item is not ConsumableData:
			continue
		var consumable := item as ConsumableData
		if not consumable.effect_properties.has(effect_key):
			continue
		# Score: a potion that fits (<= cap) ranks by heal size, biggest first;
		# one that overshoots ranks below every fitting potion, smallest first.
		var amount := float(consumable.effect_properties.get(effect_key, 0))
		var score := amount if amount <= cap else -amount
		if pot_id.is_empty() or score > best_score:
			pot_id = entry.get("item_id", "")
			pot_name = entry.get("name", "")
			pot_price = entry.get("price", 0)
			best_score = score
	if pot_id.is_empty():
		return  # this merchant does not sell that potion type

	_merchant_pot_cache[effect_key] = pot_price

	var count := _count_consumable(effect_key)
	while count < POTION_STOCK_TARGET:
		if pot_price <= 0 or player.player_inventory.monies_amount < pot_price:
			break
		if not merchant.can_player_buy_from_stock(bot_id, pot_name):
			break
		if player.inventory_component.get_empty_slots().is_empty():
			break
		player.player_inventory.monies_amount -= pot_price
		player.inventory_component.server_add_item(pot_id)
		merchant.record_player_purchase(bot_id, pot_name)
		count += 1


## The max stat a potion of this effect type refills — used to size potion
## choice so the bot doesn't buy heals that overshoot its pool.
func _potion_effect_cap(effect_key: String) -> int:
	match effect_key:
		"heal_amount":
			return player.health_component.max_health if is_instance_valid(player.health_component) else 0
		"regain_amount":
			return player.mana_component.max_mana if is_instance_valid(player.mana_component) else 0
	return 0


## Whether the bot can afford a potion of the given effect type, using the price
## learned at a merchant. Before the bot has ever reached one, assume yes so it
## still makes the discovery trip — it spawns in town, so this gap is brief.
func _can_afford_potion(effect_key: String, gold: int) -> bool:
	if not _merchant_pot_cache.has(effect_key):
		return true
	return gold >= _merchant_pot_cache[effect_key]


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
	# A projectile homes to its target and is freed after PROJECTILE_LIFETIME
	# (see projectile.gd), so its real reach is speed * lifetime. The margin
	# keeps the bot from firing a shot that expires just short of the target.
	if behavior.is_projectile:
		return behavior.projectile_speed * PROJECTILE_LIFETIME * PROJECTILE_RANGE_MARGIN
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
