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


func to_dictionary() -> Dictionary:
	return {
		"stat_type": stat_type,
		"base_value": base_value,
		"flat_bonus_value": flat_bonus_value,
		"percent_bonus_value": percent_bonus_value,
	}


static func from_dictionary(dict: Dictionary) -> StatData:
	var stat_data = StatData.new()
	stat_data.stat_type = dict.get("stat_type", 0)
	stat_data.base_value = dict.get("base_value", 0)
	stat_data.flat_bonus_value = dict.get("flat_bonus_value", 0)
	stat_data.percent_bonus_value = dict.get("percent_bonus_value", 0.0)
	return stat_data
