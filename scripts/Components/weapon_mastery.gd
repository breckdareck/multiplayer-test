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
## PR 8 (2026-05-31): raised 20 → 100 to align with the character level cap.
## Mastery climbs ~1.4× faster than character level via the recalibrated XP
## curve, so a focused player reaches mastery 100 around character level 70.
## Char 70-100 is the "refinement phase" — mastery already capped, char XP
## continues for attribute points + gear. See
## docs/adr/... and project_ability_point_economy_redesign memory note.
const MASTERY_CAP: int = 100

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
## character starting fresh on Halberd kills Lv 70 enemies for ~75 XP per
## kill, so the catch-up is fast. Meanwhile, that same Lv 70 character
## one-shotting Lv 1 slimes still earns next to nothing — farming stays
## suppressed.
##
## Early-game pass (2026-06-11): pure `enemy_level` starved levels 1-15 —
## L1-10 mobs paid 1-10 XP against level costs of 60+, and the -15%/level
## diff penalty floored normal early play (a char-11 in the L5 forest) to
## 1 XP/kill. Three changes, all invisible at endgame:
##   - KILL_XP_FLAT_BASE 0 → 5: every kill pays a real minimum (3-6× early
##     income; +7% at L70).
##   - KILL_XP_LEVEL_DIFF_SCALAR 0.15 → 0.10 and MIN_MODIFIER 0.10 → 0.30:
##     a few levels' gap — "the next map over" early on — is a haircut, not
##     a cliff. Endgame slime-farming stays dead because the BASE for an L1
##     mob is tiny regardless of the modifier.
##
## Formula:
##   base = max(1, KILL_XP_FLAT_BASE + enemy_level * KILL_XP_PER_ENEMY_LEVEL)
##   modifier = clamp(1 + (enemy_level - player_level) * SCALAR, MIN, MAX)
##   final = max(FLOOR, round(base * modifier))
##
## Examples (player_level = 70):
##   Lv 70 enemy → base 75 × 1.0 = 75 XP (baseline at-level kill)
##   Lv 80 enemy → base 85 × 2.0 = 170 XP (reach-up bonus)
##   Lv 1 slime  → base 6 × 0.30 (floored) = 2 XP (farming useless)
## Examples (player_level = 11, the early band the pass targets):
##   Lv 10 enemy → base 15 × 0.90 = 14 XP (was ~9)
##   Lv 5 enemy  → base 10 × 0.40 = 4 XP  (was 1 — floored)
##
## Tune via:
##   KILL_XP_FLAT_BASE:          flat paid on every kill — the early-game lever
##   KILL_XP_PER_ENEMY_LEVEL:    base scalar — raise to multiply all kills
##   KILL_XP_LEVEL_DIFF_SCALAR:  modifier shift per level of gap
##   KILL_XP_MIN_MODIFIER:       floor multiplier (caps farming penalty)
##   KILL_XP_MAX_MODIFIER:       ceiling multiplier (caps reach-up bonus)
##   KILL_XP_FLOOR:              absolute minimum XP per kill
const KILL_XP_FLAT_BASE: float = 5.0
const KILL_XP_PER_ENEMY_LEVEL: float = 1.0
const KILL_XP_LEVEL_DIFF_SCALAR: float = 0.10
const KILL_XP_MIN_MODIFIER: float = 0.30
const KILL_XP_MAX_MODIFIER: float = 2.5
const KILL_XP_FLOOR: int = 1


## Computes the mastery XP awarded for a single kill, given the enemy's
## level and the player's character level. Static so combat.gd can call
## without needing a component instance (used for both primary + secondary
## weapon credits in the same hit).
static func compute_kill_xp(enemy_level: int, player_level: int) -> int:
	var base_xp: float = max(1.0, KILL_XP_FLAT_BASE + float(enemy_level) * KILL_XP_PER_ENEMY_LEVEL)
	var level_diff: int = enemy_level - player_level
	var modifier: float = clampf(
		1.0 + level_diff * KILL_XP_LEVEL_DIFF_SCALAR,
		KILL_XP_MIN_MODIFIER,
		KILL_XP_MAX_MODIFIER
	)
	return max(KILL_XP_FLOOR, roundi(base_xp * modifier))

