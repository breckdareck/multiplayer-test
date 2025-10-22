@tool
class_name StatData
extends Resource

@export var stat_type:Constants.StatType
@export var base_value: int = 4
@export var flat_bonus_value: int = 0
@export var percent_bonus_value: float = 0.0

var percent_increase: int:
	get:
		return int(base_value * (percent_bonus_value/100))

# Combined Value = Flat + Percent
var combined_bonus_value: int:
	get:
		return int(flat_bonus_value + percent_increase)

# Total Value = Base Value + Combined
var total_value: int:
	get:
		return int(base_value + combined_bonus_value)


func _init(type_id: Constants.StatType = 0 as Constants.StatType, base: int = 4):
	stat_type = type_id
	base_value = base
