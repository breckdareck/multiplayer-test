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
	var ctx := _make_owner(1, 0)
	var s := _mount_stats(ctx)
	assert_eq(s.get_attribute_respec_cost(), 30, "L1 = 1 * 30")
	ctx.leveling.level = 100
	assert_eq(s.get_attribute_respec_cost(), 3000, "L100 = 100 * 30")

func test_ability_respec_cost_formula() -> void:
	var ctx := _make_owner(100, 0)
	var a := _mount_ability(ctx)
	assert_eq(a.get_respec_cost("ability"), 500, "per-ability L100 = 100 * 5")
	assert_eq(a.get_respec_cost("discipline"), 2000, "per-discipline L100 = 100 * 20")
	assert_eq(a.get_respec_cost("all"), 6000, "all L100 = 100 * 60")
	ctx.leveling.level = 10
	assert_eq(a.get_respec_cost("ability"), 50, "per-ability L10 = 10 * 5")
	assert_eq(a.get_respec_cost("all"), 600, "all L10 = 10 * 60")

func test_ability_respec_cost_unknown_scope_is_zero() -> void:
	var ctx := _make_owner(50, 0)
	var a := _mount_ability(ctx)
	assert_eq(a.get_respec_cost("bogus"), 0, "unknown scope costs nothing")


# ── Attribute respec gate ─────────────────────────────────────────────────────

func test_attribute_respec_blocked_when_poor() -> void:
	var ctx := _make_owner(10, 0)       # cost = 300, monies = 0
	var s := _mount_stats(ctx)
	s._allocated_attributes = {Constants.StatType.STRENGTH: 5}
	s._respec_attributes_local()
	assert_eq(s.get_allocated_attribute(Constants.StatType.STRENGTH), 5, "allocation untouched when too poor")
	assert_eq(ctx.inv.monies_amount, 0, "monies unchanged when respec blocked")

func test_attribute_respec_succeeds_and_deducts_exact_cost() -> void:
	var ctx := _make_owner(10, 1000)    # cost = 300
	var s := _mount_stats(ctx)
	s._allocated_attributes = {Constants.StatType.STRENGTH: 5, Constants.StatType.LUCK: 3}
	s._respec_attributes_local()
	assert_true(s._allocated_attributes.is_empty(), "all attributes refunded on success")
	assert_eq(ctx.inv.monies_amount, 700, "exactly 300 (cost) deducted from 1000")

func test_attribute_respec_noop_when_nothing_allocated_does_not_charge() -> void:
	var ctx := _make_owner(10, 1000)
	var s := _mount_stats(ctx)
	s._allocated_attributes = {}
	s._respec_attributes_local()
	assert_eq(ctx.inv.monies_amount, 1000, "no charge when there is nothing to refund")

func test_attribute_respec_exact_funds_succeeds() -> void:
	var ctx := _make_owner(10, 300)     # cost == monies
	var s := _mount_stats(ctx)
	s._allocated_attributes = {Constants.StatType.STRENGTH: 1}
	s._respec_attributes_local()
	assert_true(s._allocated_attributes.is_empty(), "respec proceeds when monies == cost")
	assert_eq(ctx.inv.monies_amount, 0, "spent down to exactly zero")


# ── Ability "all" respec gate ─────────────────────────────────────────────────

func test_ability_respec_all_blocked_when_poor() -> void:
	var ctx := _make_owner(10, 100)     # all cost = 600, monies = 100
	var a := _mount_ability(ctx)
	a._available_points_per_discipline = {"sword": 3, "bow": 0, "staff": 0, "dagger": 0}
	var ok: bool = a._respec_all_local()
	assert_false(ok, "respec_all denied when too poor")
	assert_eq(ctx.inv.monies_amount, 100, "monies unchanged when blocked")
	assert_eq(a.get_available_points_for_discipline("sword"), 3, "pools unchanged when blocked")

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
	a._ability_levels = {_sword_ability_id(a): 3}   # something actually spent to refund
	var ok: bool = a._respec_all_local()
	assert_true(ok, "respec_all succeeds with funds + spent points")
	assert_eq(ctx.inv.monies_amount, 400, "exactly 600 (cost) deducted from 1000")

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
	var ctx := _make_owner(10, 50)      # discipline cost = 200
	var a := _mount_ability(ctx)
	a._available_points_per_discipline = {"sword": 2, "bow": 0, "staff": 0, "dagger": 0}
	var ok: bool = a._respec_discipline_local("sword")
	assert_false(ok, "discipline respec denied when too poor")
	assert_eq(ctx.inv.monies_amount, 50, "monies unchanged when blocked")

func test_ability_respec_discipline_succeeds_and_deducts() -> void:
	var ctx := _make_owner(10, 1000)    # discipline cost = 200
	var a := _mount_ability(ctx)
	a._available_points_per_discipline = {"sword": 0, "bow": 0, "staff": 0, "dagger": 0}
	a._ability_levels = {_sword_ability_id(a): 3}   # something spent in the sword tree
	var ok: bool = a._respec_discipline_local("sword")
	assert_true(ok, "discipline respec succeeds with funds + spent points")
	assert_eq(ctx.inv.monies_amount, 800, "exactly 200 (cost) deducted from 1000")

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
