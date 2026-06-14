class_name StatsComponent
extends Node

signal stats_changed
## Economy sink (2026-06-02): emitted server-side when a respec is rejected for
## insufficient monies. The owning client's StatsWindow surfaces a brief ping.
signal respec_denied(reason: String)

## Economy sink: attribute respec costs monies, scaling with character level
## (a proxy for how much progression is being undone). Kept modest because the
## coin faucet is thin (mob drops + quests). L100 -> 3,000. The cost gate lives
## in `_respec_attributes_local`, the single server-side mutation point both the
## host-direct call and the `respec_attributes_request` RPC funnel through.
# Respec cost scales with the NUMBER of points refunded, not character level —
# early (few points) is cheap, late (many points) costs more, matching income.
const ATTR_RESPEC_COST_PER_POINT: int = 5

# All classes scale from level 1 (base classes are created at level 1;
# advanced classes at level 30). The BASE_MAX_* constants are the level-1
# values; SCALING_MULTIPLIER is the per-level gain.

# Unified Health Scaling — every weapon discipline shares ONE health curve.
# The old per-class curves (Warrior 120+26, Rogue 95+22, Mage 70+23, ...) were
# a class-system remnant; under weapon-driven identity HP differentiation comes
# from CON allocation and gear, never from which weapon you started with.
# Health: int(100 + (24 * (_level_component.level - 1)))  -> 2,476 at L100

const PLAYER_BASE_MAX_HEALTH: int = 100
const PLAYER_HEALTH_SCALING_MULTIPLIER: int = 24

# Unified Mana Scaling — same rationale as health: the old per-class curves
# (Mage 100+37, Warrior 30+5, ...) were a class-system remnant. INT is mana's
# CON (INT_TO_MANA flat MP + MPREGEN per point), so pool differentiation comes
# from INT allocation and gear, never from which weapon you started with.
# Mana: int(50 + (6 * (_level_component.level - 1)))  -> 644 at L100
# (2026-06-11 mana-pressure pass: growth 12 -> 6. Costs scale with ABILITY level
# (caps at 10, shallow per_level) while the pool scales with CHAR level, so a
# fat pool dissolves all potion pressure by endgame. ~65s of nonstop spam now
# empties a melee bar at L100. INT_TO_MANA/INT_TO_MPREGEN halved same pass.)

const PLAYER_BASE_MAX_MANA: int = 50
const PLAYER_MANA_SCALING_MULTIPLIER: int = 6

# (Advanced-class HP/MP constants removed in PR 7 — Job Advancement is gone;
# only the four weapon disciplines exist. primary_discipline can never be an
# advanced class: WeaponMasteryComponent's setter normalizes any legacy
# CRUSADER/RANGER/ARCHMAGE/ASSASSIN save back to its tier-1 discipline on load.)

# Flat knockback resistance every class starts with. Equipment and buffs add
# flat bonuses on top through the normal stat aggregation.
const BASE_KNOCKBACK_RESIST: int = 80


@export var stats: Dictionary[Constants.StatType, StatData] = {
	Constants.StatType.STRENGTH: StatData.new(Constants.StatType.STRENGTH, 4),
	Constants.StatType.DEXTERITY: StatData.new(Constants.StatType.DEXTERITY, 4),
	Constants.StatType.INTELLIGENCE: StatData.new(Constants.StatType.INTELLIGENCE, 4),
	Constants.StatType.LUCK: StatData.new(Constants.StatType.LUCK, 4),
	Constants.StatType.HEALTH: StatData.new(Constants.StatType.HEALTH, 100),
	Constants.StatType.MANA: StatData.new(Constants.StatType.MANA, 100),
	Constants.StatType.HPREGEN: StatData.new(Constants.StatType.HPREGEN, 10),
	Constants.StatType.MPREGEN: StatData.new(Constants.StatType.MPREGEN, 5),
	Constants.StatType.DEFENSE: StatData.new(Constants.StatType.DEFENSE, 0),
	Constants.StatType.MAGICDEFENSE: StatData.new(Constants.StatType.MAGICDEFENSE, 0),
	Constants.StatType.CRITCHANCE: StatData.new(Constants.StatType.CRITCHANCE, 5),
	Constants.StatType.CRITDAMAGE: StatData.new(Constants.StatType.CRITDAMAGE, 0),
	Constants.StatType.WEAPONATTACK: StatData.new(Constants.StatType.WEAPONATTACK, 0),
	Constants.StatType.MAGICATTACK: StatData.new(Constants.StatType.MAGICATTACK, 0),
	Constants.StatType.KNOCKBACKRESIST: StatData.new(Constants.StatType.KNOCKBACKRESIST, BASE_KNOCKBACK_RESIST),
	Constants.StatType.CONSTITUTION: StatData.new(Constants.StatType.CONSTITUTION, 4),
	Constants.StatType.ACCURACY: StatData.new(Constants.StatType.ACCURACY, 0),
	Constants.StatType.EVASIONCHANCE: StatData.new(Constants.StatType.EVASIONCHANCE, 0),

}

