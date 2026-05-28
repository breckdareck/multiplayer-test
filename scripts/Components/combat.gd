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

## Damage range shown in the stats window. Uses the active weapon's attack
## stat (`_get_weapon_attack_stat()`) — for a Staff or Wand that's
## MAGICATTACK, reflecting the channel their abilities scale on (which is
## what they actually fight with). Basic-attack *actual* damage is a
## separate concern: `calculate_attack_damage` always uses WEAPONATTACK
## regardless of weapon type.
var display_max_damage: int:
	get:
		return _calculate_max_range(_get_weapon_attack_stat())
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
var _weapon_mastery_component: WeaponMasteryComponent
var _sword_combo_component: SwordComboComponent

## PR 5: transient damage multiplier applied to the NEXT ability damage
## calculation. Used by AL_SlashBlast to scale damage by combo points spent
## (+25% per point). calculate_ability_damage reads + clears this so it
## never lingers past one hit. Defaults to 1.0 (no effect).
var pending_ability_damage_multiplier: float = 1.0

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
	_weapon_mastery_component = get_parent().get_node_or_null("WeaponMastery")
	_sword_combo_component = get_parent().get_node_or_null("SwordCombo")

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
	# PR 5 — Sword combo: clear the per-cast damage multiplier set by
	# AL_SlashBlast. Guards against bleed-through to the next ability cast
	# in the case where the player chains Slash → another sword ability
	# while pending_ability_damage_multiplier is still non-1.0.
	pending_ability_damage_multiplier = 1.0


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

		var proj_max_targets = current_level_stats.max_targets + _upgrade_int(current_ability_data, "bonus_targets")
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
		max_targets = current_level_stats.max_targets + _upgrade_int(current_ability_data, "bonus_targets")
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

	var attacker_level = owner_node.level_component.level
	var target_level = target_enemy.monster_level

	# --- Hit Chance Calculation ---
	var level_diff = attacker_level - target_level
	# Base 95% chance to hit. Lose 2% chance for each level the monster is above you.
	var hit_chance = clamp(95.0 + (level_diff * 2.0), 5.0, 100.0)
	
	var max_hits = 1
	if ability and level_stats:
		max_hits = level_stats.max_hits + _upgrade_int(ability, "bonus_hits")
	
	var damage_values: Array = []
	var crit_values: Array = []
	
	for i in range(max_hits):
		var roll = randf() * 100
		if roll > hit_chance:
			damage_values.append(-1) # -1 signifies a MISS
			crit_values.append(false)
			#print("Attack MISSED! (Roll: %.2f > Chance: %.2f)" % [roll, hit_chance])
			continue # Skip to the next hit

		# --- Damage Calculation ---
		var base_damage = 0
		if attack_name != "":
			base_damage = calculate_attack_damage()
		elif ability and level_stats:
			base_damage = calculate_ability_damage(ability, level_stats)

		var modified_damage = float(base_damage)

		if target_enemy.has_node("Stats"):
			var target_stats = target_enemy.get_node("Stats")
			var target_defense = target_stats.stats.get(Constants.StatType.DEFENSE).total_value

			var level_modifier = clamp(1.0 + (level_diff * 0.05), 0.5, 1.5)
			var defense_multiplier = 1.0 - (float(target_defense) / (target_defense + 500.0))

			modified_damage *= level_modifier * defense_multiplier
		
		var crit_chance = _stats_component.stats.get(Constants.StatType.CRITCHANCE).total_value
		var is_crit = (randf() * 100) < crit_chance
		
		if is_crit:
			var crit_damage_bonus = _stats_component.stats.get(Constants.StatType.CRITDAMAGE).total_value
			var crit_multiplier = randf_range(1.2, 1.5) + (crit_damage_bonus / 100.0)
			modified_damage *= crit_multiplier

		var damage_to_deal = roundi(modified_damage)

		damage_values.append(damage_to_deal)
		crit_values.append(is_crit)

		var was_alive: bool = not health_comp.is_dead
		health_comp.take_damage(damage_to_deal, self, true, is_crit, false)

		# PR 4 fix (2026-05-28): cast XP, formerly granted unconditionally in
		# ability.gd at cast time, now requires the ability to actually LAND
		# a hit. Spam-cast-in-empty-area exploit gone. Only credits the active
		# weapon's discipline (not secondary — distinct from the kill rule
		# which credits both), since cast XP is for actively USING the weapon.
		# Multi-hit abilities credit per landed hit (Lucky Seven's 2 hits =
		# 2 XP) — they're harder to land so the bonus is earned.
		#
		# Skipped for:
		#  - Basic attacks where `ability == null` (the melee-swing path).
		#  - Internal-pathway abilities with empty `required_class` (the
		#    convention from the Arrow Shot fix earlier today). Archers' basic
		#    attack routes through the Arrow Shot AbilityData so `ability` IS
		#    non-null here — without this second guard, archers would double-
		#    dip relative to sword/dagger (which use basic-melee with
		#    `ability == null`). Future "basic attack via internal ability"
		#    additions (Mage's basic staff projectile, etc.) get the same
		#    treatment for free by following the empty-required_class
		#    convention.
		#
		# Self-targeted buff/heal abilities that never reach _execute_hit
		# give zero mastery XP — combat engagement is the proxy for growth.
		if ability and _weapon_mastery_component:
			var is_internal_ability: bool = ability.required_class == null or ability.required_class.is_empty()
			if not is_internal_ability:
				var hit_discipline := _active_weapon_discipline()
				if hit_discipline != -1:
					_weapon_mastery_component.grant_mastery_xp_server(
						hit_discipline,
						WeaponMasteryComponent.XP_PER_CAST
					)

		# Mastery-XP-on-kill (PR 2; rule corrected 2026-05-28). If this hit
		# transitioned the target from alive -> dead, grant XP to BOTH the
		# primary AND the secondary equipped weapons' disciplines — so a
		# carried-but-unused weapon doesn't fall infinitely behind. (Cast XP
		# in ability.gd still only credits the active weapon, so swap-spammers
		# still gain casts on whatever they're actively wielding.) Multi-hit
		# iterations land on an already-dead target with was_alive=false, so
		# the grants fire at most once per enemy.
		#
		# PR 4 fix (2026-05-28): kill XP now scales with enemy level vs. player
		# level via WeaponMasteryComponent.compute_kill_xp. Flat XP_PER_KILL
		# was a farming exploit (one-shotting level-1 mobs for full XP). Now
		# below-level kills give the floor and higher-level kills give a
		# scaling bonus. Computed once and applied to both equipped weapons
		# so both disciplines see the same level-modified amount.
		if was_alive and health_comp.is_dead and _weapon_mastery_component:
			var kill_xp: int = WeaponMasteryComponent.compute_kill_xp(
				target_enemy.monster_level,
				owner_node.level_component.level
			)
			var kill_discipline := _active_weapon_discipline()
			if kill_discipline != -1:
				_weapon_mastery_component.grant_mastery_xp_server(kill_discipline, kill_xp)
			var secondary_discipline := _secondary_weapon_discipline()
			if secondary_discipline != -1 and secondary_discipline != kill_discipline:
				_weapon_mastery_component.grant_mastery_xp_server(secondary_discipline, kill_xp)

		# PR 6: passive-on-kill event dispatch. Bloodthirst (and future
		# kill-triggered passives) wire here. Fires once per landed killing
		# blow — multi-hit abilities that down a target on hit N still only
		# fire on_kill once because `was_alive` flips false after the
		# downing hit.
		if was_alive and health_comp.is_dead and _ability_component:
			if _ability_component.has_method("dispatch_passive_event_on_kill"):
				_ability_component.dispatch_passive_event_on_kill(target_enemy)

		# PR 5 — Sword signature: build a combo point on every BASIC-ATTACK
		# HIT while wielding a sword. Conditions:
		#  - `ability == null` (the basic-melee pathway; not the ability or
		#    Arrow-Shot internal pathway). Multi-hit ability hits don't
		#    build combo per the locked design — combo is built by basic
		#    attacks specifically.
		#  - Active weapon discipline is SWORD (so a Tab-swap to bow stops
		#    building combo, matching the "I am my weapon" rule).
		#  - Past the miss `continue` above — connected swings count even
		#    at zero damage; the connection is the signal of intent.
		# Cap behavior, decay restart, and RPC sync are owned by the
		# SwordComboComponent itself.
		if ability == null and is_instance_valid(_sword_combo_component):
			if _active_weapon_discipline() == Constants.ClassType.SWORD:
				_sword_combo_component.add_combo_point()

		# PR 5 follow-up: per-ability on_hit hook. Mirrors the execute/on_proc
		# pattern — if the ability defines an active_behavior.logic_script with
		# an on_hit(owner, target, ability) method, fire it for each landed
		# hit. Lets per-ability behaviors (e.g. Brandish building combo on
		# hit) live in their own AL_*.gd files instead of new bool fields on
		# ActiveBehaviorData. Server-only via the surrounding pathway.
		if ability and ability.active_behavior and ability.active_behavior.logic_script:
			var hit_logic = ability.active_behavior.logic_script.new()
			if hit_logic.has_method("on_hit"):
				hit_logic.on_hit(owner_node, target_enemy, ability)

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


