# Unit tests for AbilityScalingFormula.calculate() — the per-level scaling math
# that every ability stat is generated from.
extends "res://test/test_case.gd"

func _flat(base: float, per_level: float) -> AbilityScalingFormula:
	var f := AbilityScalingFormula.new()
	f.scaling_type = AbilityScalingFormula.ScalingType.FLAT
	f.base_value = base
	f.per_level = per_level
	return f

func _mult(base: float, multiplier: float) -> AbilityScalingFormula:
	var f := AbilityScalingFormula.new()
	f.scaling_type = AbilityScalingFormula.ScalingType.MULTIPLICATIVE
	f.base_value = base
	f.multiplier = multiplier
	return f

func _stepped(base: float, steps: Dictionary) -> AbilityScalingFormula:
	var f := AbilityScalingFormula.new()
	f.scaling_type = AbilityScalingFormula.ScalingType.STEPPED
	f.base_value = base
	# step_values is a typed Dictionary[int, int]; copy into a typed local so the
	# assignment doesn't fail the runtime type check on an untyped literal.
	var typed: Dictionary[int, int] = {}
	for key in steps:
		typed[int(key)] = int(steps[key])
	f.step_values = typed
	return f

func _custom(base: float, expr: String) -> AbilityScalingFormula:
	var f := AbilityScalingFormula.new()
	f.scaling_type = AbilityScalingFormula.ScalingType.CUSTOM
	f.base_value = base
	f.custom_formula = expr
	return f


# ---- FLAT: base + (level - 1) * per_level ----

func test_flat_level_one_returns_base() -> void:
	assert_almost_eq(_flat(100.0, 5.0).calculate(1), 100.0, 0.001)

func test_flat_scales_linearly_per_level() -> void:
	var f := _flat(100.0, 5.0)
	assert_almost_eq(f.calculate(2), 105.0, 0.001, "level 2")
	assert_almost_eq(f.calculate(10), 145.0, 0.001, "level 10")

func test_flat_zero_per_level_is_constant() -> void:
	var f := _flat(42.0, 0.0)
	assert_almost_eq(f.calculate(1), 42.0, 0.001)
	assert_almost_eq(f.calculate(99), 42.0, 0.001)

func test_flat_negative_per_level_decays() -> void:
	# e.g. cooldown shrinking with level
	assert_almost_eq(_flat(5.0, -0.1).calculate(5), 4.6, 0.001)


# ---- MULTIPLICATIVE: base * multiplier ^ (level - 1) ----

func test_multiplicative_level_one_returns_base() -> void:
	assert_almost_eq(_mult(100.0, 1.1).calculate(1), 100.0, 0.001)

func test_multiplicative_compounds() -> void:
	var f := _mult(100.0, 1.1)
	assert_almost_eq(f.calculate(2), 110.0, 0.001, "level 2")
	assert_almost_eq(f.calculate(3), 121.0, 0.001, "level 3")
	assert_almost_eq(f.calculate(5), 146.41, 0.001, "level 5")


# ---- STEPPED: holds a value until the next breakpoint ----

func test_stepped_holds_value_between_breakpoints() -> void:
	var f := _stepped(50.0, {1: 100, 5: 150, 10: 200})
	assert_almost_eq(f.calculate(1), 100.0, 0.001, "at first breakpoint")
	assert_almost_eq(f.calculate(4), 100.0, 0.001, "before second breakpoint")
	assert_almost_eq(f.calculate(5), 150.0, 0.001, "at second breakpoint")
	assert_almost_eq(f.calculate(9), 150.0, 0.001, "before third breakpoint")
	assert_almost_eq(f.calculate(10), 200.0, 0.001, "at third breakpoint")
	assert_almost_eq(f.calculate(100), 200.0, 0.001, "past last breakpoint")

func test_stepped_below_first_breakpoint_returns_base() -> void:
	# No breakpoint at or below the level => falls back to base_value.
	assert_almost_eq(_stepped(50.0, {5: 150}).calculate(1), 50.0, 0.001)

func test_stepped_empty_returns_base() -> void:
	assert_almost_eq(_stepped(77.0, {}).calculate(10), 77.0, 0.001)


# ---- CUSTOM: GDScript expression with `level` and `base_value` ----

func test_custom_evaluates_expression() -> void:
	var f := _custom(100.0, "base_value + (level * 5)")
	assert_almost_eq(f.calculate(1), 105.0, 0.001, "level 1")
	assert_almost_eq(f.calculate(10), 150.0, 0.001, "level 10")

func test_custom_can_use_level_quadratically() -> void:
	assert_almost_eq(_custom(0.0, "level * level").calculate(4), 16.0, 0.001)

func test_custom_empty_formula_returns_base() -> void:
	assert_almost_eq(_custom(7.0, "").calculate(50), 7.0, 0.001)

func test_custom_invalid_formula_falls_back_to_base() -> void:
	# Malformed expression -> calculate() push_errors and returns base_value.
	# The ERROR line printed during this test is expected and asserts graceful
	# degradation (regression guard for the execute-failure fallback).
	assert_almost_eq(_custom(9.0, "this is +/+ not valid").calculate(3), 9.0, 0.001)
