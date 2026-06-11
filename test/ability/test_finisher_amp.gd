# The first-target-only finisher amp (docs/sword_outlier_review.md, O1):
# the staged pending_ability_damage_multiplier latches onto the cast's first
# target and only that target's rolls are amplified. Pure member-state logic
# on CombatComponent, so a bare instance suffices.
extends "res://test/test_case.gd"

const CombatScript = preload("res://scripts/Components/combat.gd")


func _combat():
	var c = CombatScript.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(c)
	return c


func test_no_amp_staged_allows_everyone() -> void:
	var c = _combat()
	var a := Node.new()
	var b := Node.new()
	assert_true(c._amp_allowed_for(a), "mult 1.0 = nothing staged, no gating")
	assert_true(c._amp_allowed_for(b))
	assert_null(c._amp_target, "no latch when nothing staged")
	a.free(); b.free(); c.queue_free()


func test_amp_latches_first_target_only() -> void:
	var c = _combat()
	c.pending_ability_damage_multiplier = 4.0
	var first := Node.new()
	var second := Node.new()
	assert_true(c._amp_allowed_for(first), "first target seen gets the amp")
	assert_false(c._amp_allowed_for(second), "second target rolls base damage")
	assert_true(c._amp_allowed_for(first), "repeat rolls on the first target stay amped (multi-hit)")
	first.free(); second.free(); c.queue_free()


func test_amp_target_clears_with_cast_reset() -> void:
	var c = _combat()
	c.pending_ability_damage_multiplier = 4.0
	var first := Node.new()
	c._amp_allowed_for(first)
	# the cast-end reset clears both the multiplier and the latch
	c.pending_ability_damage_multiplier = 1.0
	c._amp_target = null
	c.pending_ability_damage_multiplier = 2.0
	var next_cast := Node.new()
	assert_true(c._amp_allowed_for(next_cast), "next cast latches a fresh primary target")
	first.free(); next_cast.free(); c.queue_free()


func test_freed_latch_relatches() -> void:
	var c = _combat()
	c.pending_ability_damage_multiplier = 4.0
	var first := Node.new()
	c._amp_allowed_for(first)
	first.free()
	var second := Node.new()
	assert_true(c._amp_allowed_for(second), "a freed primary target re-latches (e.g. it died mid-cast)")
	second.free(); c.queue_free()
