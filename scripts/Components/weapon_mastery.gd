class_name WeaponMasteryComponent
extends Node

## Tracks per-weapon-discipline mastery levels. Each tier-1 weapon discipline
## (Sword / Bow / Staff / Dagger) has its own independent mastery scale capped
## at MASTERY_CAP. Mastery XP is granted on the server when the character lands
## an enemy kill with that weapon (see compute_kill_xp for the level-scaled
## formula) or casts an ability while that weapon is equipped (XP_PER_CAST).
## Mastery drives the player's STR/DEX/INT/LUK scaling in StatsComponent
## additively on top of class-level scaling.
##
## Server-authoritative: only the server mutates state; clients receive updates
## via sync_mastery_to_client RPCs and maintain a mirror copy for UI.

#region #################### Constants ####################

## Maximum mastery level a single discipline can reach.
const MASTERY_CAP: int = 20

## XP granted to the active weapon's discipline when its wielder lands a HIT
## with an ability. PR 4 fix (2026-05-28): the grant moved from cast-time
## (in ability.gd) to hit-time (in combat.gd._execute_hit) because granting
## on bare casts let a player spam an ability in an empty area to grind
## mastery without engaging enemies. Now the cast must actually hit an
## enemy. Multi-hit abilities credit per landed hit (so a 2-hit ability that
## lands both hits gives 2 XP). Self-targeted buff/heal abilities that never
## reach _execute_hit give zero mastery XP — combat engagement is the proxy.
##
## Skipped for:
##  - Basic attacks (where `ability == null` in _execute_hit)
##  - Internal-pathway abilities with empty `required_class` (the convention
##    from the Arrow Shot fix). Archers' basic attack routes through Arrow
##    Shot which IS an AbilityData; without that guard, archers would double-
##    dip mastery XP compared to sword/dagger basic swings.
##
## Flat (not level-scaled): a single hit isn't a strong enough signal of
## difficulty to warrant scaling, and casts are already MP/cooldown-bounded.
const XP_PER_CAST: int = 1

## PR 4 fix (2026-05-28 revision 2): kill XP now uses `enemy_level` as the
## BASE (scaled by KILL_XP_PER_ENEMY_LEVEL), with the relative-level-diff
## modifier on top. This solves the high-level-pickup problem: a Lv 70
## character starting fresh on Halberd kills Lv 70 enemies for ~70 XP per
## kill, so the catch-up is fast. Meanwhile, that same Lv 70 character
## one-shotting Lv 1 slimes still hits the floor (1 XP) — farming stays
## suppressed.
##
## Formula:
##   base = max(1, enemy_level * KILL_XP_PER_ENEMY_LEVEL)
##   modifier = clamp(1 + (enemy_level - player_level) * SCALAR, MIN, MAX)
##   final = max(FLOOR, round(base * modifier))
##
## Examples (player_level = 70):
##   Lv 70 enemy → base 70 × 1.0 = 70 XP (baseline at-level kill)
##   Lv 80 enemy → base 80 × 2.5 (clamped) = 200 XP (reach-up bonus)
##   Lv 1 slime  → base 1 × 0.10 (floored) = 1 XP (farming useless)
##
## Tune via:
##   KILL_XP_PER_ENEMY_LEVEL:    base scalar — raise to multiply all kills
##   KILL_XP_LEVEL_DIFF_SCALAR:  modifier shift per level of gap
##   KILL_XP_MIN_MODIFIER:       floor multiplier (caps farming penalty)
##   KILL_XP_MAX_MODIFIER:       ceiling multiplier (caps reach-up bonus)
##   KILL_XP_FLOOR:              absolute minimum XP per kill
const KILL_XP_PER_ENEMY_LEVEL: float = 1.0
const KILL_XP_LEVEL_DIFF_SCALAR: float = 0.15
const KILL_XP_MIN_MODIFIER: float = 0.10
const KILL_XP_MAX_MODIFIER: float = 2.5
const KILL_XP_FLOOR: int = 1


## Computes the mastery XP awarded for a single kill, given the enemy's
## level and the player's character level. Static so combat.gd can call
## without needing a component instance (used for both primary + secondary
## weapon credits in the same hit).
static func compute_kill_xp(enemy_level: int, player_level: int) -> int:
	var base_xp: float = max(1.0, float(enemy_level) * KILL_XP_PER_ENEMY_LEVEL)
	var level_diff: int = enemy_level - player_level
	var modifier: float = clampf(
		1.0 + level_diff * KILL_XP_LEVEL_DIFF_SCALAR,
		KILL_XP_MIN_MODIFIER,
		KILL_XP_MAX_MODIFIER
	)
	return max(KILL_XP_FLOOR, roundi(base_xp * modifier))

