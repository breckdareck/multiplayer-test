class_name CombatComponent
extends Node

signal dealt_damage(target: Node, damage_values: Array, crit_values: Array)

@export var attack_hitbox: CollisionShape2D
@export_category("Debug - Weapon Stats")
## Weapon Multipliers = 1.2 ~ 1.75
@export var weapon_multiplier: float = 1.2
## Mastery: min damage as a fraction of max (0.2 = 20%, 0.6 = 60%)
@export var mastery: float = 0.2

# Attack type tracking
enum AttackMode {NONE, BASIC, ABILITY}
var _current_attack_mode: AttackMode = AttackMode.NONE

# Basic attack data
var current_attack_data: String = "" # Using string ID as a flag for basic attack

# Ability attack data
var current_ability_data: AbilityData = null
var current_active_data: ActiveBehaviorData = null
var current_level_stats: AbilityLevelData = null

var hit_list: Array = []
var _unique_targets_for_attack: Dictionary = {}
var _pending_bodies: Array = []

## Damage range shown in the stats window. Uses the class's attack stat
## (`_get_class_attack_stat()`) — for Mages and other INT-primary classes
## that's MAGICATTACK, reflecting the channel their abilities scale on (which
## is what they actually fight with). Basic-attack *actual* damage is a
## separate concern: `calculate_attack_damage` always uses WEAPONATTACK
## regardless of class.
var display_max_damage: int:
	get:
		return _calculate_max_range(_get_class_attack_stat())
var display_min_damage: int:
	get:
		return roundi(display_max_damage * mastery)

var original_attack_shape: Shape2D
var original_attack_transform: Vector2

# Cached owner map node — avoids repeated MapManager dictionary lookups on
# every hitbox collision. Refreshed lazily when the owner changes maps.
var _cached_map_node: Node = null
var _cached_map_id: String = ""

var _stats_component: StatsComponent
var _class_component: ClassComponent
var _equipment_component: EquipmentComponent
var _ability_component: AbilityComponent

@onready var owner_node: CharacterBody2D = get_owner()
@onready var attack_hitbox_timer: Timer = $"../../AttackHitboxTimer"
@onready var hitbox_area: Area2D = attack_hitbox.get_parent()

func _ready() -> void:
	if not attack_hitbox:
		push_error("CombatComponent: Attack Hitbox not assigned!")
		return
	
	original_attack_shape = attack_hitbox.shape
	original_attack_transform = attack_hitbox.position
		
	_stats_component = get_parent().get_node_or_null("Stats")
	_class_component = get_parent().get_node_or_null("Class")
	_equipment_component = get_parent().get_node_or_null("Equipment")
	_ability_component = get_parent().get_node_or_null("Ability")

	hitbox_area.monitoring = false

	# Connect to hitbox area
	if not hitbox_area.area_entered.is_connected(_on_hitbox_area_entered):
		hitbox_area.area_entered.connect(_on_hitbox_area_entered)

	attack_hitbox_timer.one_shot = true
	if not attack_hitbox_timer.timeout.is_connected(_on_attack_hitbox_timer_timeout):
		attack_hitbox_timer.timeout.connect(_on_attack_hitbox_timer_timeout)


func perform_attack(_attack_name: String, _duration: float) -> void:
	"""Called by the attack state when a basic attack is triggered"""
	if not multiplayer.is_server():
		return
		
	if current_attack_data != "" or current_ability_data != null:
		force_end_current_attack()

	# Set basic attack flag and data
	_current_attack_mode = AttackMode.BASIC
	current_attack_data = _attack_name
	
	attack_hitbox.shape = original_attack_shape
	attack_hitbox.position = original_attack_transform
	
	turn_on_hitbox()

	attack_hitbox_timer.start(0.1)


const BASIC_ARROW_SCENE = preload("uid://d0ig4oiimrnei")
const BASIC_ARROW_SPEED: float = 250.0

