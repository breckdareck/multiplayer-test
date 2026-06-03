# Economy-sink tests (2026-06-02): respecs cost monies, server-validated.
#
# Covers the cost formula at a couple levels and the server-side gate in both
# the StatsComponent (attribute respec) and AbilityComponent (ability /
# discipline / all respec) mutation points:
#   - BLOCKED when monies < cost  -> state + monies unchanged, no mutation
#   - SUCCEEDS when monies >= cost -> deducts EXACTLY cost, mutation happens
#
# Mirrors test_ability_component.gd's mount pattern: a bare component under a
# stub owner that carries a player_id, a fake PlayerInventory (monies_amount +
# set_monies_rpc), and a Leveling child the component reads `level` off. The
# components early-return out of their auto-seeding _ready() because the stub
# lacks the WeaponMastery/Stats siblings — leaving clean, directly-driven state.
extends "res://test/test_case.gd"


# ── Fakes ─────────────────────────────────────────────────────────────────────

## A REAL PlayerInventory (the cost gate's _player_inventory() return type is
## typed to PlayerInventory, so a duck-typed stub is rejected at runtime). We
## just keep it in loading mode so the monies setter doesn't fan out to the
## save-notify path, and never give it an InventoryComponent (the only thing its
## _ready wants — it push_errors benignly and returns, leaving monies usable).
class _FakeInventory extends PlayerInventory:
	func _init() -> void:
		_loading_mode = true

## Owner stub: player_id + the player_inventory property the components resolve
## monies through, plus a "Leveling" child wired as the level component.
class _OwnerStub extends Node:
	var player_id: int = 1
	var player_inventory = null


# ── Mount helpers ─────────────────────────────────────────────────────────────

func _ensure_offline_peer() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var mp := tree.get_multiplayer()
	if not (mp.multiplayer_peer is OfflineMultiplayerPeer):
		mp.multiplayer_peer = OfflineMultiplayerPeer.new()

## Builds {owner, inv, leveling} mounted in the tree, with the given level + monies.
## Uses a REAL LevelingComponent (the component fields are typed to it), with its
## loading flag set so assigning `level` doesn't fire the level-up SFX/party path.
func _make_owner(level: int, monies: int) -> Dictionary:
	_ensure_offline_peer()
	var tree := Engine.get_main_loop() as SceneTree
	var owner := _OwnerStub.new()
	var inv := _FakeInventory.new()
	inv.monies_amount = monies
	var leveling := LevelingComponent.new()
	leveling.name = "Leveling"
	leveling._is_loading_data = true   # silence the level-up SFX/party fan-out
	owner.player_inventory = inv
	owner.add_child(inv)
	# Mount Leveling FIRST so component _ready()s resolve get_node("Leveling").
	owner.add_child(leveling)
	tree.root.add_child(owner)
	# Set level only AFTER the node is in the tree, so the setter's
	# multiplayer.is_server() guard (level.gd:19) has a live multiplayer peer.
	leveling.level = level
	return {"owner": owner, "inv": inv, "leveling": leveling}

func _mount_stats(ctx: Dictionary) -> StatsComponent:
	var c := StatsComponent.new()
	ctx.owner.add_child(c)          # _ready early-returns (no Leveling-wired siblings yet)
	c.owner = ctx.owner
	c._level_component = ctx.leveling
	c._loading_mode = true          # keep the deferred stats recalc inert (no Mastery sibling)
	return c

func _mount_ability(ctx: Dictionary) -> AbilityComponent:
	var c := AbilityComponent.new()
	ctx.owner.add_child(c)
	c.owner = ctx.owner
	c._level_component = ctx.leveling
	return c


# ── Cost formula ──────────────────────────────────────────────────────────────

