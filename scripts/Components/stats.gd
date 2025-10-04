class_name StatsComponent
extends Node

signal stats_changed

@export var stats: Dictionary = {
	Constants.StatType.STRENGTH: StatData.new(Constants.StatType.STRENGTH, 4),
	Constants.StatType.DEXTERITY: StatData.new(Constants.StatType.DEXTERITY, 4),
	Constants.StatType.INTELLIGENCE: StatData.new(Constants.StatType.INTELLIGENCE, 4),
	Constants.StatType.LUCK: StatData.new(Constants.StatType.LUCK, 4)
}

var _level_component: LevelingComponent
var _class_component: ClassComponent

func _ready() -> void:
	_level_component = get_parent().get_node_or_null("Leveling")
	_class_component = get_parent().get_node_or_null("Class")
	
	#TODO: Fix Syncing of Stats for Clients - SLIGHTY FIXED - LOOK AT LATER
	if !multiplayer.is_server():
		return

	# Find the level component on the same node
	if _level_component:
		_level_component.leveled_up.connect(_on_leveled_up)
	
	# Find the class component on the same node
	if _class_component:
		_class_component.class_changed.connect(_on_class_changed)
		

func _recalculate_stats() -> void:
	var base_stats:Dictionary[Constants.StatType, int] = _class_component.get_base_stats()
	for stat in base_stats:
		stats.get(stat).base_value = base_stats[stat]
	
	var class_bonuses:Dictionary[Constants.StatType, int] = _class_component.get_class_bonuses()
	for stat in class_bonuses:
		stats.get(stat).flat_bonus_value = class_bonuses[stat] * _level_component.level
		
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
