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

var _recalc_scheduled: bool = false
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
		

func _recalculate_stats() -> void:
	# Get's base stats from class
	var base_stats:Dictionary[Constants.StatType, int] = _class_component.get_base_stats()
	for stat in base_stats:
		stats.get(stat).base_value = base_stats[stat]
		
		
	match _class_component.current_class:
		Constants.ClassType.BEGINNER:
			stats.get(Constants.StatType.HEALTH).base_value = int(BEGINNER_BASE_MAX_HEALTH + (BEGINNER_HEALTH_SCALING_MULTIPLIER * (_level_component.level - 1)))
			stats.get(Constants.StatType.MANA).base_value = int(BEGINNER_BASE_MAX_MANA + (BEGINNER_MANA_SCALING_MULTIPLIER * (_level_component.level - 1)))
		Constants.ClassType.SWORDSMAN:
			stats.get(Constants.StatType.HEALTH).base_value = int(WARRIOR_BASE_MAX_HEALTH + (WARRIOR_HEALTH_SCALING_MULTIPLIER * (_level_component.level - 10)))
			stats.get(Constants.StatType.MANA).base_value = int(WARRIOR_BASE_MAX_MANA + (WARRIOR_MANA_SCALING_MULTIPLIER * (_level_component.level - 10)))
		Constants.ClassType.MAGE:
			stats.get(Constants.StatType.HEALTH).base_value = int(MAGE_BASE_MAX_HEALTH + (MAGE_HEALTH_SCALING_MULTIPLIER * (_level_component.level - 10)))
			stats.get(Constants.StatType.MANA).base_value = int(MAGE_BASE_MAX_MANA + (MAGE_MANA_SCALING_MULTIPLIER * (_level_component.level - 10)))
		Constants.ClassType.ARCHER:
			stats.get(Constants.StatType.HEALTH).base_value = int(ARCHER_BASE_MAX_HEALTH + (ARCHER_HEALTH_SCALING_MULTIPLIER * (_level_component.level - 10)))
			stats.get(Constants.StatType.MANA).base_value = int(ARCHER_BASE_MAX_MANA + (ARCHER_MANA_SCALING_MULTIPLIER * (_level_component.level - 10)))
		Constants.ClassType.ROGUE:
			stats.get(Constants.StatType.HEALTH).base_value = int(ROGUE_BASE_MAX_HEALTH + (ROGUE_HEALTH_SCALING_MULTIPLIER * (_level_component.level - 10)))
			stats.get(Constants.StatType.MANA).base_value = int(ROGUE_BASE_MAX_MANA + (ROGUE_MANA_SCALING_MULTIPLIER * (_level_component.level - 10)))
		_:
			stats.get(Constants.StatType.HEALTH).base_value = int(BEGINNER_BASE_MAX_HEALTH + (BEGINNER_HEALTH_SCALING_MULTIPLIER * (_level_component.level - 1)))
			stats.get(Constants.StatType.MANA).base_value = int(BEGINNER_BASE_MAX_MANA + (BEGINNER_MANA_SCALING_MULTIPLIER * (_level_component.level - 1)))
		
	# Reset flat bonuses before recalculating
	for stat_type in stats:
		stats[stat_type].flat_bonus_value = 0
		stats[stat_type].percent_bonus_value = 0

	# Get Class Bonus's
	var class_bonuses:Dictionary[Constants.StatType, int] = _class_component.get_class_bonuses()
	var print_string: String = ""
	for stat in class_bonuses:
		stats.get(stat).base_value += class_bonuses[stat] * _level_component.level
		print_string += (Constants.StatType.find_key(stat) + ":" + str(class_bonuses[stat] * _level_component.level) + ", ")
		
	print("StatsComponent: Applied class bonuses for %s: %s" % [_class_component.get_class_name(), print_string])
	
		
	# Add equipment bonuses
	if _equipment_component:
		for slot in _equipment_component.get_slots():
			if slot.item != null and slot.item.bonus_stats != null:
				var item_bonus_stats = slot.item.bonus_stats
				for stat_type in item_bonus_stats:
					if stats.has(stat_type):
						var item_stat_data: StatData = item_bonus_stats[stat_type]
						stats[stat_type].flat_bonus_value += item_stat_data.flat_bonus_value
						stats[stat_type].percent_bonus_value += item_stat_data.percent_bonus_value

		print_string = ""
		for slot in _equipment_component.get_slots():
			if slot.item != null and slot.item.bonus_stats != null:
				for stat_type in slot.item.bonus_stats:
					var value: StatData = slot.item.bonus_stats[stat_type]
					if value.flat_bonus_value != 0 or value.percent_bonus_value != 0:
						print_string += "%s: (Flat: %d, Percent: %.2f), " % [Constants.StatType.find_key(stat_type), value.flat_bonus_value, value.percent_bonus_value]
		if not print_string.is_empty():
			print("StatsComponent: Applied equipment bonuses: " + print_string)

	# Add passive ability bonuses
	var ability_component = get_parent().get_node_or_null("Ability")
	if ability_component and ability_component.has_method("get_passive_effect_modifiers"):
		var ability_bonuses = ability_component.get_passive_effect_modifiers()
		print_string = ""
		for stat_type in ability_bonuses:
			if stats.has(stat_type):
				stats[stat_type].flat_bonus_value += ability_bonuses[stat_type].flat_bonus_value
				print_string += "{ FLAT- " + (Constants.StatType.find_key(stat_type) + ":" + str(ability_bonuses[stat_type].flat_bonus_value) + ", ")
				stats[stat_type].percent_bonus_value += ability_bonuses[stat_type].percent_bonus_value
				print_string += "PERCENT- " + (Constants.StatType.find_key(stat_type) + ":" + str(ability_bonuses[stat_type].percent_bonus_value) + "}, ")
		print("StatsComponent: Applied ability passive bonuses: %s" % print_string)
		
	# Add buff bonuses (near the end, after equipment and abilities)
	var buff_component = get_parent().get_node_or_null("Buff")
	if buff_component and buff_component.has_method("get_buff_stat_modifiers"):
		var buff_bonuses = buff_component.get_buff_stat_modifiers()
		for stat_type in buff_bonuses:
			if stats.has(stat_type):
				stats[stat_type].flat_bonus_value += buff_bonuses[stat_type].flat_bonus_value
				stats[stat_type].percent_bonus_value += buff_bonuses[stat_type].percent_bonus_value

	## --- Special Defense Calculation ---
	#var str_val = stats.get(Constants.StatType.STRENGTH).total_value
	#var dex_val = stats.get(Constants.StatType.DEXTERITY).total_value
	#var luk_val = stats.get(Constants.StatType.LUCK).total_value
	#var new_base_defense = (1.5 * str_val) + (0.4 * (dex_val + luk_val))
	#stats.get(Constants.StatType.DEFENSE).base_value = roundi(new_base_defense)


	var stat_string = ""
	for stat in stats:
		stat_string += (Constants.StatType.find_key(stat)) + " - "
		stat_string += "{" + "BASE" + ": " + str(stats[stat].base_value) + ", "
		stat_string += "FLAT" + ": " + str(stats[stat].flat_bonus_value) + ", "
		stat_string += "PERCENT" + ": " + str(stats[stat].percent_bonus_value) + ", "
		stat_string += "COMBINED" + ": " + str(stats[stat].combined_bonus_value) + ", "
		stat_string += "TOTAL" + ": " + str(stats[stat].total_value) + "} \n"
	print("StatsComponent: \n%s" % stat_string)
	
	stats_changed.emit()
	

