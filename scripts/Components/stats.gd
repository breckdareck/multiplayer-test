class_name StatsComponent
extends Node

signal stats_changed

const BASE_MAX_HEALTH: int = 100
const SCALING_MULTIPLIER: float = 3.65
const SCALING_EXPONENT: float = 1.5

@export var stats: Dictionary[Constants.StatType, StatData] = {
	Constants.StatType.STRENGTH: StatData.new(Constants.StatType.STRENGTH, 4),
	Constants.StatType.DEXTERITY: StatData.new(Constants.StatType.DEXTERITY, 4),
	Constants.StatType.INTELLIGENCE: StatData.new(Constants.StatType.INTELLIGENCE, 4),
	Constants.StatType.LUCK: StatData.new(Constants.StatType.LUCK, 4),
	Constants.StatType.HEALTH: StatData.new(Constants.StatType.HEALTH, 100),
	Constants.StatType.MANA: StatData.new(Constants.StatType.MANA, 100),
	Constants.StatType.DEFENSE: StatData.new(Constants.StatType.DEFENSE, 100),
	Constants.StatType.CRITCHANCE: StatData.new(Constants.StatType.CRITCHANCE, 5),
	Constants.StatType.CRITDAMAGE: StatData.new(Constants.StatType.CRITDAMAGE, 0),
	Constants.StatType.WEAPONATTACK: StatData.new(Constants.StatType.WEAPONATTACK, 0),
	Constants.StatType.MAGICATTACK: StatData.new(Constants.StatType.MAGICATTACK, 0),
	
}

var _level_component: LevelingComponent
var _class_component: ClassComponent
var _equipment_component: EquipmentComponent

var _recalc_scheduled: bool = false

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
		

func _recalculate_stats() -> void:
	# Get's base stats from class
	var base_stats:Dictionary[Constants.StatType, int] = _class_component.get_base_stats()
	for stat in base_stats:
		stats.get(stat).base_value = base_stats[stat]
		
	# Setup Health from Forumla
	stats.get(Constants.StatType.HEALTH).base_value = int(BASE_MAX_HEALTH + (SCALING_MULTIPLIER * pow(_level_component.level - 1, SCALING_EXPONENT)))
	
	# Reset flat bonuses before recalculating
	for stat_type in stats:
		stats[stat_type].flat_bonus_value = 0

	# Get Class Bonus's
	var class_bonuses:Dictionary[Constants.StatType, int] = _class_component.get_class_bonuses()
	for stat in class_bonuses:
		stats.get(stat).flat_bonus_value += class_bonuses[stat] * _level_component.level
		
	# Add equipment bonuses
	# TODO: Add the Percent Bonus's as well
	if _equipment_component:
		var equipment_bonuses: Dictionary = {}
		for slot in _equipment_component.get_slots():
			if slot.item != null:
				if slot.item.bonus_stats != null:
					var item_bonus_stats = slot.item.bonus_stats
					for stat_type in item_bonus_stats:
						if !equipment_bonuses.has(stat_type):
							equipment_bonuses[stat_type] = 0
						equipment_bonuses[stat_type] += item_bonus_stats[stat_type].flat_bonus_value

		for stat_type in equipment_bonuses:
			if stats.has(stat_type):
				stats[stat_type].flat_bonus_value += equipment_bonuses[stat_type]
		print("StatsComponent: Applied equipment bonuses: %s" % equipment_bonuses)

	# Add passive ability bonuses
	var ability_component = get_parent().get_node_or_null("Ability")
	if ability_component and ability_component.has_method("get_passive_effect_modifiers"):
		var ability_bonuses = ability_component.get_passive_effect_modifiers()
		for stat_type in ability_bonuses:
			if stats.has(stat_type):
				stats[stat_type].flat_bonus_value += ability_bonuses[stat_type]
		print("StatsComponent: Applied ability passive bonuses: %s" % ability_bonuses)

	print("StatsComponent: Applied class bonuses for %s: %s" % [_class_component.get_class_name(), class_bonuses])
	print("StatsComponent: Final stats - STR: %d, DEX: %d, INT: %d, LUK: %d" % [stats[Constants.StatType.STRENGTH].total_value, stats[Constants.StatType.DEXTERITY].total_value, stats[Constants.StatType.INTELLIGENCE].total_value, stats[Constants.StatType.LUCK].total_value])
	
	stats_changed.emit()
	

@rpc("any_peer","call_local","reliable")
func _recalculate_stats_server(from: String) -> void:
	print("Recalc called from %s" % from)
	_recalculate_stats()
	await get_tree().process_frame
	_recalculate_stats_client.rpc_id(owner.player_id, from)


@rpc("authority", "call_local", "reliable")
func _recalculate_stats_client(from: String) -> void:
	print("Called from %s on %d with Class: %s - Level: %d" % [from, owner.player_id, _class_component.current_class, _level_component.level])
	_recalculate_stats()


func _on_leveled_up(_new_level: int) -> void:
	print("STATS: OnLevelUp - PID: %s - NewLevel: %d" % [str(owner.player_id), _new_level])
	_recalculate_stats_server("OnLeveledUp")

func _on_class_changed(_new_class: String) -> void:
	print("STATS: OnClassChange - PID: %s - NewClass: %s" % [str(owner.player_id), _new_class])
	_recalculate_stats_server("OnClassChange")

func _on_equipment_changed() -> void:
	if _recalc_scheduled:
		return
	_recalc_scheduled = true
	call_deferred("_deferred_recalculate_stats")

func _deferred_recalculate_stats() -> void:
	print("STATS: OnEquipmentChanged - PID: %s" % str(owner.player_id))
	_recalculate_stats_server("OnEquipmentChanged")
	_recalc_scheduled = false
