# Unit tests for the boss phase/enrage threshold logic in EnemyBase. These are
# the pure, server-authoritative crossing functions, tested without a full scene:
#   BossPhaseLogic.compute_phase_index(prev_idx, hp_fraction, thresholds)
#   BossPhaseLogic.should_enrage(hp_fraction, enrage_fraction)
extends "res://test/test_case.gd"

# The crossing math lives in a dependency-free helper (boss_phase_logic.gd) so we
# can test it without pulling in the whole EnemyBase compile graph (which, under a
# fresh --script boot, can transiently fail to resolve its dot_visuals.gd preload
# and would then not expose any statics). EnemyBase delegates to this same helper.
const BossPhaseLogic = preload("res://scripts/Enemy/boss_phase_logic.gd")

const THRESHOLDS: Array = [0.66, 0.33]


# --- Phase crossing: feed a descending HP sequence and assert each phase fires
#     exactly once, in order, and never re-fires on a heal-then-redamage. -------

## Drives compute_boss_phase_index across a sequence of HP fractions exactly the
## way EnemyBase._on_boss_health_changed does (monotonic prev_idx tracker that
## fires _enter_boss_phase for each newly-entered index). Returns the ordered
## list of phase indices that fired.
func _run_sequence(fractions: Array, thresholds: Array) -> Array:
	var prev_idx: int = -1
	var fired: Array = []
	for frac in fractions:
		var new_idx: int = BossPhaseLogic.compute_phase_index(prev_idx, frac, thresholds)
		while new_idx > prev_idx:
			prev_idx += 1
			fired.append(prev_idx)
	return fired


func test_no_phase_above_first_threshold() -> void:
	# Full health, light chip — nothing crossed yet.
	assert_eq(BossPhaseLogic.compute_phase_index(-1, 1.0, THRESHOLDS), -1, "full hp")
	assert_eq(BossPhaseLogic.compute_phase_index(-1, 0.8, THRESHOLDS), -1, "above 0.66")


func test_first_phase_fires_at_first_threshold() -> void:
	assert_eq(BossPhaseLogic.compute_phase_index(-1, 0.66, THRESHOLDS), 0, "exactly 0.66")
	assert_eq(BossPhaseLogic.compute_phase_index(-1, 0.5, THRESHOLDS), 0, "between 0.66 and 0.33")


func test_second_phase_fires_at_second_threshold() -> void:
	assert_eq(BossPhaseLogic.compute_phase_index(0, 0.33, THRESHOLDS), 1, "exactly 0.33")
	assert_eq(BossPhaseLogic.compute_phase_index(0, 0.1, THRESHOLDS), 1, "below 0.33")


func test_each_phase_fires_exactly_once_in_order() -> void:
	# A smooth descent should fire [0, 1] in order, once each.
	var fired := _run_sequence([1.0, 0.7, 0.66, 0.5, 0.4, 0.33, 0.2, 0.05], THRESHOLDS)
	assert_eq(fired, [0, 1], "phases fire once each, in order")


func test_phase_does_not_refire_on_heal_then_redamage() -> void:
	# Cross 0.66 (phase 0), heal back to 0.9, re-damage to 0.5 — phase 0 must NOT
	# fire again.
	var fired := _run_sequence([0.5, 0.9, 0.5], THRESHOLDS)
	assert_eq(fired, [0], "phase 0 fires once despite heal+redamage")


func test_big_single_drop_fires_all_passed_phases_in_order() -> void:
	# One hit from full to 0.1 should still fire phase 0 then phase 1 (the
	# while-loop in _on_boss_health_changed walks them in sequence).
	var fired := _run_sequence([1.0, 0.1], THRESHOLDS)
	assert_eq(fired, [0, 1], "both phases fire in order on a single big drop")


func test_empty_thresholds_never_fire() -> void:
	var fired := _run_sequence([1.0, 0.5, 0.1, 0.0], [])
	assert_eq(fired, [], "no thresholds => no phases")


# --- Enrage ----------------------------------------------------------------

func test_enrage_triggers_at_or_below_threshold() -> void:
	assert_true(BossPhaseLogic.should_enrage(0.2, 0.2), "exactly at threshold")
	assert_true(BossPhaseLogic.should_enrage(0.1, 0.2), "below threshold")


func test_enrage_does_not_trigger_above_threshold() -> void:
	assert_false(BossPhaseLogic.should_enrage(0.3, 0.2), "above threshold")
	assert_false(BossPhaseLogic.should_enrage(1.0, 0.2), "full hp")


func test_zero_enrage_threshold_disables_enrage() -> void:
	assert_false(BossPhaseLogic.should_enrage(0.0, 0.0), "0 threshold disables even at 0 hp")
	assert_false(BossPhaseLogic.should_enrage(0.01, 0.0), "0 threshold disables")


# --- Non-boss EnemyData triggers nothing -----------------------------------

func test_non_boss_enemy_data_has_boss_disabled() -> void:
	# A default EnemyData is NOT a boss, so every boss branch is skipped. We can't
	# instance the full EnemyBase scene headlessly here, but we assert the data
	# contract the guards key off of: is_boss defaults false and the threshold
	# list is empty, so even if the logic ran it would fire nothing.
	var ed := EnemyData.new()
	assert_false(ed.is_boss, "default EnemyData is not a boss")
	assert_eq(ed.phase_health_thresholds.size(), 0, "no phase thresholds by default")
	assert_eq(ed.enrage_health_threshold, 0.0, "enrage disabled by default")
	# And the pure logic confirms: empty thresholds + 0 enrage => nothing fires.
	assert_eq(_run_sequence([1.0, 0.5, 0.1], ed.phase_health_thresholds), [], "no phases for non-boss")
	assert_false(BossPhaseLogic.should_enrage(0.05, ed.enrage_health_threshold), "no enrage for non-boss")


func test_eternal_warlord_is_configured_as_boss() -> void:
	# Sanity-check the upgraded .tres parses and carries the boss contract.
	var ed: EnemyData = load("res://resources/Enemies/EternalWarlord/ED_EternalWarlord.tres")
	assert_not_null(ed, "Eternal Warlord EnemyData loads")
	assert_true(ed.is_boss, "Eternal Warlord is a boss")
	assert_eq(ed.boss_title, "Eternal Warlord", "boss title set")
	assert_eq(ed.phase_health_thresholds.size(), 2, "two phase thresholds")
	assert_almost_eq(ed.enrage_health_threshold, 0.2, 0.0001, "enrage at 0.2")
	assert_almost_eq(ed.special_attack_radius, 140.0, 0.0001, "special radius 140")
