# Unit tests for AbilityData — level-stat lookup with bounds clamping and the
# tooltip placeholder substitution ($[damage_percent], etc.).
extends "res://test/test_case.gd"

func _flat(base: float, per_level: float) -> AbilityScalingFormula:
	var f := AbilityScalingFormula.new()
	f.scaling_type = AbilityScalingFormula.ScalingType.FLAT
	f.base_value = base
	f.per_level = per_level
	return f

func _make_ability(max_level: int) -> AbilityData:
	var ability := AbilityData.new()
	ability.ability_name = "Power Strike"
	ability.ability_type = Constants.AbilityType.ACTIVE
	ability.max_level = max_level
	var scaling := AbilityScalingData.new()
	scaling.damage_percent_formula = _flat(150.0, 10.0)
	scaling.mana_cost_formula = _flat(20.0, 0.0)
	scaling.cooldown_formula = _flat(3.0, 0.0)
	ability.scaling_data = scaling
	return ability


func test_get_level_stats_below_one_is_null() -> void:
	assert_null(_make_ability(10).get_level_stats(0))

func test_get_level_stats_above_max_is_null() -> void:
	assert_null(_make_ability(10).get_level_stats(11))

func test_get_level_stats_valid_level_returns_data() -> void:
	var stats := _make_ability(10).get_level_stats(5)
	assert_not_null(stats, "level 5 within range")
	assert_eq(stats.level, 5)
	assert_eq(stats.damage_percent, 190, "150 + (5-1)*10")

func test_get_level_stats_at_max_level_is_valid() -> void:
	assert_not_null(_make_ability(10).get_level_stats(10))

func test_get_level_stats_without_scaling_data_is_null() -> void:
	# Misconfigured ability (no scaling_data) returns null rather than crashing.
	# The ERROR line printed below is the expected push_error guard.
	var ability := AbilityData.new()
	ability.max_level = 5
	ability.scaling_data = null
	assert_null(ability.get_level_stats(1))

func test_tooltip_substitutes_damage_placeholder() -> void:
	var ability := _make_ability(10)
	ability.description = "Deals $[damage_percent] damage to one enemy."
	var tooltip := ability.get_tooltip_text(1)
	assert_true("150%" in tooltip, "placeholder replaced with level-1 value")
	assert_false("$[damage_percent]" in tooltip, "raw placeholder removed")

func test_tooltip_shows_level_line_when_learned() -> void:
	var tooltip := _make_ability(10).get_tooltip_text(3)
	assert_true("Level 3 / 10" in tooltip, "current/max level shown")

func test_tooltip_unlearned_uses_level_one_preview() -> void:
	# At level 0 the line says Unlearned but placeholders preview level-1 values.
	var ability := _make_ability(10)
	ability.description = "Deals $[damage_percent] damage."
	var tooltip := ability.get_tooltip_text(0)
	assert_true("Unlearned" in tooltip, "marked unlearned")
	assert_true("150%" in tooltip, "still previews level-1 damage")
