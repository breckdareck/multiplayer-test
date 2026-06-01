extends Node

## Sundering Arrow (bow active) — SECOND MOMENTUM-SPENDER. Consumes all
## current Momentum to fire a single heavy arrow that PIERCES every enemy in
## a horizontal line in the facing direction.
##
## Fixes Snipe-mono-payoff: bow had only ONE momentum-spender before
## (Snipe, single-target burst). Now the player has a choice:
##   - Snipe: big single-target damage to one priority target
##   - Sundering Arrow: medium per-enemy damage but pierces the whole line
## Both consume Momentum so they can't both be cast back-to-back without
## rebuilding the gauge.
##
## Implementation: the actual pierce-line collision is handled by the
## projectile this ability spawns (configured on the ability's
## active_behavior, similar to Snipe). THIS script only consumes the
## Momentum gauge on cast. Per-enemy damage falloff (so a tightly-packed
## line doesn't melt instantly) is a v2 feature pending a per-pierce damage
## modifier hook in combat.gd.


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return

	# Consume Momentum via the existing BowMomentumComponent API. The base
	# hit's damage scaling lives on the projectile / ability's formulas
	# (mirrors Snipe), so this script just clears the gauge.
	var bm = owner_node.get("bow_momentum_component")
	if bm == null or not is_instance_valid(bm):
		return
	if bm.has_method("spend_all"):
		bm.spend_all()
	elif bm.has_method("get_stacks") and bm.has_method("spend"):
		var s: int = int(bm.get_stacks())
		if s > 0:
			bm.spend(s)
