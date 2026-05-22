class_name StatsComponent
extends Node

signal stats_changed

# All classes scale from level 1 (base classes are created at level 1;
# advanced classes at level 30). The BASE_MAX_* constants are the level-1
# values; SCALING_MULTIPLIER is the per-level gain.

# Beginner Health Scaling
# Health: int(50 + (13 * (_level_component.level - 1)))
# Mana: int(50 + (11 * (_level_component.level - 1)))

const BEGINNER_BASE_MAX_HEALTH: int = 50
const BEGINNER_BASE_MAX_MANA: int = 50
const BEGINNER_HEALTH_SCALING_MULTIPLIER: int = 13
const BEGINNER_MANA_SCALING_MULTIPLIER: int = 11

# Warrior Health Scaling
# Health: int(120 + (26 * (_level_component.level - 1)))
# Mana: int(30 + (5 * (_level_component.level - 1)))

const WARRIOR_BASE_MAX_HEALTH: int = 120
const WARRIOR_BASE_MAX_MANA: int = 30
const WARRIOR_HEALTH_SCALING_MULTIPLIER: int = 26
const WARRIOR_MANA_SCALING_MULTIPLIER: int = 5

# Rogue Health Scaling
# Health: int(95 + (22 * (_level_component.level - 1)))
# Mana: int(45 + (15 * (_level_component.level - 1)))

const ROGUE_BASE_MAX_HEALTH: int = 95
const ROGUE_BASE_MAX_MANA: int = 45
const ROGUE_HEALTH_SCALING_MULTIPLIER: int = 22
const ROGUE_MANA_SCALING_MULTIPLIER: int = 15

# Mage Health Scaling
# Health: int(70 + (23 * (_level_component.level - 1)))
# Mana: int(100 + (37 * (_level_component.level - 1)))

const MAGE_BASE_MAX_HEALTH: int = 70
const MAGE_BASE_MAX_MANA: int = 100
const MAGE_HEALTH_SCALING_MULTIPLIER: int = 23
const MAGE_MANA_SCALING_MULTIPLIER: int = 37

# Archer Health Scaling
# Health: int(90 + (22 * (_level_component.level - 1)))
# Mana: int(50 + (16 * (_level_component.level - 1)))

const ARCHER_BASE_MAX_HEALTH: int = 90
const ARCHER_BASE_MAX_MANA: int = 50
const ARCHER_HEALTH_SCALING_MULTIPLIER: int = 22
const ARCHER_MANA_SCALING_MULTIPLIER: int = 16

# Advanced classes — earned at level 30 via Job Advancement. Each is calibrated
# to be ~1.5× the base class at level 30 (a noticeable jump on advancement) and
# scale slightly faster per level than the base.

# Crusader (advanced Swordsman)
const CRUSADER_BASE_MAX_HEALTH: int = 180
const CRUSADER_BASE_MAX_MANA: int = 45
const CRUSADER_HEALTH_SCALING_MULTIPLIER: int = 34
const CRUSADER_MANA_SCALING_MULTIPLIER: int = 7

# Ranger (advanced Archer)
const RANGER_BASE_MAX_HEALTH: int = 135
const RANGER_BASE_MAX_MANA: int = 75
const RANGER_HEALTH_SCALING_MULTIPLIER: int = 28
const RANGER_MANA_SCALING_MULTIPLIER: int = 20

# Archmage (advanced Mage)
const ARCHMAGE_BASE_MAX_HEALTH: int = 105
const ARCHMAGE_BASE_MAX_MANA: int = 150
const ARCHMAGE_HEALTH_SCALING_MULTIPLIER: int = 28
const ARCHMAGE_MANA_SCALING_MULTIPLIER: int = 47

# Assassin (advanced Rogue)
const ASSASSIN_BASE_MAX_HEALTH: int = 142
const ASSASSIN_BASE_MAX_MANA: int = 67
const ASSASSIN_HEALTH_SCALING_MULTIPLIER: int = 28
const ASSASSIN_MANA_SCALING_MULTIPLIER: int = 19

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

}

var _level_component: LevelingComponent
var _class_component: ClassComponent
var _equipment_component: EquipmentComponent

var _stats_dirty: bool = false
var _loading_mode: bool = false

