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
## Vertical band (px) within which the bot counts as standing on the SAME ground
## as its target. Beyond it — or while airborne — the bot paths toward the enemy
## instead of attacking, so it climbs fully onto the enemy's platform first.
const SAME_GROUND_Y_BAND: float = 12.0

## Attributes a bot is allowed to pour points into — mirrors
## StatsComponent.ALLOCATABLE_ATTRIBUTES (kept local so the bot doesn't couple to
## that component's private const). Used to filter a discipline's stat_bonuses.
const BOT_ALLOCATABLE_ATTRIBUTES: Array = [
	Constants.StatType.STRENGTH, Constants.StatType.DEXTERITY,
	Constants.StatType.INTELLIGENCE, Constants.StatType.LUCK,
	Constants.StatType.CONSTITUTION,
]
## Baseline CONSTITUTION weight folded into every bot's attribute build on top of
## its weapon's stat_bonuses ratio, so bots bank enough HP to survive the potion
## loop instead of being glass cannons.
const CON_SURVIVAL_WEIGHT: float = 2.0
## Role weights for the ability-point greedy: passives are flat-valued (they're
## class-neutral and always useful), buffs rank lowest, attack actives are
## damage-weighted between ATTACK_WEIGHT_FLOOR and ATTACK_WEIGHT_FLOOR+ATTACK_WEIGHT_SPAN.
const ROLE_WEIGHT_PASSIVE: float = 0.85
const ROLE_WEIGHT_BUFF: float = 0.55
const ATTACK_WEIGHT_FLOOR: float = 0.6
const ATTACK_WEIGHT_SPAN: float = 0.4

var _buff_abilities: Array[String] = []
var _attack_abilities: Array[String] = []
## Highest attack-ability damage potential in the bot's catalogue, refreshed each
## spend pass — the denominator that normalises attack role weights.
var _max_attack_potential: float = 1.0
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

	# Gather in-range, non-blacklisted enemies, nearest first, then return the
	# closest one the bot can actually PATH to — never aggro something stranded on
	# an unreachable part of the map (it would just stand there "fighting" it).
	var candidates: Array = []
	for node: EnemyBase in BotManager.get_enemies_on_map(MapManager.get_player_map(brain.bot_id), map_node):
		if node in _blacklisted_enemies:
			continue
		var dist_sq := player.global_position.distance_squared_to(node.global_position)
		if dist_sq < aggro_range * aggro_range:
			candidates.append([dist_sq, node])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for c in candidates:
		var enemy: EnemyBase = c[1]
		if brain._navigator.is_target_reachable(enemy.global_position):
			return enemy
	return null


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
		var foe: EnemyBase = null
		var mate = BotManager.get_bot_brain(member_id)
		if mate != null:
			# Untyped hop: mate.target_enemy may be a previously-freed node.
			var mate_target = mate.target_enemy
			if is_instance_valid(mate_target):
				foe = mate_target
		else:
			# Human teammate: no explicit target lock, so focus their most
			# recently-damaged enemy (get_recent_combat_target, stale-guarded).
			var human = PlayerManager.get_player_node(member_id)
			if is_instance_valid(human) and human.has_method("get_recent_combat_target"):
				foe = human.get_recent_combat_target()
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
	# Read untyped first: brain.target_enemy can hold a previously-freed node
	# (the enemy was freed without target_enemy being nulled). A typed read of a
	# freed instance trips Godot's "previously freed instance" error before we can
	# guard it, so validate on the Variant before narrowing to EnemyBase.
	var target_ref = brain.target_enemy
	if not is_instance_valid(target_ref):
		disengage()
		return
	var target_enemy: EnemyBase = target_ref

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

	# Only fight once the bot is standing on the SAME ground as the enemy: on the
	# floor and within a small vertical band. Otherwise keep pathing toward it.
	# The floor check matters because a mid-jump tick can momentarily align Y while
	# the bot is still climbing — without it the bot swings in the air a platform
	# short instead of landing on the enemy's level.
	if not player.is_on_floor() or absf(dy) > SAME_GROUND_Y_BAND:
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
	# Drop the planned path too: if the bot gave up mid-traversal (e.g. couldn't
	# mount a rope within the disengage window), a lingering CLIMB segment would
	# keep is_on_climb_segment() true and block the think loop from re-routing.
	brain._navigator._nav_path = PackedInt64Array()


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
	_auto_spend_attribute_points(player)

	for ability_id in ability_comp.get_all_ability_ids():
		var level: int = ability_comp.get_ability_level(ability_id)
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

	# primary_discipline is normalised to a tier-1 weapon discipline by
	# WeaponMasteryComponent, so only SWORD/BOW/STAFF/DAGGER ever appear here.
	_is_ranged_class = false
	if is_instance_valid(player) and is_instance_valid(player.weapon_mastery_component):
		match player.weapon_mastery_component.primary_discipline:
			Constants.ClassType.BOW, Constants.ClassType.STAFF:
				_is_ranged_class = true


