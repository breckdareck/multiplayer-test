class_name AbilityComponent
extends Node

## Manages a character's abilities, including learning, leveling, usage, cooldowns,
## passive effects, and multiplayer synchronization.
## Requires ClassComponent and StatsComponent as siblings to function correctly.


#region #################### Signals ####################
signal ability_used(ability_id: String)
signal cooldown_started(ability_id: String, duration: float)
signal ability_leveled_up(ability_id: String, new_level: int)
signal ability_learned(ability_id: String)
## PR 4: ability points are pooled per-weapon-discipline. The signal
## carries the affected discipline ("sword" / "bow" / "staff" / "dagger")
## and the new total for that discipline only. UI consumers should refresh
## the matching tab; existing "mark data dirty" callbacks ignore the args
## and just re-save.
signal ability_points_changed(discipline_key: String, new_total: int)
## PR 6: fired when an ability upgrade is purchased (server-auth, synced to
## the owning client). The AbilityWindow upgrade panel refreshes on this.
signal ability_upgrade_purchased(ability_id: String, upgrade_id: String)
## PR 6: fired when an upgrade purchase was denied. Reason is one of
## "not_learned" / "unknown_upgrade" / "already_owned" / "tier_locked" /
## "variant_taken" / "no_points". The UI surfaces a ping.
signal ability_upgrade_denied(ability_id: String, upgrade_id: String, reason: String)
## PR 4: fired when a spend was denied because the discipline pool was
## empty (or the ability is not bound to any tier-1 discipline). The
## AbilityWindow uses this to surface a UI ping.
signal ability_points_spend_denied(ability_id: String, reason: String)
#endregion


#region #################### Exports & Properties ####################
@export_category("Debug")
@export var hitbox: CollisionShape2D
@export var debug_ability: AbilityData:
	get:
		return debug_ability
	set(new_ability_data):
		debug_ability = new_ability_data
		if not is_instance_valid(hitbox):
			printerr("Hitbox is not valid. Cannot set shape.")
			return
		
		# Update the debug hitbox shape and position based on the assigned AbilityData
		if new_ability_data and new_ability_data.active_behavior and is_instance_valid(new_ability_data.active_behavior.hit_box_shape_data):
			##print("Setting debug hitbox from: %s" % new_ability_data.ability_name)
			hitbox.shape = new_ability_data.active_behavior.hit_box_shape_data.duplicate()
			hitbox.position = new_ability_data.active_behavior.hit_box_position_data
		else:
			# Fallback to a default shape if the ability data is invalid
			##print("Setting debug hitbox to default shape.")
			var default_shape := RectangleShape2D.new()
			default_shape.size = Vector2(21, 21)
			hitbox.shape = default_shape
			hitbox.position = Vector2(9.5, -10.5)
#endregion


#region #################### Member Variables ####################
# Component references
var _class_component: ClassComponent
var _stats_component: StatsComponent
var _level_component: LevelingComponent
var _mana_component: ManaComponent
var _equipment_component: EquipmentComponent
var _weapon_mastery_component: WeaponMasteryComponent

# State variables
var _cooldowns: Dictionary = {} # { ability_id: time_remaining }
var _ability_levels: Dictionary = {} # { ability_id: current_level }
## PR 6: purchased per-ability upgrades. { ability_id: Array[String] of
## upgrade_ids }. Server-authoritative; mirrored to the owning client via the
## ability sync RPCs. Persisted alongside ability_levels in save_abilities().
var _learned_upgrades: Dictionary = {}
## PR 4: per-weapon-discipline ability point pools. Keys are the lowercase
## discipline strings ("sword" / "bow" / "staff" / "dagger"); values are
## ints. Replaces the legacy single-pool `_available_ability_points: int`.
## Save migration in `load_abilities` redistributes the legacy int evenly
## across the four pools, with the remainder going to the player's
## starting discipline.
var _available_points_per_discipline: Dictionary = {
	"sword": 0,
	"bow": 0,
	"staff": 0,
	"dagger": 0,
}
var _loading_mode: bool = false

## PR 4: how many ability points each level-up grants. Awarded entirely to
## the active weapon's discipline pool (the discipline the player is
## wielding at the moment the level-up signal fires).
## PR 4 fix (2026-05-27): ability points are granted per MASTERY-LEVEL of the
## relevant weapon discipline, NOT per character level. A level-30 character
## who never used a bow has zero Bow ability points — they earn them by
## actually using the bow (mastery XP from kills + casts → mastery levels →
## ability points to that discipline's pool). Replaces the earlier per-character-
## level grant rule which leaked points evenly across the 4 trees and let a
## character earn points for trees they never touched.
##
## PR 6 balance pass (2026-05-28): raised 3 -> 6 so a maxed-mastery discipline
## (MASTERY_CAP 20) yields 120 points. Target endgame build at 120: MAX 3
## actives + fully upgrade them (3 * 24) + 2 filler actives + MAX 2 passives +
## passive upgrades. You still can't max all 8 actives, so build identity comes
## from WHICH abilities + upgrades you pick. The reconcile_ability_points()
## guard makes this retroactive — existing characters get the new total on
## next load (granted = mastery_level * 6 recomputed against spent).
const ABILITY_POINTS_PER_MASTERY_LEVEL: int = 6

## PR 4: canonical lowercase discipline keys, in display order (the order
## the AbilityWindow renders tabs).
const DISCIPLINE_KEYS: Array[String] = ["sword", "bow", "staff", "dagger"]

# PR 3: per-weapon hotbar bindings (Option A — ESO model).
# Each weapon carries its own independent hotbar layout. Bind Slash Blast to
# slot 1 for the sword, Strafe to slot 1 for the bow — they don't collide.
# On swap, the live `hotbar.save_hotbar_config()` is captured into the
# leaving binding, then the becoming-active binding is pushed into
# `hotbar.load_hotbar_config()`. The hotbar UI re-renders in lockstep with
# the active weapon flip.
var _primary_hotbar_bindings: Dictionary = {}
var _secondary_hotbar_bindings: Dictionary = {}

# Track proc cooldowns per passive ability
var _passive_proc_cooldowns: Dictionary = {} # { "ability_id_event_type": last_proc_time }

# Track active passive abilities for easy access
@warning_ignore("unused_private_class_variable")
var _active_passive_abilities: Array[AbilityData] = []

const MAX_ABILITY_REQUESTS_PER_SECOND: int = 10
var _ability_request_times: Array[float] = []

# Projectile container
var _projectiles_container: Node

# UI references
@onready var hotbar: Hotbar = $"../../CanvasLayer/PlayerHUD/Hotbar"
#endregion


#region #################### Godot Engine Callbacks ####################
func _ready() -> void:
	# Fetch required sibling components
	_class_component = get_parent().get_node_or_null("Class")
	_stats_component = get_parent().get_node_or_null("Stats")
	_level_component = get_parent().get_node_or_null("Leveling")
	_mana_component = get_parent().get_node_or_null("Mana")
	_equipment_component = get_parent().get_node_or_null("Equipment")
	_weapon_mastery_component = get_parent().get_node_or_null("WeaponMastery")
	
	if not _class_component or not _stats_component:
		push_error("AbilityComponent requires ClassComponent and StatsComponent siblings.")
		set_process(false)
		return

	# Connect to ClassComponent to handle class changes
	if _class_component:
		_class_component.class_changed.connect(_on_class_changed)

	# PR 3: react to active-weapon flips by swapping the live hotbar to the
	# becoming-active weapon's bindings. Runs on both server and client so the
	# host (server + client in one tree) and remote clients both refresh.
	if _equipment_component:
		_equipment_component.active_weapon_changed.connect(_on_active_weapon_changed)

	# Find or create the projectiles container inside the current visible map.
	var map_node = MapManager.get_current_visible_map()
	if map_node:
		_projectiles_container = map_node.get_node_or_null("Projectiles")
		if not is_instance_valid(_projectiles_container):
			_projectiles_container = Node.new()
			_projectiles_container.name = "Projectiles"
			map_node.add_child(_projectiles_container)
	else:
		# Fallback to legacy path if available
		var legacy = get_node_or_null("/root/MainMenu/Level/Game")
		if legacy:
			_projectiles_container = legacy.get_node_or_null("Projectiles")
			if not is_instance_valid(_projectiles_container):
				_projectiles_container = Node.new()
				_projectiles_container.name = "Projectiles"
				legacy.add_child(_projectiles_container)

	# PR 4 fix (2026-05-27): grant ability points per-mastery-level, not per-
	# character-level. The old _level_component.leveled_up hookup is gone —
	# WeaponMasteryComponent.mastery_level_changed is now the only point-grant
	# source. See ABILITY_POINTS_PER_MASTERY_LEVEL for the rate.
	if _weapon_mastery_component:
		if multiplayer.is_server():
			_weapon_mastery_component.mastery_level_changed.connect(_on_mastery_level_up)
	else:
		push_warning("AbilityComponent: No WeaponMasteryComponent found. Points won't be granted on mastery level up.")
		
	# Initialize class abilities on the server or in single-player.
	# Clients will receive this data via an RPC sync when they connect.
	#
	# Each discipline's starter ability (configured on WeaponDisciplineData.starter_ability)
	# is auto-leveled to 1 so a fresh character can cast something immediately.
	# Without this, classes like Mage (whose basic attack uses the staff's
	# tiny WEAPONATTACK while their kit is built around MAGICATTACK abilities)
	# can't fight effectively until they earn their first ability point on
	# level-up. Save data still overrides this — returning characters keep
	# whatever level they had leveled the ability to.
	#
	# PR 4 fix (2026-05-28): all FOUR tier-1 disciplines' starter abilities
	# are auto-leveled to 1, not just the player's starting class's starter.
	# So when a Swordsman picks up a bow they immediately have Double Shot
	# ready to fire instead of being stuck with a basic-attack swing of a
	# weapon they have no abilities for. Each discipline's full ability list
	# is also added at level 0 so the AbilityWindow can show them with a
	# "Learn" / "+" affordance.
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		# Original class abilities first (keeps the existing per-class starter
		# behavior intact for the player's chosen discipline).
		var starter: AbilityData = _class_component.get_starter_ability() if _class_component else null
		for ability_data in _class_component.get_class_abilities():
			if ability_data and not _ability_levels.has(ability_data.ability_id):
				var initial_level: int = 1 if (starter and ability_data == starter) else 0
				_learn_ability_local(ability_data.ability_id, initial_level, false)

		# Then iterate the OTHER three tier-1 disciplines and seed their
		# starter abilities at level 1 + the rest of each tree at level 0.
		# Skips the starting discipline (already handled above) and tier-2
		# advancement classes (those live in their tier-1 parent's tree).
		var starting_class: int = _class_component.current_class if _class_component else -1
		for tier1_disc in [
			Constants.ClassType.SWORD,
			Constants.ClassType.BOW,
			Constants.ClassType.STAFF,
			Constants.ClassType.DAGGER,
		]:
			if tier1_disc == starting_class:
				continue
			var disc_data: WeaponDisciplineData = ResourceManager.get_class_data(tier1_disc)
			if disc_data == null:
				continue
			var disc_starter: AbilityData = disc_data.starter_ability
			for ability_data in disc_data.skills:
				if ability_data == null or _ability_levels.has(ability_data.ability_id):
					continue
				var initial_level: int = 1 if (disc_starter and ability_data == disc_starter) else 0
				_learn_ability_local(ability_data.ability_id, initial_level, false)

	##print("AbilityComponent ready. Loaded abilities: ", _ability_levels)