@rpc("any_peer","call_local","reliable")
func _recalculate_stats_server(from: String) -> void:
	if _loading_mode:
		return
		
	print("Recalc called from %s" % from)
	_recalculate_stats()
	await get_tree().process_frame
	_recalculate_stats_client.rpc_id(owner.player_id, from)


@rpc("authority", "call_local", "reliable")
func _recalculate_stats_client(from: String) -> void:
	print("Called from %s on %d with Class: %s - Level: %d" % [from, owner.player_id, _class_component.current_class, _level_component.level])
	_recalculate_stats()


func _on_leveled_up(_new_level: int) -> void:
	if _loading_mode or _recalc_scheduled:
		return
	print("STATS: OnLevelUp - PID: %s - NewLevel: %d" % [str(owner.player_id), _new_level])
	_recalculate_stats_server("OnLeveledUp")


func _on_class_changed(_new_class: String) -> void:
	if _loading_mode or _recalc_scheduled:
		return
	print("STATS: OnClassChange - PID: %s - NewClass: %s" % [str(owner.player_id), _new_class])
	_recalculate_stats_server("OnClassChange")


func _on_equipment_changed() -> void:
	if _loading_mode or _recalc_scheduled:
		return
	_recalc_scheduled = true
	call_deferred("_deferred_recalculate_stats")


func _deferred_recalculate_stats() -> void:
	print("STATS: OnEquipmentChanged - PID: %s" % str(owner.player_id))
	_recalculate_stats_server("OnEquipmentChanged")
	_recalc_scheduled = false


func set_loading_mode(enabled: bool) -> void:
	_loading_mode = enabled

func is_loading() -> bool:
	return _loading_mode
