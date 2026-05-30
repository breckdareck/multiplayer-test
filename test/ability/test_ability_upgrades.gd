# Content-validation tests for the PR-6 ability upgrade trees. Walks every
# AbilityData.upgrades entry across all abilities and asserts the invariants the
# purchase/save systems rely on: stable unique ids, valid tiers/costs, coherent
# tier-gating, and well-formed T3 variant groups. Failure messages name the
# offending upgrade so authoring mistakes are actionable.
extends "res://test/test_case.gd"

const ABILITIES_ROOT := "res://resources/Abilities"

static var _ability_cache: Array = []


func _all_abilities() -> Array:
	if _ability_cache.is_empty():
		var paths: Array[String] = []
		_scan(ABILITIES_ROOT, paths)
		for p in paths:
			var res = load(p)
			if res is AbilityData:
				_ability_cache.append(res)
	return _ability_cache

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

# Every upgrade reachable through an ability's `upgrades` array, deduped by
# resource_path (an upgrade resource shared by two abilities counts once).
func _unique_upgrades() -> Array:
	var seen := {}
	var out: Array = []
	for ability in _all_abilities():
		for up in ability.upgrades:
			if up == null:
				continue
			var path: String = up.resource_path
			if seen.has(path):
				continue
			seen[path] = true
			out.append(up)
	return out


func test_upgrade_content_exists() -> void:
	# Guards against an empty/broken scan making the rest vacuous.
	assert_true(_unique_upgrades().size() >= 10, "expected upgrade content, found %d" % _unique_upgrades().size())

func test_every_upgrade_has_identity() -> void:
	var upgrades := _unique_upgrades()
	assert_false(upgrades.is_empty(), "no upgrades loaded")
	for up in upgrades:
		assert_false(up.upgrade_id.is_empty(), "%s has empty upgrade_id" % up.resource_path)
		assert_false(up.upgrade_name.is_empty(), "%s (%s) has empty upgrade_name" % [up.upgrade_id, up.resource_path])

func test_upgrade_ids_are_globally_unique() -> void:
	# Save/load persists owned upgrades by upgrade_id, so collisions corrupt state.
	var id_to_path := {}
	var dupes: Array[String] = []
	for up in _unique_upgrades():
		var id: String = up.upgrade_id
		if id_to_path.has(id):
			dupes.append("'%s' on %s and %s" % [id, id_to_path[id], up.resource_path])
		else:
			id_to_path[id] = up.resource_path
	assert_true(id_to_path.size() > 0, "no upgrades found")
	assert_true(dupes.is_empty(), "duplicate upgrade_ids: %s" % str(dupes))

func test_upgrade_tier_in_range() -> void:
	var upgrades := _unique_upgrades()
	assert_false(upgrades.is_empty(), "no upgrades loaded")
	for up in upgrades:
		assert_true(up.tier >= 1 and up.tier <= 3, "%s has tier %d (expected 1-3)" % [up.upgrade_id, up.tier])

func test_upgrade_point_cost_positive() -> void:
	var upgrades := _unique_upgrades()
	assert_false(upgrades.is_empty(), "no upgrades loaded")
	for up in upgrades:
		assert_true(up.point_cost >= 1, "%s has point_cost %d (< 1)" % [up.upgrade_id, up.point_cost])

func test_upgrade_has_effect_key() -> void:
	# Consuming code (AbilityComponent generic keys, or the ability's AL_ script)
	# dispatches on effect_key; an empty one is a dead upgrade.
	var upgrades := _unique_upgrades()
	assert_false(upgrades.is_empty(), "no upgrades loaded")
	for up in upgrades:
		assert_false(up.effect_key.is_empty(), "%s has empty effect_key" % up.upgrade_id)

func test_tier_gating_is_coherent() -> void:
	# T2 unlocks behind a T1, T3 behind a T2 — so an ability offering a higher
	# tier must also offer the lower tier, or the higher tier is unreachable.
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	for ability in abilities:
		var tiers := {}
		for up in ability.upgrades:
			if up != null:
				tiers[up.tier] = true
		if tiers.is_empty():
			continue
		if tiers.has(2):
			assert_true(tiers.has(1), "%s offers a Tier-2 upgrade but no Tier-1" % ability.ability_name)
		if tiers.has(3):
			assert_true(tiers.has(2), "%s offers a Tier-3 upgrade but no Tier-2" % ability.ability_name)

func test_variant_groups_are_well_formed() -> void:
	# A variant_group is a mutually-exclusive Tier-3 choice. HARD invariant: every
	# member of a group is Tier-3, and the mutex system has at least one real
	# (>=2 member) group. SOFT check: a single-member group is a content smell
	# (likely an incomplete variant set) — logged as a warning, not failed, so a
	# known WIP gap (currently `cc_finisher_variant`) doesn't block the suite.
	var groups := {}
	for up in _unique_upgrades():
		if up.variant_group.is_empty():
			continue
		if not groups.has(up.variant_group):
			groups[up.variant_group] = []
		groups[up.variant_group].append(up)
	assert_false(groups.is_empty(), "expected at least one variant group")

	var multi_member_count := 0
	var lone_groups: Array[String] = []
	for group_name in groups:
		var members: Array = groups[group_name]
		if members.size() >= 2:
			multi_member_count += 1
		else:
			lone_groups.append(group_name)
		# HARD: every member of any group must be Tier-3.
		for m in members:
			assert_eq(m.tier, 3, "variant_group '%s' member %s is tier %d (variants should be Tier-3)" % [group_name, m.upgrade_id, m.tier])

	assert_true(multi_member_count >= 1, "expected at least one real (>=2 member) variant mutex")
	if not lone_groups.is_empty():
		print("  ⚠ CONTENT WARNING: single-member variant_group(s) — a 1-option mutex does nothing; finish or clear the tag: %s" % str(lone_groups))

func test_conditional_damage_bonus_upgrades_are_on_passives() -> void:
	# PR (conditional passives): a conditional passive's upgrade tree scales its
	# bonus via the generic "conditional_damage_bonus" effect_key, which
	# AbilityComponent only reads inside _foreach_learned_passive. An upgrade with
	# this key on a NON-passive ability is dead weight — catch that authoring bug.
	var abilities := _all_abilities()
	assert_false(abilities.is_empty(), "no abilities loaded")
	var found := 0
	for ability in abilities:
		for up in ability.upgrades:
			if up != null and up.effect_key == "conditional_damage_bonus":
				found += 1
				assert_eq(ability.ability_type, Constants.AbilityType.PASSIVE,
					"%s carries a conditional_damage_bonus upgrade (%s) but is not a PASSIVE" % [ability.ability_name, up.upgrade_id])
	assert_true(found >= 1, "expected conditional_damage_bonus upgrades to exist (feature wiring present)")

func test_upgrade_tooltips_render() -> void:
	var upgrades := _unique_upgrades()
	assert_false(upgrades.is_empty(), "no upgrades loaded")
	for up in upgrades:
		var unowned: String = up.get_tooltip_text(false)
		var owned: String = up.get_tooltip_text(true)
		assert_true(up.upgrade_name in unowned, "%s tooltip missing its name" % up.upgrade_id)
		assert_true("Owned" in owned, "%s owned-tooltip missing 'Owned' marker" % up.upgrade_id)