func calculate_ability_damage(_ability: AbilityData, level_stats: AbilityLevelData) -> int:
	var max_range = _calculate_max_range(_ability.damage_stat)
	var damage = roundi(randf_range(max_range * mastery, max_range))

	damage = roundi(damage * (level_stats.damage_percent / 100.0))

	if _ability_component:
		var passive_modifier = _ability_component.get_ability_damage_modifier(_ability.ability_id)
		damage = roundi(damage * passive_modifier)
		#print("Applied passive damage modifier: %.2fx" % passive_modifier)

	# PR 5 — Sword combo: AL_SlashBlast stages a transient damage multiplier
	# on this component (pending_ability_damage_multiplier) when it spends
	# combo on cast. Apply it to every damage roll for this ability cast
	# (covers multi-hit + multi-target abilities — all hits of a finisher
	# should share the bonus). Reset to 1.0 in end_ability_attack so the
	# multiplier never bleeds into the next cast.
	if pending_ability_damage_multiplier != 1.0:
		damage = roundi(damage * pending_ability_damage_multiplier)

	# PR 6: generic "bonus_damage_mult" upgrade (additive %, e.g. +0.25).
	# Applied here so ANY ability's damage upgrades work without per-AL code.
	var dmg_bonus: float = _upgrade_float(_ability, "bonus_damage_mult")
	if dmg_bonus != 0.0:
		damage = roundi(damage * (1.0 + dmg_bonus))

	return damage