# PR 7 — manual attribute allocation (New World style). Pool = 5/level, spent
# into STR/DEX/INT/LUCK/CON; replaces the old auto per-level discipline scaling.
# Secondary utilities (tunable starting rates) feed derived stats.
const ATTRIBUTE_POINTS_PER_LEVEL: int = 5
const ALLOCATABLE_ATTRIBUTES: Array = [
	Constants.StatType.STRENGTH, Constants.StatType.DEXTERITY,
	Constants.StatType.INTELLIGENCE, Constants.StatType.LUCK,
	Constants.StatType.CONSTITUTION,
]
# Canonical starting value for a primary attribute (matches the `stats` dict init
# and WeaponDisciplineData.base_stats). Used to reset allocatable attributes the
# discipline's base_stats doesn't define — see the recompute note below.
const BASE_ATTRIBUTE_VALUE: int = 4
const STR_TO_DEFENSE: float = 1.0
const INT_TO_MANA: float = 2.5
const INT_TO_MPREGEN: float = 0.05
const LUCK_TO_CRIT: float = 0.1   # % crit per LUCK (full rate below the knee)
## LUCK -> crit DIMINISHING RETURNS (2026-06-08): full LUCK_TO_CRIT up to the knee,
## then a reduced slope above it, so a high-LUCK build (dagger) no longer trivially
## reaches 100% crit. At LUCK ~800 this gives ~31% crit from LUCK (was ~80%).
const LUCK_CRIT_KNEE: float = 100.0
const LUCK_CRIT_SLOPE: float = 0.30
const CON_TO_HP: float = 8.0
const CON_TO_HPREGEN: float = 0.2
## CON also grants DEFENSE so survivability isn't STR-locked — every build (caster,
## rogue, archer) gets a class-neutral way to be less paper by investing CON, at the
## cost of offense. Below STR's rate so STR stays the premier defensive stat for the
## sword's tank identity. (Tuning lever — adjust after playtesting.)
const CON_TO_DEFENSE: float = 0.6
const DEX_TO_ACCURACY: float = 0.05  # % hit per DEX, consumed in combat.gd

# PR 7 balance — attribute SOFT-CAP (diminishing returns on hard mono-stacking).
# Allocated points into a SINGLE stat keep full value up to ATTR_SOFT_CAP_KNEE,
# then each point beyond counts at ATTR_SOFT_CAP_SLOPE. This shrinks the
# pure-primary advantage (was ~+43% damage, always-correct) so spreading into
# the secondary / CON / utility is competitive — without nerfing the default
# discipline-ratio build, whose L100 primary (~297) sits UNDER the knee. Applies
# only to the manually-allocated pool, NOT base / mastery / gear. Point ACCOUNTING
# (reconcile_ability_points / save) is unaffected — it tracks spent points, not
# effective stat value. Tunable starting values.
const ATTR_SOFT_CAP_KNEE: int = 300
const ATTR_SOFT_CAP_SLOPE: float = 0.4


## Diminishing-returns transform on the raw points allocated to one stat.
## Full value up to the knee, then ATTR_SOFT_CAP_SLOPE beyond it.
func _effective_allocation(raw: int) -> int:
	if raw <= ATTR_SOFT_CAP_KNEE:
		return raw
	return ATTR_SOFT_CAP_KNEE + int((raw - ATTR_SOFT_CAP_KNEE) * ATTR_SOFT_CAP_SLOPE)

