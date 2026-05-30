# Behavior tests for the live AbilityComponent: cooldown ticking, per-discipline
# ability-point pools, discipline mapping, leveling, the skill-tree climb-gate
# (PR ~7), and ability-upgrade purchase (PR 6).
#
# AbilityComponent is a Node that needs to live in the SceneTree (so its
# `multiplayer` resolves) and reads `owner.player_id`. We mount one bare
# component under a stub owner WITHOUT Class/Stats siblings, so
# AbilityComponent._ready() early-returns before its auto-seeding block, leaving
# clean, deterministic state we reset between tests. The two expected error
# lines at mount ("requires ClassComponent and StatsComponent" + missing hotbar
# node path) are benign — the component is fully usable for the direct-API
# behavior we exercise here.
#
# FIXTURES ARE RESOLVED DYNAMICALLY from ResourceManager.ability_data — never by
# hardcoded .tres path. A prior version hardcoded A_Slash.tres and silently broke
# when the sword abilities were renamed (A_Slash -> A_Crescent_Cleave). Dynamic
# resolution by structural shape (discipline / type / tree position / upgrade
# layout) survives content renames and tests the actual indexed content.
extends "res://test/test_case.gd"

class _OwnerStub extends Node:
	var player_id: int = 1

# One shared in-tree component across all tests (mounting it logs 2 expected
# errors, so we do it once). State is reset per test in before_each().
static var _shared_owner: Node = null
static var _shared_component = null


func _comp():
	if _shared_component != null and is_instance_valid(_shared_component):
		return _shared_component
	var tree := Engine.get_main_loop() as SceneTree
	var mp := tree.get_multiplayer()
	if not (mp.multiplayer_peer is OfflineMultiplayerPeer):
		mp.multiplayer_peer = OfflineMultiplayerPeer.new()
	_shared_owner = _OwnerStub.new()
	_shared_owner.name = "AbilityTestOwner"
	_shared_component = AbilityComponent.new()
	_shared_owner.add_child(_shared_component)
	tree.root.add_child(_shared_owner)   # fires _ready -> early return (no siblings)
	_shared_component.owner = _shared_owner
	return _shared_component

func before_each() -> void:
	var c = _comp()
	c._cooldowns = {}
	c._ability_levels = {}
	c._available_points_per_discipline = {"sword": 0, "bow": 0, "staff": 0, "dagger": 0}
	c._learned_upgrades = {}


#region #################### Dynamic fixture resolution ####################
## First indexed ability matching `predicate(ability) -> bool`, else null.
func _find_ability(predicate: Callable):
	for a in ResourceManager.ability_data.values():
		if a != null and predicate.call(a):
			return a
	return null

## An ACTIVE, sword-discipline, path-ROOT (tree_depth 0, so the climb-gate never
## blocks it) ability with room to level and no prerequisites — drives the
## leveling tests deterministically regardless of its display name.
func _sword_root_active():
	var c = _comp()
	return _find_ability(func(a):
		return a.ability_type == Constants.AbilityType.ACTIVE \
			and c._ability_primary_discipline(a) == "sword" \
			and a.tree_depth == 0 and a.tree_path >= 0 \
			and a.max_level >= 2 \
			and a.prerequisite_abilities.is_empty())

## A placed tree CHILD (tree_depth == 1) plus its resolved path-parent. The
## integration test satisfies the child's prerequisites explicitly so the
## climb-gate (parent level) is the only variable. Returns {child, parent} or {}.
func _tree_child_with_parent() -> Dictionary:
	var c = _comp()
	for a in ResourceManager.ability_data.values():
		if a == null or a.tree_path < 0 or a.tree_depth != 1:
			continue
		var parent = c._get_path_parent(a)
		if parent != null:
			return {"child": a, "parent": parent}
	return {}

## An ability carrying a full upgrade tree: a tier-1, a tier-2, and a
## variant_group with >=2 tier-3 members — drives the purchase tests. Returns
## {ability, t1, t2, variants:[>=2 ids]} or {} if none found.
func _ability_with_full_upgrade_tree() -> Dictionary:
	for a in ResourceManager.ability_data.values():
		if a == null or a.upgrades == null or a.upgrades.is_empty():
			continue
		var t1 := ""
		var t2 := ""
		var groups := {}
		for up in a.upgrades:
			if up == null:
				continue
			if up.tier == 1 and t1 == "":
				t1 = up.upgrade_id
			elif up.tier == 2 and t2 == "":
				t2 = up.upgrade_id
			if not up.variant_group.is_empty():
				if not groups.has(up.variant_group):
					groups[up.variant_group] = []
				groups[up.variant_group].append(up.upgrade_id)
		if t1 == "" or t2 == "":
			continue
		for g in groups:
			if groups[g].size() >= 2:
				return {"ability": a, "t1": t1, "t2": t2, "variants": groups[g]}
	return {}
