# Unit tests for the status-tag synergy layer (ADR 0013) — EnemyStatus tag
# aggregation, consume semantics (incl. the chill speed-restore invariant),
# and the three escalation rules (Thermal Shock / Septic / Brittle).
#
# Stubs are plain Nodes: the registry works on metas alone, and the
# escalations only need a `health_component` property with take_damage().
# EventJuice calls inside escalations no-op safely here (no active maps),
# which doubles as coverage for its invalid-context guard.
extends "res://test/test_case.gd"

const EnemyStatus = preload("res://scripts/Gameplay/enemy_status.gd")


class _FakeHealth extends Node:
	var is_dead := false
	var max_health := 1000
	var hits: Array = []
	func take_damage(amount: int, _source, _ignore_armor := false, _is_crit := false, _bypass := false) -> void:
		hits.append(amount)


class _FakeEnemy extends Node:
	var health_component: Node = null
	var movement_speed: float = 60.0
	var animated_sprite = null


func _make_enemy() -> _FakeEnemy:
	var e := _FakeEnemy.new()
	var hc := _FakeHealth.new()
	e.add_child(hc)
	e.health_component = hc
	# In the tree so is_instance_valid + (potential) timers behave like prod.
	(Engine.get_main_loop() as SceneTree).root.add_child(e)
	return e


func _cleanup(e: Node) -> void:
	if is_instance_valid(e):
		e.queue_free()


# ── Tag aggregation ──────────────────────────────────────────────────────────

func test_known_key_counts_without_register() -> void:
	# KNOWN_KEYS is the safety net: a meta written by an applier that never
	# called register() must still be queryable.
	var e := _make_enemy()
	e.set_meta("hemorrhage_bleed", {"stacks": 3, "per_tick": 5})
	assert_true(EnemyStatus.has_tag(e, EnemyStatus.TAG_BLEED), "known key should count")
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_BLEED), 3)
	_cleanup(e)


func test_stacks_sum_across_sources() -> void:
	var e := _make_enemy()
	e.set_meta("hemorrhage_bleed", {"stacks": 2})
	e.set_meta("barbed_shot_bleed", {"stacks": 3})
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_BLEED), 5, "sources SUM per ADR 0013")
	_cleanup(e)


func test_dynamically_registered_key_counts() -> void:
	# A key outside KNOWN_KEYS becomes queryable through the index meta.
	var e := _make_enemy()
	e.set_meta("modded_bleed_xyz", {"stacks": 2})
	EnemyStatus.register(e, EnemyStatus.TAG_BLEED, "modded_bleed_xyz")
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_BLEED), 2)
	_cleanup(e)


func test_mark_expiry_is_lazy_pruned() -> void:
	var e := _make_enemy()
	var now: int = Time.get_ticks_msec()
	e.set_meta("sentinels_mark_remaining", now + 60000)
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_MARK), 1, "live mark = 1 stack")
	e.set_meta("sentinels_mark_remaining", now - 1)
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_MARK), 0, "stale mark = 0")
	assert_false(e.has_meta("sentinels_mark_remaining"), "stale mark meta is pruned on read")
	_cleanup(e)


func test_non_dict_meta_counts_as_one_stack() -> void:
	var e := _make_enemy()
	e.set_meta("caltrops_slow", 60.0)  # chill keys store the pre-slow speed
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_CHILL), 1)
	_cleanup(e)


# ── Consume semantics ────────────────────────────────────────────────────────

func test_consume_returns_total_and_clears() -> void:
	var e := _make_enemy()
	e.set_meta("hemorrhage_bleed", {"stacks": 2})
	e.set_meta("barbed_shot_bleed", {"stacks": 3})
	assert_eq(EnemyStatus.consume_tag(e, EnemyStatus.TAG_BLEED), 5)
	assert_false(e.has_meta("hemorrhage_bleed"))
	assert_false(e.has_meta("barbed_shot_bleed"))
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_BLEED), 0)
	_cleanup(e)


func test_consume_chill_restores_movement_speed() -> void:
	# Chill keys hold the pre-slow speed; consuming must restore it or the
	# pending restore timer would no-op and leave the enemy slowed forever.
	var e := _make_enemy()
	e.movement_speed = 36.0
	e.set_meta("upgrade_slow_on_hit", 60.0)
	EnemyStatus.consume_tag(e, EnemyStatus.TAG_CHILL)
	assert_almost_eq(e.movement_speed, 60.0, 0.001, "consume must restore the saved base speed")
	assert_false(e.has_meta("upgrade_slow_on_hit"))
	_cleanup(e)


func test_consume_empty_tag_is_zero_noop() -> void:
	var e := _make_enemy()
	assert_eq(EnemyStatus.consume_tag(e, EnemyStatus.TAG_BURN), 0)
	_cleanup(e)


# ── Escalation: Thermal Shock ────────────────────────────────────────────────