func _ready() -> void:
	_level_component = get_parent().get_node_or_null("Leveling")
	_class_component = get_parent().get_node_or_null("Class")
	_equipment_component = get_parent().get_node_or_null("Equipment")

	#TODO: Fix Syncing of Stats for Clients - SLIGHTY FIXED - LOOK AT LATER
	if !multiplayer.is_server():
		return

	# Find the level component on the same node
	if _level_component:
		_level_component.leveled_up.connect(_on_leveled_up)

	# Find the class component on the same node
	if _class_component:
		_class_component.class_changed.connect(_on_class_changed)

	if _equipment_component:
		_equipment_component.on_equipment_changed.connect(_on_equipment_changed)
		

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
	# Get base stats from class
	var base_stats: Dictionary[Constants.StatType, int] = _class_component.get_base_stats()
	for stat in base_stats:
		stats[stat].base_value = base_stats[stat]

	# Apply class-specific health/mana scaling
	var level: int = _level_component.level
	match _class_component.current_class:
		Constants.ClassType.BEGINNER:
			stats[Constants.StatType.HEALTH].base_value = int(BEGINNER_BASE_MAX_HEALTH + (BEGINNER_HEALTH_SCALING_MULTIPLIER * (level - 1)))
			stats[Constants.StatType.MANA].base_value = int(BEGINNER_BASE_MAX_MANA + (BEGINNER_MANA_SCALING_MULTIPLIER * (level - 1)))
		Constants.ClassType.SWORDSMAN:
			stats[Constants.StatType.HEALTH].base_value = int(WARRIOR_BASE_MAX_HEALTH + (WARRIOR_HEALTH_SCALING_MULTIPLIER * (level - 1)))
			stats[Constants.StatType.MANA].base_value = int(WARRIOR_BASE_MAX_MANA + (WARRIOR_MANA_SCALING_MULTIPLIER * (level - 1)))
		Constants.ClassType.MAGE:
			stats[Constants.StatType.HEALTH].base_value = int(MAGE_BASE_MAX_HEALTH + (MAGE_HEALTH_SCALING_MULTIPLIER * (level - 1)))
			stats[Constants.StatType.MANA].base_value = int(MAGE_BASE_MAX_MANA + (MAGE_MANA_SCALING_MULTIPLIER * (level - 1)))
		Constants.ClassType.ARCHER:
			stats[Constants.StatType.HEALTH].base_value = int(ARCHER_BASE_MAX_HEALTH + (ARCHER_HEALTH_SCALING_MULTIPLIER * (level - 1)))
			stats[Constants.StatType.MANA].base_value = int(ARCHER_BASE_MAX_MANA + (ARCHER_MANA_SCALING_MULTIPLIER * (level - 1)))
		Constants.ClassType.ROGUE:
			stats[Constants.StatType.HEALTH].base_value = int(ROGUE_BASE_MAX_HEALTH + (ROGUE_HEALTH_SCALING_MULTIPLIER * (level - 1)))
			stats[Constants.StatType.MANA].base_value = int(ROGUE_BASE_MAX_MANA + (ROGUE_MANA_SCALING_MULTIPLIER * (level - 1)))
		Constants.ClassType.CRUSADER:
			stats[Constants.StatType.HEALTH].base_value = int(CRUSADER_BASE_MAX_HEALTH + (CRUSADER_HEALTH_SCALING_MULTIPLIER * (level - 1)))
			stats[Constants.StatType.MANA].base_value = int(CRUSADER_BASE_MAX_MANA + (CRUSADER_MANA_SCALING_MULTIPLIER * (level - 1)))
		Constants.ClassType.RANGER:
			stats[Constants.StatType.HEALTH].base_value = int(RANGER_BASE_MAX_HEALTH + (RANGER_HEALTH_SCALING_MULTIPLIER * (level - 1)))
			stats[Constants.StatType.MANA].base_value = int(RANGER_BASE_MAX_MANA + (RANGER_MANA_SCALING_MULTIPLIER * (level - 1)))
		Constants.ClassType.ARCHMAGE:
			stats[Constants.StatType.HEALTH].base_value = int(ARCHMAGE_BASE_MAX_HEALTH + (ARCHMAGE_HEALTH_SCALING_MULTIPLIER * (level - 1)))
			stats[Constants.StatType.MANA].base_value = int(ARCHMAGE_BASE_MAX_MANA + (ARCHMAGE_MANA_SCALING_MULTIPLIER * (level - 1)))
		Constants.ClassType.ASSASSIN:
			stats[Constants.StatType.HEALTH].base_value = int(ASSASSIN_BASE_MAX_HEALTH + (ASSASSIN_HEALTH_SCALING_MULTIPLIER * (level - 1)))
			stats[Constants.StatType.MANA].base_value = int(ASSASSIN_BASE_MAX_MANA + (ASSASSIN_MANA_SCALING_MULTIPLIER * (level - 1)))
		_:
			stats[Constants.StatType.HEALTH].base_value = int(BEGINNER_BASE_MAX_HEALTH + (BEGINNER_HEALTH_SCALING_MULTIPLIER * (level - 1)))
			stats[Constants.StatType.MANA].base_value = int(BEGINNER_BASE_MAX_MANA + (BEGINNER_MANA_SCALING_MULTIPLIER * (level - 1)))

	# Reset flat bonuses before recalculating
	for stat_type in stats:
		stats[stat_type].flat_bonus_value = 0
		stats[stat_type].percent_bonus_value = 0

	# Apply class bonus scaling
	var class_bonuses: Dictionary[Constants.StatType, int] = _class_component.get_class_bonuses()
	for stat in class_bonuses:
		stats[stat].base_value += class_bonuses[stat] * level

	# Add equipment bonuses (single pass) — read the SlotData model so this
	# works with no equipment UI (headless / bot).
	if _equipment_component:
		for slot in _equipment_component.get_all_slot_data():
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

	stats_changed.emit()


@rpc("authority", "call_local", "reliable")
func _recalculate_stats_client() -> void:
	_recalculate_stats()


func _on_leveled_up(_new_level: int) -> void:
	mark_stats_dirty()


func _on_class_changed(_new_class: String) -> void:
	mark_stats_dirty()


func _on_equipment_changed() -> void:
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