func perform_ranged_attack(_attack_name: String, _duration: float) -> void:
	if not multiplayer.is_server():
		return

	if current_attack_data != "" or current_ability_data != null:
		return

	_current_attack_mode = AttackMode.BASIC
	current_attack_data = _attack_name

	if not _ability_component:
		return

	var direction := Vector2(owner_node.facing_direction, 0).normalized()
	var projectile := BASIC_ARROW_SCENE.instantiate()
	projectile.initialize(owner_node, null, null, null, BASIC_ARROW_SPEED, direction)
	projectile.set_meta("basic_attack_caster", owner_node)
	var proj_name := "Proj_%d_%d" % [Time.get_ticks_msec(), randi()]
	projectile.name = proj_name

	var current_map = owner_node.get_parent().get_parent()
	var container: Node = null
	if current_map and current_map.is_in_group("map_base"):
		container = current_map.get_node_or_null("Projectiles")
		if not container:
			container = Node.new()
			container.name = "Projectiles"
			current_map.add_child(container)
	if not container:
		return

	container.add_child(projectile, true)
	var spawn_pos: Vector2 = owner_node.global_position
	if is_instance_valid(owner_node.projectile_spawn_location):
		spawn_pos = owner_node.projectile_spawn_location.global_position
	projectile.global_position = spawn_pos

	# Replicate the visual to same-map clients. Clients simulate the arrow's
	# movement locally; the server's copy stays authoritative for any hit.
	if current_map and current_map.is_in_group("map_base"):
		var map_name: String = current_map.name.replace("Map_", "")
		for peer_id in MapManager.get_real_players_on_map(map_name):
			if peer_id != 1:
				MapManager.spawn_projectile_visual.rpc_id(peer_id, proj_name, BASIC_ARROW_SCENE.resource_path, spawn_pos, direction, BASIC_ARROW_SPEED, NodePath(""))

	get_tree().create_timer(0.1).timeout.connect(func(): current_attack_data = "")


func force_end_current_attack() -> void:
	"""Force-clears any in-progress attack state so a new attack can begin."""
	if not multiplayer.is_server():
		return
	attack_hitbox_timer.stop()
	if current_attack_data != "":
		end_attack()
	elif current_ability_data != null:
		end_ability_attack()


func _on_attack_hitbox_timer_timeout() -> void:
	if current_attack_data != "":
		end_attack()
	elif current_ability_data != null:
		end_ability_attack()


func process_ability_hit(ability: AbilityData, level_stats: AbilityLevelData, duration_override: float = -1.0) -> void:
	"""Called by the attack state when an ability attack is triggered"""
	if not multiplayer.is_server():
		return

	if current_attack_data != "" or current_ability_data != null:
		force_end_current_attack()

	_current_attack_mode = AttackMode.ABILITY
	current_ability_data = ability
	current_active_data = ability.active_behavior
	current_level_stats = level_stats

	attack_hitbox.shape = ability.active_behavior.hit_box_shape_data
	attack_hitbox.position = ability.active_behavior.hit_box_position_data

	turn_on_hitbox()

	var attack_duration = duration_override if duration_override > 0.0 else level_stats.cast_time
	if attack_duration <= 0.0:
		attack_duration = 0.05

	attack_hitbox_timer.start(attack_duration)


func turn_on_hitbox() -> void:
	if not multiplayer.is_server():
		return
		
	attack_hitbox.position.x = abs(attack_hitbox.position.x) * owner_node.facing_direction
	
	hit_list.clear()
	_unique_targets_for_attack.clear()
	_pending_bodies.clear()
		
	hitbox_area.monitoring = true


func end_attack() -> void:
	if not multiplayer.is_server():
		return
		
	_process_collected_bodies()
	
	hitbox_area.monitoring = false
	_current_attack_mode = AttackMode.NONE
	current_attack_data = ""


func end_ability_attack() -> void:
	if not multiplayer.is_server():
		return
		
	_process_collected_bodies()
		
	hitbox_area.monitoring = false
	_current_attack_mode = AttackMode.NONE
	current_ability_data = null
	current_active_data = null
	current_level_stats = null
	
	hit_list.clear()
	_unique_targets_for_attack.clear()


