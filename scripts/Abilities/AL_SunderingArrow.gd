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

	# Consume Momentum via the existing BowMomentumComponent.reset() — drops
	# stacks to zero, same effect as Snipe's gauge clear. The base hit's
	# damage scaling lives on the projectile / ability's formulas (mirrors
	# Snipe), so this script just clears the gauge.
	var bm = owner_node.get("bow_momentum_component")
	if bm == null or not is_instance_valid(bm) or not bm.has_method("reset"):
		return
	bm.reset()


## Refunding Sundering (T3): if this cast kills any enemy on the pierce line,
## refund Momentum. on_hit fires per landed hit (after damage is applied, so
## `is_dead` reflects this hit). The pierce line hits several enemies in the same
## instant, so a short per-owner window dedupes to a single refund per cast.
const REFUND_WINDOW_MS: int = 400
const REFUND_META: String = "sdr_refund_window_ms"

func on_hit(owner_node: Node, target: Node, _ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return
	var refund: int = 0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		refund = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_momentum_refund"))
	if refund <= 0:
		return

	var hc = target.get("health_component")
	if hc == null or not is_instance_valid(hc) or not hc.is_dead:
		return

	# Dedupe: one refund per cast even though the pierce hits multiple enemies.
	var now: int = Time.get_ticks_msec()
	var last: int = int(owner_node.get_meta(REFUND_META, 0))
	if now - last < REFUND_WINDOW_MS:
		return
	owner_node.set_meta(REFUND_META, now)

	var bm = owner_node.get("bow_momentum_component")
	if bm and is_instance_valid(bm) and bm.has_method("add_momentum"):
		bm.add_momentum(refund)
