@tool
class_name StatData
extends Resource

@export var stat_type:Constants.StatType
@export var base_value: int = 4
@export var flat_bonus_value: int = 0
@export var percent_bonus_value: float = 0.0

# Combined Value = Flat + (Percent * Base)
var combined_bonus_value: int:
	get:
		var percent_increase = base_value * (percent_bonus_value/100)
		return int(flat_bonus_value + percent_increase)

# Total Value = (Base Value×(1+Percent Bonus))+Flat Bonus
var total_value: int:
	get:
		var percent_increase = base_value * (percent_bonus_value/100)
		return (base_value * (1 + percent_increase/100)) + flat_bonus_value


func _init(type_id: Constants.StatType = 0 as Constants.StatType, base: int = 4):
	stat_type = type_id
	base_value = base