#endregion


# ---- cooldowns ----

func test_cooldown_unknown_ability_is_zero() -> void:
	assert_almost_eq(_comp().get_cooldown_remaining("does_not_exist"), 0.0, 0.001)

func test_cooldown_ticks_down_with_process() -> void:
	var c = _comp()
	c._cooldowns["x"] = 2.0
	c._process(0.5)
	assert_almost_eq(c.get_cooldown_remaining("x"), 1.5, 0.001, "after 0.5s")
	c._process(1.0)
	assert_almost_eq(c.get_cooldown_remaining("x"), 0.5, 0.001, "after 1.5s total")

func test_cooldown_expires_and_is_erased() -> void:
	var c = _comp()
	c._cooldowns["x"] = 1.0
	c._process(1.5)  # overshoot
	assert_almost_eq(c.get_cooldown_remaining("x"), 0.0, 0.001, "expired reads as 0")
	assert_false(c._cooldowns.has("x"), "expired cooldown removed from the dict")


# ---- per-discipline point pools ----

func test_add_points_to_one_discipline() -> void:
	var c = _comp()
	c._add_ability_points(5, "sword")
	assert_eq(c.get_available_points_for_discipline("sword"), 5, "sword credited")
	assert_eq(c.get_available_points_for_discipline("bow"), 0, "bow untouched")

func test_points_sum_across_disciplines() -> void:
	var c = _comp()
	c._add_ability_points(3, "sword")
	c._add_ability_points(4, "bow")
	assert_eq(c.get_available_ability_points(), 7, "total is the sum of pools")

func test_points_snapshot_is_a_copy() -> void:
	var c = _comp()
	c._add_ability_points(2, "staff")
	var snap: Dictionary = c.get_available_points_per_discipline()
	assert_eq(int(snap["staff"]), 2, "snapshot reflects pool")
	snap["staff"] = 999
	assert_eq(c.get_available_points_for_discipline("staff"), 2, "mutating the snapshot must not change the pool")

func test_unknown_discipline_reads_zero() -> void:
	assert_eq(_comp().get_available_points_for_discipline("bogus"), 0)


# ---- discipline mapping ----

func test_class_type_maps_to_discipline() -> void:
	var c = _comp()
	assert_eq(c._class_type_to_discipline_key(Constants.ClassType.SWORD), "sword")
	assert_eq(c._class_type_to_discipline_key(Constants.ClassType.BOW), "bow")
	assert_eq(c._class_type_to_discipline_key(Constants.ClassType.STAFF), "staff")
	assert_eq(c._class_type_to_discipline_key(Constants.ClassType.DAGGER), "dagger")
	assert_eq(c._class_type_to_discipline_key(Constants.ClassType.CRUSADER), "sword", "tier-2 advancement maps to base discipline")
	assert_eq(c._class_type_to_discipline_key(Constants.ClassType.BEGINNER), "", "beginner maps to no discipline")

func test_ability_primary_discipline_reads_required_class() -> void:
	var ability = _sword_root_active()
	assert_not_null(ability, "found a sword root active fixture")
	if ability:
		assert_eq(_comp()._ability_primary_discipline(ability), "sword")


# ---- leveling / gating ----

func test_level_up_spends_one_point_and_increments() -> void:
	var c = _comp()
	var ability = _sword_root_active()
	assert_not_null(ability, "found a sword root active fixture")
	if not ability:
		return
	var id: String = ability.ability_id
	c._ability_levels[id] = 1
	c._available_points_per_discipline["sword"] = 3
	var ok: bool = c._level_up_ability_local(id)
	assert_true(ok, "level-up succeeded")
	assert_eq(c.get_ability_level(id), 2, "ability level incremented")
	assert_eq(c.get_available_points_for_discipline("sword"), 2, "exactly one sword point spent")

func test_cannot_level_without_points() -> void:
	var c = _comp()
	var ability = _sword_root_active()
	assert_not_null(ability, "fixture present")
	if not ability:
		return
	c._ability_levels[ability.ability_id] = 1
	c._available_points_per_discipline["sword"] = 0
	assert_false(c.can_level_up_ability(ability.ability_id), "empty discipline pool blocks leveling")

func test_cannot_level_at_max_level() -> void:
	var c = _comp()
	var ability = _sword_root_active()
	assert_not_null(ability, "fixture present")
	if not ability:
		return
	c._ability_levels[ability.ability_id] = ability.max_level
	c._available_points_per_discipline["sword"] = 5
	assert_false(c.can_level_up_ability(ability.ability_id), "at max_level, leveling is blocked even with points")

