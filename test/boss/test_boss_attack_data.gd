# Unit tests for the BossAttackData data layer: EnemyData.get_special_attacks()
# returns authored attacks when present, else synthesises one dash-slam from the
# legacy special_attack_* fields (so pre-BossAttackData bosses keep working).
extends "res://test/test_case.gd"


func _legacy_enemy() -> EnemyData:
	var ed := EnemyData.new()
	ed.is_boss = true
	ed.special_attack_cooldown = 8.0
	ed.special_telegraph_time = 1.3
	ed.special_attack_radius = 100.0
	ed.special_attack_damage_mult = 2.5
	return ed


func test_legacy_synth_when_no_authored_attacks() -> void:
	var ed := _legacy_enemy()
	var attacks := ed.get_special_attacks()
	assert_eq(attacks.size(), 1, "one synthesised attack")
	var a: BossAttackData = attacks[0]
	assert_eq(a.shape, BossAttackData.Shape.RECT, "synth is a RECT slam")
	assert_almost_eq(a.reach, 200.0, 0.001, "reach = radius*2")
	assert_eq(a.movement, BossAttackData.Movement.DASH, "synth dashes")
	assert_almost_eq(a.cooldown, 8.0, 0.001, "cooldown from legacy")
	assert_almost_eq(a.hit_time, 1.3, 0.001, "hit_time from telegraph")
	assert_almost_eq(a.damage_mult, 2.5, 0.001, "damage mult from legacy")
	assert_eq(a.anim_mode, BossAttackData.AnimMode.STRETCH, "synth stretches the anim")


func test_no_special_when_cooldown_zero() -> void:
	var ed := _legacy_enemy()
	ed.special_attack_cooldown = 0.0
	assert_eq(ed.get_special_attacks().size(), 0, "cooldown 0 = no special")


func test_authored_attacks_win_over_legacy() -> void:
	var ed := _legacy_enemy()
	var breath := BossAttackData.new()
	breath.attack_name = "Fire Breath"
	breath.shape = BossAttackData.Shape.CONE
	breath.cone_angle_deg = 60.0
	ed.special_attacks = [breath]
	var attacks := ed.get_special_attacks()
	assert_eq(attacks.size(), 1, "authored list returned verbatim")
	assert_eq(attacks[0].shape, BossAttackData.Shape.CONE, "authored cone, not legacy synth")
	assert_eq(attacks[0].attack_name, "Fire Breath", "identity preserved")


func test_authored_supports_multiple_attacks() -> void:
	var ed := _legacy_enemy()
	var slam := BossAttackData.new()
	var nova := BossAttackData.new()
	nova.shape = BossAttackData.Shape.CIRCLE
	ed.special_attacks = [slam, nova]
	assert_eq(ed.get_special_attacks().size(), 2, "multiple attacks per boss")
