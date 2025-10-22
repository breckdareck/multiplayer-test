@tool
class_name StatBonusFormula
extends Resource

## Defines how a stat bonus scales, supporting both flat and percent bonuses

@export var stat_type: Constants.StatType

## Formula for flat bonus value
@export var flat_bonus_formula: AbilityScalingFormula

## Formula for percent bonus value
@export var percent_bonus_formula: AbilityScalingFormula


## Generate a StatData for a specific level
func generate_stat_data(level: int) -> StatData:
	var stat_data = StatData.new(stat_type, 0)
	
	if flat_bonus_formula:
		stat_data.flat_bonus_value = int(flat_bonus_formula.calculate(level))
	
	if percent_bonus_formula:
		stat_data.percent_bonus_value = percent_bonus_formula.calculate(level)
	
	return stat_data
