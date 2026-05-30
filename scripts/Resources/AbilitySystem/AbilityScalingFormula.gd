@tool
class_name AbilityScalingFormula
extends Resource

## Defines how a specific stat scales per level using a formula
## Example: damage might be "100 + (level * 5)" or "100 * (1.1 ^ level)"

enum ScalingType {
	FLAT,           # value + (level * per_level)
	MULTIPLICATIVE, # value * (multiplier ^ level)
	STEPPED,        # Changes at specific level breakpoints
	CUSTOM          # Uses a custom expression
}

@export var scaling_type: ScalingType = ScalingType.FLAT

## Base value at level 1
@export var base_value: float = 0.0

## For FLAT: added per level (e.g., +5 damage per level)
@export var per_level: float = 0.0

## For MULTIPLICATIVE: multiplier per level (e.g., 1.1 = 10% increase per level)
@export var multiplier: float = 1.0

## For STEPPED: Define breakpoints { level: value }
## Example: {1: 100, 5: 150, 10: 200} means damage is 100 until level 5, then 150, etc.
@export var step_values: Dictionary[int, int] = {}

## For CUSTOM: GDScript expression (e.g., "base_value + (level * 5) + (level * level * 0.5)")
## Available variables: level, base_value
@export var custom_formula: String = ""


## Calculate the value for a given level
func calculate(level: int) -> float:
	match scaling_type:
		ScalingType.FLAT:
			return base_value + ((level - 1) * per_level)

		ScalingType.MULTIPLICATIVE:
			return base_value * pow(multiplier, level - 1)

		ScalingType.STEPPED:
			var result = base_value
			var sorted_levels = step_values.keys()
			sorted_levels.sort()

			for step_level in sorted_levels:
				if level >= step_level:
					result = step_values[step_level]
				else:
					break
			return result

		ScalingType.CUSTOM:
			if custom_formula.is_empty():
				return base_value

			# Use Expression to evaluate custom formulas
			var expr = Expression.new()
			var error = expr.parse(custom_formula, ["level", "base_value"])
			if error != OK:
				push_error("Invalid formula: %s" % custom_formula)
				return base_value

			var result = expr.execute([level, base_value])
			if expr.has_execute_failed():
				push_error("Formula execution failed: %s" % custom_formula)
				return base_value

			return result

	return base_value
