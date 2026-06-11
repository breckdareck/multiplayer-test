# Integration test for the pairtest build pipeline: mounts the REAL
# Leveling/WeaponMastery/Stats/Ability component stack, caps mastery on two
# disciplines (the legit 100-point pools), then runs the command's own spend
# helper against the sword|dagger tables. Guards the whole chain the unit
# tests can't see: mastery -> point grants, learn/level gates, upgrade
# purchase validation, and the budget actually covering the curated build.
extends "res://test/test_case.gd"

const SWORD := Constants.ClassType.SWORD
const DAGGER := Constants.ClassType.DAGGER


class _PlayerStub extends Node:
	var player_id: int = -1   # bot path: skips client sync RPCs throughout


func _mount() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var mp := tree.get_multiplayer()
	if not (mp.multiplayer_peer is OfflineMultiplayerPeer):
		mp.multiplayer_peer = OfflineMultiplayerPeer.new()

	var player := _PlayerStub.new()
	var leveling = load("res://scripts/Components/level.gd").new()
	leveling.name = "Leveling"
	leveling._is_loading_data = true
	player.add_child(leveling)
	var wm = load("res://scripts/Components/weapon_mastery.gd").new()
	wm.name = "WeaponMastery"
	player.add_child(wm)
	# Components read `owner.player_id` for the bot-vs-client sync guard -
	# an unset owner aborts grant_mastery_xp_server mid-function (level ticks,
	# points never granted). Caught by this very test's first failure.
	wm.owner = player
	leveling.owner = player
	var stats = load("res://scripts/Components/stats.gd").new()
	stats.name = "Stats"
	player.add_child(stats)
	stats.owner = player
	stats._level_component = leveling
	stats._weapon_mastery_component = wm
	stats._loading_mode = true
	var ac = load("res://scripts/Components/ability.gd").new()
	ac.name = "Ability"
	player.add_child(ac)
	ac.owner = player
	tree.root.add_child(player)
	leveling.level = 100
	wm.primary_discipline = SWORD
	return {"player": player, "wm": wm, "ac": ac}


func _cap_mastery(ctx: Dictionary, disc: int) -> void:
	var wm = ctx.wm
	while wm.get_mastery_level(disc) < WeaponMasteryComponent.MASTERY_CAP:
		wm.grant_mastery_xp_server(disc, wm.get_xp_to_next_level(disc))


func test_capped_mastery_grants_exactly_100_points_per_discipline() -> void:
	var ctx := _mount()
	_cap_mastery(ctx, SWORD)
	_cap_mastery(ctx, DAGGER)
	assert_eq(int(ctx.ac.get_available_points_for_discipline("sword")), 100,
		"MASTERY_CAP x ABILITY_POINTS_PER_MASTERY_LEVEL must equal the legit budget")
	assert_eq(int(ctx.ac.get_available_points_for_discipline("dagger")), 100)
	ctx.player.queue_free()


func test_sword_dagger_build_executes_within_budget() -> void:
	var ctx := _mount()
	_cap_mastery(ctx, SWORD)
	_cap_mastery(ctx, DAGGER)
	var ac = ctx.ac

	var panel = load("res://scripts/UI/debug_panel.gd").new()
	var consts: Dictionary = panel.get_script().get_script_constant_map()
	var rm = (Engine.get_main_loop() as SceneTree).root.get_node("/root/ResourceManager")

	for pair in [["sword|dagger", "sword"], ["dagger|sword", "dagger"]]:
		var names: Array = []
		names.append_array(consts["PAIRTEST_LOADOUTS"][pair[0]])
		names.append_array(consts["PAIRTEST_PASSIVES"][pair[1]])
		for n in names:
			panel._pairtest_build_ability(ac, String(n))

	# Every curated ACTIVE must be at max level with its upgrade line bought.
	for pair_key in ["sword|dagger", "dagger|sword"]:
		for n in consts["PAIRTEST_LOADOUTS"][pair_key]:
			var ability = rm.get_ability_data(String(n))
			assert_eq(int(ac.get_ability_level(ability.ability_id)), int(ability.max_level),
				"'%s' must reach max level on the legit budget" % n)
			var owned := 0
			for up in ability.upgrades:
				if up != null and ac.has_upgrade(ability.ability_id, up.upgrade_id):
					owned += 1
			assert_true(owned >= 3, "'%s' must own T1+T2+one T3 (owned %d)" % [n, owned])

	# Budget discipline: never negative, duo threshold met on both sides.
	for key in ["sword", "dagger"]:
		var left: int = int(ac.get_available_points_for_discipline(key))
		var spent: int = int(ac.get_points_spent_in_discipline(key))
		assert_true(left >= 0, "%s pool must never go negative (left %d)" % [key, left])
		assert_true(spent <= 100, "%s spent %d exceeds the legit budget" % [key, spent])
		assert_true(spent >= 30, "%s spent %d - duo threshold (30) must be met" % [key, spent])

	panel.free()
	ctx.player.queue_free()
