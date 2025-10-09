class_name PassiveEffectData
extends Resource

# Example: {"STR": 5, "HP_MAX_PERCENT": 0.15}
@export var stat_modifiers: Dictionary[Constants.StatType, StatData] = {} 
# e.g., "ON_EQUIP", "ON_LOW_HP", "ON_KILL"
@export var condition_type: String = "ALWAYS_ON" 