## {StatType: spent_points}. Server-authoritative; synced to the owning client.
var _allocated_attributes: Dictionary = {}

signal attribute_points_changed(unused: int)

var _level_component: LevelingComponent
var _equipment_component: EquipmentComponent
var _weapon_mastery_component: WeaponMasteryComponent

var _stats_dirty: bool = false
var _loading_mode: bool = false

func _ready() -> void:
	_level_component = get_parent().get_node_or_null("Leveling")
	_equipment_component = get_parent().get_node_or_null("Equipment")
	_weapon_mastery_component = get_parent().get_node_or_null("WeaponMastery")

	#TODO: Fix Syncing of Stats for Clients - SLIGHTY FIXED - LOOK AT LATER
	if !multiplayer.is_server():
		return

	# Find the level component on the same node
	if _level_component:
		_level_component.leveled_up.connect(_on_leveled_up)

	if _equipment_component:
		_equipment_component.on_equipment_changed.connect(_on_equipment_changed)

	# Mastery levels drive per-mastery-level STR/DEX/INT/LUK scaling (PR 2):
	# whenever a discipline gains a level, stats need a recalc. The primary
	# discipline (base stats + HP/MP curve) is also owned here now — recalc when
	# it's set at spawn (replaces the old ClassComponent.class_changed hookup).
	if _weapon_mastery_component:
		_weapon_mastery_component.mastery_level_changed.connect(_on_mastery_level_changed)
		_weapon_mastery_component.primary_discipline_changed.connect(_on_primary_discipline_changed)



## Marks stats as needing recalculation. Multiple calls in the same frame
## are coalesced into a single recalc via call_deferred.
func mark_stats_dirty() -> void:
	if _loading_mode or _stats_dirty:
		return
	_stats_dirty = true
	call_deferred("_flush_recalculate")


func _flush_recalculate() -> void:
	if not _stats_dirty:
		return
	_stats_dirty = false
	_recalculate_stats()
	if not BotManager.is_bot(owner.player_id):
		_recalculate_stats_client.rpc_id(owner.player_id)