## PR 6 helpers: read summed upgrade magnitude for an ability via the
## AbilityComponent. Return 0 when unavailable so callers stay simple.
func _upgrade_float(ability: AbilityData, effect_key: String) -> float:
	if ability == null or not is_instance_valid(_ability_component):
		return 0.0
	if not _ability_component.has_method("get_ability_upgrade_magnitude"):
		return 0.0
	return _ability_component.get_ability_upgrade_magnitude(ability.ability_id, effect_key)


func _upgrade_int(ability: AbilityData, effect_key: String) -> int:
	return int(_upgrade_float(ability, effect_key))


func calculate_attack_damage() -> int:
	# Read through the active weapon accessor so PR 3's primary/secondary swap
	# is honored — the inactive weapon must not contribute to basic-attack
	# damage even though it stays in the equipment dictionary.
	if not (_equipment_component and _equipment_component.active_weapon_data):
		return 0

	# Basic attacks always use WEAPONATTACK, regardless of weapon type. A
	# Staff's basic swing intentionally uses the Wooden Staff's WEAPONATTACK,
	# not its MAGICATTACK — abilities are the channel for MAGICATTACK and
	# pass their own stat via `_calculate_max_range(_ability.damage_stat)`.
	var max_range = _calculate_max_range()
	return roundi(randf_range(max_range * mastery, max_range))


## Returns the `Constants.ClassType` discipline of the ACTIVE weapon (PR 3),
## or -1 if there's no weapon equipped in the active slot (or the equipped
## weapon is not one of the four tier-1 disciplines). Used by the mastery-XP
## grant path so kills only feed mastery to weapons the system actually
## tracks. Falls back to the character's `current_class` when the active slot
## is empty but the character's discipline is a tier-1 weapon, so a
## bare-fisted kill still credits the player's chosen discipline. Routes
## through `active_weapon_data` instead of the raw `weapon_slot.item` so the
## swap UX correctly attributes mastery to whichever weapon is wielded.
func _active_weapon_discipline() -> int:
	# Preferred: the actual weapon currently in the ACTIVE slot.
	if _equipment_component:
		var weapon: WeaponData = _equipment_component.active_weapon_data
		if weapon != null:
			var discipline := WeaponMasteryComponent.weapon_type_to_discipline(weapon.weapon_type)
			if discipline != -1:
				return discipline

	# Fallback: the character's current discipline (relevant for unarmed kills
	# on a Beginner whose only tier-1 lineage is the picked starter).
	if _class_component:
		match _class_component.current_class:
			Constants.ClassType.SWORD, Constants.ClassType.BOW, \
			Constants.ClassType.STAFF, Constants.ClassType.DAGGER:
				return _class_component.current_class
	return -1


## Returns the discipline of the SECONDARY-slot weapon, or -1 if no secondary
## is equipped. Added 2026-05-28 so kill-XP can credit both equipped weapons
## (the player's "carried but not wielded" weapon shouldn't fall infinitely
## behind the one they're actively swinging — see _execute_hit).
func _secondary_weapon_discipline() -> int:
	if not _equipment_component:
		return -1
	var sd: SlotData = _equipment_component.secondary_weapon_slot_data
	if sd == null or sd.item == null:
		return -1
	var weapon: WeaponData = sd.item as WeaponData
	if weapon == null:
		return -1
	return WeaponMasteryComponent.weapon_type_to_discipline(weapon.weapon_type)


## Returns the StatType the ACTIVE weapon's damage scales off. PR 3 replaced
## the old class-driven attack-stat lookup with this — once the player carries
## two weapons, the channel a Staff vs a Sword fights through is a per-weapon
## decision, not a per-character one. Staff / Wand → MAGICATTACK;
## anything else (including bare hands) → WEAPONATTACK.
func _get_weapon_attack_stat() -> Constants.StatType:
	if _equipment_component:
		var weapon: WeaponData = _equipment_component.active_weapon_data
		if weapon != null:
			match weapon.weapon_type:
				Constants.WeaponType.STAFF:
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