func _get_owner_map_node() -> Node:
	"""Returns the owner's current map node, re-resolving it through MapManager
	only when the owner has actually changed maps."""
	var map_id := MapManager.get_player_map(owner_node.player_id)
	if map_id != _cached_map_id or not is_instance_valid(_cached_map_node):
		_cached_map_id = map_id
		var map_data: Dictionary = MapManager.active_maps.get(map_id, {})
		_cached_map_node = map_data.get("scene_instance")
	return _cached_map_node


func _is_on_same_map(target: Node) -> bool:
	var map_node := _get_owner_map_node()
	# No resolvable map (e.g. empty map_id) — fall back to allowing the hit.
	if not is_instance_valid(map_node):
		return true
	return map_node.is_ancestor_of(target)


func _on_hitbox_area_entered(area: Area2D) -> void:
	if not multiplayer.is_server():
		return
	if not "health_component" in (area.owner as EnemyBase):
		return
	if not _is_on_same_map(area.owner):
		return

	var health_comp = area.owner.get("health_component")
	if not health_comp or health_comp.is_dead:
		return

	if not _pending_bodies.has(area):
		_pending_bodies.append(area)


func _process_collected_bodies() -> void:
	# Also gather any areas currently overlapping the hitbox, in case
	# area_entered signals didn't fire (e.g. hitbox toggled same frame).
	if hitbox_area.monitoring:
		for area in hitbox_area.get_overlapping_areas():
			if not _pending_bodies.has(area) and is_instance_valid(area) and is_instance_valid(area.owner):
				if "health_component" in area.owner and _is_on_same_map(area.owner):
					var hc = area.owner.get("health_component")
					if hc and not hc.is_dead:
						_pending_bodies.append(area)

	# For projectiles, we might fire even if no body was collected.
	if current_ability_data and current_ability_data.active_behavior.is_projectile:
		# Sort bodies by distance to prioritize closest targets
		_pending_bodies.sort_custom(func(a, b):
			return owner_node.global_position.distance_squared_to(a.global_position) < owner_node.global_position.distance_squared_to(b.global_position)
		)

		var proj_max_targets = current_level_stats.max_targets
		var proj_targets_processed = 0

		for body_area in _pending_bodies:
			if proj_targets_processed >= proj_max_targets:
				break

			var health_comp = body_area.owner.get("health_component")
			if health_comp and not health_comp.is_dead:
				if _ability_component:
					# Spawn one projectile for each valid target
					_ability_component.spawn_projectile(current_ability_data, current_level_stats, body_area.owner)
				proj_targets_processed += 1

		# If no targets were in the hitbox, spawn one projectile straight ahead
		if proj_targets_processed == 0:
			if _ability_component:
				_ability_component.spawn_projectile(current_ability_data, current_level_stats, null)

		_pending_bodies.clear()
		return # We are done for projectiles

	# Melee / Hitbox attack processing
	if _pending_bodies.is_empty():
		return

	var max_targets = 0
	
	if current_ability_data and current_level_stats:
		max_targets = current_level_stats.max_targets
	elif current_attack_data != "":
		max_targets = 1
	else:
		_pending_bodies.clear()
		return
	
	_pending_bodies.sort_custom(func(a, b):
		return owner_node.global_position.distance_to(a.global_position) < owner_node.global_position.distance_to(b.global_position)
	)
	
	var targets_processed = 0
	for body in _pending_bodies:
		if targets_processed >= max_targets:
			break
		
		var health_comp = body.owner.get("health_component")
		if not health_comp or health_comp.is_dead:
			continue
		
		_unique_targets_for_attack[body] = true
		
		# Execute the full hit logic for this target
		_execute_hit(body.owner, current_ability_data, current_level_stats, current_attack_data)
		
		targets_processed += 1
	
	_pending_bodies.clear()


