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
## Bonus strike = this fraction of a full basic-hit's max_range (the WHOLE
## damage formula: 1.2 × (primary×4 + secondary) × WEAPONATTACK). Was a flat
## fraction of WEAPONATTACK alone (2026-06-02 fix) — negligible at scale
## because it ignored the primary-stat term. 1.0 = a full extra hit's worth,
## fitting for a stealth-gated execute finisher.
const EXECUTE_BONUS_PCT: float = 1.0


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
	# Butcher's Opening (T3): the execute window no longer needs stealth —
	# turns the stealth-opener payoff into a general low-HP finisher.
	if not stealthed:
		var ac = owner_node.get("ability_component")
		if ac and _ability != null and ac.has_method("get_ability_upgrade_magnitude"):
			stealthed = ac.get_ability_upgrade_magnitude(_ability.ability_id, "execute_without_stealth") > 0.0
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

	# Execute strike scaled off the FULL damage formula (max_range), not a flat
	# fraction of WEAPONATTACK — so the finisher's payoff scales with the
	# player's primary stat + gear like every real hit does. max_range is the
	# pre-damage-percent top of a basic hit's roll for the active weapon's stat.
	var combat = owner_node.get("combat_component")
	if combat == null or not is_instance_valid(combat) or not combat.has_method("_calculate_max_range"):
		return
	var max_range: int = int(combat._calculate_max_range(Constants.StatType.WEAPONATTACK))
	var bonus: int = maxi(1, roundi(max_range * EXECUTE_BONUS_PCT))
	# crit visual on (it's a finisher), bypass i-frames so it lands alongside the hit.
	hc.take_damage(bonus, owner_node, true, true, true)
	EventJuice.proc(target, "EXECUTE", EventJuice.COLOR_EXECUTE)