func test_chill_on_burning_enemy_detonates() -> void:
	var e := _make_enemy()
	e.set_meta("immolate_burn", {"stacks": 2, "per_tick": 10})
	e.set_meta("upgrade_slow_on_hit", 60.0)
	EnemyStatus.register(e, EnemyStatus.TAG_CHILL, "upgrade_slow_on_hit")

	# burst = per_tick(10) x stacks(2) x THERMAL_SHOCK_TICKS
	var expected: int = 10 * 2 * EnemyStatus.THERMAL_SHOCK_TICKS
	assert_eq(e.health_component.hits, [expected], "burn's next ticks paid as one burst")
	assert_false(e.has_meta("immolate_burn"), "burn consumed")
	assert_false(e.has_meta("upgrade_slow_on_hit"), "chill consumed")
	assert_almost_eq(e.movement_speed, 60.0, 0.001, "chill consume restored speed")
	_cleanup(e)


func test_burn_on_chilled_enemy_also_detonates() -> void:
	var e := _make_enemy()
	e.set_meta("staff_element_chill", 60.0)
	e.set_meta("pyre_burst_burn", {"stacks": 1, "per_tick": 7})
	EnemyStatus.register(e, EnemyStatus.TAG_BURN, "pyre_burst_burn")
	assert_eq(e.health_component.hits, [7 * EnemyStatus.THERMAL_SHOCK_TICKS])
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_BURN), 0)
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_CHILL), 0)
	_cleanup(e)


func test_chill_without_burn_does_not_detonate() -> void:
	var e := _make_enemy()
	e.set_meta("upgrade_slow_on_hit", 60.0)
	EnemyStatus.register(e, EnemyStatus.TAG_CHILL, "upgrade_slow_on_hit")
	assert_true(e.health_component.hits.is_empty(), "no burn = no burst")
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_CHILL), 1, "chill stays applied")
	_cleanup(e)


# ── Escalation: Septic ───────────────────────────────────────────────────────

func test_poison_on_bleeding_enemy_ticks_harder_once() -> void:
	var e := _make_enemy()
	e.set_meta("hemorrhage_bleed", {"stacks": 1, "per_tick": 5})
	e.set_meta("envenom_poison", {"stacks": 1, "per_tick": 10})
	EnemyStatus.register(e, EnemyStatus.TAG_POISON, "envenom_poison")

	var state: Dictionary = e.get_meta("envenom_poison")
	assert_eq(int(state["per_tick"]), int(round(10 * EnemyStatus.SEPTIC_MULT)), "poison amplified")
	assert_true(bool(state.get("septic", false)), "septic flag set")

	# A second registration of the SAME application must not compound.
	EnemyStatus.register(e, EnemyStatus.TAG_POISON, "envenom_poison")
	assert_eq(int(e.get_meta("envenom_poison")["per_tick"]), int(round(10 * EnemyStatus.SEPTIC_MULT)), "no double-dip")
	_cleanup(e)


func test_poison_without_bleed_is_unchanged() -> void:
	var e := _make_enemy()
	e.set_meta("envenom_poison", {"stacks": 1, "per_tick": 10})
	EnemyStatus.register(e, EnemyStatus.TAG_POISON, "envenom_poison")
	assert_eq(int(e.get_meta("envenom_poison")["per_tick"]), 10)
	_cleanup(e)


# ── Escalation: Brittle ──────────────────────────────────────────────────────

func test_bleed_threshold_on_marked_enemy_goes_brittle() -> void:
	var e := _make_enemy()
	e.set_meta("death_mark_remaining", Time.get_ticks_msec() + 60000)
	e.set_meta("hemorrhage_bleed", {"stacks": EnemyStatus.BRITTLE_BLEED_STACKS, "per_tick": 5})
	EnemyStatus.register(e, EnemyStatus.TAG_BLEED, "hemorrhage_bleed")

	assert_true(e.has_meta(EnemyStatus.BRITTLE_META), "next hit primed to crit")
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_MARK), 0, "mark consumed by Brittle")
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_BLEED), EnemyStatus.BRITTLE_BLEED_STACKS, "bleed NOT consumed")
	_cleanup(e)


func test_bleed_below_threshold_does_not_trigger_brittle() -> void:
	var e := _make_enemy()
	e.set_meta("death_mark_remaining", Time.get_ticks_msec() + 60000)
	e.set_meta("hemorrhage_bleed", {"stacks": EnemyStatus.BRITTLE_BLEED_STACKS - 1, "per_tick": 5})
	EnemyStatus.register(e, EnemyStatus.TAG_BLEED, "hemorrhage_bleed")
	assert_false(e.has_meta(EnemyStatus.BRITTLE_META))
	assert_eq(EnemyStatus.stack_count(e, EnemyStatus.TAG_MARK), 1, "mark untouched below threshold")
	_cleanup(e)


func test_bleed_threshold_without_mark_does_nothing() -> void:
	var e := _make_enemy()
	e.set_meta("hemorrhage_bleed", {"stacks": EnemyStatus.BRITTLE_BLEED_STACKS + 2, "per_tick": 5})
	EnemyStatus.register(e, EnemyStatus.TAG_BLEED, "hemorrhage_bleed")
	assert_false(e.has_meta(EnemyStatus.BRITTLE_META))
	_cleanup(e)


# ── Guards ───────────────────────────────────────────────────────────────────

func test_registry_is_null_safe() -> void:
	assert_eq(EnemyStatus.stack_count(null, EnemyStatus.TAG_BLEED), 0)
	assert_eq(EnemyStatus.consume_tag(null, EnemyStatus.TAG_BLEED), 0)
	EnemyStatus.register(null, EnemyStatus.TAG_BLEED, "x")  # must not crash
	assert_true(true, "null target paths are no-ops")