func test_attribute_respec_cost_formula() -> void:
	# Cost = allocated points * ATTR_RESPEC_COST_PER_POINT (5) — scales with points,
	# NOT character level.
	var ctx := _make_owner(1, 0)
	var s := _mount_stats(ctx)
	assert_eq(s.get_attribute_respec_cost(), 0, "nothing allocated = free")
	s._allocated_attributes = {Constants.StatType.STRENGTH: 10}
	assert_eq(s.get_attribute_respec_cost(), 50, "10 points * 5")
	s._allocated_attributes = {Constants.StatType.STRENGTH: 10, Constants.StatType.LUCK: 20}
	assert_eq(s.get_attribute_respec_cost(), 150, "30 points * 5")

func test_ability_respec_cost_formula() -> void:
	# Cost = points-in-scope * ABILITY_RESPEC_COST_PER_POINT (20).
	var ctx := _make_owner(100, 0)
	var a := _mount_ability(ctx)
	assert_eq(a.get_respec_cost("all"), 0, "nothing spent = free")
	var sid := _sword_ability_id(a)
	a._ability_levels = {sid: 4}        # 4 points in the sword tree
	assert_eq(a.get_respec_cost("ability", sid), 80, "4 points * 20")
	assert_eq(a.get_respec_cost("discipline", "sword"), 80, "4 sword points * 20")
	assert_eq(a.get_respec_cost("all"), 80, "4 total points * 20")

func test_ability_respec_cost_unknown_scope_is_zero() -> void:
	var ctx := _make_owner(50, 0)
	var a := _mount_ability(ctx)
	assert_eq(a.get_respec_cost("bogus"), 0, "unknown scope costs nothing")


# ── Attribute respec gate ─────────────────────────────────────────────────────

func test_attribute_respec_blocked_when_poor() -> void:
	var ctx := _make_owner(10, 0)       # 5 points -> cost = 25, monies = 0
	var s := _mount_stats(ctx)
	s._allocated_attributes = {Constants.StatType.STRENGTH: 5}
	s._respec_attributes_local()
	assert_eq(s.get_allocated_attribute(Constants.StatType.STRENGTH), 5, "allocation untouched when too poor")
	assert_eq(ctx.inv.monies_amount, 0, "monies unchanged when respec blocked")

func test_attribute_respec_succeeds_and_deducts_exact_cost() -> void:
	var ctx := _make_owner(10, 1000)
	var s := _mount_stats(ctx)
	s._allocated_attributes = {Constants.StatType.STRENGTH: 5, Constants.StatType.LUCK: 3}  # 8 pts -> 40
	s._respec_attributes_local()
	assert_true(s._allocated_attributes.is_empty(), "all attributes refunded on success")
	assert_eq(ctx.inv.monies_amount, 960, "exactly 40 (8 points * 5) deducted from 1000")

func test_attribute_respec_noop_when_nothing_allocated_does_not_charge() -> void:
	var ctx := _make_owner(10, 1000)
	var s := _mount_stats(ctx)
	s._allocated_attributes = {}
	s._respec_attributes_local()
	assert_eq(ctx.inv.monies_amount, 1000, "no charge when there is nothing to refund")

func test_attribute_respec_exact_funds_succeeds() -> void:
	var ctx := _make_owner(10, 5)       # 1 point -> cost 5 == monies
	var s := _mount_stats(ctx)
	s._allocated_attributes = {Constants.StatType.STRENGTH: 1}
	s._respec_attributes_local()
	assert_true(s._allocated_attributes.is_empty(), "respec proceeds when monies == cost")
	assert_eq(ctx.inv.monies_amount, 0, "spent down to exactly zero")


# ── Ability "all" respec gate ─────────────────────────────────────────────────

func test_ability_respec_all_blocked_when_poor() -> void:
	var ctx := _make_owner(10, 50)      # 5 points -> all cost = 100, monies = 50
	var a := _mount_ability(ctx)
	a._available_points_per_discipline = {"sword": 0, "bow": 0, "staff": 0, "dagger": 0}
	var sid := _sword_ability_id(a)
	a._ability_levels = {sid: 5}
	var ok: bool = a._respec_all_local()
	assert_false(ok, "respec_all denied when too poor")
	assert_eq(ctx.inv.monies_amount, 50, "monies unchanged when blocked")
	assert_eq(int(a._ability_levels.get(sid, 0)), 5, "levels untouched when blocked")