## Spends the bot's earned ability points with a build in mind rather than at
## random. Each point goes to the highest value/point ability the bot can level
## (value = role weight × marginal gain, so early points spread into a usable
## kit and later points deepen the signature attack skills); once an ability is
## maxed, leftover points reinvest into its upgrades. AbilityComponent's per-
## discipline pool gating guarantees a discipline's points only ever buy that
## discipline's content, so the bot naturally builds the weapon it wields.
func _auto_spend_ability_points(ability_comp: AbilityComponent) -> void:
	# Refresh the attack-potential normaliser for this spend pass.
	_max_attack_potential = 1.0
	for ability_id in ability_comp.get_all_ability_ids():
		var data: AbilityData = ResourceManager.get_ability_data(ability_id)
		if data and data.ability_type == Constants.AbilityType.ACTIVE and not data.applies_buff:
			_max_attack_potential = maxf(_max_attack_potential, _ability_damage_potential(data))

	var guard := 0
	while ability_comp.get_available_ability_points() > 0 and guard < 1000:
		guard += 1
		var target := _choose_level_target(ability_comp)
		if not target.is_empty():
			ability_comp.level_up_ability(target)
			continue
		var upgrade := _choose_upgrade(ability_comp)
		if not upgrade.is_empty():
			ability_comp.purchase_upgrade(upgrade.ability_id, upgrade.upgrade_id)
			continue
		# Points remain but nothing is legally buyable (e.g. an empty pool in a
		# discipline the bot has no abilities to spend on) — stop rather than spin.
		break


## Picks the next ability to level: the highest value/point among everything the
## bot can currently level. Returns "" when nothing is levelable.
func _choose_level_target(ability_comp: AbilityComponent) -> String:
	var best_id := ""
	var best_value := 0.0
	for ability_id in ability_comp.get_all_ability_ids():
		if not ability_comp.can_level_up_ability(ability_id):
			continue
		var data: AbilityData = ResourceManager.get_ability_data(ability_id)
		if not data:
			continue
		var value := _level_value(ability_comp, ability_id, data)
		# Deterministic tie-break on id so identical bots build identically.
		if value > best_value or (value == best_value and (best_id.is_empty() or ability_id < best_id)):
			best_value = value
			best_id = ability_id
	return best_id


## Value-per-point of putting the next point into an ability: role weight ×
## marginal gain. marginal = 1/(level+1) front-loads the first point in any
## skill; attack actives are damage-weighted, passives flat, buffs lowest.
func _level_value(ability_comp: AbilityComponent, ability_id: String, data: AbilityData) -> float:
	var lvl := ability_comp.get_ability_level(ability_id)
	var marginal := 1.0 / float(lvl + 1)
	var role_weight := ROLE_WEIGHT_PASSIVE
	if data.ability_type == Constants.AbilityType.ACTIVE:
		if data.applies_buff:
			role_weight = ROLE_WEIGHT_BUFF
		else:
			var dmg_norm := clampf(_ability_damage_potential(data) / _max_attack_potential, 0.0, 1.0)
			role_weight = ATTACK_WEIGHT_FLOOR + ATTACK_WEIGHT_SPAN * dmg_norm
	return role_weight * marginal


## An ability's full damage potential (evaluated at its max level), used to rank
## attack actives. Passives / buffs / non-damaging abilities return 0.
func _ability_damage_potential(data: AbilityData) -> float:
	if not data:
		return 0.0
	var stats: AbilityLevelData = data.get_level_stats(maxi(1, data.max_level))
	if not stats:
		return 0.0
	return float(stats.damage_percent) * float(maxi(stats.max_hits, 1))


