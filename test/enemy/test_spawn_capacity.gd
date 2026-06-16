# Unit tests for the MapleStory population-scaling capacity curve
# (EnemySpawner.capacity_for). Validates the published scalar table, the
# hibernation (0-occupant) case, the full-party clamp, and the min-1 floor that
# keeps tiny pools (e.g. a lone boss) from being scaled out of existence.
# See docs/maplestory_spawn_mechanics.md.
extends "res://test/test_case.gd"


# The doc's reference table on a 30-spawn-point map: solo 75% -> 22, rising to
# 100% -> 30 at a full party of 6. floor() is what produces the documented 22/25/28.
func test_doc_table_on_thirty_point_map() -> void:
	assert_eq(EnemySpawner.capacity_for(30, 1), 22, "solo = 75% -> floor(22.5)")
	assert_eq(EnemySpawner.capacity_for(30, 2), 24, "2 players = 80%")
	assert_eq(EnemySpawner.capacity_for(30, 3), 25, "3 players = 85% -> floor(25.5)")
	assert_eq(EnemySpawner.capacity_for(30, 4), 27, "4 players = 90%")
	assert_eq(EnemySpawner.capacity_for(30, 5), 28, "5 players = 95% -> floor(28.5)")
	assert_eq(EnemySpawner.capacity_for(30, 6), 30, "full party = 100%")


func test_zero_occupants_is_hibernation() -> void:
	assert_eq(EnemySpawner.capacity_for(30, 0), 0, "empty map: no spawning")
	assert_eq(EnemySpawner.capacity_for(5, 0), 0, "empty map: no spawning (small pool)")


func test_party_larger_than_six_clamps_to_full() -> void:
	assert_eq(EnemySpawner.capacity_for(30, 7), 30, "beyond full party stays at 100%")
	assert_eq(EnemySpawner.capacity_for(30, 50), 30, "huge crowd still capped at pool_size")


func test_min_one_so_tiny_pools_survive() -> void:
	# A lone-boss spawner (pool_size 1) solo: floor(1 * 0.75) = 0, but the min-1
	# floor keeps the boss present.
	assert_eq(EnemySpawner.capacity_for(1, 1), 1, "solo boss never scaled to 0")
	assert_eq(EnemySpawner.capacity_for(2, 1), 1, "floor(1.5) = 1")


func test_capacity_is_monotonic_in_occupants() -> void:
	var prev := EnemySpawner.capacity_for(10, 1)
	for occ in range(2, 8):
		var cur := EnemySpawner.capacity_for(10, occ)
		assert_true(cur >= prev, "cap never shrinks as occupants rise (occ=%d)" % occ)
		prev = cur


# The over-cap / "spawn debt" rule isn't in capacity_for itself (it's the
# to_spawn = cap - alive clamp in _replenish), but we can assert the invariant the
# clamp relies on: when alive already meets or exceeds the solo cap, the deficit is
# non-positive, so nothing is added and nothing is removed.
func test_overcap_yields_no_spawn_deficit() -> void:
	var solo_cap := EnemySpawner.capacity_for(30, 1) # 22
	var alive_left_by_party := 28
	var to_spawn := solo_cap - alive_left_by_party
	assert_true(to_spawn <= 0, "28 alive vs 22 cap -> no respawn (spawn debt)")
	# Down to exactly cap: still no respawn.
	assert_true(solo_cap - 22 <= 0, "at cap -> no respawn")
	# One below cap: exactly one respawn owed.
	assert_eq(solo_cap - 21, 1, "21 alive vs 22 cap -> one respawn owed")
