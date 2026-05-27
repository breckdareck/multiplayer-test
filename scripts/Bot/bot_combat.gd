extends RefCounted
## Bot combat: target selection, attack/buff ability use, kiting, and the
## "fight" action. Owned by a BotBrain. The brain's think loop calls
## find_best_enemy / party_focus_target / set_target_enemy to acquire a target
## (stored in brain.target_enemy), and _apply_current_action dispatches the
## "fight" action to do_fight(). build_ability_lists() is ticked on the brain's
## ability timer. Terrain movement (chasing, wall jumps) is delegated back
## through the brain's navigator.

var brain                       ## The owning BotBrain node.

var aggro_range: float = 200.0
var attack_range: float = 25.0

var _combat_timer: float = 0.0
var _combat_last_enemy_hp: int = -1
## Global cooldown countdown: time before the bot may start another attack
## (basic swing or ability). Armed on every attack, ticked down by the brain.
var _gcd_timer: float = 0.0
var _blacklisted_enemies: Array[EnemyBase] = []
const COMBAT_DISENGAGE_TIME: float = 6.0
## While fighting, switch to a different enemy only when it is this much closer
## (fraction of the current target's squared distance) — hysteresis so the bot
## doesn't flip-flop between similar-distance foes.
const RETARGET_FACTOR: float = 0.36
## A ranged bot gives ground only when an enemy closes inside this distance;
## beyond it the bot holds and attacks. Kept tight so the bot actually fights
## instead of fleeing.
const KITE_DANGER_RANGE: float = 60.0
## Enemies within this radius of the target count as a cluster, biasing the
## bot's ability choice toward AoE skills.
const AOE_CLUSTER_RADIUS: float = 72.0
## Global cooldown between any two attacks the bot starts — basic swing or
## ability. Without it the bot chains a free, cooldown-less basic attack onto
## every Slash and attacks at roughly twice the intended rate.
const GCD: float = 1.0

var _buff_abilities: Array[String] = []
var _attack_abilities: Array[String] = []
# Combat profile, refreshed in build_ability_lists. A bot kites only when it
# is a ranged class AND actually has a projectile attack ability.
var _combat_range: float = 25.0       ## Longest attack reach (abilities or melee).
var _is_ranged_class: bool = false
var _has_ranged_ability: bool = false


func _init(owner_brain) -> void:
	brain = owner_brain