func process_projectile_hit(target_enemy: Node, ability: AbilityData, level_stats: AbilityLevelData) -> void:
	"""Public function for projectiles to call when they hit a target."""
	if not multiplayer.is_server():
		return

	#print("CombatComponent: Processing projectile hit on %s" % target_enemy.name)
	var attack_name := "basic_arrow" if ability == null else ""
	_execute_hit(target_enemy, ability, level_stats, attack_name)


func _execute_hit(target_enemy: Node, ability: AbilityData, level_stats: AbilityLevelData, attack_name: String) -> void:
	"""Runs the full, authoritative damage calculation for a single hit on a single target."""
	var health_comp = target_enemy.get("health_component")
	if not health_comp or health_comp.is_dead:
		return

	var attacker_level: int = owner_node.level_component.level
	var target_level: int = target_enemy.monster_level

	# --- Hit Chance Calculation ---
	var level_diff: int = attacker_level - target_level
	var hit_chance: float = _compute_hit_chance(level_diff)

	var max_hits: int = 1
	if ability and level_stats:
		max_hits = level_stats.max_hits

	var damage_values: Array = []
	var crit_values: Array = []

	for i in range(max_hits):
		var roll: float = randf() * 100.0
		if roll > hit_chance:
			damage_values.append(-1) # -1 signifies a MISS
			crit_values.append(false)
			#print("Attack MISSED! (Roll: %.2f > Chance: %.2f)" % [roll, hit_chance])
			continue # Skip to the next hit

		# --- Damage Calculation ---
		var base_damage: int = 0
		if attack_name != "":
			base_damage = calculate_attack_damage()
		elif ability and level_stats:
			base_damage = calculate_ability_damage(ability, level_stats)

		var rolled: Dictionary = _compute_damage_to(target_enemy, float(base_damage), level_diff)
		var damage_to_deal: int = rolled.damage
		var is_crit: bool = rolled.is_crit

		damage_values.append(damage_to_deal)
		crit_values.append(is_crit)

		health_comp.take_damage(damage_to_deal, self, true, is_crit, false)

		if damage_to_deal > 0:
			# Knockback, gated by the target's knockback resist.
			var knockback_dir = owner.facing_direction
			var knockback_strength = 90.0
			var knockback_lift = -90.0
			var knockback_vec = Vector2(knockback_dir * knockback_strength, knockback_lift)
			var target_stats: StatsComponent = target_enemy.get_node_or_null("Stats")
			if target_enemy.has_method("apply_knockback") and StatsComponent.rolls_knockback(target_stats, knockback_strength):
				target_enemy.apply_knockback(knockback_vec)

		if _ability_component:
			var event_type = "on_crit" if is_crit else "on_hit"
			var context = {
				"base_damage": damage_to_deal,
				"target": target_enemy,
				"is_crit": is_crit
			}
			_ability_component.try_trigger_procs(event_type, target_enemy, context)

	# Apply target debuff if the ability defines one
	if ability and ability.applies_target_debuff and target_enemy is EnemyBase:
		var debuff_duration := 10.0
		if ability.debuff_duration_formula:
			debuff_duration = ability.debuff_duration_formula.calculate(level_stats.level)
		_apply_enemy_debuff(target_enemy, ability.applies_target_debuff, debuff_duration)

	# After the loop, emit signal first so listeners (e.g. Shadow Partner) can append hits
	if not damage_values.is_empty():
		dealt_damage.emit(target_enemy, damage_values, crit_values)

		# Now display the combined combo (signal handlers may have appended to the arrays)
		var spawn_pos = health_comp.damage_number_origin.global_position
		var dmg_spawner = null
		var map_to_spawn_on: Node = null
		var attacker = owner_node

		if attacker is MultiplayerPlayerV2:
			map_to_spawn_on = MapManager.get_player_map_node(attacker.player_id)
		else:
			for map_id in MapManager.active_maps.keys():
				var map_instance = MapManager.active_maps[map_id].scene_instance
				if is_instance_valid(map_instance) and map_instance.is_ancestor_of(attacker):
					map_to_spawn_on = map_instance
					break

		if is_instance_valid(map_to_spawn_on):
			dmg_spawner = map_to_spawn_on.find_child("DmgNumberSpawner", true, false)

		if dmg_spawner:
			dmg_spawner.display_number_combo(damage_values, crit_values, spawn_pos)