## XP curve (PR 8 — recalibrated for MASTERY_CAP 100 alignment with char 70):
## `_xp_to_next_level(N) = XP_BASE + XP_LINEAR*N + XP_QUADRATIC*N² + XP_CUBIC*N³`.
## Front-loaded (cheap early levels for instant gratification) with a cubic
## tail so late ranks are a real commitment. Target: cumulative XP to rank 100
## ≈ 1.05M, roughly what a focused at-level grinder earns hitting char level 70
## (calibrated against leveling_curve.tres + monster_exp_curve.tres).
##
## Early-game pass (2026-06-11): XP_BASE 30 → 15 and XP_LINEAR 30 → 20. The
## old early costs (62/98/139 for ranks 2-4) were priced for mid-game kill
## payouts, but L1-10 kills only pay ~6-15 XP even after the kill-XP flat
## base — chars hit level 11 at mastery 3. Levels 1-10 cost ~2K of the ~1.05M
## total, so cheapening them moves early pacing without touching the late
## grind. With the kill-XP changes, an at-level grinder now tracks roughly
## mastery ≈ char level through the first ~15 levels, pulling ahead after.
##
##   level 0 -> 1:        15 XP    (~2-3 kills — first pick immediately)
##   level 1 -> 2:        37 XP    (~4 at-lvl kills)
##   level 9 -> 10:      393 XP    (~26 at-lvl-10 kills)
##   level 29 -> 30:   3,496 XP    (~100 at-lvl-30 kills)
##   level 49 -> 50:  11,679 XP    (~210 at-lvl-50 kills)
##   level 69 -> 70:  27,342 XP    (~365 at-lvl-70 kills)
##   level 99 -> 100: 70,111 XP    (~670 at-lvl-99 kills)
##   total 0 -> 100: ~1.05M XP — reached around character level 70
##
## Tune these constants together. Raising XP_CUBIC most steeply punishes late
## levels; raising XP_BASE slows the first few levels.
const XP_BASE: int = 15
const XP_LINEAR: int = 20
const XP_QUADRATIC: int = 2
const XP_CUBIC: float = 0.05

#endregion


#region #################### Signals ####################

## Emitted on both server and client whenever a discipline's mastery level
## changes. Listeners (Stats, UI) should call `mark_stats_dirty()` or refresh
## the relevant display.
signal mastery_level_changed(discipline: int, new_level: int)

## Emitted whenever mastery XP changes (level-up included). Mainly for UI
## progress bars; not used by stat scaling.
signal mastery_xp_changed(discipline: int, current_xp: int, xp_to_next: int)

## Emitted when the character's PRIMARY discipline changes (set once at spawn
## from the saved character_type; never changes mid-session now that job
## advancement is removed). Stats/Ability/UI listeners recalc or re-seed.
## Replaces the old ClassComponent.class_changed signal.
signal primary_discipline_changed(discipline: int)

#endregion


#region #################### State ####################

## Per-discipline mastery records, keyed by `Constants.ClassType` int.
## Each value is a Dictionary: `{"level": int, "xp": int}` where `xp` is the
## progress toward the NEXT level (resets on level-up). Only tier-1 weapon
## disciplines (SWORD / BOW / STAFF / DAGGER) are populated by default.
## Persisted by save_mastery / load_mastery.
var mastery_data: Dictionary = {}

var _loading_mode: bool = false

## The character's PRIMARY weapon discipline — the "default identity" pointer
## that answers: which discipline am I when no weapon decides it? Drives the
## unarmed/sprite fallback, base-stat baseline, HP/MP curve, and the
## starting-ability seed. Persisted via the existing `character_type` save
## field (→ backend `character_class` column); NOT round-tripped in
## save_mastery. Set once at spawn from character_type via set_primary_discipline.
##
## Absorbs the legacy ClassComponent role. The setter normalizes any legacy
## advanced class (CRUSADER/RANGER/ARCHMAGE/ASSASSIN) back to its tier-1 weapon
## discipline so existing advanced characters revert to weapon-pure on load —
## no backend migration needed; the setter catches every assignment.
var primary_discipline: int = Constants.ClassType.SWORD:
	set(value):
		primary_discipline = _ADVANCED_TO_BASE.get(value, value)