## When every levelable ability is exhausted but points remain, reinvest into
## upgrades: lower tiers first (foundation before variants), biggest magnitude,
## nudged toward the highest-damage maxed ability. Returns {} when nothing is
## purchasable. can_purchase_upgrade enforces level/tier/variant/pool rules.
func _choose_upgrade(ability_comp: AbilityComponent) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	for ability_id in ability_comp.get_all_ability_ids():
		var data: AbilityData = ResourceManager.get_ability_data(ability_id)
		if not data or data.upgrades == null:
			continue
		for up in data.upgrades:
			if up == null:
				continue
			var check: Dictionary = ability_comp.can_purchase_upgrade(ability_id, up.upgrade_id)
			if not check.ok:
				continue
			var score := (4.0 - float(up.tier)) * 1000.0 + up.magnitude + _ability_damage_potential(data) * 0.0001
			if score > best_score:
				best_score = score
				best = {"ability_id": ability_id, "upgrade_id": up.upgrade_id}
	return best


## Spends the bot's attribute points to reinforce its weapon identity: it mirrors
## the discipline's own stat_bonuses ratio (the canonical primary/secondary for
## that weapon) plus a CONSTITUTION survival bias, allocating only the shortfall
## vs what's already spent so it never fights the migration default-allocation
## and never unallocates. allocate_attribute() runs server-side immediately for
## bots (no client to RPC).
## (player left untyped so the spend logic is unit-testable with a lightweight
## stub; callers always pass a MultiplayerPlayerV2.)
func _auto_spend_attribute_points(player) -> void:
	var stats_comp = player.stats_component
	if not is_instance_valid(stats_comp):
		return
	var remaining: int = stats_comp.get_attribute_points_unused()
	if remaining <= 0:
		return

	var weights := _attribute_weights(player)
	var total_weight := 0.0
	for w in weights.values():
		total_weight += float(w)
	if total_weight <= 0.0:
		return

	# Desired allocation across the FULL granted pool, on the weapon ratio. Top up
	# each stat's shortfall vs current, bounded by the points actually available.
	var granted: int = stats_comp.get_attribute_points_granted()
	var stat_list: Array = weights.keys()
	stat_list.sort_custom(func(a, b): return float(weights[a]) > float(weights[b]))
	for stat_type in stat_list:
		if remaining <= 0:
			break
		var desired := int(round(float(weights[stat_type]) / total_weight * float(granted)))
		var add := mini(maxi(0, desired - stats_comp.get_allocated_attribute(stat_type)), remaining)
		if add > 0:
			stats_comp.allocate_attribute(stat_type, add)
			remaining -= add
	# Rounding can leave a few points unspent — dump them into the top-weight stat.
	if remaining > 0 and not stat_list.is_empty():
		stats_comp.allocate_attribute(stat_list[0], remaining)


## The bot's attribute-point target ratio: its discipline's stat_bonuses (filtered
## to allocatable attributes) with a baseline CONSTITUTION survival weight added.
func _attribute_weights(player) -> Dictionary:
	var weights: Dictionary = {}
	var wm = player.weapon_mastery_component
	if is_instance_valid(wm):
		var disc: WeaponDisciplineData = ResourceManager.get_class_data(wm.primary_discipline)
		if disc:
			for stat_type in disc.stat_bonuses:
				if stat_type in BOT_ALLOCATABLE_ATTRIBUTES:
					weights[stat_type] = float(disc.stat_bonuses[stat_type])
	# Always bank some CONSTITUTION for survivability, on top of the weapon ratio.
	var con: int = Constants.StatType.CONSTITUTION
	weights[con] = float(weights.get(con, 0.0)) + CON_SURVIVAL_WEIGHT
	return weights


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
	# Untyped read guards against a previously-freed brain.target_enemy (see do_fight).
	var target_ref = brain.target_enemy
	var target_enemy: EnemyBase = target_ref if is_instance_valid(target_ref) else null
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
		level = maxi(1, player.ability_component.get_ability_level(ability_id))
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
