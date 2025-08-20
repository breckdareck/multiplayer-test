class_name StatsComponent
extends Node

signal stats_changed

@export_category("Base Stats")
@export var base_strength: int = 10
@export var base_dexterity: int = 10
@export var base_intelligence: int = 10
@export var base_vitality: int = 10

@export_category("Stat Growth")
@export var strength_growth: float = 1.2
@export var dexterity_growth: float = 1.15
@export var intelligence_growth: float = 1.25
@export var vitality_growth: float = 1.1

var current_strength: int
var current_dexterity: int
var current_intelligence: int
var current_vitality: int

var _level_component: LevelingComponent
var _class_component: ClassComponent

func _ready() -> void:
	_level_component = get_parent().get_node_or_null("Leveling")
	_class_component = get_parent().get_node_or_null("Class")
	
	if not multiplayer.is_server():
		return 
		
	# Find the level component on the same node
	if _level_component:
		_level_component.leveled_up.connect(_on_leveled_up)
	
	# Find the class component on the same node
	if _class_component:
		_class_component.class_changed.connect(_on_class_changed)
		
	# Initialize stats
	_recalculate_stats()

func _recalculate_stats() -> void:
	var level = _level_component.level if _level_component else 1
	
	# Calculate base stats from level
	current_strength = int(base_strength * pow(strength_growth, level - 1))
	current_dexterity = int(base_dexterity * pow(dexterity_growth, level - 1))
	current_intelligence = int(base_intelligence * pow(intelligence_growth, level - 1))
	current_vitality = int(base_vitality * pow(vitality_growth, level - 1))
	
	# Apply class bonuses if available
	if _class_component:
		var class_bonuses = _class_component.get_class_bonuses()
		if class_bonuses.has("strength_bonus"):
			current_strength += class_bonuses["strength_bonus"]
		if class_bonuses.has("dexterity_bonus"):
			current_dexterity += class_bonuses["dexterity_bonus"]
		if class_bonuses.has("intelligence_bonus"):
			current_intelligence += class_bonuses["intelligence_bonus"]
		if class_bonuses.has("vitality_bonus"):
			current_vitality += class_bonuses["vitality_bonus"]
		
		print("StatsComponent: Applied class bonuses for %s: %s" % [_class_component.get_class_name(), class_bonuses])
	
	print("StatsComponent: Final stats - STR: %d, DEX: %d, INT: %d, VIT: %d" % [current_strength, current_dexterity, current_intelligence, current_vitality])
	
	stats_changed.emit()

func _on_leveled_up(new_level: int) -> void:
	_recalculate_stats()

func _on_class_changed(new_class: String) -> void:
	_recalculate_stats()

# Getter methods for other components
func get_strength() -> int:
	return current_strength

func get_dexterity() -> int:
	return current_dexterity

func get_intelligence() -> int:
	return current_intelligence

func get_vitality() -> int:
	return current_vitality

# Get total stats including class bonuses
func get_total_stats() -> Dictionary:
	return {
		"strength": current_strength,
		"dexterity": current_dexterity,
		"intelligence": current_intelligence,
		"vitality": current_vitality
	}

# Get class bonuses currently applied
func get_applied_class_bonuses() -> Dictionary:
	if _class_component:
		return _class_component.get_class_bonuses()
	return {}

# Calculate derived stats
func get_attack_power() -> int:
	return current_strength * 2 + current_dexterity

func get_magic_power() -> int:
	return current_intelligence * 3

func get_defense() -> int:
	return current_vitality + current_strength

func get_critical_chance() -> float:
	return current_dexterity * 0.5  # 0.5% per dex point