## A real ability id that maps to the "sword" discipline (resolved dynamically).
func _sword_ability_id(a) -> String:
	for ability in ResourceManager.ability_data.values():
		if a._ability_primary_discipline(ability) == "sword":
			return ability.ability_id
	return ""

func test_ability_respec_all_succeeds_and_deducts_exact_cost() -> void:
	var ctx := _make_owner(10, 1000)    # all cost = 600
	var a := _mount_ability(ctx)
	a._available_points_per_discipline = {"sword": 0, "bow": 0, "staff": 0, "dagger": 0}
	a._ability_levels = {_sword_ability_id(a): 3}   # 3 points -> all cost = 60
	var ok: bool = a._respec_all_local()
	assert_true(ok, "respec_all succeeds with funds + spent points")
	assert_eq(ctx.inv.monies_amount, 940, "exactly 60 (3 points * 20) deducted from 1000")

func test_ability_respec_all_noop_when_nothing_spent_does_not_charge() -> void:
	var ctx := _make_owner(10, 1000)
	var a := _mount_ability(ctx)
	a._available_points_per_discipline = {"sword": 0, "bow": 0, "staff": 0, "dagger": 0}
	a._ability_levels = {}              # nothing spent anywhere
	var ok: bool = a._respec_all_local()
	assert_false(ok, "respec_all is a no-op when nothing is spent")
	assert_eq(ctx.inv.monies_amount, 1000, "no charge for a no-op respec")


# ── Ability per-discipline respec gate ────────────────────────────────────────

func test_ability_respec_discipline_blocked_when_poor() -> void:
	var ctx := _make_owner(10, 50)      # 5 points -> discipline cost = 100, monies = 50
	var a := _mount_ability(ctx)
	a._available_points_per_discipline = {"sword": 0, "bow": 0, "staff": 0, "dagger": 0}
	a._ability_levels = {_sword_ability_id(a): 5}
	var ok: bool = a._respec_discipline_local("sword")
	assert_false(ok, "discipline respec denied when too poor")
	assert_eq(ctx.inv.monies_amount, 50, "monies unchanged when blocked")

func test_ability_respec_discipline_succeeds_and_deducts() -> void:
	var ctx := _make_owner(10, 1000)
	var a := _mount_ability(ctx)
	a._available_points_per_discipline = {"sword": 0, "bow": 0, "staff": 0, "dagger": 0}
	a._ability_levels = {_sword_ability_id(a): 3}   # 3 points -> discipline cost = 60
	var ok: bool = a._respec_discipline_local("sword")
	assert_true(ok, "discipline respec succeeds with funds + spent points")
	assert_eq(ctx.inv.monies_amount, 940, "exactly 60 (3 points * 20) deducted from 1000")

func test_ability_respec_discipline_noop_when_nothing_spent_does_not_charge() -> void:
	var ctx := _make_owner(10, 1000)
	var a := _mount_ability(ctx)
	a._available_points_per_discipline = {"sword": 0, "bow": 0, "staff": 0, "dagger": 0}
	a._ability_levels = {}              # nothing spent in the sword tree
	var ok: bool = a._respec_discipline_local("sword")
	assert_false(ok, "discipline respec is a no-op when nothing is spent")
	assert_eq(ctx.inv.monies_amount, 1000, "no charge for a no-op respec")

func test_ability_respec_discipline_unknown_key_does_not_charge() -> void:
	var ctx := _make_owner(10, 1000)
	var a := _mount_ability(ctx)
	a._available_points_per_discipline = {"sword": 0, "bow": 0, "staff": 0, "dagger": 0}
	var ok: bool = a._respec_discipline_local("bogus")
	assert_false(ok, "unknown discipline key is rejected before charging")
	assert_eq(ctx.inv.monies_amount, 1000, "no charge for an invalid discipline")
