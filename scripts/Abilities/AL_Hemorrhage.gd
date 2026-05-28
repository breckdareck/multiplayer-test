extends Node

## Hemorrhage — single-target bleed-setter. On hit, applies (or refreshes
## and stacks) a bleed DOT on the target. Each stack ticks 5% of the
## applier's WEAPONATTACK per second for 6 seconds. Max 3 stacks.
##
## Enemies don't yet have a full BuffComponent (PR 6 scope keeps that
## deferred). Bleed is implemented via direct meta-tracking on the
## EnemyBase node — a self-contained pattern that doesn't require
## extending the global buff system. If/when enemies grow a BuffComponent,
## this can be migrated to use B_Bleed.tres + BL_Bleed.gd cleanly.

const MAX_STACKS: int = 3
const TICK_INTERVAL: float = 1.0
const DURATION_SECONDS: float = 6.0
const DAMAGE_PER_STACK_PCT: float = 0.05  # 5% of WEAPONATTACK per tick per stack

const BLEED_META: String = "hemorrhage_bleed"


func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(_target):
		return

	var stats_comp = _owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.WEAPONATTACK):
		return
	var wpn_attack: int = int(stats_comp.stats[Constants.StatType.WEAPONATTACK].total_value)
	var per_tick: int = maxi(1, roundi(wpn_attack * DAMAGE_PER_STACK_PCT))

	if _target.has_meta(BLEED_META):
		# Existing bleed — increment stack count (capped) and refresh duration.
		var existing: Dictionary = _target.get_meta(BLEED_META)
		existing["stacks"] = mini(MAX_STACKS, int(existing.get("stacks", 1)) + 1)
		existing["remaining"] = DURATION_SECONDS
		existing["per_tick"] = per_tick  # refresh to latest applier's damage
		_target.set_meta(BLEED_META, existing)
		return

	# Fresh bleed — set up state and start the tick timer.
	var fresh: Dictionary = {
		"stacks": 1,
		"remaining": DURATION_SECONDS,
		"per_tick": per_tick,
		"applier": _owner_node,
	}
	_target.set_meta(BLEED_META, fresh)
	_schedule_bleed_tick(_target)


func _schedule_bleed_tick(target: Node) -> void:
	if not is_instance_valid(target):
		return
	target.get_tree().create_timer(TICK_INTERVAL).timeout.connect(
		func():
			_on_bleed_tick(target)
	)


func _on_bleed_tick(target: Node) -> void:
	if not is_instance_valid(target):
		return
	if not target.has_meta(BLEED_META):
		return

	var state: Dictionary = target.get_meta(BLEED_META)
	var health_comp = target.get("health_component")
	if health_comp == null or not is_instance_valid(health_comp) or health_comp.is_dead:
		target.remove_meta(BLEED_META)
		return

	var damage: int = int(state.get("per_tick", 1)) * int(state.get("stacks", 1))
	if damage > 0:
		health_comp.take_damage(damage, null, false, false, false)

	state["remaining"] = float(state.get("remaining", 0.0)) - TICK_INTERVAL
	if state["remaining"] <= 0.0:
		target.remove_meta(BLEED_META)
		return

	target.set_meta(BLEED_META, state)
	# Schedule next tick.
	_schedule_bleed_tick(target)