func execute_shadow_hit(target: Node, hit_count: int, damage_percent: float) -> Dictionary:
	"""Runs `hit_count` "shadow" hits on `target` at `damage_percent` of the
	owner's basic-attack damage. Each shadow hit rolls hit-chance, defense,
	level diff, and crit through the same pipeline `_execute_hit` uses, then
	deals damage. Server-only.

	Returns {damages: Array, crits: Array} matching `hit_count` in length so a
	caller (e.g. BL_ShadowPartner) can splice the results into a combo display.
	Misses are represented as -1 in `damages`, matching `_execute_hit`'s
	convention."""
	var result: Dictionary = {"damages": [], "crits": []}

	if not multiplayer.is_server():
		return result

	var health_comp = target.get("health_component")
	if not health_comp or health_comp.is_dead:
		return result

	var attacker_level: int = owner_node.level_component.level
	var target_level: int = target.monster_level if "monster_level" in target else attacker_level
	var level_diff: int = attacker_level - target_level
	var hit_chance: float = _compute_hit_chance(level_diff)

	for i in range(hit_count):
		var roll: float = randf() * 100.0
		if roll > hit_chance:
			result.damages.append(-1)
			result.crits.append(false)
			continue

		var base_damage: float = float(calculate_attack_damage()) * (damage_percent / 100.0)
		var rolled: Dictionary = _compute_damage_to(target, base_damage, level_diff)
		var damage_to_deal: int = rolled.damage
		var is_crit: bool = rolled.is_crit

		result.damages.append(damage_to_deal)
		result.crits.append(is_crit)

		health_comp.take_damage(damage_to_deal, self, true, is_crit, false)

	return result


func _compute_hit_chance(level_diff: int) -> float:
	# Base 95% chance to hit. Lose 2% chance for each level the monster is above you.
	return clampf(95.0 + (level_diff * 2.0), 5.0, 100.0)


func _compute_damage_to(target_enemy: Node, base_damage: float, level_diff: int) -> Dictionary:
	"""Applies the per-target damage pipeline: defense reduction, level-diff
	modifier, then crit roll. Mirrors the inner block of `_execute_hit` so any
	balance change to defense/crit/level-diff propagates to every call site."""
	var modified_damage: float = base_damage

	if target_enemy.has_node("Stats"):
		var target_stats = target_enemy.get_node("Stats")
		var target_defense: int = target_stats.stats.get(Constants.StatType.DEFENSE).total_value

		var level_modifier: float = clampf(1.0 + (level_diff * 0.05), 0.5, 1.5)
		var defense_multiplier: float = 1.0 - (float(target_defense) / (target_defense + 500.0))

		modified_damage *= level_modifier * defense_multiplier

	var crit_chance: float = _stats_component.stats.get(Constants.StatType.CRITCHANCE).total_value
	var is_crit: bool = (randf() * 100.0) < crit_chance

	if is_crit:
		var crit_damage_bonus: float = _stats_component.stats.get(Constants.StatType.CRITDAMAGE).total_value
		var crit_multiplier: float = randf_range(1.2, 1.5) + (crit_damage_bonus / 100.0)
		modified_damage *= crit_multiplier

	return {"damage": roundi(modified_damage), "is_crit": is_crit}


func calculate_ability_damage(_ability: AbilityData, level_stats: AbilityLevelData) -> int:
	var max_range = _calculate_max_range(_ability.damage_stat)
	var damage = roundi(randf_range(max_range * mastery, max_range))

	damage = roundi(damage * (level_stats.damage_percent / 100.0))

	if _ability_component:
		var passive_modifier = _ability_component.get_ability_damage_modifier(_ability.ability_id)
		damage = roundi(damage * passive_modifier)
		#print("Applied passive damage modifier: %.2fx" % passive_modifier)

	return damage