## XP curve (PR 4 fix 2026-05-28 — replaced flat linear (N+1)*100):
## `_xp_to_next_level(N) = XP_BASE + XP_LINEAR * N + XP_QUADRATIC * N * N`.
## Quick early levels for instant gratification, then quadratic ramp so
## maxing a weapon is a real commitment (New World-style mastery feel).
##
##   level 0 -> 1:    30 XP    (~6 kills, ~30 seconds)
##   level 4 -> 5:   550 XP    (~110 kills, ~10 minutes)
##   level 9 -> 10: 2,325 XP   (~465 kills, ~30-45 minutes)
##   level 14 -> 15: 5,350 XP  (~1,070 kills, ~1-2 hours)
##   level 19 -> 20: 9,625 XP  (~1,925 kills, ~3+ hours)
##   total 0 -> 20:  ~68,000 XP (~10-15 hours focused play per weapon)
##
## Tune these constants together — they trade off early gratification vs.
## late-game commitment. Raising XP_QUADRATIC most steeply punishes late
## levels; raising XP_BASE most slows the first few levels.
const XP_BASE: int = 30
const XP_LINEAR: int = 30
const XP_QUADRATIC: int = 25

#endregion


#region #################### Signals ####################

## Emitted on both server and client whenever a discipline's mastery level
## changes. Listeners (Stats, UI) should call `mark_stats_dirty()` or refresh
## the relevant display.
signal mastery_level_changed(discipline: int, new_level: int)

## Emitted whenever mastery XP changes (level-up included). Mainly for UI
## progress bars; not used by stat scaling.
signal mastery_xp_changed(discipline: int, current_xp: int, xp_to_next: int)

#endregion


#region #################### State ####################

## Per-discipline mastery records, keyed by `Constants.ClassType` int.
## Each value is a Dictionary: `{"level": int, "xp": int}` where `xp` is the
## progress toward the NEXT level (resets on level-up). Only tier-1 weapon
## disciplines (SWORD / BOW / STAFF / DAGGER) are populated by default.
## Persisted by save_mastery / load_mastery.
var mastery_data: Dictionary = {}

var _loading_mode: bool = false

#endregion


#region #################### Lifecycle ####################

func _ready() -> void:
	_ensure_default_disciplines()


## Populates mastery_data with zero-state entries for the four tier-1 weapon
## disciplines. Safe to call multiple times — existing entries are preserved.
func _ensure_default_disciplines() -> void:
	for discipline in [
		Constants.ClassType.SWORD,
		Constants.ClassType.BOW,
		Constants.ClassType.STAFF,
		Constants.ClassType.DAGGER,
	]:
		if not mastery_data.has(discipline):
			mastery_data[discipline] = {"level": 0, "xp": 0}

#endregion


#region #################### Public API ####################

## Returns the mastery level for a given discipline. Disciplines without a
## record return 0 — they behave as if mastery were never started.
func get_mastery_level(discipline: int) -> int:
	var entry: Dictionary = mastery_data.get(discipline, {})
	return int(entry.get("level", 0))


## Returns the current XP progress toward the next level for a given
## discipline. Resets to 0 each time the level increments.
func get_mastery_xp(discipline: int) -> int:
	var entry: Dictionary = mastery_data.get(discipline, {})
	return int(entry.get("xp", 0))


## XP required to advance from `current_level` to `current_level + 1`.
## Quadratic curve calibrated for quick early levels + a real late-game grind.
## See XP_BASE / XP_LINEAR / XP_QUADRATIC constants for the curve shape and
## the cost-per-level table.
func _xp_to_next_level(current_level: int) -> int:
	var n: int = current_level
	return XP_BASE + XP_LINEAR * n + XP_QUADRATIC * n * n


## Returns the XP cost to advance from a discipline's CURRENT level. Useful
## for UI progress bars.
func get_xp_to_next_level(discipline: int) -> int:
	return _xp_to_next_level(get_mastery_level(discipline))