const _ADVANCED_TO_BASE: Dictionary = {
	Constants.ClassType.CRUSADER: Constants.ClassType.SWORD,
	Constants.ClassType.RANGER: Constants.ClassType.BOW,
	Constants.ClassType.ARCHMAGE: Constants.ClassType.STAFF,
	Constants.ClassType.ASSASSIN: Constants.ClassType.DAGGER,
}

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

#region ---- Primary discipline (absorbed ClassComponent role) ----

## Returns the character's primary weapon discipline (Constants.ClassType int).
func get_primary_discipline() -> int:
	return primary_discipline


## Sets the primary discipline, normalizing legacy advanced classes to tier-1.
## Emits primary_discipline_changed on a real change (drives stat recalc +
## ability re-seed) and notifies PartyManager on the server. Mirrors the old
## ClassComponent.change_class. Safe to call on server and on the client mirror
## (the RPC variant routes here on every peer).
func set_primary_discipline(new_discipline: int) -> void:
	var normalized: int = _ADVANCED_TO_BASE.get(new_discipline, new_discipline)
	if normalized == primary_discipline:
		return
	primary_discipline = normalized
	primary_discipline_changed.emit(primary_discipline)
	if multiplayer and multiplayer.is_server():
		PartyManager.notify_player_data_changed(get_owner().player_id)


## Server -> all peers. Authoritative primary-discipline set; call_local so the
## host (server + client in one tree) runs it too. Replaces
## ClassComponent.change_class_rpc.
@rpc("authority", "call_local", "reliable")
func set_primary_discipline_rpc(new_discipline: int) -> void:
	set_primary_discipline(new_discipline)


## The abilities belonging to the primary discipline's tree. Replaces
## ClassComponent.get_class_abilities (computed fresh — no cache needed).
func get_primary_abilities() -> Array[AbilityData]:
	return ResourceManager.get_class_skills(primary_discipline)


## Base stat dictionary for the primary discipline. Replaces
## ClassComponent.get_base_stats.
func get_base_stats() -> Dictionary:
	return ResourceManager.get_base_stats(primary_discipline)


## Primary discipline's class bonuses. Replaces ClassComponent.get_class_bonuses.
func get_class_bonuses() -> Dictionary:
	return ResourceManager.get_class_bonuses(primary_discipline)


## Display name of the primary discipline. Replaces ClassComponent.get_class_name.
func get_discipline_name() -> String:
	return ResourceManager.get_class_name(primary_discipline)

#endregion


#region ---- Wielded identity (the "I am my weapon" lookups) ----

## Returns the discipline the character is CURRENTLY WIELDING — the discipline of
## the active weapon — falling back to `primary_discipline` when no weapon is
## equipped. This is the "I am my weapon" identity lookup: use it for sprite
## picking, attack-state branches, ability gating, signature activation, and any
## behavior that should follow the equipped weapon rather than the chosen primary
## discipline. (HP/MP curves intentionally stay anchored to primary_discipline —
## they do NOT shift on weapon swap.)
##
## Moved here from the player root (multiplayer_controller_v2) in the candidate-1
## deepening: WeaponMastery is the single owner of weapon identity (ADR-0004), so
## it owns BOTH the primary pointer and the active/wielded lookup. The player root
## keeps a thin forwarder for its many duck-typed callers.
func get_active_discipline() -> int:
	var equip = owner.get("equipment_component") if owner != null else null
	if is_instance_valid(equip):
		var weapon: WeaponData = equip.active_weapon_data
		if weapon != null:
			var disc: int = weapon_type_to_discipline(weapon.weapon_type)
			if disc != -1:
				return disc
	return primary_discipline


