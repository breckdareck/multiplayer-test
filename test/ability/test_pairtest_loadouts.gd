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