## Server-only. Grants `amount` mastery XP to `discipline`, levels up while
## the XP threshold is met, emits the level-changed signal, and broadcasts
## the new state to the owning client (skip for bots — they have no client).
## Marks the owner's save dirty so the change persists.
func grant_mastery_xp_server(discipline: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	if amount <= 0:
		return
	# Mastery only applies to the four tier-1 weapon disciplines; any other
	# enum value (BEGINNER, the six tier-2 advancement classes) is ignored
	# so we don't accidentally grow mastery for slots that don't exist.
	if not _is_tier1_discipline(discipline):
		return

	if not mastery_data.has(discipline):
		mastery_data[discipline] = {"level": 0, "xp": 0}

	var entry: Dictionary = mastery_data[discipline]
	var level: int = int(entry.get("level", 0))
	var xp: int = int(entry.get("xp", 0))

	# Already capped: silently ignore further XP gains.
	if level >= MASTERY_CAP:
		return

	xp += amount
	var leveled_up: bool = false

	while level < MASTERY_CAP and xp >= _xp_to_next_level(level):
		xp -= _xp_to_next_level(level)
		level += 1
		leveled_up = true

	# At the cap, drop residual XP to keep the save tidy.
	if level >= MASTERY_CAP:
		xp = 0

	entry["level"] = level
	entry["xp"] = xp
	mastery_data[discipline] = entry

	# Notify the owning client so the mirror copy + UI stay in sync. Bots have
	# no client, so skip the RPC for them entirely.
	if not BotManager.is_bot(owner.player_id):
		sync_mastery_to_client.rpc_id(owner.player_id, discipline, level, xp)

	# Local emit on the server side — stats / UI listeners react here too.
	if leveled_up:
		mastery_level_changed.emit(discipline, level)
	mastery_xp_changed.emit(discipline, xp, _xp_to_next_level(level))

	# Persist. The player root listens for this through the same _data_changed
	# path the other stateful components use.
	_mark_owner_save_dirty()


## Returns the sum of (mastery_level * discipline.stat_bonuses[stat]) across all
## owned disciplines for a given stat. Stacks across disciplines so a player
## with mastery in multiple weapons grows their stats in multiple channels.
## Used by StatsComponent._recalculate_stats.
func get_summed_stat_bonus(stat: int) -> int:
	var total: int = 0
	for discipline in mastery_data:
		var level: int = get_mastery_level(discipline)
		if level <= 0:
			continue
		var data: WeaponDisciplineData = ResourceManager.get_class_data(discipline)
		if data == null:
			continue
		var bonus: int = int(data.stat_bonuses.get(stat, 0))
		if bonus == 0:
			continue
		total += bonus * level
	return total

#endregion


#region #################### Save / Load ####################

## Returns the persistable mastery state. Keyed by the lowercase discipline
## name (sword/bow/staff/dagger) for backend / save-file legibility. Round-trip
## with load_mastery: both `level` and `xp` are preserved.
func save_mastery() -> Dictionary:
	var out: Dictionary = {}
	for discipline in mastery_data:
		var key: String = _discipline_key(discipline)
		if key.is_empty():
			continue
		var entry: Dictionary = mastery_data[discipline]
		out[key] = {
			"level": int(entry.get("level", 0)),
			"xp": int(entry.get("xp", 0)),
		}
	# Guarantee all four tier-1 disciplines are present in the save payload
	# even if no XP has been earned yet, so older saves loaded into a newer
	# build still round-trip the full shape.
	for tier1 in [
		Constants.ClassType.SWORD,
		Constants.ClassType.BOW,
		Constants.ClassType.STAFF,
		Constants.ClassType.DAGGER,
	]:
		var key2: String = _discipline_key(tier1)
		if not out.has(key2):
			out[key2] = {"level": 0, "xp": 0}
	return out


## Loads a previously-saved mastery payload. Accepts the lowercase-discipline
## shape from save_mastery; missing disciplines fall back to zero. Suppresses
## signals while loading via the standard `set_loading_mode` pattern other
## components use.
func load_mastery(data: Dictionary) -> void:
	_loading_mode = true

	mastery_data.clear()
	_ensure_default_disciplines()

	for key in data:
		var discipline: int = _key_to_discipline(str(key))
		if discipline == -1:
			continue
		var entry_in = data[key]
		var level: int = 0
		var xp: int = 0
		if entry_in is Dictionary:
			level = int(entry_in.get("level", 0))
			xp = int(entry_in.get("xp", 0))
		elif entry_in is int or entry_in is float:
			# Legacy shape (level-only int) — accept gracefully.
			level = int(entry_in)
		mastery_data[discipline] = {
			"level": clamp(level, 0, MASTERY_CAP),
			"xp": max(xp, 0),
		}

	_loading_mode = false


func set_loading_mode(enabled: bool) -> void:
	_loading_mode = enabled


func is_loading() -> bool:
	return _loading_mode

#endregion


#region #################### RPCs ####################

## Server -> owning client. Mirrors the authoritative mastery state so the
## client's UI and downstream stat refresh can react. The body is idempotent
## (just sets values), so `call_local` is safe: on the server, running this
## with the values it just wrote is a no-op overwrite. `call_local` is required
## because the host is both server and client — without it, the server's
## `rpc_id(1, ...)` to itself errors with "RPC on yourself is not allowed".
@rpc("authority", "call_local", "reliable")
func sync_mastery_to_client(discipline: int, level: int, xp: int) -> void:
	if not mastery_data.has(discipline):
		mastery_data[discipline] = {"level": 0, "xp": 0}
	var entry: Dictionary = mastery_data[discipline]
	var old_level: int = int(entry.get("level", 0))
	entry["level"] = level
	entry["xp"] = xp
	mastery_data[discipline] = entry

	if level != old_level:
		mastery_level_changed.emit(discipline, level)
	mastery_xp_changed.emit(discipline, xp, _xp_to_next_level(level))

#endregion


#region #################### Helpers ####################

## Routes "this character's data has meaningfully changed" through the same
## debounced save path the other stateful components use. The player root
## connects component signals to its `_data_changed("stats")` helper; we
## piggyback by emitting on the StatsComponent's stats_changed signal — but
## that would over-couple the two. Instead we call the owner's `_data_changed`
## directly when available.
func _mark_owner_save_dirty() -> void:
	# Bots: PlayerManager.set_carried_state holds their state in memory across
	# despawn/respawn, but their kill/cast loop still wants the save to land
	# the next time SaveManager flushes. The owner's `_data_changed` already
	# guards against double-saving and respects the cleanup flag.
	var root := get_owner()
	if root == null:
		return
	if root.has_method("_data_changed"):
		root._data_changed("stats")


## True iff `discipline` is one of the four tier-1 weapon disciplines
## (SWORD / BOW / STAFF / DAGGER). Beginner and the six tier-2 advancement
## classes return false — they do not earn mastery XP in PR 2.
func _is_tier1_discipline(discipline: int) -> bool:
	return discipline == Constants.ClassType.SWORD \
		or discipline == Constants.ClassType.BOW \
		or discipline == Constants.ClassType.STAFF \
		or discipline == Constants.ClassType.DAGGER


## Maps a ClassType enum int to the canonical lowercase save key.
## Returns "" for non-tier-1 disciplines (they aren't persisted).
func _discipline_key(discipline: int) -> String:
	match discipline:
		Constants.ClassType.SWORD:
			return "sword"
		Constants.ClassType.BOW:
			return "bow"
		Constants.ClassType.STAFF:
			return "staff"
		Constants.ClassType.DAGGER:
			return "dagger"
	return ""


## Maps a lowercase save key back to the matching ClassType enum int.
## Returns -1 on unknown keys so callers can skip them.
func _key_to_discipline(key: String) -> int:
	match key.to_lower():
		"sword":
			return Constants.ClassType.SWORD
		"bow":
			return Constants.ClassType.BOW
		"staff":
			return Constants.ClassType.STAFF
		"dagger":
			return Constants.ClassType.DAGGER
	return -1

#endregion


#region #################### Static Helpers ####################

## Maps a `Constants.WeaponType` enum value to the matching tier-1
## `Constants.ClassType` discipline. Returns -1 if no mapping exists
## (callers should treat that as "no mastery grant for this weapon").
## Shared by CombatComponent and AbilityComponent.
static func weapon_type_to_discipline(weapon_type: int) -> int:
	match weapon_type:
		Constants.WeaponType.SWORD:
			return Constants.ClassType.SWORD
		Constants.WeaponType.BOW:
			return Constants.ClassType.BOW
		Constants.WeaponType.STAFF:
			return Constants.ClassType.STAFF
		Constants.WeaponType.DAGGER:
			return Constants.ClassType.DAGGER
	return -1

#endregion
