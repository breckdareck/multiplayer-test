class_name AbilityLevelData
extends Resource

@export var level: int = 1
@export var mana_cost: int = 0
@export var cooldown_time: float = 0.0
@export var damage_percent: int = 100
@export var max_targets: int = 1
@export var max_hits: int = 1
@export var cast_time: float = 0.0

## Additional level-specific properties
@export var status_effect_chance: float = 0.0
@export var status_effect_duration: float = 0.0
@export var range_multiplier: float = 1.0
@export var knockback_force: float = 0.0

## For passive skills that give stat bonuses
@export var stat_bonuses: Dictionary[Constants.StatType, StatData]

func _init(p_level: int = 1):
	level = p_level