func _recalculate_stats() -> void:
	# Get base stats from the primary weapon discipline
	var base_stats: Dictionary[Constants.StatType, int] = _weapon_mastery_component.get_base_stats()
	for stat in base_stats:
		stats[stat].base_value = base_stats[stat]

	# CONSTITUTION (StatType 15) was appended AFTER WeaponDisciplineData.base_stats
	# was authored, so base_stats omits it and the loop above never resets its
	# base_value. Reset any allocatable attribute the discipline doesn't define to
	# the canonical base — otherwise the `base_value += allocation` below COMPOUNDS
	# every recompute (HP balloons on each allocate; respec never lowers it again).
	for attr in ALLOCATABLE_ATTRIBUTES:
		if not base_stats.has(attr):
			stats[attr].base_value = BASE_ATTRIBUTE_VALUE

	# Health + Mana: ONE unified curve each, for every discipline (weapon-driven
	# identity — pool differentiation comes from CON/INT allocation + gear, not
	# from which weapon you started with).
	var level: int = _level_component.level
	stats[Constants.StatType.HEALTH].base_value = int(PLAYER_BASE_MAX_HEALTH + (PLAYER_HEALTH_SCALING_MULTIPLIER * (level - 1)))
	stats[Constants.StatType.MANA].base_value = int(PLAYER_BASE_MAX_MANA + (PLAYER_MANA_SCALING_MULTIPLIER * (level - 1)))

	# Apply the character's CURRENT-CLASS per-level STR/DEX/INT/LUK scaling.
	# This is the familiar Maple-shape baseline: a level-30 Swordsman gets
	# ~+87 STR purely from class progression, regardless of any weapon mastery.
	# Mastery (below) layers on top as additional growth that rewards focused
	# specialisation. Cards / signature systems (later PRs) layer on top of that.
	#
	# This restores behaviour the first cut of PR 2 inadvertently removed when
	# it routed all primary-stat scaling exclusively through mastery — the
	# resulting un-mastered baseline felt punishingly weak relative to today.
	# PR 7: manually-allocated attribute points replace the old auto per-level
	# discipline scaling. The 5/level pool is spent into STR/DEX/INT/LUCK/CON;
	# mastery scaling (below) still auto-grants on top. Existing characters are
	# default-allocated to their starting discipline's ratio on load (see
	# reconcile_attribute_points), so nothing changes until they choose to respec.
	# Soft-capped: diminishing returns above ATTR_SOFT_CAP_KNEE per stat, so hard
	# mono-stacking (pure-primary) is reined in while split/default builds keep
	# full value. The raw allocation is still what's stored/accounted; only the
	# stat CONTRIBUTION is softened here.
	for stat_type in _allocated_attributes:
		if stats.has(stat_type):
			stats[stat_type].base_value += _effective_allocation(int(_allocated_attributes[stat_type]))

	# Reset flat bonuses before recalculating
	for stat_type in stats:
		stats[stat_type].flat_bonus_value = 0
		stats[stat_type].percent_bonus_value = 0

	# Apply per-mastery-level STR/DEX/INT/LUK scaling (PR 2 weapon-identity
	# overhaul). For every owned discipline (mastery level > 0), apply
	# `discipline.stat_bonuses[stat] * mastery_level_of_that_discipline`,
	# summed across disciplines. This stacks across all four tier-1 weapons,
	# encouraging build versatility on TOP of the per-character-level
	# baseline above. A level-30 Sword main with mastery 20 ends at roughly
	# 87 (level) + 60 (mastery) = +147 primary STR before equipment/cards —
	# meaningful reward for focused play, not a punishment for being level 1.
	#
	# `stat_bonuses` is reused verbatim from each WeaponDisciplineData —
	# zero new balance numbers in this PR.
	if _weapon_mastery_component:
		for stat_type in stats:
			var bonus: int = _weapon_mastery_component.get_summed_stat_bonus(stat_type)
			if bonus != 0:
				stats[stat_type].base_value += bonus

	# Add equipment bonuses (single pass) — read the SlotData model so this
	# works with no equipment UI (headless / bot). PR 3: use the
	# stat-contributing filter so only the ACTIVE weapon's bonus_stats fold
	# in. The inactive (secondary or primary, depending on swap state) sits
	# in equipment storage but does NOT contribute to live stats.
	if _equipment_component:
		for slot in _equipment_component.get_stat_contributing_slot_data():
			if slot.item != null and slot.item.bonus_stats != null:
				for stat_type in slot.item.bonus_stats:
					if stats.has(stat_type):
						var item_stat_data: StatData = slot.item.bonus_stats[stat_type]
						stats[stat_type].flat_bonus_value += item_stat_data.flat_bonus_value
						stats[stat_type].percent_bonus_value += item_stat_data.percent_bonus_value

	# Add passive ability bonuses
	var ability_component = get_parent().get_node_or_null("Ability")
	if ability_component and ability_component.has_method("get_passive_effect_modifiers"):
		var ability_bonuses = ability_component.get_passive_effect_modifiers()
		for stat_type in ability_bonuses:
			if stats.has(stat_type):
				stats[stat_type].flat_bonus_value += ability_bonuses[stat_type].flat_bonus_value
				stats[stat_type].percent_bonus_value += ability_bonuses[stat_type].percent_bonus_value

	# Add buff bonuses
	var buff_component = get_parent().get_node_or_null("Buff")
	if buff_component and buff_component.has_method("get_buff_stat_modifiers"):
		var buff_bonuses = buff_component.get_buff_stat_modifiers()
		for stat_type in buff_bonuses:
			if stats.has(stat_type):
				stats[stat_type].flat_bonus_value += buff_bonuses[stat_type].flat_bonus_value
				stats[stat_type].percent_bonus_value += buff_bonuses[stat_type].percent_bonus_value

	# PR 7: attribute secondary utilities — read FINAL attribute totals (base +
	# allocated + mastery + equipment + buffs) and feed derived stats.
	_apply_attribute_utilities()

	stats_changed.emit()


@rpc("authority", "call_local", "reliable")
func _recalculate_stats_client() -> void:
	_recalculate_stats()