func _process(delta: float) -> void:
	# Tick down active cooldowns
	var finished_cooldowns = []
	for ability_id in _cooldowns:
		_cooldowns[ability_id] -= delta
		if _cooldowns[ability_id] <= 0.0:
			finished_cooldowns.append(ability_id)

	for ability_id in finished_cooldowns:
		_cooldowns.erase(ability_id)
#endregion


#region #################### Public API ####################
## Attempts to use an ability.
func use_ability(ability_id: String) -> bool:
	var validation = _validate_ability_use(ability_id)
	if not validation.valid:
		return false
	
	# Client-side check to prevent sending pointless requests
	if _cooldowns.has(ability_id):
		##print("Ability '%s' is on cooldown." % validation.ability.ability_name)
		return false
		
	# In multiplayer, clients request the server to use the ability.
	if _is_multiplayer_client():
		_request_ability_use(ability_id)
		return true
	
	# In single-player or on the server, execute directly.
	return _handle_authoritative_use(ability_id, validation.ability, validation.level_stats)


## Attempts to level up an ability.
func level_up_ability(ability_id: String) -> bool:
	if _is_multiplayer_client():
		level_up_ability_request.rpc_id(1, ability_id)
		return true
	
	return _level_up_ability_local(ability_id)


## Learns a new ability.
func learn_ability(ability_id: String, initial_level: int = 0) -> bool:
	if _is_multiplayer_client():
		learn_ability_request.rpc_id(1, ability_id, initial_level)
		return true

	return _learn_ability_local(ability_id, initial_level)


func get_passive_effect_modifiers() -> Dictionary:
	var modifiers = {}
	
	_foreach_learned_passive(func(_ability: AbilityData, level_stats: AbilityLevelData, _ability_id: String):
		# PR 6: "passive_stat_percent_bonus" upgrade adds extra % to whatever
		# stat(s) this passive boosts (e.g. Hardened Frame's +HP%, Iron
		# Sinews' +STR%). Applied per modified stat.
		var pct_bonus: float = get_ability_upgrade_magnitude(_ability_id, "passive_stat_percent_bonus")
		# Use stat bonuses from the level data
		for stat_name in level_stats.stat_bonuses:
			if not modifiers.has(stat_name):
				modifiers[stat_name] = StatData.new(stat_name, 0)
			# Accumulate bonuses from multiple passives
			modifiers[stat_name].flat_bonus_value += level_stats.stat_bonuses[stat_name].flat_bonus_value
			modifiers[stat_name].percent_bonus_value += level_stats.stat_bonuses[stat_name].percent_bonus_value + pct_bonus
	)

	return modifiers


func get_ability_damage_modifier(ability_id: String) -> float:
	return _get_ability_modifier(ability_id, func(level_stats, id): return level_stats.get_ability_damage_modifier(id))


func get_ability_cooldown_modifier(ability_id: String) -> float:
	return _get_ability_modifier(ability_id, func(level_stats, id): return level_stats.get_ability_cooldown_modifier(id))


func get_ability_mana_modifier(ability_id: String) -> float:
	return _get_ability_modifier(ability_id, func(level_stats, id): return level_stats.get_ability_mana_modifier(id))


