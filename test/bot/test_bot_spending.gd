# Bot point-spending tests (2026-06-04): the weapon-system bot must spend its
# attribute points on its weapon's stat ratio (plus a CONSTITUTION survival
# bias) rather than letting them pile up unused.
#
# Scope: BotCombat._auto_spend_attribute_points against a REAL StatsComponent.
# The ability-point greedy leans on AbilityComponent's own (separately tested)
# can_level_up / level_up / purchase_upgrade API, so it is exercised live in
# game rather than re-mocked here. We drive the attribute path because its
# ratio math is pure and deterministic.
#
# Mount pattern mirrors test_respec_economy.gd: a bare StatsComponent under a
# stub owner carrying a NEGATIVE player_id (so it reads as a bot and the sync
# fan-out is skipped) and a real Leveling child the component reads `level` off.
extends "res://test/test_case.gd"

const BotCombat := preload("res://scripts/Bot/bot_combat.gd")

const CON := Constants.StatType.CONSTITUTION
const STR := Constants.StatType.STRENGTH
const DEX := Constants.StatType.DEXTERITY
const LUCK := Constants.StatType.LUCK
const INT := Constants.StatType.INTELLIGENCE


# ── Fakes ─────────────────────────────────────────────────────────────────────

## Minimal weapon-mastery stand-in: the bot only reads `primary_discipline`.
class _WMStub extends Node:
	var primary_discipline: int = Constants.ClassType.SWORD

## Player stand-in exposing the members the bot's spend path resolves, plus the
## player_id the StatsComponent sync guard reads (negative = bot).
class _PlayerStub extends Node:
	var player_id: int = -1
	var stats_component: StatsComponent = null
	var weapon_mastery_component = null


# ── Mount helper ──────────────────────────────────────────────────────────────

func _ensure_offline_peer() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var mp := tree.get_multiplayer()
	if not (mp.multiplayer_peer is OfflineMultiplayerPeer):
		mp.multiplayer_peer = OfflineMultiplayerPeer.new()

## Builds a player stub with a live StatsComponent at the given level + discipline.
func _make_player(level: int, discipline: int) -> _PlayerStub:
	_ensure_offline_peer()
	var tree := Engine.get_main_loop() as SceneTree
	var player := _PlayerStub.new()
	player.player_id = -1   # negative = bot: skips the client sync fan-out

	var leveling := LevelingComponent.new()
	leveling.name = "Leveling"
	leveling._is_loading_data = true
	player.add_child(leveling)

	var wm := _WMStub.new()
	wm.primary_discipline = discipline
	player.weapon_mastery_component = wm
	player.add_child(wm)

	var stats := StatsComponent.new()
	player.add_child(stats)
	stats.owner = player
	stats._level_component = leveling
	stats._loading_mode = true
	player.stats_component = stats

	tree.root.add_child(player)
	leveling.level = level   # set in-tree so the setter's is_server guard has a peer
	return player


func _bot() -> RefCounted:
	return BotCombat.new(null)   # brain unused by the attribute spend path


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_sword_bot_spends_on_str_dex_con_ratio() -> void:
	# Sword stat_bonuses = {STR:3, DEX:2}; the bot folds in CON survival (+2),
	# giving weights {STR:3, DEX:2, CON:2} over a 7-share total.
	# Level 11 -> 5*(11-1) = 50 granted points.
	var player := _make_player(11, Constants.ClassType.SWORD)
	var stats := player.stats_component
	assert_eq(stats.get_attribute_points_granted(), 50, "5 * (level-1)")
	assert_eq(stats.get_attribute_points_unused(), 50, "nothing spent yet")

	_bot()._auto_spend_attribute_points(player)

	# round(3/7*50)=21, round(2/7*50)=14 each -> 49, remainder 1 dumped on the
	# top-weight stat (STR) -> 22 / 14 / 14.
	assert_eq(stats.get_attribute_points_unused(), 0, "all points spent")
	assert_eq(stats.get_allocated_attribute(STR), 22, "STR gets the largest share + remainder")
	assert_eq(stats.get_allocated_attribute(DEX), 14, "DEX secondary")
	assert_eq(stats.get_allocated_attribute(CON), 14, "CON survival bias")
	assert_eq(stats.get_allocated_attribute(INT), 0, "no off-weapon stat")
	assert_eq(stats.get_allocated_attribute(LUCK), 0, "no off-weapon stat")


func test_dagger_bot_favors_luck() -> void:
	# Dagger stat_bonuses = {DEX:2, LUCK:3} + CON:2 -> LUCK is the top weight.
	var player := _make_player(11, Constants.ClassType.DAGGER)
	var stats := player.stats_component

	_bot()._auto_spend_attribute_points(player)

	assert_eq(stats.get_attribute_points_unused(), 0, "all points spent")
	assert_true(stats.get_allocated_attribute(LUCK) >= stats.get_allocated_attribute(DEX),
		"LUCK (primary) >= DEX (secondary)")
	assert_true(stats.get_allocated_attribute(CON) > 0, "CON survival bias present")
	assert_eq(stats.get_allocated_attribute(STR), 0, "no off-weapon stat")


func test_level_one_bot_has_nothing_to_spend() -> void:
	# Level 1 grants 0 points — the spend pass must be a safe no-op.
	var player := _make_player(1, Constants.ClassType.SWORD)
	var stats := player.stats_component
	assert_eq(stats.get_attribute_points_granted(), 0, "no points at level 1")

	_bot()._auto_spend_attribute_points(player)

	assert_eq(stats.get_attribute_points_spent(), 0, "nothing allocated")


func test_spend_is_idempotent() -> void:
	# Running the pass twice spends each point exactly once (no double-dipping,
	# no unallocation) — the second pass finds zero unused and changes nothing.
	var player := _make_player(11, Constants.ClassType.SWORD)
	var stats := player.stats_component

	_bot()._auto_spend_attribute_points(player)
	var str_after_first := stats.get_allocated_attribute(STR)
	assert_eq(stats.get_attribute_points_unused(), 0, "first pass drains the pool")

	_bot()._auto_spend_attribute_points(player)
	assert_eq(stats.get_allocated_attribute(STR), str_after_first, "second pass is a no-op")
	assert_eq(stats.get_attribute_points_unused(), 0, "still fully spent")


func test_new_points_after_leveling_top_up_con_toward_target() -> void:
	# A migrated bot pre-allocated to the OLD class ratio (STR/DEX, no CON) keeps
	# those points; new points earned by leveling funnel into CON until it catches
	# its target share. Verifies the shortfall-only top-up never unallocates.
	var player := _make_player(11, Constants.ClassType.SWORD)
	var stats := player.stats_component
	# Simulate the migration default-allocation: all 50 points on the weapon ratio
	# with no CON (old _default_allocate had no CONSTITUTION line).
	stats._allocated_attributes = {STR: 30, DEX: 20}
	assert_eq(stats.get_attribute_points_unused(), 0, "fully migrated, no spare points")

	# Bot dings to level 12 -> +5 granted points become available.
	player.get_node("Leveling").level = 12
	assert_eq(stats.get_attribute_points_unused(), 5, "5 fresh points from the level")

	_bot()._auto_spend_attribute_points(player)

	assert_eq(stats.get_attribute_points_unused(), 0, "fresh points spent")
	assert_eq(stats.get_allocated_attribute(STR), 30, "migrated STR untouched")
	assert_eq(stats.get_allocated_attribute(DEX), 20, "migrated DEX untouched")
	assert_true(stats.get_allocated_attribute(CON) > 0, "fresh points went to under-target CON")
