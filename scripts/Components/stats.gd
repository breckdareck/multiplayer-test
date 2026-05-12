class_name StatsComponent
extends Node

signal stats_changed

# Beginner Health Scaling
# Health: int(50 + (13 * (_level_component.level - 1)))
# Mana: int(50 + (11 * (_level_component.level - 1)))

const BEGINNER_BASE_MAX_HEALTH: int = 50
const BEGINNER_BASE_MAX_MANA: int = 50
const BEGINNER_HEALTH_SCALING_MULTIPLIER: int = 13
const BEGINNER_MANA_SCALING_MULTIPLIER: int = 11

# Warrior Health Scaling
# Health: int(500 + (26 * (_level_component.level - 10)))
# Mana: int(161 + (5 * (_level_component.level - 10)))

const WARRIOR_BASE_MAX_HEALTH: int = 500
const WARRIOR_BASE_MAX_MANA: int = 160
const WARRIOR_HEALTH_SCALING_MULTIPLIER: int = 26
const WARRIOR_MANA_SCALING_MULTIPLIER: int = 5

# Rogue Health Scaling
# Health: int(356 + (22 * (_level_component.level - 10)))
# Mana: int(249 + (15 * (_level_component.level - 10)))

const ROGUE_BASE_MAX_HEALTH: int = 356
const ROGUE_BASE_MAX_MANA: int = 249
const ROGUE_HEALTH_SCALING_MULTIPLIER: int = 22
const ROGUE_MANA_SCALING_MULTIPLIER: int = 15

# Mage Health Scaling
# Health: int(190 + (23 * (_level_component.level - 10)))
# Mana: int(550 + (37 * (_level_component.level - 10)))

const MAGE_BASE_MAX_HEALTH: int = 190
const MAGE_BASE_MAX_MANA: int = 550
const MAGE_HEALTH_SCALING_MULTIPLIER: int = 23
const MAGE_MANA_SCALING_MULTIPLIER: int = 37

# Archer Health Scaling
# Health: int(352 + (22 * (_level_component.level - 10)))
# Mana: int(250 + (16 * (_level_component.level - 10)))

const ARCHER_BASE_MAX_HEALTH: int = 352
const ARCHER_BASE_MAX_MANA: int = 250
const ARCHER_HEALTH_SCALING_MULTIPLIER: int = 22
const ARCHER_MANA_SCALING_MULTIPLIER: int = 16


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
			stats[Constants.StatType.HEALTH].base_value = int(WARRIOR_BASE_MAX_HEALTH + (WARRIOR_HEALTH_SCALING_MULTIPLIER * (level - 10)))
			stats[Constants.StatType.MANA].base_value = int(WARRIOR_BASE_MAX_MANA + (WARRIOR_MANA_SCALING_MULTIPLIER * (level - 10)))
		Constants.ClassType.MAGE:
			stats[Constants.StatType.HEALTH].base_value = int(MAGE_BASE_MAX_HEALTH + (MAGE_HEALTH_SCALING_MULTIPLIER * (level - 10)))
			stats[Constants.StatType.MANA].base_value = int(MAGE_BASE_MAX_MANA + (MAGE_MANA_SCALING_MULTIPLIER * (level - 10)))
		Constants.ClassType.ARCHER:
			stats[Constants.StatType.HEALTH].base_value = int(ARCHER_BASE_MAX_HEALTH + (ARCHER_HEALTH_SCALING_MULTIPLIER * (level - 10)))
			stats[Constants.StatType.MANA].base_value = int(ARCHER_BASE_MAX_MANA + (ARCHER_MANA_SCALING_MULTIPLIER * (level - 10)))
		Constants.ClassType.ROGUE:
			stats[Constants.StatType.HEALTH].base_value = int(ROGUE_BASE_MAX_HEALTH + (ROGUE_HEALTH_SCALING_MULTIPLIER * (level - 10)))
			stats[Constants.StatType.MANA].base_value = int(ROGUE_BASE_MAX_MANA + (ROGUE_MANA_SCALING_MULTIPLIER * (level - 10)))
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

	# Add equipment bonuses (single pass)
	if _equipment_component:
		for slot in _equipment_component.get_slots():
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