## Picks the nearest live, non-blacklisted enemy within aggro range.
func find_best_enemy() -> EnemyBase:
	var player: MultiplayerPlayerV2 = brain.player
	var map_node: Node = brain._get_map_node()
	if not is_instance_valid(map_node):
		return null

	var best: EnemyBase = null
	var best_dist_sq := aggro_range * aggro_range

	for node: EnemyBase in BotManager.get_enemies_on_map(MapManager.get_player_map(brain.bot_id), map_node):
		if node in _blacklisted_enemies:
			continue
		var dist_sq := player.global_position.distance_squared_to(node.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = node

	return best


## Sets the combat target and resets the per-fight disengage tracking.
func set_target_enemy(enemy: EnemyBase) -> void:
	brain.target_enemy = enemy
	_combat_timer = 0.0
	_combat_last_enemy_hp = -1


## An enemy a party member is already fighting and that's within this bot's
## aggro range — so a squad focus-fires one target instead of scattering.
## Returns the nearest such enemy, or null when not useful.
func party_focus_target() -> EnemyBase:
	var player: MultiplayerPlayerV2 = brain.player
	var members := PartyManager.get_party_members(brain.bot_id)
	if members.size() <= 1:
		return null
	var map_node: Node = brain._get_map_node()
	if not is_instance_valid(map_node):
		return null

	var best: EnemyBase = null
	var best_sq := aggro_range * aggro_range
	for member_id in members:
		if member_id == brain.bot_id:
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


func do_fight() -> void:
	var player: MultiplayerPlayerV2 = brain.player
	var target_enemy: EnemyBase = brain.target_enemy
	if not is_instance_valid(target_enemy):
		disengage()
		return

	if _combat_timer >= COMBAT_DISENGAGE_TIME:
		_blacklisted_enemies.append(target_enemy)
		disengage()
		return

	if _is_in_attack_state():
		return

	var to_enemy := target_enemy.global_position - player.global_position
	var dx := absf(to_enemy.x)
	var dy := to_enemy.y
	var dir := 1 if to_enemy.x > 0 else -1

	if abs(dy) > 12.0:
		# Enemy on another level — route across terrain via the nav graph.
		brain._navigator.navigate_smart(target_enemy.global_position)
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
				_try_basic_attack()
			_kite_away(dir)
		else:
			player.direction = 0
		return

	# Enemy inside melee-threat range — give ground, but keep attacking so the
	# bot is fighting on the way out, not just fleeing.
	if is_ranged and dx < KITE_DANGER_RANGE:
		if not _try_use_attack_ability(dx) and dx <= attack_range:
			_try_basic_attack()
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
		brain._navigator.navigate_smart(target_enemy.global_position)
		return

	if brain._navigator.is_wall_between(player.global_position, target_enemy.global_position):
		player.direction = dir
		if player.is_on_wall() and player.is_on_floor():
			brain._navigator.try_jump()
		return

	player.direction = 0
	if not _try_use_attack_ability(dx):
		_try_basic_attack()


## Issues a basic melee attack, but only once the global cooldown has elapsed.
## Arms the GCD so the next attack — basic or ability — waits its full duration.
func _try_basic_attack() -> void:
	if _gcd_timer > 0.0:
		return
	brain.player.do_attack = true
	_gcd_timer = GCD


## Steps a ranged bot away from an enemy to re-open attack distance while
## keeping it facing the enemy. Holds position rather than backing off a ledge
## or into a wall.
func _kite_away(enemy_dir: int) -> void:
	var player: MultiplayerPlayerV2 = brain.player
	var dir := -enemy_dir
	player.direction = dir
	player.facing_direction = enemy_dir
	if not player.is_on_floor():
		return
	if player.is_on_wall():
		player.direction = 0
		return
	if brain._navigator.is_near_ledge() and not brain._navigator.raycast_down(player.global_position + Vector2(dir * 18.0, 0), 200.0):
		player.direction = 0


func disengage() -> void:
	brain.target_enemy = null
	_combat_timer = 0.0
	_combat_last_enemy_hp = -1
	brain.current_action = "idle"
	brain.action_timer = 2.0


func build_ability_lists() -> void:
	_buff_abilities.clear()
	_attack_abilities.clear()

	var player: MultiplayerPlayerV2 = brain.player
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
	var player: MultiplayerPlayerV2 = brain.player
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
			Constants.ClassType.BOW, Constants.ClassType.STAFF, \
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
	if _gcd_timer > 0.0:
		return false
	var player: MultiplayerPlayerV2 = brain.player
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
		_gcd_timer = GCD
		return true
	return false


## Picks and casts the best usable attack ability for the situation — highest
## damage potential, biased toward AoE skills when enemies are clustered.
func _try_use_attack_ability(distance_to_target: float = 0.0) -> bool:
	if _attack_abilities.is_empty():
		return false
	if _gcd_timer > 0.0:
		return false
	var player: MultiplayerPlayerV2 = brain.player
	var ability_comp: AbilityComponent = player.ability_component
	if not is_instance_valid(ability_comp):
		return false

	# How many enemies are bunched on the target — drives AoE preference.
	var target_enemy: EnemyBase = brain.target_enemy
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
	_gcd_timer = GCD
	return true


## Rates an attack ability for the current situation: base damage potential,
## boosted when it is an AoE skill and several enemies are clustered.
func _score_attack_ability(ability_id: String, cluster: int) -> float:
	var data: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not data:
		return 0.0
	var player: MultiplayerPlayerV2 = brain.player
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
	var map_node: Node = brain._get_map_node()
	if not is_instance_valid(map_node):
		return 0
	var r_sq := radius * radius
	var count := 0
	for node: EnemyBase in BotManager.get_enemies_on_map(MapManager.get_player_map(brain.bot_id), map_node):
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
	var player: MultiplayerPlayerV2 = brain.player
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


## An attack ability's horizontal reach, derived from its AbilityData hitbox
## shape (position offset + half-extent). Projectile abilities reach exactly as
## far as their cast hitbox: the cast only spawns a homing projectile for an
## enemy already inside that hitbox (see combat.gd _process_collected_bodies).
## projectile_speed governs travel time, not reach — it is deliberately ignored.
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
	var player: MultiplayerPlayerV2 = brain.player
	var state_machine = player.get_node_or_null("StateMachine")
	if not state_machine or not "current_state" in state_machine:
		return false
	var attack_state = state_machine.get_node_or_null("attack")
	return attack_state and state_machine.current_state == attack_state
