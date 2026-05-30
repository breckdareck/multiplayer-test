extends Node

## Eviscerate — dagger finisher with a Shadowmeld EXECUTE. The base hit already
## gets the ambush ×2 + guaranteed crit from combat.gd when struck from stealth;
## THIS adds an execute on top: if Eviscerate lands FROM STEALTH (the Shadowmeld
## toggle OR the Vanish buff) on a target at/under EXECUTE_HP_PCT health, it deals
## a heavy bonus strike — the assassination payoff for opening from the shadows.
##
## on_hit fires per landed hit DURING combat.gd's damage loop, BEFORE the ambush
## consumes stealth (the break runs after the loop), so is_stealthed() / the Vanish
## buff are still readable here. The HP check reads CURRENT health (post the main
## hit this tick), so a big Eviscerate that drops the target into the window
## immediately finishes them.

const EXECUTE_HP_PCT: float = 0.35    ## target at/under 35% max HP = execute window
const EXECUTE_BONUS_PCT: float = 1.0  ## bonus strike = 100% of WEAPONATTACK


func on_hit(owner_node: Node, target: Node, _ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return

	# Must be FROM STEALTH — Shadowmeld toggle or the Vanish ability's buff.
	var stealthed: bool = false
	var sm = owner_node.get("shadowmeld_component")
	if sm != null and is_instance_valid(sm) and sm.has_method("is_stealthed"):
		stealthed = sm.is_stealthed()
	if not stealthed:
		var bc = owner_node.get("buff_component")
		if bc != null and is_instance_valid(bc) and bc.has_method("has_buff"):
			stealthed = bc.has_buff("Vanish")
	if not stealthed:
		return

	var hc = target.get("health_component")
	if hc == null or not is_instance_valid(hc) or hc.is_dead:
		return
	var max_hp: int = int(hc.max_health) if "max_health" in hc else 0
	var cur_hp: int = int(hc.current_health) if "current_health" in hc else 0
	if max_hp <= 0:
		return
	if float(cur_hp) / float(max_hp) > EXECUTE_HP_PCT:
		return  # above the execute window — no bonus

	# Execute strike, scaled off WEAPONATTACK (daggers scale WEAPONATTACK).
	var stats = owner_node.get("stats_component")
	if stats == null or not stats.stats.has(Constants.StatType.WEAPONATTACK):
		return
	var wpn: int = int(stats.stats[Constants.StatType.WEAPONATTACK].total_value)
	var bonus: int = maxi(1, roundi(wpn * EXECUTE_BONUS_PCT))
	# crit visual on (it's a finisher), bypass i-frames so it lands alongside the hit.
	hc.take_damage(bonus, owner_node, true, true, true)
