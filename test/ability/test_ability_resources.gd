# Content-validation tests over EVERY real ability .tres in resources/Abilities/.
# These load the actual authored content and assert per-ability, per-level
# invariants — so an authoring mistake (missing scaling_data, an active with no
# behavior, an impossible prerequisite, a level that fails to generate) fails CI
# instead of shipping. Failure messages name the offending ability + level.
extends "res://test/test_case.gd"

const ABILITIES_ROOT := "res://resources/Abilities"

# Loading + scanning every ability is the same for all tests, so cache it across
# the fresh-per-test instances the runner creates.
static var _cache: Array = []


func _all_abilities() -> Array:
	if _cache.is_empty():
		var paths: Array[String] = []
		_scan(ABILITIES_ROOT, paths)
		for p in paths:
			var res = load(p)
			if res is AbilityData:
				_cache.append(res)
	return _cache

func _scan(dir_path: String, out_paths: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan(full, out_paths)
		elif entry.ends_with(".tres"):
			out_paths.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

# Mirrors AbilityComponent._class_type_to_discipline_key. PR-7 renamed the
# ClassType enum to weapon disciplines (SWORD/BOW/STAFF/DAGGER); tier-2
# advancement members map back to their base discipline.
func _discipline_for_class(class_type: int) -> String:
	match class_type:
		Constants.ClassType.SWORD, Constants.ClassType.CRUSADER:
			return "sword"
		Constants.ClassType.BOW, Constants.ClassType.RANGER:
			return "bow"
		Constants.ClassType.STAFF, Constants.ClassType.ARCHMAGE:
			return "staff"
		Constants.ClassType.DAGGER, Constants.ClassType.ASSASSIN:
			return "dagger"
	return ""


func test_ability_resources_load() -> void:
	# Guards against a broken scan silently making every other test vacuous.
	var abilities := _all_abilities()
	assert_true(abilities.size() >= 10, "expected to load the authored abilities, got %d" % abilities.size())

func test_every_ability_has_identity() -> void:
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	for ability in abilities:
		assert_false(ability.ability_id.is_empty(), "%s has empty ability_id" % ability.resource_path)
		assert_false(ability.ability_name.is_empty(), "%s has empty ability_name" % ability.resource_path)
		assert_true(ability.max_level >= 1, "%s has max_level %d (< 1)" % [ability.ability_name, ability.max_level])

func test_every_level_generates_stats() -> void:
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	for ability in abilities:
		for level in range(1, ability.max_level + 1):
			var stats: AbilityLevelData = ability.get_level_stats(level)
			assert_not_null(stats, "%s failed to generate level %d (missing scaling_data?)" % [ability.ability_name, level])
			if stats:
				assert_eq(stats.level, level, "%s level %d tagged wrong" % [ability.ability_name, level])

func test_level_stats_are_sane() -> void:
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	for ability in abilities:
		# Enemy-targeting actives must hit >=1 target >=1 time. Self/ally buffs,
		# passives, and utility (teleport, stealth) legitimately resolve to 0.
		var enemy_targeting: bool = ability.ability_type == Constants.AbilityType.ACTIVE \
			and ability.active_behavior != null \
			and ability.active_behavior.target_type == Constants.TargetType.ENEMY
		for level in range(1, ability.max_level + 1):
			var s: AbilityLevelData = ability.get_level_stats(level)
			if s == null:
				continue
			var where := "%s level %d" % [ability.ability_name, level]
			assert_true(s.mana_cost >= 0, "%s mana_cost %d < 0" % [where, s.mana_cost])
			assert_true(s.cooldown_time >= 0.0 and is_finite(s.cooldown_time), "%s cooldown %s invalid" % [where, str(s.cooldown_time)])
			assert_true(s.damage_percent >= 0, "%s damage_percent %d < 0" % [where, s.damage_percent])
			assert_true(s.max_targets >= 0, "%s max_targets %d < 0" % [where, s.max_targets])
			assert_true(s.max_hits >= 0, "%s max_hits %d < 0" % [where, s.max_hits])
			if enemy_targeting:
				assert_true(s.max_targets >= 1, "%s is enemy-targeting but max_targets is %d" % [where, s.max_targets])
				assert_true(s.max_hits >= 1, "%s is enemy-targeting but max_hits is %d" % [where, s.max_hits])

func test_level_bounds_return_null() -> void:
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	for ability in abilities:
		assert_null(ability.get_level_stats(0), "%s should return null at level 0" % ability.ability_name)
		assert_null(ability.get_level_stats(ability.max_level + 1), "%s should return null above max_level" % ability.ability_name)

func test_active_abilities_have_active_behavior() -> void:
	# _trigger_ability_state_change push_errors without active_behavior, so an
	# active ability missing it is unusable in combat.
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	for ability in abilities:
		if ability.ability_type == Constants.AbilityType.ACTIVE:
			assert_not_null(ability.active_behavior, "active ability %s has no active_behavior" % ability.ability_name)

func test_required_class_maps_to_a_discipline() -> void:
	# PR-4 invariant: an ability's class must map to a weapon discipline pool.
	# Class-neutral debug abilities (empty required_class, e.g. FMA) are exempt.
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	for ability in abilities:
		for class_type in ability.required_class:
			assert_ne(_discipline_for_class(class_type), "", "%s required_class %d maps to no discipline" % [ability.ability_name, class_type])

func test_prerequisites_are_satisfiable() -> void:
	# A prerequisite that demands a level above the prereq ability's max_level
	# can never be met — a soft-lock authoring bug.
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	for ability in abilities:
		for prereq in ability.prerequisite_abilities:
			var required_level: int = ability.prerequisite_abilities[prereq]
			assert_true(prereq != null, "%s has a null prerequisite ability" % ability.ability_name)
			if prereq:
				assert_true(required_level <= prereq.max_level,
					"%s requires %s level %d but its max_level is %d" % [ability.ability_name, prereq.ability_name, required_level, prereq.max_level])

func test_tooltips_render_at_min_and_max_level() -> void:
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	for ability in abilities:
		var low: String = ability.get_tooltip_text(1)
		var high: String = ability.get_tooltip_text(ability.max_level)
		assert_true(ability.ability_name in low, "%s level-1 tooltip missing its name" % ability.ability_name)
		assert_true(ability.ability_name in high, "%s max-level tooltip missing its name" % ability.ability_name)
		assert_false("$[damage_percent]" in low, "%s left a raw $[damage_percent] placeholder" % ability.ability_name)


# ---- skill-tree layout (PR ~7: tree_path / tree_depth + climb-gate) ----

# Discipline key for an ability via its first required_class, else "" (unplaced /
# class-neutral). Mirrors AbilityComponent._ability_primary_discipline.
func _ability_discipline(ability) -> String:
	if ability.required_class == null or ability.required_class.is_empty():
		return ""
	return _discipline_for_class(ability.required_class[0])

func test_tree_fields_in_valid_range() -> void:
	# tree_path: -1 (unplaced), 0 (Path A), or 1 (Path B). tree_depth: row >= 0.
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	for ability in abilities:
		assert_true(ability.tree_path >= -1 and ability.tree_path <= 1,
			"%s has tree_path %d (expected -1, 0, or 1)" % [ability.ability_name, ability.tree_path])
		assert_true(ability.tree_depth >= 0,
			"%s has tree_depth %d (< 0)" % [ability.ability_name, ability.tree_depth])

func test_placed_tree_nodes_have_a_path_parent() -> void:
	# The climb-gate requires the same-discipline, same-path node at depth-1.
	# A placed node deeper than the root with no such parent is unreachable —
	# a soft-lock authoring bug (you could never satisfy the gate to learn it).
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	for ability in abilities:
		if ability.tree_path < 0 or ability.tree_depth <= 0:
			continue
		var disc := _ability_discipline(ability)
		var found_parent := false
		for other in abilities:
			if other == ability:
				continue
			if other.tree_path == ability.tree_path \
					and other.tree_depth == ability.tree_depth - 1 \
					and _ability_discipline(other) == disc:
				found_parent = true
				break
		assert_true(found_parent,
			"%s (%s path %d depth %d) has no depth-%d path-parent — unreachable via climb-gate" \
			% [ability.ability_name, disc, ability.tree_path, ability.tree_depth, ability.tree_depth - 1])

func test_each_populated_path_has_a_root() -> void:
	# Every (discipline, path) that has any placed node must have a depth-0 root,
	# otherwise the whole path is unreachable.
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	var paths_seen := {}      # "disc:path" -> true
	var roots_seen := {}      # "disc:path" -> true (has a depth-0 node)
	for ability in abilities:
		if ability.tree_path < 0:
			continue
		var key := "%s:%d" % [_ability_discipline(ability), ability.tree_path]
		paths_seen[key] = true
		if ability.tree_depth == 0:
			roots_seen[key] = true
	assert_false(paths_seen.is_empty(), "expected at least one placed skill-tree node")
	for key in paths_seen:
		assert_true(roots_seen.has(key), "tree path '%s' has nodes but no depth-0 root" % key)
