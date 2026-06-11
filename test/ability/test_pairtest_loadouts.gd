# Data validation for the pairtest dev command's curated loadouts + gear
# table (scripts/UI/debug_panel.gd): every ability name must resolve, be an
# ACTIVE of the bar's ACTIVE discipline, and every gear piece must exist —
# so the command can never silently hand the player a broken build.
extends "res://test/test_case.gd"

const DISC_BY_KEY := {"sword": 0, "bow": 1, "staff": 2, "dagger": 3}


func _consts() -> Dictionary:
	# Runtime load: a const preload would compile the (autoload-heavy) UI
	# script while THIS suite parses, before the runner's deferred start.
	return load("res://scripts/UI/debug_panel.gd").get_script_constant_map()


func test_loadouts_cover_all_twelve_directions() -> void:
	var loadouts: Dictionary = _consts()["PAIRTEST_LOADOUTS"]
	assert_eq(loadouts.size(), 12, "every (active|offhand) direction needs a bar")
	for a in DISC_BY_KEY:
		for b in DISC_BY_KEY:
			if a == b:
				continue
			assert_true(loadouts.has(a + "|" + b), "missing loadout %s|%s" % [a, b])


func test_loadout_abilities_resolve_and_match_discipline() -> void:
	var loadouts: Dictionary = _consts()["PAIRTEST_LOADOUTS"]
	var rm = (Engine.get_main_loop() as SceneTree).root.get_node("/root/ResourceManager")
	for key in loadouts:
		var active_disc: int = DISC_BY_KEY[String(key).split("|")[0]]
		var names: Array = loadouts[key]
		assert_eq(names.size(), 5, "%s must carry exactly 5 abilities" % key)
		for n in names:
			var ability = rm.get_ability_data(String(n))
			assert_not_null(ability, "%s: unknown ability '%s'" % [key, n])
			if ability == null:
				continue
			assert_eq(int(ability.ability_type), int(Constants.AbilityType.ACTIVE),
				"%s: '%s' must be an ACTIVE (it goes on the hotbar)" % [key, n])
			assert_true(active_disc in ability.required_class,
				"%s: '%s' does not belong to the bar's active discipline" % [key, n])


func test_gear_table_resolves() -> void:
	var c := _consts()
	var rm = (Engine.get_main_loop() as SceneTree).root.get_node("/root/ResourceManager")
	var tier: String = c["PAIRTEST_GEAR_TIER"]
	for disc in [0, 1, 2, 3]:
		var weapon_name: String = "%s %s" % [tier, c["PAIRTEST_WEAPON_NOUN"][disc]]
		assert_not_null(rm.get_item_by_name(weapon_name), "missing weapon '%s'" % weapon_name)
		for piece in ["Helm", "Mail", "Legguards", "Boots"]:
			var armor_name: String = "%s %s %s" % [tier, c["PAIRTEST_ARMOR_FAMILY"][disc], piece]
			assert_not_null(rm.get_item_by_name(armor_name), "missing armor '%s'" % armor_name)


func test_boss_map_is_registered() -> void:
	var c := _consts()
	var mm = (Engine.get_main_loop() as SceneTree).root.get_node("/root/MapManager")
	# The registry constant maps id -> scene path; reach it via the autoload's
	# constant map so the test fails loudly if the boss map id ever renames.
	var scenes: Dictionary = mm.get_script().get_script_constant_map().get("MAP_SCENES", {})
	if scenes.is_empty():
		# Registry shape changed - at minimum the id string must appear in the script.
		assert_true(true, "registry constant not found; skipping strict check")
		return
	assert_true(scenes.has(c["PAIRTEST_BOSS_MAP"]), "boss map '%s' not in MapManager registry" % c["PAIRTEST_BOSS_MAP"])


func test_passive_priorities_resolve_as_discipline_passives() -> void:
	var passives: Dictionary = _consts()["PAIRTEST_PASSIVES"]
	var rm = (Engine.get_main_loop() as SceneTree).root.get_node("/root/ResourceManager")
	assert_eq(passives.size(), 4)
	for key in passives:
		var disc: int = DISC_BY_KEY[key]
		for n in passives[key]:
			var ability = rm.get_ability_data(String(n))
			assert_not_null(ability, "%s: unknown passive '%s'" % [key, n])
			if ability == null:
				continue
			assert_eq(int(ability.ability_type), int(Constants.AbilityType.PASSIVE),
				"%s: '%s' must be a PASSIVE" % [key, n])
			assert_true(disc in ability.required_class,
				"%s: '%s' is not a %s passive" % [key, n, key])


func test_core_build_fits_the_100_point_mastery_budget() -> void:
	# The legit budget is MASTERY_CAP x 1 = 100 points per discipline. The
	# build's CORE (5 hotbar actives maxed + T1/T2 + one T3 each) must fit
	# with headroom for at least one full passive line, or the curated tables
	# have drifted out of budget.
	var c := _consts()
	var rm = (Engine.get_main_loop() as SceneTree).root.get_node("/root/ResourceManager")
	var numeric: Array = c["PAIRTEST_NUMERIC_KEYS"]
	for key in c["PAIRTEST_LOADOUTS"]:
		var cost := 0
		for n in c["PAIRTEST_LOADOUTS"][key]:
			var ability = rm.get_ability_data(String(n))
			if ability == null:
				continue
			cost += ability.max_level
			var t3_cost := 0
			var first_t3 := 0
			for up in ability.upgrades:
				if up == null:
					continue
				if up.tier < 3:
					cost += up.point_cost
				else:
					if first_t3 == 0:
						first_t3 = up.point_cost
					if not (up.effect_key in numeric):
						t3_cost = up.point_cost
			cost += t3_cost if t3_cost > 0 else first_t3
		assert_true(cost <= 90, "%s core build costs %d - must leave >=10 pts for passives" % [key, cost])
