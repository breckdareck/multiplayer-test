class_name PassiveEffectData
extends Resource

@export var stat_modifiers: Dictionary[Constants.StatType, StatData] = {} 
# Example: {"STR": 5, "HP_MAX_PERCENT": 0.15}
@export var condition_type: String = "ALWAYS_ON" 
# e.g., "ON_EQUIP", "ON_LOW_HP", "ON_KILL"
@export var required_level: int = 0