func try_trigger_procs(event_type: String, target: Node = null, context: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return
	
	_foreach_learned_passive(func(_ability: AbilityData, level_stats: AbilityLevelData, ability_id: String):
		var proc_key = ability_id + "_" + event_type
		var last_proc_time = _passive_proc_cooldowns.get(proc_key, 0.0)
		
		var proc_effect = level_stats.try_proc_event(event_type, {event_type: last_proc_time})
		if proc_effect:
			_execute_proc(proc_effect, target, context)
			_passive_proc_cooldowns[proc_key] = Time.get_ticks_msec() / 1000.0
	)

#endregion


#region #################### Helper Functions ####################
## Helper to check if we're a client in a multiplayer session
func _is_multiplayer_client() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.is_server()


## PR 4: returns the lowercase discipline key for an ability based on its
## `required_class[0]`. Maps SWORD/CRUSADER -> "sword", BOW/RANGER ->
## "bow", STAFF/ARCHMAGE -> "staff", DAGGER/ASSASSIN -> "dagger". Returns
## "" for abilities without a `required_class` entry; those become
## unspendable per the locked design ("every ability belongs to a weapon
## tree"). Authors should fix any flagged ability instead of relying on
## a fallback bucket.
func _ability_primary_discipline(ability: AbilityData) -> String:
	if ability == null:
		return ""
	if ability.required_class == null or ability.required_class.is_empty():
		return ""
	return _class_type_to_discipline_key(ability.required_class[0])


## Maps a `Constants.ClassType` enum value (tier-1 starting discipline OR
## tier-2 advancement) to the lowercase discipline key the per-pool dict
## uses. Returns "" for BEGINNER (no tree).
func _class_type_to_discipline_key(class_type: int) -> String:
	match class_type:
		Constants.ClassType.SWORD, Constants.ClassType.CRUSADER:
			return "sword"
		Constants.ClassType.BOW, Constants.ClassType.RANGER:
			return "bow"
		Constants.ClassType.STAFF, Constants.ClassType.ARCHMAGE:
			return "staff"
		Constants.ClassType.DAGGER, Constants.ClassType.ASSASSIN:
			return "dagger"
	return ""


## Returns the discipline key the player is *currently wielding* - driven
## by the active weapon, not the starting class. Falls back to "" when no
## weapon is equipped (callers can substitute the starting discipline).
func _active_discipline_key() -> String:
	if not is_instance_valid(owner):
		return ""
	if owner.has_method("get_active_discipline"):
		var disc: int = owner.get_active_discipline()
		return _class_type_to_discipline_key(disc)
	return ""


## PR 4 fix (2026-05-28): true iff the given ability's discipline matches
## the currently-wielded weapon's discipline. Used by _validate_ability_use
## to reject cross-discipline casts (e.g. firing Slash while wielding a
## staff). Falls back to the starting class's discipline when the player
## has no weapon equipped, so a bare-handed Swordsman can still cast Slash.
func _ability_matches_active_discipline(ability: AbilityData) -> bool:
	var ability_disc: String = _ability_primary_discipline(ability)
	if ability_disc == "":
		return true  # defensive: discipline-less abilities aren't gated
	var active_disc: String = _active_discipline_key()
	if active_disc == "":
		active_disc = _starting_discipline_key()
	return ability_disc == active_disc


## Returns the discipline key for the player's starting class - used as a
## fallback when the active weapon can't supply one (e.g. unequipped at
## first level-up after creation) and as the "remainder" target for the
## legacy-save even-distribute migration.
func _starting_discipline_key() -> String:
	if is_instance_valid(_class_component):
		return _class_type_to_discipline_key(_class_component.current_class)
	return ""


## Helper function to iterate through all learned passive abilities
## Calls the provided callable for each passive ability with its data
##
## PR 4 fix (2026-05-28, refined 2026-05-28): passives apply when the
## matching weapon is in EITHER equipped slot (primary or secondary), not
## just the currently-wielded active. The "I am my weapon" rule applies
## to active casts and the sprite/attack-pattern identity, but passives
## come from carrying the weapon at all — a Swordsman with Sword in
## primary and Bow in secondary keeps both trees' passives active, while
## Staff and Dagger passives (no weapon equipped in those disciplines)
## stay dormant.
##
## This filter cascades to every consumer of learned-passive iteration
## (stat modifiers, on-hit/on-crit/on-kill procs, ability-damage/cooldown
## modifiers). StatsComponent recalcs on equipment_changed, so the filter
## refreshes whenever a slot's weapon item changes.
func _foreach_learned_passive(callback: Callable) -> void:
	var equipped_disc_keys: Dictionary = _equipped_discipline_keys()
	for ability_id in _ability_levels:
		var ability_level = _ability_levels[ability_id]

		# Skip unlearned abilities
		if ability_level <= 0:
			continue

		var ability = ResourceManager.get_ability_data(ability_id)
		if not ability or ability.ability_type != Constants.AbilityType.PASSIVE:
			continue

		# Discipline gate: only apply this passive if its discipline matches
		# an EQUIPPED weapon (primary or secondary). Abilities with no
		# required_class (defensive — shouldn't exist post-PR-4) pass through.
		var ability_disc_key: String = _ability_primary_discipline(ability)
		if ability_disc_key != "" and not equipped_disc_keys.has(ability_disc_key):
			continue

		var level_stats = ability.get_level_stats(ability_level)
		if not level_stats:
			continue

		# Call the callback with the ability data
		callback.call(ability, level_stats, ability_id)


## Returns a Dictionary keyed by discipline string (set-like) for every
## currently-equipped weapon's discipline. Used by _foreach_learned_passive
## to gate passive effects to equipped disciplines only. Routes through the
## player root's get_equipped_disciplines() method so this component
## doesn't have to reach across to EquipmentComponent directly.
func _equipped_discipline_keys() -> Dictionary:
	var result: Dictionary = {}
	if not is_instance_valid(owner):
		return result
	if owner.has_method("get_equipped_disciplines"):
		var disciplines: Array = owner.get_equipped_disciplines()
		for disc in disciplines:
			var key: String = _class_type_to_discipline_key(int(disc))
			if key != "":
				result[key] = true
	return result


## Generic modifier calculator - reduces code duplication
func _get_ability_modifier(ability_id: String, modifier_getter: Callable) -> float:
	var total_modifier: float = 1.0
	# Iterate synchronously - avoid capturing outer-scope reassignments inside lambdas
	for passive_id in _ability_levels:
		var lvl = _ability_levels[passive_id]
		if lvl <= 0:
			continue
		var ability = ResourceManager.get_ability_data(passive_id)
		if not ability or ability.ability_type != Constants.AbilityType.PASSIVE:
			continue
		var level_stats = ability.get_level_stats(lvl)
		if not level_stats:
			continue
		total_modifier *= modifier_getter.call(level_stats, ability_id)

	return total_modifier


## Validates if an ability can be used - reduces duplication
func _validate_ability_use(ability_id: String) -> Dictionary:
	var result = {
		"valid": false,
		"ability": null,
		"level": 0,
		"level_stats": null
	}
	
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not ability:
		#printerr("Ability ID '%s' not found." % ability_id)
		return result
	
	var ability_level := get_ability_level(ability_id)
	if ability_level <= 0:
		##print("Ability '%s' has not been learned." % ability.ability_name)
		return result
	
	if ability.ability_type != Constants.AbilityType.ACTIVE:
		##print("Ability '%s' is not an active ability." % ability.ability_name)
		return result

	# PR 4 fix (2026-05-28): you can only cast an ability while wielding a
	# weapon of its discipline. Catches the case where the player swapped
	# the ITEM in their active slot (e.g. sword -> staff) but the hotbar
	# binding still points at a sword ability — the binding's cast must
	# fail instead of incorrectly firing a sword swing while holding a
	# staff. Abilities with no required_class (shouldn't exist post-PR-4)
	# pass through.
	if not _ability_matches_active_discipline(ability):
		##print("Ability '%s' is for a different discipline than the wielded weapon." % ability.ability_name)
		return result

	var level_stats = ability.get_level_stats(ability_level)
	if not level_stats:
		#printerr("Invalid level data for '%s' at level %d" % [ability.ability_name, ability_level])
		return result
	
	result.valid = true
	result.ability = ability
	result.level = ability_level
	result.level_stats = level_stats
	return result


## Checks if resources and state allow ability use
func _can_afford_ability(ability_id: String, level_stats: AbilityLevelData) -> bool:
	# Check mana
	var modified_mana_cost = level_stats.mana_cost * get_ability_mana_modifier(ability_id)
	if _mana_component.current_mana < modified_mana_cost:
		##print("Server: Not enough mana.")
		return false

	# Check if already attacking
	var state_machine = owner.get_node_or_null("StateMachine")
	if state_machine:
		var attack_state = state_machine.get_node_or_null("attack")
		if "current_state" in state_machine and state_machine.current_state == attack_state:
			##print("Server: Cannot use ability, an attack is already in progress.")
			return false

	return true


## Returns the `Constants.ClassType` discipline of the ACTIVE weapon (PR 3),
## or -1 if there's no tier-1 weapon equipped in the active slot. Used by the
## mastery-XP-on-cast grant. Falls back to the character's current_class when
## the active slot is empty (a Beginner casting their starter ability with no
## weapon still credits the chosen discipline if it's tier-1).
## Mirrors CombatComponent._active_weapon_discipline — kept duplicated
## (~10 lines) rather than centralised so each component can be read in
## isolation; both go through WeaponMasteryComponent.weapon_type_to_discipline
## for the actual mapping. Routes through `active_weapon_data` so the
## primary/secondary swap correctly attributes XP.
func _active_weapon_discipline() -> int:
	if _equipment_component:
		var weapon: WeaponData = _equipment_component.active_weapon_data
		if weapon != null:
			var discipline := WeaponMasteryComponent.weapon_type_to_discipline(weapon.weapon_type)
			if discipline != -1:
				return discipline

	if _class_component:
		match _class_component.current_class:
			Constants.ClassType.SWORD, Constants.ClassType.BOW, \
			Constants.ClassType.STAFF, Constants.ClassType.DAGGER:
				return _class_component.current_class
	return -1


## Consumes resources and starts cooldown for an ability
func _consume_ability_resources(ability_id: String, level_stats: AbilityLevelData) -> float:
	# Consume mana
	if _mana_component.current_mana:
		var modified_mana_cost = roundi(level_stats.mana_cost * get_ability_mana_modifier(ability_id))
		# PR 6: generic "mana_flat_reduction" upgrade (flat MP off, clamped >= 0).
		modified_mana_cost = maxi(0, modified_mana_cost - int(get_ability_upgrade_magnitude(ability_id, "mana_flat_reduction")))
		_mana_component.current_mana -= modified_mana_cost
	
	# Start cooldown. PR 6: subtract any flat cooldown reduction from owned
	# upgrades (effect_key "cooldown_flat_reduction", magnitude = seconds)
	# AFTER the multiplicative passive modifier, clamped to >= 0.
	var modified_cooldown = level_stats.cooldown_time * get_ability_cooldown_modifier(ability_id)
	modified_cooldown = maxf(0.0, modified_cooldown - get_ability_upgrade_magnitude(ability_id, "cooldown_flat_reduction"))
	_cooldowns[ability_id] = modified_cooldown

	return modified_cooldown

#endregion


#region #################### Internal Logic & Execution ####################
## The authoritative logic for using an ability (runs on server or in single-player).
func _handle_authoritative_use(ability_id: String, ability: AbilityData, level_stats: AbilityLevelData) -> bool:
	# Final server-side validation
	if _cooldowns.has(ability_id):
		return false
	
	# Check resources and state
	if not _can_afford_ability(ability_id, level_stats):
		return false
	
	# Consume resources and start cooldown
	var cooldown_duration = _consume_ability_resources(ability_id, level_stats)
	
	# Trigger the visual/gameplay effect
	_trigger_ability_state_change(ability, level_stats)
	
	# Trigger on_ability_cast procs
	try_trigger_procs("on_ability_cast", null, {"ability": ability, "level_stats": level_stats})
	
	# Emit signals and notify clients
	ability_used.emit(ability_id)
	cooldown_started.emit(ability_id, cooldown_duration)
	
	if multiplayer.is_server():
		if BotManager.is_bot(owner.player_id):
			# A bot's AbilityComponent node may be missing on a client mid
			# map-transition; route the cast visual through MapManager instead.
			_broadcast_bot_ability_visual(ability_id, level_stats.level)
		else:
			ability_used_client.rpc(ability_id, cooldown_duration)

		# PR 4 fix (2026-05-28): cast XP grant moved to combat.gd._execute_hit
		# so it only fires when the ability actually LANDS a hit on an enemy.
		# Granting on the bare cast was a farming exploit — a player could
		# spam an ability in an empty area to grind mastery without engaging
		# enemies. Self-targeted abilities (buffs/heals) now give no mastery
		# XP, which is intended — combat engagement is the proxy for
		# weapon-mastery growth.

	return true


## Routes a bot's ability-cast visual through MapManager (an autoload that
## always resolves) rather than the bot's AbilityComponent node, which a client
## may lack mid map-transition.
func _broadcast_bot_ability_visual(ability_id: String, level: int) -> void:
	var map_name: String = MapManager.get_player_map(owner.player_id)
	for peer_id in MapManager.get_real_players_on_map(map_name):
		if peer_id != 1:
			MapManager.bot_ability_used.rpc_id(peer_id, owner.player_id, ability_id, level)


## Triggers the state machine transition and custom logic for an active ability.
func _trigger_ability_state_change(ability: AbilityData, level_stats: AbilityLevelData) -> void:
	##print("Executing %s (Level %d)" % [ability.ability_name, level_stats.level])
	
	var active_behavior = ability.active_behavior
	if not active_behavior:
		push_error("Ability '%s' is missing ActiveBehavior data." % ability.ability_name)
		return

	# All active abilities now go through the state machine.
	# The CombatComponent will handle the difference between projectile and hitbox attacks.
	var state_machine = owner.get_node_or_null("StateMachine")
	if not state_machine:
		push_error("Could not find StateMachine on owner.")
		return
		
	var attack_state = state_machine.get_node_or_null("attack")
	if not attack_state or not attack_state.has_method("set_ability_data"):
		push_error("Attack state is invalid or missing 'set_ability_data' method.")
		return
	
	# Configure the attack state with this ability's data
	attack_state.set_ability_data(ability, level_stats)
	
	# Transition to the attack state
	if "current_state" in state_machine and state_machine.current_state != attack_state:
		state_machine.current_state = attack_state
		attack_state.enter()
		if active_behavior.sfx_path:
			AudioManager.play_sfx_for_map(MapManager.get_player_map(owner.player_id), active_behavior.sfx_path, owner.global_position)

	# Execute optional custom logic from the ability's script resource
	if active_behavior.logic_script:
		var custom_logic = active_behavior.logic_script.new()
		if custom_logic.has_method("execute"):
			custom_logic.execute(owner, ability, level_stats)


## The authoritative logic for leveling up an ability.
func _level_up_ability_local(ability_id: String) -> bool:
	if not can_level_up_ability(ability_id):
		##print("Validation failed for leveling up ability: %s." % ability_id)
		# PR 4: surface a precise denial reason for the AbilityWindow to ping.
		var ability_for_reason: AbilityData = ResourceManager.get_ability_data(ability_id)
		if ability_for_reason:
			var denial_key: String = _ability_primary_discipline(ability_for_reason)
			if denial_key == "":
				ability_points_spend_denied.emit(ability_id, "no_discipline")
			elif int(_available_points_per_discipline.get(denial_key, 0)) <= 0:
				ability_points_spend_denied.emit(ability_id, "no_points")
			else:
				ability_points_spend_denied.emit(ability_id, "blocked")
		return false

	var ability = ResourceManager.get_ability_data(ability_id)
	# PR 4 fix (2026-05-27): use safe get() because unlearned abilities (level 0)
	# may not be in _ability_levels yet — they're only pre-seeded for the
	# player's starting class. Now that the AbilityWindow shows all 4 trees, a
	# player can level up an ability from a discipline they never started in,
	# which would crash on the bare `_ability_levels[ability_id]` lookup.
	var current_level: int = int(_ability_levels.get(ability_id, 0))

	# PR 4: spend one point from the discipline pool that owns this ability.
	# `can_level_up_ability` already validated the pool; we re-derive the key
	# here rather than trust the caller.
	var disc_key: String = _ability_primary_discipline(ability)
	if disc_key != "" and _available_points_per_discipline.has(disc_key):
		_available_points_per_discipline[disc_key] = max(0, int(_available_points_per_discipline[disc_key]) - 1)
	_ability_levels[ability_id] = current_level + 1

	# Re-apply passive effects if a passive ability was leveled up
	if ability.ability_type == Constants.AbilityType.PASSIVE:
		_apply_passive_effects()

	ability_leveled_up.emit(ability_id, current_level + 1)
	##print("Leveled up %s to level %d" % [ability.ability_name, current_level + 1])

	# PR 4: fire the per-discipline points-changed signal so the right tab
	# refreshes.
	if disc_key != "":
		ability_points_changed.emit(disc_key, int(_available_points_per_discipline.get(disc_key, 0)))

	# Sync changes to clients (bots have no client UI — skip to avoid a
	# node-addressed RPC failing on clients that lack the bot node).
	if multiplayer.is_server() and not BotManager.is_bot(owner.player_id):
		sync_ability_level.rpc(ability_id, current_level + 1)
		sync_ability_points_per_discipline.rpc(_available_points_per_discipline.duplicate())

	return true


## The authoritative logic for learning an ability.
func _learn_ability_local(ability_id: String, initial_level: int = 0, send_rpc: bool = true) -> bool:
	if _ability_levels.has(ability_id):
		return false
	
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability:
		#printerr("AbilityData not found for ID: %s" % ability_id)
		return false
	
	_ability_levels[ability_id] = initial_level
	
	if ability.ability_type == Constants.AbilityType.PASSIVE:
		_apply_passive_effects()
		
	ability_learned.emit(ability_id)
	##print("Learned ability: %s at level %d" % [ability.ability_name, initial_level])
	
	if send_rpc and multiplayer.is_server() and not BotManager.is_bot(owner.player_id):
		sync_ability_learned.rpc(ability_id, initial_level)
	
	return true


## Forces the StatsComponent to recalculate stats, applying all passive bonuses.
func _apply_passive_effects() -> void:
	if _stats_component and multiplayer.is_server():
		_stats_component.mark_stats_dirty()


## PR 4: grants ability points to a specific weapon-discipline pool.
## `discipline_key` is one of "sword" / "bow" / "staff" / "dagger". An
## empty or unknown key falls back to the player's starting-class
## discipline so level-ups never silently lose points.
func _add_ability_points(amount: int, discipline_key: String = "") -> void:
	var key: String = discipline_key
	if key == "" or not _available_points_per_discipline.has(key):
		key = _starting_discipline_key()
	if key == "":
		push_warning("AbilityComponent: no discipline available to credit %d points to" % amount)
		return
	_available_points_per_discipline[key] = int(_available_points_per_discipline.get(key, 0)) + amount
	##print("Added %d ability points to %s. Total: %d" % [amount, key, _available_points_per_discipline[key]])
	ability_points_changed.emit(key, int(_available_points_per_discipline[key]))

	if multiplayer.is_server() and not BotManager.is_bot(owner.player_id):
		sync_ability_points_per_discipline.rpc(_available_points_per_discipline.duplicate())


func _execute_proc(proc: ProcEffectData, target: Node, context: Dictionary) -> void:
	##print("Proc triggered! Chance was: %.1f%%" % (proc.proc_chance * 100))
	
	# Deal damage if specified
	if proc.damage_percent > 0 and target and "health_component" in target:
		var base_damage = context.get("base_damage", 0)
		var proc_damage = base_damage * (proc.damage_percent / 100.0)
		target.health_component.take_damage(proc_damage, owner, true)
		##print("Proc dealt %d damage" % proc_damage)
	
	# Execute ability if specified
	if proc.execute_ability:
		use_ability(proc.execute_ability.ability_id)
	
	# Apply buff if specified
	if proc.apply_buff:
		var buff_component = target.get_node_or_null("Buff")
		if buff_component:
			buff_component.apply_buff(proc.apply_buff.buff_id, owner)
	
	# Play animation
	if proc.animation_name and owner.has_method("play_animation"):
		owner.play_animation(proc.animation_name)
	
	# Play sound
	if proc.sfx_path:
		AudioManager.play_sfx_for_map(MapManager.get_player_map(owner.player_id), proc.sfx_path, owner.global_position)
	
	# Custom logic
	if proc.logic_script:
		var script_instance = proc.logic_script.new()
		if script_instance.has_method("on_proc"):
			script_instance.on_proc(owner, target, context)

#endregion


#region #################### Multiplayer & RPCs ####################
func spawn_projectile(ability: AbilityData, level_stats: AbilityLevelData, target: Node2D):
	if not multiplayer.is_server():
		return

	var active_behavior = ability.active_behavior
	if not active_behavior.projectile_scene:
		printerr("Projectile scene not set for ability: %s" % ability.ability_name)
		return

	# Target can be null. If it is, we fire straight.
	var initial_direction: Vector2
	if is_instance_valid(target):
		var target_position = target.global_position
		if target.has_node("aim_target"):
			target_position = target.get_node("aim_target").global_position
		initial_direction = (target_position - owner.global_position).normalized()
	else:
		# No target, fire straight ahead based on player's facing direction.
		initial_direction = Vector2(owner.facing_direction, 0).normalized()

	var projectile_instance = active_behavior.projectile_scene.instantiate()
	var proj_name := "Proj_%d_%d" % [Time.get_ticks_msec(), randi()]
	projectile_instance.name = proj_name

	# The projectile will now store the ability data and call back to the CombatComponent to process the hit.
	projectile_instance.initialize(owner, target, ability, level_stats, active_behavior.projectile_speed, initial_direction)
	
	# Find the correct container based on the player's current map
	# Player structure: Map -> Players -> Player -> AbilityComponent
	# So owner (Player) -> parent (Players) -> parent (Map)
	var current_map = owner.get_parent().get_parent()
	var target_container = _projectiles_container # Default fallback
	
	if current_map and current_map.is_in_group("map_base"):
		var map_container = current_map.get_node_or_null("Projectiles")
		if map_container:
			target_container = map_container
		else:
			# Create if missing on this map
			var new_container = Node.new()
			new_container.name = "Projectiles"
			current_map.add_child(new_container)
			target_container = new_container
			#print("Created missing Projectiles container on map: %s" % current_map.name)
	
	if not is_instance_valid(target_container):
		printerr("Could not find valid Projectiles container for ability: %s" % ability.ability_name)
		return

	# Add projectile to scene tree first, then set global position
	target_container.add_child(projectile_instance, true)
	
	var spawn_pos = owner.global_position
	if is_instance_valid(owner.projectile_spawn_location):
		spawn_pos = owner.projectile_spawn_location.global_position
	else:
		printerr("Projectile spawn location not set on player controller. Spawning at player position.")
	
	projectile_instance.global_position = spawn_pos
	
	# Replicate the visual to same-map clients. Routed through MapManager (an
	# autoload that always resolves on every peer) so it works for bot casters
	# too. Clients simulate the projectile locally; the server is authoritative
	# for hit detection.
	var target_path = NodePath("")
	if is_instance_valid(target):
		target_path = target.get_path()

	if current_map and current_map.is_in_group("map_base"):
		var map_name = current_map.name.replace("Map_", "")
		var scene_path: String = active_behavior.projectile_scene.resource_path
		for peer_id in MapManager.get_real_players_on_map(map_name):
			if peer_id != 1: # Server already has it
				MapManager.spawn_projectile_visual.rpc_id(peer_id, proj_name, scene_path, spawn_pos, initial_direction, active_behavior.projectile_speed, target_path)


## [Client] Plays an ability's cast visual without the cooldown/UI bookkeeping
## that ability_used_client does. Used for bot casts, which are routed through
## MapManager (the bot's AbilityComponent node may be missing on this client).
func play_ability_visual(ability_id: String, level: int) -> void:
	if multiplayer.is_server():
		return
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability:
		return
	var level_stats = ability.get_level_stats(level)
	if level_stats:
		_trigger_ability_state_change(ability, level_stats)


## [Server->Client] Sends all ability data to a newly connected client in a single RPC.
func sync_all_abilities_to_client(peer_id: int) -> void:
	if not multiplayer.is_server(): return

	#print("Syncing all ability data to peer %d" % peer_id)
	# PR 3: snapshot the live hotbar back to whichever binding side is active
	# before sending so the dirty in-memory state lines up with the persisted
	# pair. The client receives both arrays + the active flag (via the
	# equipment sync RPC), so it can re-hydrate and swap freely.
	var live_config: Dictionary = hotbar.save_hotbar_config() if is_instance_valid(hotbar) else {}
	_capture_active_bindings(live_config)
	sync_all_abilities_batch.rpc_id(
		peer_id,
		_ability_levels.duplicate(),
		_available_points_per_discipline.duplicate(),
		live_config,
		_cooldowns.duplicate(),
		_primary_hotbar_bindings.duplicate(),
		_secondary_hotbar_bindings.duplicate()
	)
	# PR 6: send purchased upgrades in the same join handshake so the
	# AbilityWindow renders correct state immediately on connect.
	sync_learned_upgrades.rpc_id(peer_id, _learned_upgrades.duplicate(true))


@rpc("authority", "call_local", "reliable")
## PR 4: `ability_points` is now a per-discipline Dictionary, not an int.
## Older clients that still send an int will be normalized via the
## migration helper so the round-trip stays safe through the rollout.
func sync_all_abilities_batch(
		abilities: Dictionary,
		ability_points,
		hotbar_config: Dictionary = {},
		cooldowns: Dictionary = {},
		primary_bindings: Dictionary = {},
		secondary_bindings: Dictionary = {}
		) -> void:
	if multiplayer.is_server(): return

	for ability_id in abilities:
		_ability_levels[ability_id] = abilities[ability_id]
		ability_learned.emit(ability_id)
	_apply_per_discipline_payload(ability_points)
	for key in DISCIPLINE_KEYS:
		ability_points_changed.emit(key, int(_available_points_per_discipline.get(key, 0)))

	# PR 3: restore both binding arrays so the inactive weapon's bindings
	# survive client-side swaps until the next save round-trip.
	_primary_hotbar_bindings = primary_bindings.duplicate()
	_secondary_hotbar_bindings = secondary_bindings.duplicate()

	if is_instance_valid(hotbar):
		hotbar.load_hotbar_config(hotbar_config)

	for ability_id in cooldowns:
		var remaining: float = cooldowns[ability_id]
		if remaining > 0.0:
			_cooldowns[ability_id] = remaining
			cooldown_started.emit(ability_id, remaining)


## [Client->Server] Client-side wrapper to request ability use from the server.
func _request_ability_use(ability_id: String) -> void:
	#print("Client: Sending request to use ability %s" % ability_id)
	use_ability_server.rpc_id(1, ability_id) # Server is always peer ID 1


func _is_ability_rpc_rate_limited() -> bool:
	var now = Time.get_ticks_msec() / 1000.0
	while _ability_request_times.size() > 0 and now - _ability_request_times[0] > 1.0:
		_ability_request_times.pop_front()
	if _ability_request_times.size() >= MAX_ABILITY_REQUESTS_PER_SECOND:
		return true
	_ability_request_times.append(now)
	return false


@rpc("any_peer", "call_local", "reliable")
## [Client->Server] RPC for a client to request using an ability.
func use_ability_server(ability_id: String) -> void:
	if not multiplayer.is_server(): return

	if _is_ability_rpc_rate_limited():
		return

	var validation = _validate_ability_use(ability_id)
	if not validation.valid:
		return
	
	# Let the authoritative function handle the final execution
	_handle_authoritative_use(ability_id, validation.ability, validation.level_stats)


@rpc("authority", "call_local", "reliable")
## [Server->Client] Notifies all clients that an ability was used successfully.
func ability_used_client(ability_id: String, cooldown_time: float) -> void:
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability: return
	
	# Set cooldown locally for all instances (server and clients)
	_cooldowns[ability_id] = cooldown_time
	
	# Emit signals for UI and other systems
	ability_used.emit(ability_id)
	cooldown_started.emit(ability_id, cooldown_time)
	
	# On clients, we must also trigger the visual part of the ability
	if not multiplayer.is_server():
		var level = get_ability_level(ability_id)
		var level_stats = ability.get_level_stats(level)
		if level_stats:
			_trigger_ability_state_change(ability, level_stats)
	
	#print("Synchronized ability use for %s." % ability_id)


@rpc("any_peer", "call_local", "reliable")
## [Client->Server] RPC for a client to request leveling up an ability.
func level_up_ability_request(ability_id: String) -> void:
	if multiplayer.is_server():
		_level_up_ability_local(ability_id)


@rpc("any_peer", "call_local", "reliable")
## [Client->Server] RPC for a client to request learning an ability.
func learn_ability_request(ability_id: String, initial_level: int) -> void:
	if multiplayer.is_server():
		_learn_ability_local(ability_id, initial_level)


@rpc("authority", "call_local", "reliable")
## [Server->Client] Syncs a single ability's level to all clients.
func sync_ability_level(ability_id: String, new_level: int) -> void:
	_ability_levels[ability_id] = new_level
	ability_leveled_up.emit(ability_id, new_level)
	#print("Synced ability level: %s to %d" % [ability_id, new_level])


@rpc("authority", "call_local", "reliable")
## [Server->Client] Syncs a newly learned ability to all clients.
func sync_ability_learned(ability_id: String, initial_level: int) -> void:
	_ability_levels[ability_id] = initial_level
	ability_learned.emit(ability_id)


@rpc("authority", "reliable")
## [Server->Client] PR 4: syncs the per-weapon-discipline ability point pools
## to all clients. Replaces the legacy `sync_ability_points` int RPC.
func sync_ability_points_per_discipline(new_pools) -> void:
	# This RPC should only be processed by clients, not the server that sent it.
	if multiplayer.is_server(): return

	_apply_per_discipline_payload(new_pools)
	for key in DISCIPLINE_KEYS:
		ability_points_changed.emit(key, int(_available_points_per_discipline.get(key, 0)))
#endregion


#region #################### Signal Callbacks ####################
## PR 4 fix (2026-05-27): replaced the level-up grant. Called when
## WeaponMasteryComponent emits `mastery_level_changed(discipline_int, new_level)`.
## Each mastery level grants ABILITY_POINTS_PER_MASTERY_LEVEL points to THAT
## discipline's pool — and ONLY that discipline's. Trees you don't use grant
## you nothing; trees you main accumulate points as your mastery climbs.
func _on_mastery_level_up(discipline: int, _new_level: int) -> void:
	var key: String = _class_type_to_discipline_key(discipline)
	if key == "":
		push_warning("AbilityComponent: mastery_level_changed for discipline %d with no key mapping" % discipline)
		return
	#print("Mastery up: %s -> level %d. +%d ability points to %s pool." % [key, _new_level, ABILITY_POINTS_PER_MASTERY_LEVEL, key])
	_add_ability_points(ABILITY_POINTS_PER_MASTERY_LEVEL, key)


func _on_class_changed(_new_class_name: String) -> void:
	# On initial character creation the component pre-loaded the default
	# class's abilities in _ready() (including its starter at level 1)
	# before the real class was assigned, so anything not in the new class
	# must be dropped — including a stale level-1 starter from the default
	# class. Job advancement stays safe because the advanced class's skill
	# list is a superset of the base class's, so any leveled ability is
	# present in new_class_ids and survives.
	#
	# PR 4 fix (2026-05-28): "valid" abilities span ALL FOUR tier-1
	# disciplines now, not just the new class's skills. Without this, the
	# all-disciplines-starter init in _ready was getting wiped here — class
	# change from default → BOW would prune Sword/Staff/Dagger starters
	# because they weren't in Bow's skills list. With the broadened set,
	# only stale non-tier-1 abilities (e.g. from a default BEGINNER class)
	# get pruned, while cross-discipline starters persist.
	#
	# RPCs are not broadcast here because the class change itself is synced,
	# so clients run this same logic locally.
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		var new_class_ids: Dictionary = {}
		# Include the current class's abilities (covers tier-2 advancements
		# whose superset includes their tier-1 parent's tree).
		for ability_data in _class_component.get_class_abilities():
			if ability_data:
				new_class_ids[ability_data.ability_id] = true
		# Also include every tier-1 discipline's abilities so cross-discipline
		# starters aren't pruned.
		for tier1_disc in [
			Constants.ClassType.SWORD,
			Constants.ClassType.BOW,
			Constants.ClassType.STAFF,
			Constants.ClassType.DAGGER,
		]:
			var disc_data: WeaponDisciplineData = ResourceManager.get_class_data(tier1_disc)
			if disc_data == null:
				continue
			for ability_data in disc_data.skills:
				if ability_data:
					new_class_ids[ability_data.ability_id] = true

		for ability_id in _ability_levels.keys():
			if not new_class_ids.has(ability_id):
				_ability_levels.erase(ability_id)

		# Re-seed each tier-1 discipline's starter ability at level 1 if it's
		# missing from _ability_levels (defensive — the init in _ready does
		# this, but the prune above could have removed it in edge cases).
		# Other abilities get added at level 0 so they show in the UI.
		for tier1_disc in [
			Constants.ClassType.SWORD,
			Constants.ClassType.BOW,
			Constants.ClassType.STAFF,
			Constants.ClassType.DAGGER,
		]:
			var disc_data: WeaponDisciplineData = ResourceManager.get_class_data(tier1_disc)
			if disc_data == null:
				continue
			var disc_starter: AbilityData = disc_data.starter_ability
			for ability_data in disc_data.skills:
				if ability_data == null or _ability_levels.has(ability_data.ability_id):
					continue
				var initial_level: int = 1 if (disc_starter and ability_data == disc_starter) else 0
				_learn_ability_local(ability_data.ability_id, initial_level, false)

		# Re-seed the current class's starter too (covers tier-2 advancement
		# starter abilities that aren't in any tier-1 tree).
		var starter: AbilityData = _class_component.get_starter_ability()
		for ability_data in _class_component.get_class_abilities():
			if ability_data and not _ability_levels.has(ability_data.ability_id):
				var initial_level: int = 1 if (starter and ability_data == starter) else 0
				_learn_ability_local(ability_data.ability_id, initial_level, false)

#endregion


#region #################### Save & Load System ####################
## Returns a dictionary of all ability data for saving. PR 3 saves both
## binding arrays — the live hotbar reflects whichever weapon is currently
## active, so before serializing we snapshot it into the matching slot.
func save_abilities() -> Dictionary:
	# `hotbar` is a UI node; a bot frees its UI subtree, so guard the access.
	var live_config: Dictionary = hotbar.save_hotbar_config() if is_instance_valid(hotbar) else {}
	# Sync the live binding back into the per-weapon dict so the save reflects
	# any edits the player made since the last swap.
	_capture_active_bindings(live_config)
	# PR 4: defensively normalize int values (in case a level-up's max(0, ...)
	# or similar accidentally stored a float). Sum the pools for the legacy
	# fallback column on the backend.
	var per_disc_copy: Dictionary = {}
	var legacy_total: int = 0
	for key in _available_points_per_discipline:
		var v: int = int(_available_points_per_discipline[key])
		per_disc_copy[key] = v
		legacy_total += v
	return {
		"ability_levels": _ability_levels.duplicate(),
		# PR 6: purchased per-ability upgrades. Deep-duplicated so the nested
		# arrays don't alias the live state. Backend persistence lands with
		# the learned_ability_upgrades column (A3); in local-save mode this
		# round-trips through the JSON immediately.
		"learned_ability_upgrades": _learned_upgrades.duplicate(true),  # PR6

		# PR 4: legacy fallback (sum of per-discipline pools). Kept populated
		# for one release so the backend's legacy `ability_points` column
		# stays useful if the new JSONB column is somehow missing.
		"available_points": legacy_total,
		"available_points_per_discipline": per_disc_copy,
		# Legacy compatibility: keep `hotbar_config` writing the active set so
		# older clients / tools that read it still see a coherent layout.
		"hotbar_config": live_config,
		"primary_hotbar_bindings": _primary_hotbar_bindings.duplicate(),
		"secondary_hotbar_bindings": _secondary_hotbar_bindings.duplicate(),
		"cooldowns": _cooldowns.duplicate()
	}


## Loads and applies ability data from a dictionary.
func load_abilities(data: Dictionary) -> void:
	if data.is_empty(): return

	# First, ensure all current class abilities are initialized
	for ability_data in _class_component.get_class_abilities():
		if ability_data != null and not _ability_levels.has(ability_data.ability_id):
			_ability_levels[ability_data.ability_id] = 0
			#print("Added new ability from class: %s at level 0" % ability_data.ability_id)

	# Load saved data by merging (not replacing) to preserve new abilities
	var saved_levels = data.get("ability_levels", {})
	for ability_id in saved_levels:
		_ability_levels[ability_id] = saved_levels[ability_id]

	# PR 6 balance pass: if a balance change LOWERED an ability's max_level
	# (e.g. Vow of the Vanguard 30 -> 20), clamp any saved level that now
	# exceeds the cap. reconcile_ability_points() (called at the end of this
	# function) then refunds the freed points back into the discipline pool.
	for ability_id in _ability_levels:
		var capped_ability: AbilityData = ResourceManager.get_ability_data(ability_id)
		if capped_ability and int(_ability_levels[ability_id]) > capped_ability.max_level:
			_ability_levels[ability_id] = capped_ability.max_level

	# PR 6: restore purchased upgrades — but ONLY when the key is present.
	# A load payload missing the key (a stale backend reload, an older save,
	# or the backend before its column exists) must NOT wipe upgrades that a
	# prior load already restored. Absent key => leave _learned_upgrades as-is.
	if data.has("learned_ability_upgrades"):
		var saved_upgrades = data.get("learned_ability_upgrades", {})
		if saved_upgrades is Dictionary:
			_learned_upgrades = (saved_upgrades as Dictionary).duplicate(true)

	# PR 4: per-discipline pool migration. Defers to a helper so the priority
	# order (new dict > legacy int > zeros) is documented in one place.
	_load_ability_points_with_migration(data)

	# PR 3: restore both binding arrays. Legacy saves that only have
	# `hotbar_config` populate the primary binding so a returning character
	# keeps their layout (the secondary starts empty until they bind it).
	var legacy_config: Dictionary = data.get("hotbar_config", {})
	_primary_hotbar_bindings = data.get("primary_hotbar_bindings", legacy_config).duplicate()
	_secondary_hotbar_bindings = data.get("secondary_hotbar_bindings", {}).duplicate()

	# Push the ACTIVE binding into the live hotbar. The equipment component's
	# load step (run separately by the player root) will tell us which one
	# that is — until then we assume primary, which matches a fresh-character
	# default and a legacy save's only binding.
	var active_bindings: Dictionary = _active_bindings_for_load()
	if is_instance_valid(hotbar):
		hotbar.load_hotbar_config(active_bindings)

	var saved_cooldowns: Dictionary = data.get("cooldowns", {})
	for ability_id in saved_cooldowns:
		var remaining: float = saved_cooldowns[ability_id]
		if remaining > 0.0:
			_cooldowns[ability_id] = remaining
			cooldown_started.emit(ability_id, remaining)

	# PR 6 safety net: verify the per-discipline pools match mastery level
	# (granted = mastery_level * 3 = spent + unused) and correct any drift from
	# a stale save / missed sync / legacy backend column. do_sync=false while
	# loading — the post-load sync_all_abilities_to_client broadcasts the
	# corrected pools to the owning client (player_manager._on_player_spawned).
	reconcile_ability_points(not _loading_mode)

	# Re-apply passives and update UI with loaded data
	_apply_passive_effects()
	if not _loading_mode:
		# PR 4: fire one signal per discipline so the AbilityWindow's per-tab
		# labels refresh.
		for key in DISCIPLINE_KEYS:
			ability_points_changed.emit(key, int(_available_points_per_discipline.get(key, 0)))
		for ability_id in _ability_levels:
			var level = _ability_levels[ability_id]
			if level > 0:
				ability_learned.emit(ability_id)
				ability_leveled_up.emit(ability_id, level)
			#print("Loaded ability: %s at level %d" % [ability_id, level])
	#else:
		#for ability_id in _ability_levels:
			#print("Loaded ability: %s at level %d" % [ability_id, _ability_levels[ability_id]])


## PR 3 helper. Picks the currently-active weapon's binding dict for a load.
## Used by load_abilities and by _on_active_weapon_changed to know which set
## to push into the live hotbar.
func _active_bindings_for_load() -> Dictionary:
	if _equipment_component and _equipment_component.active_weapon == EquipmentComponent.ACTIVE_SECONDARY:
		return _secondary_hotbar_bindings
	return _primary_hotbar_bindings


## PR 3 helper. Captures the live hotbar config back into whichever binding
## array is currently active. Called before saving (so any edits made since
## the last swap land in the save) and on a swap (snapshot the leaving
## weapon's layout).
func _capture_active_bindings(live_config: Dictionary) -> void:
	if not _equipment_component:
		_primary_hotbar_bindings = live_config.duplicate()
		return
	if _equipment_component.active_weapon == EquipmentComponent.ACTIVE_SECONDARY:
		_secondary_hotbar_bindings = live_config.duplicate()
	else:
		_primary_hotbar_bindings = live_config.duplicate()


## PR 3 signal handler. Snapshot the leaving weapon's bindings, then push the
## new weapon's bindings into the live hotbar. The hotbar UI re-renders.
## Runs on both server and client (signal connection in `_ready`), so the host
## and remote clients both refresh in lockstep with the authoritative swap.
func _on_active_weapon_changed(_active_weapon: String, _active_item: ItemData) -> void:
	# Capture the *outgoing* binding (whatever the live hotbar shows right now,
	# which still reflects the *previous* active weapon at the moment this
	# signal fires — EquipmentComponent emits AFTER it flipped active_weapon,
	# so we have to look at the OPPOSITE side from the current active flag).
	if not is_instance_valid(hotbar):
		return

	var live_config: Dictionary = hotbar.save_hotbar_config()
	# `_equipment_component.active_weapon` has already flipped to the NEW
	# active value, so capture the live config into the OTHER slot.
	if _equipment_component and _equipment_component.active_weapon == EquipmentComponent.ACTIVE_SECONDARY:
		# Just flipped to secondary — the live config still shows primary.
		_primary_hotbar_bindings = live_config.duplicate()
	else:
		# Just flipped to primary — the live config still shows secondary.
		_secondary_hotbar_bindings = live_config.duplicate()

	# Push the new active set into the live hotbar.
	hotbar.load_hotbar_config(_active_bindings_for_load())

	# Visual ping: flash the hotbar to draw the eye to the changed bindings.
	if hotbar.has_method("flash_swap_indicator"):
		hotbar.flash_swap_indicator()
			
## Disconnects from mastery component signals to prevent side effects during loading.
## (PR 4 fix 2026-05-27: was disconnecting LevelingComponent.leveled_up before
## the point-grant rule changed; the leveled_up hook is no longer used.)
func disconnect_level_signals() -> void:
	if _weapon_mastery_component and _weapon_mastery_component.mastery_level_changed.is_connected(_on_mastery_level_up):
		_weapon_mastery_component.mastery_level_changed.disconnect(_on_mastery_level_up)
		#print("AbilityComponent: Disconnected from mastery signals for loading.")


## Reconnects to mastery component signals after loading is complete.
func reconnect_level_signals() -> void:
	if _weapon_mastery_component and not _weapon_mastery_component.mastery_level_changed.is_connected(_on_mastery_level_up):
		_weapon_mastery_component.mastery_level_changed.connect(_on_mastery_level_up)
		#print("AbilityComponent: Reconnected to mastery signals.")


func set_loading_mode(enabled: bool) -> void:
	_loading_mode = enabled
#endregion


#region #################### Getters & Validation ####################
func get_ability_level(ability_id: String) -> int:
	return _ability_levels.get(ability_id, 0)


## PR 4: returns the sum of all per-discipline pools. Preserved for bot
## auto-spend logic and any caller that just needs "do I have any points at
## all?". UI consumers should prefer `get_available_points_for_discipline`.
func get_available_ability_points() -> int:
	var total: int = 0
	for key in _available_points_per_discipline:
		total += int(_available_points_per_discipline.get(key, 0))
	return total


## PR 4: returns the available points in a specific discipline pool.
## `discipline_key` is one of "sword" / "bow" / "staff" / "dagger".
## Returns 0 for unknown keys.
func get_available_points_for_discipline(discipline_key: String) -> int:
	return int(_available_points_per_discipline.get(discipline_key, 0))


## PR 4: returns a copy of the full per-discipline pool dictionary. UI uses
## this to render the tab header counts.
func get_available_points_per_discipline() -> Dictionary:
	return _available_points_per_discipline.duplicate()


#region #################### PR 6: Ability upgrades ####################

## True if the given upgrade has been purchased for this ability.
func has_upgrade(ability_id: String, upgrade_id: String) -> bool:
	var owned: Array = _learned_upgrades.get(ability_id, [])
	return owned.has(upgrade_id)


## Returns a copy of the purchased upgrade ids for an ability (never null).
func get_learned_upgrades(ability_id: String) -> Array:
	return (_learned_upgrades.get(ability_id, []) as Array).duplicate()


## True if ANY owned upgrade on this ability carries the given effect_key.
## AL_*.gd scripts use this for boolean effects (bleed-on-hit, knockdown, ...).
func ability_has_upgrade_effect(ability_id: String, effect_key: String) -> bool:
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if ability == null:
		return false
	for owned_id in _learned_upgrades.get(ability_id, []):
		var up: AbilityUpgradeData = _find_upgrade(ability, owned_id)
		if up != null and up.effect_key == effect_key:
			return true
	return false


## Sums the `magnitude` of owned upgrades on THIS ability with the given
## effect_key. Used for ability-scoped numeric effects (combo coefficient
## override, bleed duration, ...). Returns 0.0 if none.
func get_ability_upgrade_magnitude(ability_id: String, effect_key: String) -> float:
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if ability == null:
		return 0.0
	var total: float = 0.0
	for owned_id in _learned_upgrades.get(ability_id, []):
		var up: AbilityUpgradeData = _find_upgrade(ability, owned_id)
		if up != null and up.effect_key == effect_key:
			total += up.magnitude
	return total


## Sums the `magnitude` of owned upgrades across ALL abilities with the given
## effect_key. Used for player-wide effects whose source ability shouldn't
## matter to the consumer (e.g. SwordComboComponent's combo-cap bonus —
## "combo_cap_bonus" — so the combo component never needs to know which
## ability's upgrade granted it).
func get_total_upgrade_magnitude(effect_key: String) -> float:
	var total: float = 0.0
	for ability_id in _learned_upgrades:
		total += get_ability_upgrade_magnitude(ability_id, effect_key)
	return total


## Finds an AbilityUpgradeData by id within an ability's upgrade list.
func _find_upgrade(ability: AbilityData, upgrade_id: String) -> AbilityUpgradeData:
	if ability == null or ability.upgrades == null:
		return null
	for up in ability.upgrades:
		if up != null and up.upgrade_id == upgrade_id:
			return up
	return null


## Validates whether an upgrade can be purchased. Returns { ok: bool,
## reason: String }. reason is "" when ok. Pure (no mutation) so the UI can
## call it to grey out / explain locked upgrades.
func can_purchase_upgrade(ability_id: String, upgrade_id: String) -> Dictionary:
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if ability == null:
		return { "ok": false, "reason": "unknown_upgrade" }

	# Upgrades are post-MAX build customization, not a parallel track: the
	# ability must be at max level before any of its upgrades can be bought.
	# (level 0 = unlearned reports separately for clearer UI messaging.)
	var ability_level: int = int(_ability_levels.get(ability_id, 0))
	if ability_level <= 0:
		return { "ok": false, "reason": "not_learned" }
	if ability_level < ability.max_level:
		return { "ok": false, "reason": "not_maxed" }

	var upgrade: AbilityUpgradeData = _find_upgrade(ability, upgrade_id)
	if upgrade == null:
		return { "ok": false, "reason": "unknown_upgrade" }

	if has_upgrade(ability_id, upgrade_id):
		return { "ok": false, "reason": "already_owned" }

	# Tier gating: a tier-N upgrade needs at least one tier-(N-1) upgrade owned
	# on the same ability. Tier 1 has no prerequisite.
	if upgrade.tier > 1 and not _has_owned_upgrade_at_tier(ability, ability_id, upgrade.tier - 1):
		return { "ok": false, "reason": "tier_locked" }

	# Variant mutex: only one upgrade per variant_group may be owned.
	if not upgrade.variant_group.is_empty() and _owns_variant_in_group(ability, ability_id, upgrade.variant_group):
		return { "ok": false, "reason": "variant_taken" }

	# Point pool: drawn from the ability's discipline pool.
	var disc_key: String = _ability_primary_discipline(ability)
	if disc_key == "":
		return { "ok": false, "reason": "no_points" }
	if int(_available_points_per_discipline.get(disc_key, 0)) < upgrade.point_cost:
		return { "ok": false, "reason": "no_points" }

	return { "ok": true, "reason": "" }


## True if any owned upgrade on this ability sits at the given tier.
func _has_owned_upgrade_at_tier(ability: AbilityData, ability_id: String, tier: int) -> bool:
	var owned: Array = _learned_upgrades.get(ability_id, [])
	for owned_id in owned:
		var up: AbilityUpgradeData = _find_upgrade(ability, owned_id)
		if up != null and up.tier == tier:
			return true
	return false


## True if any owned upgrade on this ability shares the given variant_group.
func _owns_variant_in_group(ability: AbilityData, ability_id: String, group: String) -> bool:
	var owned: Array = _learned_upgrades.get(ability_id, [])
	for owned_id in owned:
		var up: AbilityUpgradeData = _find_upgrade(ability, owned_id)
		if up != null and up.variant_group == group:
			return true
	return false


## Public entry — client routes to the server via RPC; server applies locally.
func purchase_upgrade(ability_id: String, upgrade_id: String) -> bool:
	if _is_multiplayer_client():
		purchase_upgrade_request.rpc_id(1, ability_id, upgrade_id)
		return true
	return _purchase_upgrade_local(ability_id, upgrade_id)


## Server-authoritative purchase. Validates, deducts points, records the
## upgrade, re-applies passive effects (an upgrade may change a passive's
## contribution), and syncs to the owning client.
func _purchase_upgrade_local(ability_id: String, upgrade_id: String) -> bool:
	var check: Dictionary = can_purchase_upgrade(ability_id, upgrade_id)
	if not check.ok:
		ability_upgrade_denied.emit(ability_id, upgrade_id, String(check.reason))
		return false

	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	var upgrade: AbilityUpgradeData = _find_upgrade(ability, upgrade_id)
	var disc_key: String = _ability_primary_discipline(ability)

	# Deduct points.
	_available_points_per_discipline[disc_key] = max(0, int(_available_points_per_discipline.get(disc_key, 0)) - upgrade.point_cost)

	# Record the purchase.
	if not _learned_upgrades.has(ability_id):
		_learned_upgrades[ability_id] = []
	_learned_upgrades[ability_id].append(upgrade_id)

	# A purchased upgrade may alter a passive's stat contribution — recalc.
	if ability.ability_type == Constants.AbilityType.PASSIVE:
		_apply_passive_effects()

	ability_upgrade_purchased.emit(ability_id, upgrade_id)
	ability_points_changed.emit(disc_key, int(_available_points_per_discipline.get(disc_key, 0)))

	# Sync to clients (skip for bots — no client UI).
	if multiplayer.has_multiplayer_peer() and not BotManager.is_bot(owner.player_id):
		sync_ability_points_per_discipline.rpc(_available_points_per_discipline.duplicate())
		sync_learned_upgrades.rpc(_learned_upgrades.duplicate(true))

	return true


@rpc("any_peer", "call_local", "reliable")
func purchase_upgrade_request(ability_id: String, upgrade_id: String) -> void:
	if not multiplayer.is_server():
		return
	# Only the owning peer may spend this character's points.
	if multiplayer.get_remote_sender_id() != owner.player_id:
		return
	_purchase_upgrade_local(ability_id, upgrade_id)


## Server -> owning client. Mirrors the full learned-upgrades map so the
## client's AbilityWindow renders purchased state. Deep-duplicated on send so
## the nested arrays survive the RPC intact.
@rpc("authority", "call_remote", "reliable")
func sync_learned_upgrades(upgrades: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_learned_upgrades = upgrades.duplicate(true)
	# Refresh any UI listening; passive contributions are server-side, so the
	# client just needs the display state.
	for ability_id in _learned_upgrades:
		for upgrade_id in _learned_upgrades[ability_id]:
			ability_upgrade_purchased.emit(ability_id, upgrade_id)

#endregion


#region #################### PR 6: Respec ####################

## Refunds every point spent in a discipline (ability levels above the free
## starter baseline + all purchased upgrade costs), resets those abilities
## and upgrades, and returns the points to that discipline's pool. Free —
## matches Diablo 4 LoH / Last Epoch; a gold cost can layer on later.
##
## The discipline's starter ability keeps its free level-1 (it was granted at
## character creation without spending a point), so respec never over-credits
## it. Non-starter abilities reset to level 0 (unlearned).
func respec_discipline(disc_key: String) -> bool:
	if _is_multiplayer_client():
		respec_discipline_request.rpc_id(1, disc_key)
		return true
	return _respec_discipline_local(disc_key)


func _respec_discipline_local(disc_key: String) -> bool:
	if not _available_points_per_discipline.has(disc_key):
		return false
	var starter_id: String = _discipline_starter_ability_id(disc_key)
	var reset_ids: Array[String] = []
	var refund: int = 0
	for ability_id in _ability_levels.keys():
		var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
		if ability == null or _ability_primary_discipline(ability) != disc_key:
			continue
		refund += _refund_ability(ability_id, starter_id, reset_ids)
	_available_points_per_discipline[disc_key] = int(_available_points_per_discipline.get(disc_key, 0)) + refund
	_finalize_respec([disc_key], reset_ids)
	return true


@rpc("any_peer", "call_local", "reliable")
func respec_discipline_request(disc_key: String) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner.player_id:
		return
	_respec_discipline_local(disc_key)


## Per-ability respec — refunds ONE ability's levels (above the free starter
## baseline) + its purchased upgrade costs, resets it, returns the points.
func respec_ability(ability_id: String) -> bool:
	if _is_multiplayer_client():
		respec_ability_request.rpc_id(1, ability_id)
		return true
	return _respec_ability_local(ability_id)


func _respec_ability_local(ability_id: String) -> bool:
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if ability == null:
		return false
	var disc_key: String = _ability_primary_discipline(ability)
	if disc_key == "" or not _available_points_per_discipline.has(disc_key):
		return false
	var starter_id: String = _discipline_starter_ability_id(disc_key)
	var reset_ids: Array[String] = []
	var refund: int = _refund_ability(ability_id, starter_id, reset_ids)
	_available_points_per_discipline[disc_key] = int(_available_points_per_discipline.get(disc_key, 0)) + refund
	_finalize_respec([disc_key], reset_ids)
	return true


@rpc("any_peer", "call_local", "reliable")
func respec_ability_request(ability_id: String) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner.player_id:
		return
	_respec_ability_local(ability_id)


## Respecs all four tier-1 disciplines at once (quick full reset).
func respec_all() -> bool:
	if _is_multiplayer_client():
		respec_all_request.rpc_id(1)
		return true
	return _respec_all_local()


func _respec_all_local() -> bool:
	var reset_ids: Array[String] = []
	var refund_by_disc: Dictionary = {}
	for ability_id in _ability_levels.keys():
		var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
		if ability == null:
			continue
		var disc_key: String = _ability_primary_discipline(ability)
		if disc_key == "":
			continue
		var starter_id: String = _discipline_starter_ability_id(disc_key)
		refund_by_disc[disc_key] = int(refund_by_disc.get(disc_key, 0)) + _refund_ability(ability_id, starter_id, reset_ids)
	for disc_key in refund_by_disc:
		_available_points_per_discipline[disc_key] = int(_available_points_per_discipline.get(disc_key, 0)) + int(refund_by_disc[disc_key])
	_finalize_respec(DISCIPLINE_KEYS, reset_ids)
	return true


@rpc("any_peer", "call_local", "reliable")
func respec_all_request() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner.player_id:
		return
	_respec_all_local()


## Refund + reset ONE ability: points for levels above the free starter
## baseline + all owned upgrade costs. Mutates _ability_levels /
## _learned_upgrades, appends to reset_ids if the level changed. Returns the
## refund. No emit/sync — callers batch that via _finalize_respec.
func _refund_ability(ability_id: String, starter_id: String, reset_ids: Array) -> int:
	var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
	if ability == null:
		return 0
	var baseline: int = 1 if ability_id == starter_id else 0
	var current_level: int = int(_ability_levels.get(ability_id, 0))
	var refund: int = maxi(0, current_level - baseline)
	for owned_id in _learned_upgrades.get(ability_id, []):
		var up: AbilityUpgradeData = _find_upgrade(ability, owned_id)
		if up != null:
			refund += up.point_cost
	if current_level != baseline:
		_ability_levels[ability_id] = baseline
		reset_ids.append(ability_id)
	_learned_upgrades.erase(ability_id)
	return refund


## Post-respec: recompute passives, emit per-discipline + per-ability signals,
## and sync to the owning client.
func _finalize_respec(disc_keys: Array, reset_ids: Array) -> void:
	_apply_passive_effects()
	for key in disc_keys:
		ability_points_changed.emit(key, int(_available_points_per_discipline.get(key, 0)))
	for ability_id in reset_ids:
		ability_leveled_up.emit(ability_id, int(_ability_levels.get(ability_id, 0)))
	if multiplayer.has_multiplayer_peer() and not BotManager.is_bot(owner.player_id):
		for ability_id in reset_ids:
			sync_ability_level.rpc(ability_id, int(_ability_levels.get(ability_id, 0)))
		sync_ability_points_per_discipline.rpc(_available_points_per_discipline.duplicate())
		sync_learned_upgrades.rpc(_learned_upgrades.duplicate(true))


## Maps a discipline key to its starter ability's id (the one auto-leveled to
## 1 at character creation), via the WeaponDisciplineData. "" if unknown.
func _discipline_starter_ability_id(disc_key: String) -> String:
	var class_type: int = -1
	match disc_key:
		"sword": class_type = Constants.ClassType.SWORD
		"bow": class_type = Constants.ClassType.BOW
		"staff": class_type = Constants.ClassType.STAFF
		"dagger": class_type = Constants.ClassType.DAGGER
	if class_type == -1:
		return ""
	var disc_data = ResourceManager.get_class_data(class_type)
	if disc_data and disc_data.starter_ability:
		return disc_data.starter_ability.ability_id
	return ""


## Safety net (PR 6): recompute each discipline's UNUSED point pool from first
## principles and correct any drift. The invariant the player should never see
## violated: a discipline's GRANTED points == mastery_level *
## ABILITY_POINTS_PER_MASTERY_LEVEL, and granted == SPENT (levels above the
## free starter baseline + owned-upgrade costs) + UNUSED. If a save round-trip,
## a missed sync, or a stale/legacy backend column ever desyncs the unused
## pool, this restores it — adding points that went missing or removing points
## that shouldn't exist. Server-authoritative; clients take the corrected value
## via the normal point sync. Called at the end of load_abilities.
func reconcile_ability_points(do_sync: bool = true) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if not is_instance_valid(_weapon_mastery_component):
		return
	var changed: Array[String] = []
	for disc_key in DISCIPLINE_KEYS:
		var class_type: int = _discipline_key_to_class_type(disc_key)
		if class_type == -1:
			continue
		var granted: int = ABILITY_POINTS_PER_MASTERY_LEVEL * _weapon_mastery_component.get_mastery_level(class_type)
		var spent: int = _points_spent_in_discipline(disc_key)
		var expected: int = maxi(0, granted - spent)
		var current: int = int(_available_points_per_discipline.get(disc_key, 0))
		if current != expected:
			push_warning("AbilityComponent: reconciled %s pool %d -> %d (granted=%d, spent=%d)" % [
				disc_key, current, expected, granted, spent])
			_available_points_per_discipline[disc_key] = expected
			changed.append(disc_key)
	if changed.is_empty():
		return
	for key in changed:
		ability_points_changed.emit(key, int(_available_points_per_discipline[key]))
	if do_sync and multiplayer.has_multiplayer_peer() and not BotManager.is_bot(owner.player_id):
		sync_ability_points_per_discipline.rpc(_available_points_per_discipline.duplicate())


## Non-mutating sum of points SPENT in a discipline: levels above each ability's
## free baseline (1 for the discipline starter, else 0) + the point_cost of
## every owned upgrade. Mirrors what _refund_ability would hand back, without
## resetting anything.
func _points_spent_in_discipline(disc_key: String) -> int:
	var starter_id: String = _discipline_starter_ability_id(disc_key)
	var spent: int = 0
	for ability_id in _ability_levels:
		var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
		if ability == null or _ability_primary_discipline(ability) != disc_key:
			continue
		var baseline: int = 1 if ability_id == starter_id else 0
		spent += maxi(0, int(_ability_levels[ability_id]) - baseline)
		for owned_id in _learned_upgrades.get(ability_id, []):
			var up: AbilityUpgradeData = _find_upgrade(ability, owned_id)
			if up != null:
				spent += up.point_cost
	return spent


## Inverse of _class_type_to_discipline_key, restricted to the four tier-1
## disciplines (mastery is tracked per tier-1 discipline). -1 if unknown.
func _discipline_key_to_class_type(disc_key: String) -> int:
	match disc_key:
		"sword": return Constants.ClassType.SWORD
		"bow": return Constants.ClassType.BOW
		"staff": return Constants.ClassType.STAFF
		"dagger": return Constants.ClassType.DAGGER
	return -1

#endregion


func get_cooldown_remaining(ability_id: String) -> float:
	return _cooldowns.get(ability_id, 0.0)


## Checks if an ability meets all criteria to be leveled up.
## PR 4: checks the discipline-specific pool, not the global total.
func can_level_up_ability(ability_id: String) -> bool:
	var ability = ResourceManager.get_ability_data(ability_id)
	if not ability: return false

	var current_level = get_ability_level(ability_id)
	if current_level >= ability.max_level: return false

	# Check for prerequisite ability levels
	if ability.prerequisite_abilities:
		for prereq_id in ability.prerequisite_abilities:
			var required_level = ability.prerequisite_abilities[prereq_id]
			if get_ability_level(prereq_id.ability_id) < required_level:
				return false

	# PR 4: every ability belongs to exactly one weapon discipline (read off
	# `required_class[0]`). An ability with no discipline mapping is
	# unspendable; that's an authoring bug. Surface it but don't crash.
	var disc_key: String = _ability_primary_discipline(ability)
	if disc_key == "":
		push_warning("Ability '%s' has no required_class \u2014 cannot map to a discipline pool" % ability.ability_name)
		return false
	if int(_available_points_per_discipline.get(disc_key, 0)) <= 0:
		return false

	return true


## PR 4: applies the legacy-save migration logic for ability points.
##
## Priority order (revised 2026-05-28):
##   1. `available_points_per_discipline` PRESENT in `data` at all (even as
##      an empty dict) \u2192 trust it as the source of truth. Load verbatim
##      with missing keys defaulting to 0. Do NOT fall through to legacy.
##   2. New key completely absent BUT legacy `available_points` int present
##      AND > 0 \u2192 one-shot migrate: distribute evenly across the four
##      pools, remainder to the starting discipline. Logs a warning.
##   3. Neither \u2192 initialize all four pools to 0.
##
## Bug fix (2026-05-28): previously the new-shape branch required the dict
## to be non-empty (`not saved_dict.is_empty()`). An empty dict \u2014 which the
## backend can legitimately return when the new JSONB column is NULL or the
## save layer hands back `{}` for a fresh-but-zeroed-pool character \u2014 fell
## through to the legacy migration, double-granting `available_points`
## worth of points on EVERY load. A player who spent their 3 mastery points
## would get the migrated 3 added back on next load, ad infinitum.
##
## The rule now is: PRESENCE of the new key (not its contents) signals
## "this save was written by the per-discipline-aware codepath; trust it."
## A truly fresh character with no points still ends up with all-zero pools
## via the dict, which is correct. Legacy migration only fires for saves
## that predate the per-discipline shape entirely.
func _load_ability_points_with_migration(data: Dictionary) -> void:
	# Reset all pools to 0 \u2014 the dict-load case may not mention every key.
	for key in DISCIPLINE_KEYS:
		_available_points_per_discipline[key] = 0

	if data.has("available_points_per_discipline"):
		var saved_dict = data["available_points_per_discipline"]
		if saved_dict is Dictionary:
			for key in DISCIPLINE_KEYS:
				_available_points_per_discipline[key] = int(saved_dict.get(key, 0))
			return

	# Only legacy migration path \u2014 fires exactly once for saves predating PR 4.
	if data.has("available_points"):
		var legacy_total: int = int(data["available_points"])
		if legacy_total > 0:
			var base: int = legacy_total / 4
			var remainder: int = legacy_total - (base * 4)
			for key in DISCIPLINE_KEYS:
				_available_points_per_discipline[key] = base
			var starting_key: String = _starting_discipline_key()
			if starting_key == "" or not _available_points_per_discipline.has(starting_key):
				starting_key = "sword"
			_available_points_per_discipline[starting_key] = base + remainder
			push_warning("AbilityComponent: migrated legacy %d ability points \u2014 per-discipline pools (remainder %d to '%s')" % [legacy_total, remainder, starting_key])


## PR 4: normalizes a per-discipline payload from save / RPC. Accepts
## either the new Dictionary shape OR a legacy int (for cross-version
## compatibility during the rollout) and writes the result into
## `_available_points_per_discipline`. Does not emit signals; the caller
## decides whether to fan-out per-discipline notifications.
func _apply_per_discipline_payload(payload) -> void:
	for key in DISCIPLINE_KEYS:
		_available_points_per_discipline[key] = 0
	if payload is Dictionary:
		for key in DISCIPLINE_KEYS:
			_available_points_per_discipline[key] = int(payload.get(key, 0))
	elif payload is int or payload is float:
		var legacy_total: int = int(payload)
		if legacy_total > 0:
			var base: int = legacy_total / 4
			var remainder: int = legacy_total - (base * 4)
			for key in DISCIPLINE_KEYS:
				_available_points_per_discipline[key] = base
			var starting_key: String = _starting_discipline_key()
			if starting_key == "" or not _available_points_per_discipline.has(starting_key):
				starting_key = "sword"
			_available_points_per_discipline[starting_key] = base + remainder
#endregion


#region #################### PR 6: Passive event dispatch ####################

## Server-only. Iterates learned PASSIVE abilities and invokes on_kill on
## any whose `active_behavior.logic_script` defines the method. Bloodthirst
## hooks here. CombatComponent calls this when an attack downs an enemy.
##
## Per [[project_passives_class_neutral]] we don't gate by active weapon —
## passives apply from both equipped slots, and on_kill fires once per
## kill regardless of which weapon's basic/ability landed the finisher.
func dispatch_passive_event_on_kill(target: Node) -> void:
	if not multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return
	for ability_id in _ability_levels:
		var ability_level: int = _ability_levels[ability_id]
		if ability_level <= 0:
			continue
		var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
		if not ability or ability.ability_type != Constants.AbilityType.PASSIVE:
			continue
		if not ability.active_behavior or not ability.active_behavior.logic_script:
			continue
		var logic = ability.active_behavior.logic_script.new()
		if not logic.has_method("on_kill"):
			continue
		logic.on_kill(owner, target, ability_level, ability_id)

#endregion