## Returns the disciplines of ALL equipped weapons — both the primary AND the
## secondary slot — de-duplicated. Used by AbilityComponent's passive-application
## rule: a passive from discipline X applies if X has a weapon in EITHER slot (not
## just the active one). Trees you've invested but not equipped contribute nothing.
##
## If neither slot is equipped (bare-handed), falls back to [primary_discipline]
## so passives still work in the un-equipped baseline case.
func get_equipped_disciplines() -> Array[int]:
	var disciplines: Array[int] = []
	var equip = owner.get("equipment_component") if owner != null else null
	if is_instance_valid(equip):
		var primary_sd: SlotData = equip.weapon_slot_data
		if primary_sd != null and primary_sd.item != null:
			var primary_weapon: WeaponData = primary_sd.item as WeaponData
			if primary_weapon != null:
				var disc: int = weapon_type_to_discipline(primary_weapon.weapon_type)
				if disc != -1:
					disciplines.append(disc)
		var secondary_sd: SlotData = equip.secondary_weapon_slot_data
		if secondary_sd != null and secondary_sd.item != null:
			var secondary_weapon: WeaponData = secondary_sd.item as WeaponData
			if secondary_weapon != null:
				var disc2: int = weapon_type_to_discipline(secondary_weapon.weapon_type)
				if disc2 != -1 and not disciplines.has(disc2):
					disciplines.append(disc2)
	if disciplines.is_empty():
		disciplines.append(primary_discipline)
	return disciplines

#endregion


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
	return XP_BASE + XP_LINEAR * n + XP_QUADRATIC * n * n + int(XP_CUBIC * n * n * n)


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
	var levels_gained: int = 0

	while level < MASTERY_CAP and xp >= _xp_to_next_level(level):
		xp -= _xp_to_next_level(level)
		level += 1
		levels_gained += 1
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
	# One emit PER level gained: AbilityComponent grants ability points per
	# emit, so a single big XP grant that crosses several thresholds must not
	# collapse into one signal (it silently ate the extra points).
	if leveled_up:
		for i in range(levels_gained):
			mastery_level_changed.emit(discipline, level - levels_gained + 1 + i)
		# Juice: one "MASTERY UP!" float + ding per grant (not per level — a big XP
		# grant crossing several thresholds shows a single cue). Players only; bots
		# gain mastery constantly and would spam it map-wide.
		if is_instance_valid(owner) and not BotManager.is_bot(owner.player_id):
			EventJuice.proc(owner, "MASTERY UP!", EventJuice.COLOR_MOMENTUM, "res://assets/sounds/generated/mastery_ding.wav", "")
	mastery_xp_changed.emit(discipline, xp, _xp_to_next_level(level))

	# Persist. The player root listens for this through the same _data_changed
	# path the other stateful components use.
	_mark_owner_save_dirty()


## PR 8: Server-only. Bumps a discipline's mastery level from 0 to 1 without
## requiring earned XP — used at character creation so the player has 1 ability
## point to spend on their first ability of choice (replacing the old "free
## starter ability" system). Idempotent: if the discipline is already past 0,
## does nothing. Emits mastery_level_changed so AbilityComponent grants the
## point through its normal pathway.
func bootstrap_chosen_discipline(discipline: int) -> void:
	if not multiplayer.is_server():
		return
	if not _is_tier1_discipline(discipline):
		return
	if not mastery_data.has(discipline):
		mastery_data[discipline] = {"level": 0, "xp": 0}
	var entry: Dictionary = mastery_data[discipline]
	if int(entry.get("level", 0)) > 0:
		return  # already bootstrapped
	entry["level"] = 1
	entry["xp"] = 0
	mastery_data[discipline] = entry
	if not BotManager.is_bot(owner.player_id):
		sync_mastery_to_client.rpc_id(owner.player_id, discipline, 1, 0)
	mastery_level_changed.emit(discipline, 1)
	mastery_xp_changed.emit(discipline, 0, _xp_to_next_level(1))
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

## [SERVER] Pushes the FULL mastery state (every discipline's level + xp) to one
## client in a burst of sync_mastery_to_client RPCs. Called by the JoinHandshake
## SYNC phase: the incremental sync only fires on XP grants, so a fresh client
## mirror (first join AND every map-change rebuild) would otherwise read zeros
## on the mastery bar / ability window until the next kill.
func sync_all_mastery_to_client(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for discipline in mastery_data:
		var entry: Dictionary = mastery_data[discipline]
		sync_mastery_to_client.rpc_id(peer_id, discipline, int(entry.get("level", 0)), int(entry.get("xp", 0)))


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