func test_level_up_denied_leaves_state_unchanged() -> void:
	var c = _comp()
	var ability = _sword_root_active()
	assert_not_null(ability, "fixture present")
	if not ability:
		return
	var id: String = ability.ability_id
	c._ability_levels[id] = 1
	c._available_points_per_discipline["sword"] = 0
	var ok: bool = c._level_up_ability_local(id)
	assert_false(ok, "denied level-up returns false")
	assert_eq(c.get_ability_level(id), 1, "level unchanged on denial")
	assert_eq(c.get_available_points_for_discipline("sword"), 0, "no points spent on denial")


# ---- skill-tree climb-gate ----

func test_tree_root_is_always_unlocked() -> void:
	var ability = _sword_root_active()  # tree_depth 0 == path root
	assert_not_null(ability, "root fixture present")
	if ability:
		assert_true(_comp().is_tree_node_unlocked(ability.ability_id), "a path-root node is unlocked unconditionally")

func test_tree_child_locked_until_parent_learned() -> void:
	var c = _comp()
	var pair := _tree_child_with_parent()
	assert_false(pair.is_empty(), "found a tree child + parent fixture")
	if pair.is_empty():
		return
	var child_id: String = pair.child.ability_id
	var parent_id: String = pair.parent.ability_id
	# Parent unlearned (level 0) -> gate closed.
	c._ability_levels[parent_id] = 0
	assert_false(c.is_tree_node_unlocked(child_id), "child gated while parent unlearned")
	# Parent learned (level 1) -> gate open.
	c._ability_levels[parent_id] = 1
	assert_true(c.is_tree_node_unlocked(child_id), "child unlocked once parent is learned")

func test_climb_gate_blocks_level_up() -> void:
	var c = _comp()
	var pair := _tree_child_with_parent()
	assert_false(pair.is_empty(), "fixture present")
	if pair.is_empty():
		return
	var child = pair.child
	var parent = pair.parent
	var child_id: String = child.ability_id
	var disc: String = c._ability_primary_discipline(child)
	c._ability_levels[child_id] = 1
	c._available_points_per_discipline[disc] = 10
	# Satisfy every prerequisite EXCEPT the path-parent (whose level we control).
	# A child's prereq may also BE its path-parent but at a higher level (e.g.
	# Sundering Blow needs Crescent Cleave 5; the gate only needs it >= 1) — take
	# the max so the "allowed" case satisfies both. Match by ability_id, not
	# object identity.
	var parent_required: int = 1
	for prereq in child.prerequisite_abilities:
		var req: int = int(child.prerequisite_abilities[prereq])
		if prereq.ability_id == parent.ability_id:
			parent_required = max(parent_required, req)
		else:
			c._ability_levels[prereq.ability_id] = req
	# Gate closed: path-parent unlearned.
	c._ability_levels[parent.ability_id] = 0
	assert_false(c.can_level_up_ability(child_id), "blocked while path-parent unlearned")
	# Gate open + all prerequisites satisfied.
	c._ability_levels[parent.ability_id] = parent_required
	if child.max_level > 1:
		assert_true(c.can_level_up_ability(child_id), "allowed once path-parent learned to required level")


# ---- ability upgrades (PR 6 purchase API) ----

func test_upgrade_requires_learned_ability() -> void:
	var c = _comp()
	var fx := _ability_with_full_upgrade_tree()
	assert_false(fx.is_empty(), "found an ability with a full upgrade tree")
	if fx.is_empty():
		return
	var id: String = fx.ability.ability_id
	c._ability_levels[id] = 0  # unlearned
	var res: Dictionary = c.can_purchase_upgrade(id, fx.t1)
	assert_false(res.ok, "cannot buy an upgrade for an unlearned ability")
	assert_eq(res.reason, "not_learned")

func test_upgrade_requires_max_level() -> void:
	var c = _comp()
	var fx := _ability_with_full_upgrade_tree()
	assert_false(fx.is_empty(), "fixture present")
	if fx.is_empty():
		return
	var id: String = fx.ability.ability_id
	c._ability_levels[id] = 1  # learned but below max
	if fx.ability.max_level <= 1:
		return
	var res: Dictionary = c.can_purchase_upgrade(id, fx.t1)
	assert_false(res.ok, "cannot buy upgrades before the ability is maxed")
	assert_eq(res.reason, "not_maxed")