#region #################### Attribute Allocation (PR 7) ####################
func _is_multiplayer_client() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.is_server()


func get_attribute_points_granted() -> int:
	if not _level_component:
		return 0
	return ATTRIBUTE_POINTS_PER_LEVEL * maxi(0, _level_component.level - 1)


func get_attribute_points_spent() -> int:
	var total: int = 0
	for k in _allocated_attributes:
		total += int(_allocated_attributes[k])
	return total


func get_attribute_points_unused() -> int:
	return maxi(0, get_attribute_points_granted() - get_attribute_points_spent())


func get_allocated_attribute(stat_type: int) -> int:
	return int(_allocated_attributes.get(stat_type, 0))


## [Client→Server] Spend `amount` points into an attribute.
func allocate_attribute(stat_type: int, amount: int = 1) -> void:
	if _is_multiplayer_client():
		allocate_attribute_request.rpc_id(1, stat_type, amount)
		return
	_allocate_attribute_local(stat_type, amount)


func _allocate_attribute_local(stat_type: int, amount: int) -> void:
	if stat_type not in ALLOCATABLE_ATTRIBUTES:
		return
	amount = mini(amount, get_attribute_points_unused())
	if amount <= 0:
		return
	_allocated_attributes[stat_type] = get_allocated_attribute(stat_type) + amount
	mark_stats_dirty()
	_sync_attributes_and_notify()


