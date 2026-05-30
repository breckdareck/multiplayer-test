# Unit tests for AbilityScalingData.generate_level_data() — composes the
# per-stat formulas into a single AbilityLevelData for a given level.
extends "res://test/test_case.gd"

func _flat(base: float, per_level: float) -> AbilityScalingFormula:
	var f := AbilityScalingFormula.new()
	f.scaling_type = AbilityScalingFormula.ScalingType.FLAT
	f.base_value = base
	f.per_level = per_level
	return f


func test_generated_level_is_tagged() -> void:
	var data := AbilityScalingData.new()
	var level_data := data.generate_level_data(5)
	assert_eq(level_data.level, 5)

func test_basic_stats_are_generated_from_formulas() -> void:
	var data := AbilityScalingData.new()
	data.mana_cost_formula = _flat(10.0, 2.0)
	data.cooldown_formula = _flat(5.0, -0.1)
	data.damage_percent_formula = _flat(100.0, 8.0)

	var l1 := data.generate_level_data(1)
	assert_eq(l1.mana_cost, 10, "mana L1")
	assert_almost_eq(l1.cooldown_time, 5.0, 0.001, "cooldown L1")
	assert_eq(l1.damage_percent, 100, "damage L1")

	var l5 := data.generate_level_data(5)
	assert_eq(l5.mana_cost, 18, "mana L5")
	assert_almost_eq(l5.cooldown_time, 4.6, 0.001, "cooldown L5")
	assert_eq(l5.damage_percent, 132, "damage L5")

func test_int_stats_truncate_fractional_values() -> void:
	# mana_cost is an int; 10.5 must become 10, not round to 11.
	var data := AbilityScalingData.new()
	data.mana_cost_formula = _flat(10.0, 0.5)
	assert_eq(data.generate_level_data(2).mana_cost, 10)

func test_absent_formulas_keep_level_data_defaults() -> void:
	# A scaling config with no formulas yields the AbilityLevelData defaults.
	var level_data := AbilityScalingData.new().generate_level_data(1)
	assert_eq(level_data.mana_cost, 0, "default mana")
	assert_eq(level_data.damage_percent, 100, "default damage")
	assert_eq(level_data.max_targets, 1, "default targets")
	assert_eq(level_data.max_hits, 1, "default hits")
	assert_almost_eq(level_data.cooldown_time, 0.0, 0.001, "default cooldown")

func test_stat_bonus_formula_populates_stat_bonuses() -> void:
	var sbf := StatBonusFormula.new()
	sbf.stat_type = Constants.StatType.STRENGTH
	sbf.flat_bonus_formula = _flat(5.0, 1.0)  # L1 = 5, L3 = 7

	var data := AbilityScalingData.new()
	data.stat_bonus_formulas = [sbf]

	var level_data := data.generate_level_data(3)
	assert_true(level_data.stat_bonuses.has(Constants.StatType.STRENGTH), "STRENGTH key present")
	var stat: StatData = level_data.stat_bonuses[Constants.StatType.STRENGTH]
	assert_eq(stat.flat_bonus_value, 7, "flat STR bonus at L3")

func test_proc_is_generated_when_event_type_set() -> void:
	var data := AbilityScalingData.new()
	data.proc_event_type = "on_hit"
	data.proc_chance_formula = _flat(0.1, 0.01)
	data.proc_damage_formula = _flat(50.0, 5.0)

	var level_data := data.generate_level_data(1)
	assert_not_null(level_data.on_hit_proc, "on_hit proc generated")
	assert_almost_eq(level_data.on_hit_proc.proc_chance, 0.1, 0.001, "proc chance")
	assert_eq(level_data.on_hit_proc.damage_percent, 50, "proc damage")

func test_no_proc_without_event_type() -> void:
	# A chance formula alone, with no proc_event_type, generates nothing.
	var data := AbilityScalingData.new()
	data.proc_chance_formula = _flat(0.5, 0.0)
	var level_data := data.generate_level_data(1)
	assert_null(level_data.on_hit_proc, "no proc when event type empty")