func test_upgrade_tier_gating() -> void:
	var c = _comp()
	var fx := _ability_with_full_upgrade_tree()
	assert_false(fx.is_empty(), "fixture present")
	if fx.is_empty():
		return
	var ability = fx.ability
	var id: String = ability.ability_id
	var disc: String = c._ability_primary_discipline(ability)
	c._ability_levels[id] = ability.max_level
	c._available_points_per_discipline[disc] = 10
	# Tier-2 is locked until a tier-1 is owned.
	var t2res: Dictionary = c.can_purchase_upgrade(id, fx.t2)
	assert_false(t2res.ok, "tier-2 locked with no tier-1 owned")
	assert_eq(t2res.reason, "tier_locked")
	# Buy tier-1, then tier-2 unlocks.
	assert_true(c.can_purchase_upgrade(id, fx.t1).ok, "tier-1 purchasable")
	assert_true(c.purchase_upgrade(id, fx.t1), "bought tier-1")
	assert_true(c.can_purchase_upgrade(id, fx.t2).ok, "tier-2 unlocked after tier-1")

func test_upgrade_purchase_deducts_points_and_records() -> void:
	var c = _comp()
	var fx := _ability_with_full_upgrade_tree()
	assert_false(fx.is_empty(), "fixture present")
	if fx.is_empty():
		return
	var ability = fx.ability
	var id: String = ability.ability_id
	var disc: String = c._ability_primary_discipline(ability)
	var t1up = c._find_upgrade(ability, fx.t1)
	c._ability_levels[id] = ability.max_level
	c._available_points_per_discipline[disc] = 10
	assert_false(c.has_upgrade(id, fx.t1), "not owned before purchase")
	assert_true(c.purchase_upgrade(id, fx.t1), "purchase succeeds")
	assert_true(c.has_upgrade(id, fx.t1), "owned after purchase")
	assert_eq(c.get_available_points_for_discipline(disc), 10 - t1up.point_cost, "point_cost deducted")
	assert_true(c.get_learned_upgrades(id).has(fx.t1), "recorded in learned-upgrades list")
	# Re-buying the same upgrade is rejected.
	var again: Dictionary = c.can_purchase_upgrade(id, fx.t1)
	assert_false(again.ok, "cannot re-buy an owned upgrade")
	assert_eq(again.reason, "already_owned")

func test_upgrade_variant_mutex() -> void:
	var c = _comp()
	var fx := _ability_with_full_upgrade_tree()
	assert_false(fx.is_empty(), "fixture present")
	if fx.is_empty():
		return
	var ability = fx.ability
	var id: String = ability.ability_id
	var disc: String = c._ability_primary_discipline(ability)
	c._ability_levels[id] = ability.max_level
	c._available_points_per_discipline[disc] = 20
	# Open the tier gate up to tier-3 (buy a t1 and t2).
	assert_true(c.purchase_upgrade(id, fx.t1), "bought tier-1")
	assert_true(c.purchase_upgrade(id, fx.t2), "bought tier-2")
	var v0: String = fx.variants[0]
	var v1: String = fx.variants[1]
	assert_true(c.can_purchase_upgrade(id, v0).ok, "first variant purchasable")
	assert_true(c.purchase_upgrade(id, v0), "bought first variant")
	# Mutex: a second variant in the same group is now blocked.
	var blocked: Dictionary = c.can_purchase_upgrade(id, v1)
	assert_false(blocked.ok, "second variant in the same group is blocked")
	assert_eq(blocked.reason, "variant_taken")

func test_upgrade_insufficient_points() -> void:
	var c = _comp()
	var fx := _ability_with_full_upgrade_tree()
	assert_false(fx.is_empty(), "fixture present")
	if fx.is_empty():
		return
	var ability = fx.ability
	var id: String = ability.ability_id
	var disc: String = c._ability_primary_discipline(ability)
	c._ability_levels[id] = ability.max_level
	c._available_points_per_discipline[disc] = 0
	var res: Dictionary = c.can_purchase_upgrade(id, fx.t1)
	assert_false(res.ok, "cannot buy without points")
	assert_eq(res.reason, "no_points")

func test_upgrade_magnitude_helpers() -> void:
	var c = _comp()
	var fx := _ability_with_full_upgrade_tree()
	assert_false(fx.is_empty(), "fixture present")
	if fx.is_empty():
		return
	var ability = fx.ability
	var id: String = ability.ability_id
	var disc: String = c._ability_primary_discipline(ability)
	var t1up = c._find_upgrade(ability, fx.t1)
	c._ability_levels[id] = ability.max_level
	c._available_points_per_discipline[disc] = 10
	assert_true(c.purchase_upgrade(id, fx.t1), "bought tier-1")
	# The per-ability and player-wide magnitude sums include the owned upgrade.
	var per_ability: float = c.get_ability_upgrade_magnitude(id, t1up.effect_key)
	var player_wide: float = c.get_total_upgrade_magnitude(t1up.effect_key)
	assert_almost_eq(per_ability, t1up.magnitude, 0.001, "per-ability magnitude reflects the owned upgrade")
	assert_almost_eq(player_wide, t1up.magnitude, 0.001, "player-wide magnitude includes it too")
