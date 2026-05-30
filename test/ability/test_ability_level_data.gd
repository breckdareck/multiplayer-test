# Unit tests for AbilityLevelData — the per-level stat bundle: modifier getters
# (default 1.0 multipliers) and proc event resolution.
extends "res://test/test_case.gd"

func test_constructor_sets_level() -> void:
	assert_eq(AbilityLevelData.new(7).level, 7)

func test_default_level_is_one() -> void:
	assert_eq(AbilityLevelData.new().level, 1)

func test_modifier_getters_default_to_identity() -> void:
	# Abilities not present in the modifier dicts return a 1.0 multiplier so
	# unmodified abilities are unaffected.
	var data := AbilityLevelData.new(1)
	assert_almost_eq(data.get_ability_damage_modifier("unknown"), 1.0, 0.001, "damage")
	assert_almost_eq(data.get_ability_cooldown_modifier("unknown"), 1.0, 0.001, "cooldown")
	assert_almost_eq(data.get_ability_mana_modifier("unknown"), 1.0, 0.001, "mana")

func test_modifier_getters_return_configured_value() -> void:
	var data := AbilityLevelData.new(1)
	data.ability_damage_modifiers["fireball"] = 1.5
	data.ability_cooldown_modifiers["fireball"] = 0.8
	assert_almost_eq(data.get_ability_damage_modifier("fireball"), 1.5, 0.001, "damage")
	assert_almost_eq(data.get_ability_cooldown_modifier("fireball"), 0.8, 0.001, "cooldown")
	assert_almost_eq(data.get_ability_damage_modifier("other"), 1.0, 0.001, "unrelated stays 1.0")

func test_try_proc_event_returns_proc_when_chance_certain() -> void:
	var data := AbilityLevelData.new(1)
	var proc := ProcEffectData.new()
	proc.proc_chance = 1.0  # randf() < 1.0 is always true => deterministic
	data.on_hit_proc = proc
	assert_eq(data.try_proc_event("on_hit"), proc)

func test_try_proc_event_returns_null_when_chance_zero() -> void:
	var data := AbilityLevelData.new(1)
	var proc := ProcEffectData.new()
	proc.proc_chance = 0.0
	data.on_hit_proc = proc
	assert_null(data.try_proc_event("on_hit"))

func test_try_proc_event_unknown_event_returns_null() -> void:
	var data := AbilityLevelData.new(1)
	assert_null(data.try_proc_event("on_nonexistent_event"))

func test_try_proc_event_routes_by_event_type() -> void:
	# A proc on on_crit must not fire for an on_hit query.
	var data := AbilityLevelData.new(1)
	var crit_proc := ProcEffectData.new()
	crit_proc.proc_chance = 1.0
	data.on_crit_proc = crit_proc
	assert_eq(data.try_proc_event("on_crit"), crit_proc, "on_crit resolves")
	assert_null(data.try_proc_event("on_hit"), "on_hit has no proc")