func calculate_attack_damage() -> int:
	if not (_equipment_component and _equipment_component.weapon_slot_data and _equipment_component.weapon_slot_data.item):
		return 0

	# Basic attacks always use WEAPONATTACK, regardless of class. A Mage's
	# basic staff swing intentionally uses the Wooden Staff's WEAPONATTACK,
	# not its MAGICATTACK — abilities are the channel for MAGICATTACK and
	# pass their own stat via `_calculate_max_range(_ability.damage_stat)`.
	var max_range = _calculate_max_range()
	return roundi(randf_range(max_range * mastery, max_range))


func _get_class_attack_stat() -> Constants.StatType:
	if _class_component:
		var primary = ResourceManager.get_primary_stat(_class_component.current_class)
		if primary == Constants.StatType.INTELLIGENCE:
			return Constants.StatType.MAGICATTACK
	return Constants.StatType.WEAPONATTACK


func _calculate_max_range(attack_stat_type: Constants.StatType = Constants.StatType.WEAPONATTACK) -> int:
	if not _stats_component or not _class_component:
		return 0

	var attack_power = _stats_component.stats.get(attack_stat_type).total_value

	var primary_stat_type = ResourceManager.get_primary_stat(_class_component.current_class)
	var secondary_stat_type = ResourceManager.get_secondary_stat(_class_component.current_class)

	var primary_stat_value = _stats_component.stats.get(primary_stat_type).total_value
	var secondary_stat_value = _stats_component.stats.get(secondary_stat_type).total_value

	var stat_multiplier: float = (primary_stat_value * 4 + secondary_stat_value)

	var max_range = weapon_multiplier * stat_multiplier * attack_power / 100.0

	# Damage% and Final Damage% slots — currently no stats for these,
	# but the formula is ready for when they're added:
	# max_range *= (1.0 + damage_percent / 100.0)
	# max_range *= (1.0 + final_damage_percent / 100.0)

	return roundi(max_range)


func _apply_enemy_debuff(enemy: EnemyBase, debuff: BuffData, duration: float) -> void:
	if not enemy.stats_component:
		return

	var debuff_key := "debuff_%s" % debuff.buff_name
	if enemy.has_meta(debuff_key):
		return

	var saved_values: Dictionary = {}
	for stat_type in debuff.stat_modifiers:
		var modifier: StatData = debuff.stat_modifiers[stat_type]
		if enemy.stats_component.stats.has(stat_type):
			var enemy_stat: StatData = enemy.stats_component.stats[stat_type]
			saved_values[stat_type] = {
				"flat": enemy_stat.flat_bonus_value,
				"percent": enemy_stat.percent_bonus_value
			}
			enemy_stat.flat_bonus_value += modifier.flat_bonus_value
			enemy_stat.percent_bonus_value += modifier.percent_bonus_value

	enemy.set_meta(debuff_key, true)

	if enemy.animated_sprite and is_instance_valid(enemy.animated_sprite):
		enemy.animated_sprite.modulate = Color(0.6, 0.5, 0.8, 1.0)

	get_tree().create_timer(duration).timeout.connect(
		func():
			if not is_instance_valid(enemy) or not is_instance_valid(enemy.stats_component):
				return
			for stat_type in saved_values:
				if enemy.stats_component.stats.has(stat_type):
					var enemy_stat: StatData = enemy.stats_component.stats[stat_type]
					enemy_stat.flat_bonus_value = saved_values[stat_type]["flat"]
					enemy_stat.percent_bonus_value = saved_values[stat_type]["percent"]
			enemy.remove_meta(debuff_key)
			if enemy.animated_sprite and is_instance_valid(enemy.animated_sprite):
				enemy.animated_sprite.modulate = Color.WHITE
			#print("Debuff '%s' expired on %s" % [debuff.buff_name, enemy.name])
	)
	#print("Applied debuff '%s' to %s for %.1fs" % [debuff.buff_name, enemy.name, duration])
