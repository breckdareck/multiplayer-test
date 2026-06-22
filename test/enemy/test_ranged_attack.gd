# Unit tests for the ranged-attack delivery layer (ADR-0016): a RANGED / MAGIC
# enemy fires a homing projectile and only engages targets within attack_range
# horizontally and ±1 tile vertically. The RabbitWizard vertical slice is wired
# as a MAGIC caster.
extends "res://test/test_case.gd"

const TILE := 16.0


func test_melee_default_is_unchanged() -> void:
	# A plain enemy defaults to MELEE so existing content is untouched.
	var ed := EnemyData.new()
	assert_eq(ed.attack_type, Constants.AttackType.MELEE, "attack_type defaults to MELEE")


func test_projectile_speed_has_a_sane_default() -> void:
	var ed := EnemyData.new()
	assert_true(ed.ranged_projectile_speed > 0.0, "projectile speed defaults positive")
	assert_null(ed.ranged_projectile_scene, "null scene = use the shared default projectile")


func test_attack_box_same_platform_and_one_tile() -> void:
	var from := Vector2(100, 100)
	var rng := 150.0
	# Same platform, in horizontal range.
	assert_true(EnemyBase.position_in_attack_box(from, Vector2(220, 100), rng), "same platform, within range")
	# Exactly one tile up / down passes (the ±1 slack).
	assert_true(EnemyBase.position_in_attack_box(from, Vector2(120, 100 - TILE), rng), "one tile up engages")
	assert_true(EnemyBase.position_in_attack_box(from, Vector2(120, 100 + TILE), rng), "one tile down engages")


func test_attack_box_rejects_two_tiles_and_out_of_range() -> void:
	var from := Vector2(100, 100)
	var rng := 150.0
	# Two tiles up/down is out — the whole point of the clamp.
	assert_false(EnemyBase.position_in_attack_box(from, Vector2(120, 100 - 2 * TILE), rng), "two tiles up is out")
	assert_false(EnemyBase.position_in_attack_box(from, Vector2(120, 100 + 2 * TILE), rng), "two tiles down is out")
	# Beyond horizontal range is out even on the same platform.
	assert_false(EnemyBase.position_in_attack_box(from, Vector2(100 + rng + 10, 100), rng), "out of horizontal range")


func test_leaper_defaults_off() -> void:
	var ed := EnemyData.new()
	assert_false(ed.is_leaper, "is_leaper defaults off — existing enemies don't hop")


func test_boar_is_a_leaper() -> void:
	# Locks the charger config: the Boar is the ribbon-pig leaper.
	var ed: EnemyData = load("res://resources/Enemies/Boar/ED_Boar.tres")
	assert_not_null(ed, "Boar EnemyData loads")
	assert_true(ed.is_leaper, "Boar hops to follow the player")
	assert_true(ed.is_aggressive, "Boar actively chases")


func test_blocker_defaults_off() -> void:
	var ed := EnemyData.new()
	assert_false(ed.is_blocker, "is_blocker defaults off")


func test_sw_knight_is_an_armored_blocker() -> void:
	# Locks the blocker config: ARMORED archetype + the block flag, and the
	# SpriteFrames actually has the "block" clip the guard state plays.
	var ed: EnemyData = load("res://resources/Enemies/SWKnight/ED_SWKnight.tres")
	assert_not_null(ed, "SWKnight EnemyData loads")
	assert_true(ed.is_blocker, "SWKnight raises a guard")
	assert_eq(ed.archetype, Constants.MonsterArchetype.ARMORED, "armored profile")
	assert_not_null(ed.sprite_frames, "has SpriteFrames")
	assert_true(ed.sprite_frames.has_animation("block"), "SpriteFrames has a 'block' clip")
	assert_true(ed.sprite_frames.has_animation("attack_1"), "SpriteFrames has the attack clip")


func test_sw_knight_scene_loads() -> void:
	# The cloned scene parses and its ext_resources (ED, SF) resolve.
	var scene: PackedScene = load("res://scenes/NPC/sw_knight.tscn")
	assert_not_null(scene, "sw_knight.tscn loads as a PackedScene")


func test_dev_test_map_loads_with_knight() -> void:
	# The dev_test map parses with the SW Knight instance placed under Enemies.
	var scene: PackedScene = load("res://scenes/Levels/dev_test.tscn")
	assert_not_null(scene, "dev_test.tscn loads with the placed Knight")


func test_splitter_defaults_off_with_bounded_cascade() -> void:
	var ed := EnemyData.new()
	assert_false(ed.is_splitter, "is_splitter defaults off")
	assert_true(ed.split_count >= 1, "spawns at least one child when on")
	assert_eq(ed.split_generations, 1, "cascade defaults bounded to one generation")


func test_slime_is_a_splitter() -> void:
	var ed: EnemyData = load("res://resources/Enemies/Slime/ED_Slime.tres")
	assert_not_null(ed, "Slime EnemyData loads")
	assert_true(ed.is_splitter, "Slime splits on death")


func test_exploder_defaults_off() -> void:
	var ed := EnemyData.new()
	assert_false(ed.is_exploder, "is_exploder defaults off")
	assert_true(ed.explode_radius > 0.0, "has a burst radius when on")


func test_fire_slime_is_an_aggressive_exploder() -> void:
	var ed: EnemyData = load("res://resources/Enemies/FireSlime/ED_FireSlime.tres")
	assert_not_null(ed, "FireSlime EnemyData loads")
	assert_true(ed.is_exploder, "FireSlime bursts on death")
	assert_true(ed.is_aggressive, "FireSlime rushes in")


func test_feral_hare_is_a_fast_glass_swarmer() -> void:
	var ed: EnemyData = load("res://resources/Enemies/FeralHare/ED_FeralHare.tres")
	assert_not_null(ed, "FeralHare EnemyData loads")
	assert_eq(ed.archetype, Constants.MonsterArchetype.GLASS, "fragile GLASS profile")
	assert_true(ed.is_aggressive, "rushes the player")
	assert_true(ed.movement_speed >= 70.0, "fast")


func test_rabbit_wizard_is_a_ranged_magic_caster() -> void:
	# Locks the vertical-slice config: ranged MAGIC delivery, magic damage axis,
	# and an engagement range that reads as ranged without being excessive.
	var ed: EnemyData = load("res://resources/Enemies/RabbitWizard/ED_RabbitWizard.tres")
	assert_not_null(ed, "RabbitWizard EnemyData loads")
	assert_eq(ed.attack_type, Constants.AttackType.MAGIC, "delivers a ranged MAGIC attack")
	assert_true(ed.is_magic_attacker, "damage axis is magic")
	assert_true(ed.attack_range >= 120.0 and ed.attack_range <= 170.0, "ranged but not excessive")
