# Unit tests for the derived duo nodes (ADR 0013) in WeaponPairSynergyComponent:
# the 30-points-in-BOTH-disciplines unlock predicate, the direction-aware
# on-swap triggers (the reward lands on the arrival weapon, in its own
# currency), the 8s swap ICD, and the death/unequip cleanup paths.
#
# Stub owner exposes exactly the surface the component resolves: the
# equipped/active discipline API, an ability component with per-discipline
# points-spent, and gauge stubs. player_id is negative (bot path) so _proc
# emits locally instead of RPC-ing a client.
extends "res://test/test_case.gd"

const PairSynergy = preload("res://scripts/Components/weapon_pair_synergy.gd")

const SWORD := Constants.ClassType.SWORD
const BOW := Constants.ClassType.BOW
const STAFF := Constants.ClassType.STAFF
const DAGGER := Constants.ClassType.DAGGER


class _AbilityStub extends Node:
	var spent := {}
	func get_points_spent_in_discipline(key: String) -> int:
		return int(spent.get(key, 0))


class _ComboStub extends Node:
	var points := 0
	func add_combo_point() -> void:
		points += 1


class _MomentumStub extends Node:
	var stacks := 0
	func add_momentum(n: int) -> void:
		stacks += n


class _OwnerStub extends Node:
	var player_id := -1   # negative = bot: _proc emits locally, no client RPC
	var equipped: Array = []
	var active: int = 0
	var ability_component = null
	var sword_combo_component = null
	var bow_momentum_component = null
	var shadowmeld_component = null
	func get_equipped_disciplines() -> Array:
		return equipped
	func get_active_discipline() -> int:
		return active


var _procs: Array = []


## Owner + component, with `spent` points per discipline key and a pair equipped.
func _make(equipped: Array, spent: Dictionary) -> Dictionary:
	var owner := _OwnerStub.new()
	owner.equipped = equipped
	var ac := _AbilityStub.new()
	ac.spent = spent
	owner.add_child(ac)
	owner.ability_component = ac
	var combo := _ComboStub.new()
	owner.add_child(combo)
	owner.sword_combo_component = combo
	var momentum := _MomentumStub.new()
	owner.add_child(momentum)
	owner.bow_momentum_component = momentum
	var comp = PairSynergy.new()
	owner.add_child(comp)   # child of owner so _resolve_owner() walks up to it
	(Engine.get_main_loop() as SceneTree).root.add_child(owner)
	_procs = []
	comp.synergy_proc.connect(func(k): _procs.append(k))
	return {"owner": owner, "comp": comp, "combo": combo, "momentum": momentum}


func _swap_to(ctx: Dictionary, disc: int) -> void:
	ctx.owner.active = disc
	ctx.comp.on_weapon_state_changed(disc, ctx.owner.equipped)


func _cleanup(ctx: Dictionary) -> void:
	if is_instance_valid(ctx.owner):
		ctx.owner.queue_free()


const T := 30  # PairSynergy.DUO_THRESHOLD_POINTS, asserted below


func test_threshold_constant_matches_suite() -> void:
	assert_eq(PairSynergy.DUO_THRESHOLD_POINTS, T, "suite assumes the 30-point threshold")


# ── Unlock predicate ─────────────────────────────────────────────────────────

func test_duo_inactive_below_threshold() -> void:
	var ctx := _make([SWORD, BOW], {"sword": T, "bow": T - 1})
	_swap_to(ctx, BOW)
	assert_false(ctx.comp._duo_active, "29/30 on one side = locked")
	assert_eq(ctx.momentum.stacks, 0, "no arrival reward while locked")
	_cleanup(ctx)


func test_duo_active_at_threshold_both_sides() -> void:
	var ctx := _make([SWORD, BOW], {"sword": T, "bow": T})
	_swap_to(ctx, BOW)
	assert_true(ctx.comp._duo_active)
	assert_eq(ctx.comp._duo_pair_key, "sword_bow", "canonical sword/bow/staff/dagger order")
	_cleanup(ctx)


func test_duo_inactive_with_single_weapon() -> void:
	var ctx := _make([BOW], {"bow": T * 2})
	_swap_to(ctx, BOW)
	assert_false(ctx.comp._duo_active, "duos need a genuine two-weapon pair")
	_cleanup(ctx)


# ── Direction-aware swap triggers ────────────────────────────────────────────

func test_sword_bow_arrival_on_bow_grants_momentum() -> void:
	var ctx := _make([SWORD, BOW], {"sword": T, "bow": T})
	_swap_to(ctx, BOW)
	assert_eq(ctx.momentum.stacks, 3, "Skirmisher's Rhythm: to the bow = 3 Momentum")
	assert_eq(ctx.combo.points, 0, "reward lands on the ARRIVAL weapon only")
	assert_true(_procs.has("sword_bow"), "proc signal fired for the widget flash")
	_cleanup(ctx)


func test_sword_bow_arrival_on_sword_banks_combo() -> void:
	var ctx := _make([SWORD, BOW], {"sword": T, "bow": T})
	_swap_to(ctx, SWORD)
	assert_eq(ctx.combo.points, 2, "Skirmisher's Rhythm: to the sword = 2 combo")
	assert_eq(ctx.momentum.stacks, 0)
	_cleanup(ctx)


func test_sword_staff_one_shot_flags_per_direction() -> void:
	var ctx := _make([SWORD, STAFF], {"sword": T, "staff": T})
	_swap_to(ctx, STAFF)
	assert_true(ctx.comp._ss_spell_spend_double, "to the staff: next combo-spend pays double")
	assert_false(ctx.comp._ss_double_imbue)
	ctx.comp._duo_swap_ready_at_ms = 0   # bypass ICD for the reverse direction
	_swap_to(ctx, SWORD)
	assert_true(ctx.comp._ss_double_imbue, "to the sword: next stance imbue strikes twice")
	_cleanup(ctx)


# ── Swap ICD ─────────────────────────────────────────────────────────────────

func test_swap_trigger_respects_icd() -> void:
	var ctx := _make([SWORD, BOW], {"sword": T, "bow": T})
	_swap_to(ctx, BOW)
	assert_eq(ctx.momentum.stacks, 3, "first swap fires")
	_swap_to(ctx, SWORD)
	_swap_to(ctx, BOW)
	assert_eq(ctx.momentum.stacks, 3, "swaps inside the 8s ICD must not re-fire")
	assert_eq(ctx.combo.points, 0)
	ctx.comp._duo_swap_ready_at_ms = 0   # simulate the ICD elapsing
	_swap_to(ctx, BOW)
	assert_eq(ctx.momentum.stacks, 6, "fires again once the ICD elapses")
	_cleanup(ctx)


# ── Cleanup paths ────────────────────────────────────────────────────────────

func test_bd_charge_drops_when_pair_unequipped() -> void:
	var ctx := _make([BOW, DAGGER], {"bow": T, "dagger": T})
	ctx.comp._bd_charge = 7
	ctx.comp.on_weapon_state_changed(BOW, [BOW, STAFF])  # dagger swapped out
	assert_eq(ctx.comp._bd_charge, 0, "buffer drops the moment the pair breaks")
	_cleanup(ctx)


func test_owner_death_clears_one_shot_flags() -> void:
	var ctx := _make([SWORD, STAFF], {"sword": T, "staff": T})
	_swap_to(ctx, STAFF)
	assert_true(ctx.comp._ss_spell_spend_double)
	ctx.comp.on_owner_died()
	assert_false(ctx.comp._ss_spell_spend_double, "death clears pending duo payoffs")
	assert_eq(ctx.comp._bd_charge, 0)
	_cleanup(ctx)