@rpc("any_peer", "call_local", "reliable")
func allocate_attribute_request(stat_type: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner.player_id:
		return
	_allocate_attribute_local(stat_type, amount)


## Current character level (1 if the LevelingComponent is unavailable). Used by
## the respec cost formula.
func _current_level() -> int:
	if _level_component:
		return maxi(1, int(_level_component.level))
	return 1


## Resolves the owning player's PlayerInventory (where monies live). Null-safe;
## bots/headless owners may not carry one.
func _player_inventory() -> PlayerInventory:
	if owner and "player_inventory" in owner and is_instance_valid(owner.player_inventory):
		return owner.player_inventory
	return null


## Monies cost to respec all attributes at the current level. UI reads this to
## label the button without duplicating the formula.
func get_attribute_respec_cost() -> int:
	return get_attribute_points_spent() * ATTR_RESPEC_COST_PER_POINT


## [Client→Server] Refund ALL allocated attribute points (costs monies).
func respec_attributes() -> void:
	if _is_multiplayer_client():
		respec_attributes_request.rpc_id(1)
		return
	_respec_attributes_local()


func _respec_attributes_local() -> void:
	if _allocated_attributes.is_empty():
		return
	# Economy sink: charge monies before mutating. Deduction is server-authoritative
	# (set_monies_rpc broadcasts the new total). _respec_attributes_local only runs
	# on the server — the client path early-returns into respec_attributes_request —
	# but we guard the deduction on is_server() to be explicit and safe.
	if multiplayer.is_server():
		var inv: PlayerInventory = _player_inventory()
		var cost: int = get_attribute_respec_cost()
		var monies: int = inv.monies_amount if inv else 0
		if monies < cost:
			respec_denied.emit("not_enough_monies")
			return
		if inv:
			inv.set_monies_rpc(monies - cost)
	_allocated_attributes.clear()
	mark_stats_dirty()
	_sync_attributes_and_notify()


@rpc("any_peer", "call_local", "reliable")
func respec_attributes_request() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner.player_id:
		return
	_respec_attributes_local()


## Safety net (mirrors AbilityComponent.reconcile_ability_points). Default-
## allocates un-migrated characters to their starting discipline's ratio so
## existing characters keep their stats until they choose to respec.
func reconcile_attribute_points(default_allocate_if_empty: bool = true) -> void:
	if _is_multiplayer_client():
		return
	if default_allocate_if_empty and get_attribute_points_spent() == 0:
		_default_allocate_to_discipline()


func _default_allocate_to_discipline() -> void:
	if not (_weapon_mastery_component and _level_component):
		return
	var disc: WeaponDisciplineData = ResourceManager.get_class_data(_weapon_mastery_component.primary_discipline)
	if disc == null:
		return
	var lvls: int = maxi(0, _level_component.level - 1)
	for stat_type in disc.stat_bonuses:
		_allocated_attributes[stat_type] = int(disc.stat_bonuses[stat_type]) * lvls


## Attribute secondary utilities — read FINAL attribute totals, feed derived stats.
func _apply_attribute_utilities() -> void:
	var strv: int = stats[Constants.StatType.STRENGTH].total_value
	var intv: int = stats[Constants.StatType.INTELLIGENCE].total_value
	var luk: int = stats[Constants.StatType.LUCK].total_value
	var con: int = stats[Constants.StatType.CONSTITUTION].total_value
	stats[Constants.StatType.DEFENSE].flat_bonus_value += int(strv * STR_TO_DEFENSE)
	stats[Constants.StatType.DEFENSE].flat_bonus_value += int(con * CON_TO_DEFENSE)
	stats[Constants.StatType.MANA].flat_bonus_value += int(intv * INT_TO_MANA)
	stats[Constants.StatType.MPREGEN].flat_bonus_value += int(intv * INT_TO_MPREGEN)
	stats[Constants.StatType.CRITCHANCE].flat_bonus_value += int(_luck_to_crit(float(luk)))
	stats[Constants.StatType.HEALTH].flat_bonus_value += int(con * CON_TO_HP)
	stats[Constants.StatType.HPREGEN].flat_bonus_value += int(con * CON_TO_HPREGEN)


## LUCK -> crit%, with diminishing returns above LUCK_CRIT_KNEE so crit can't be
## stacked to a guaranteed 100% from a high LUCK primary alone.
func _luck_to_crit(luck: float) -> float:
	if luck <= LUCK_CRIT_KNEE:
		return luck * LUCK_TO_CRIT
	return LUCK_CRIT_KNEE * LUCK_TO_CRIT + (luck - LUCK_CRIT_KNEE) * LUCK_TO_CRIT * LUCK_CRIT_SLOPE


func save_attributes() -> Dictionary:
	return _allocated_attributes.duplicate()


func load_attributes(data) -> void:
	if data is Dictionary:
		# Backend JSON round-trips dict keys as Strings; coerce back to int StatType.
		var coerced: Dictionary = {}
		for k in data:
			coerced[int(k)] = int(data[k])
		_allocated_attributes = coerced


@rpc("authority", "reliable")
func sync_attributes(alloc: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_allocated_attributes = alloc.duplicate()
	attribute_points_changed.emit(get_attribute_points_unused())
	mark_stats_dirty()


## [Server] Push the current allocation to one client (post-spawn initial sync).
func sync_attributes_to_client(peer_id: int) -> void:
	sync_attributes.rpc_id(peer_id, _allocated_attributes.duplicate())


## Pushes the allocation to the owning client (server→client) and notifies UI.
func _sync_attributes_and_notify() -> void:
	attribute_points_changed.emit(get_attribute_points_unused())
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and not BotManager.is_bot(owner.player_id):
		sync_attributes.rpc(_allocated_attributes.duplicate())
#endregion


func _on_leveled_up(_new_level: int) -> void:
	mark_stats_dirty()


func _on_primary_discipline_changed(_discipline: int) -> void:
	mark_stats_dirty()


func _on_equipment_changed() -> void:
	mark_stats_dirty()


func _on_mastery_level_changed(_discipline: int, _new_level: int) -> void:
	mark_stats_dirty()


func set_loading_mode(enabled: bool) -> void:
	_loading_mode = enabled

func is_loading() -> bool:
	return _loading_mode


## Rolls whether a hit with the given knockback `power` should knock back a
## target. Chance is power / (power + resist): a target with 0 knockback resist
## is always knocked back, while resist far above the hit's power rarely is.
static func rolls_knockback(target_stats: StatsComponent, power: float) -> bool:
	if power <= 0.0:
		return false
	var resist: float = 0.0
	if target_stats and target_stats.stats.has(Constants.StatType.KNOCKBACKRESIST):
		resist = float(target_stats.stats[Constants.StatType.KNOCKBACKRESIST].total_value)
	return randf() < power / (power + maxf(resist, 0.0))
