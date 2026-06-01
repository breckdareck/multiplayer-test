extends Node

## Vendetta (dagger active) — POISON SPENDER. Consumes ALL Envenom poison
## stacks on a single target to deal a burst of physical damage scaled by
## the stacks consumed. Adds the missing Envenom-spender shape: today
## Envenom builds Poison but nothing consumes it (Toxicology passive
## merely buffs damage WHILE poisoned). Vendetta closes that loop.
##
## The consumed stacks are NOT lost cleanly — they're "converted" into the
## burst hit. The DOT meta is removed entirely on cast, so a Toxicology
## condition that read "vs Poisoned" no longer applies until you re-stack.
## Stacks-consumed × DAMAGE_PER_STACK_PCT % of WEAPONATTACK = burst damage.
##
## Fires via on_hit so it pairs naturally with combat.gd's hit pipeline
## (i-frames, aggro, kill credit). No effect on a target without Envenom
## stacks — the ability still fires its normal hit damage (defined by the
## ability's scaling formulas), Vendetta just adds nothing on top.

const POISON_META: String = "envenom_poison"
## Each consumed Envenom stack adds this fraction of WEAPONATTACK to the burst.
## 3 stacks = +180% WEAPONATTACK on top of the base hit.
const DAMAGE_PER_STACK_PCT: float = 0.60


func on_hit(owner_node: Node, target: Node, _ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return
	if not target.has_meta(POISON_META):
		return  # nothing to consume — Vendetta does its base hit and that's it

	var state: Dictionary = target.get_meta(POISON_META)
	var stacks: int = int(state.get("stacks", 0))
	if stacks <= 0:
		return

	# Consume the entire pool — remove the meta so Toxicology / additional
	# Vendettas can't keep paying off the same stacks.
	target.remove_meta(POISON_META)

	var stats = owner_node.get("stats_component")
	if stats == null or not stats.stats.has(Constants.StatType.WEAPONATTACK):
		return
	var wpn: int = int(stats.stats[Constants.StatType.WEAPONATTACK].total_value)
	var burst: int = maxi(1, roundi(wpn * DAMAGE_PER_STACK_PCT * float(stacks)))

	var hc = target.get("health_component")
	if hc == null or not is_instance_valid(hc) or hc.is_dead:
		return
	# Burst bypasses i-frames so it lands alongside the main hit. is_crit=false
	# (the base hit already rolled its own crit). show_number=true so the
	# spender feel is visible.
	hc.take_damage(burst, owner_node, true, false, true)
