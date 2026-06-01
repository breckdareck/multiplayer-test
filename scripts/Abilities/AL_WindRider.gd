extends Node

## Wind Rider (bow passive) — CONDITIONAL fire-rate buff: reduces basic-
## attack delay scaling with current Bow Momentum stacks. Each stack reduces
## the basic-attack cooldown by 2.5% (max -25% at 10 stacks × max passive
## level). Different axis from Tailwind:
##   - Tailwind: +damage AT FULL Momentum (payoff at cap)
##   - Wind Rider: +fire-rate THROUGHOUT the build (smooth ramp)
## So a Momentum-heavy bow build gets BOTH a damage boost at cap and a
## smoother fire-rate ramp during the build — they don't overlap.
##
## Implementation: defines an `attack_cooldown_mult(owner, level)` hook
## that combat.gd reads when computing basic-attack cooldown. Returns a
## NEGATIVE fraction (e.g. -0.25) which combat applies as
## (1.0 + that_fraction) to scale the cooldown DOWN. Class-neutral
## (stacks from both equipped weapon slots).

const REDUCTION_PER_STACK: float = 0.025   # -2.5% per Momentum stack at max level
const MAX_LEVEL: int = 5
const MAX_STACKS: float = 10.0
## Base cap on total reduction (-25% at max stacks/level). Raised by the
## "bonus_passive_cap" upgrade (Howling Wind T2 → -35%).
const BASE_CAP: float = 0.25
## Meta the per-frame cooldown hook stashes for combat.gd to read the Driving
## Wind (T3) full-Momentum damage bonus (passives have no on_hit to set it).
const FULL_DMG_META: String = "wnd_full_dmg_bonus"


## The MAGNITUDE of the basic-attack cooldown reduction this passive currently
## grants, as a positive fraction (e.g. 0.25 = -25% delay). Shared by the
## attack-speed hook and the cooldown-carryover hook so they agree on "current
## bonus". Reads Bow Momentum + this passive's upgrade tree.
func _reduction_magnitude(owner_node: Node, level: int, ability_id: String) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	var bm = owner_node.get("bow_momentum_component")
	if bm == null or not is_instance_valid(bm) or not bm.has_method("get_stacks"):
		return 0.0
	var stacks: float = clampf(float(bm.get_stacks()), 0.0, MAX_STACKS)
	if stacks <= 0.0:
		return 0.0

	# Per-stack reduction at max level — read from the shared .tres formula
	# ("per_stack", display % at max_level) so it matches the $[value:per_stack]
	# tooltip; the * level_scale below applies the per-level ramp.
	var per_stack: float = REDUCTION_PER_STACK
	var self_data: AbilityData = ResourceManager.get_ability_data(ability_id) if ability_id != "" else null
	if self_data:
		per_stack = self_data.get_custom_value("per_stack", MAX_LEVEL, REDUCTION_PER_STACK * 100.0) / 100.0
	var cap: float = BASE_CAP
	var at_full_mult: float = 0.0
	var ac = owner_node.get("ability_component")
	if ac and ability_id != "" and ac.has_method("get_ability_upgrade_magnitude"):
		per_stack += ac.get_ability_upgrade_magnitude(ability_id, "bonus_passive_potency")
		cap += ac.get_ability_upgrade_magnitude(ability_id, "bonus_passive_cap")
		at_full_mult = ac.get_ability_upgrade_magnitude(ability_id, "bonus_at_full_mult")

	var raw: float = per_stack * stacks * (float(level) / float(MAX_LEVEL))
	# Steady Wind (T3): reduction doubled at full Momentum.
	if at_full_mult > 0.0 and stacks >= MAX_STACKS:
		raw *= (1.0 + at_full_mult)
	return clampf(raw, 0.0, cap)


## Returns a NEGATIVE fraction representing the basic-attack cooldown reduction
## (e.g. -0.25). combat applies (1.0 + total) to the cooldown. 3-arg form so the
## dispatcher passes this passive's own ability_id (for its upgrade reads).
## Reads the current Bow Momentum stacks; returns 0.0 on a non-bow build.
func attack_cooldown_mult(owner_node: Node, level: int, ability_id: String = "") -> float:
	var mag: float = _reduction_magnitude(owner_node, level, ability_id)

	# Driving Wind (T3): stash the full-Momentum damage bonus for combat.gd. The
	# attack-speed getter is polled every frame, so the meta stays fresh. Guarded
	# to the server (the only place combat reads it for damage).
	if is_instance_valid(owner_node) and owner_node.multiplayer.is_server():
		var dmg_at_full: float = 0.0
		var ac = owner_node.get("ability_component")
		if ac and ability_id != "" and ac.has_method("get_ability_upgrade_magnitude"):
			var bm = owner_node.get("bow_momentum_component")
			var at_full: bool = bm != null and is_instance_valid(bm) and bm.has_method("get_stacks") \
				and float(bm.get_stacks()) >= MAX_STACKS
			if at_full:
				dmg_at_full = ac.get_ability_upgrade_magnitude(ability_id, "bonus_dmg_at_full")
		if dmg_at_full > 0.0:
			owner_node.set_meta(FULL_DMG_META, dmg_at_full)
		elif owner_node.has_meta(FULL_DMG_META):
			owner_node.remove_meta(FULL_DMG_META)

	return -mag


## Twin Wind (T3): "also reduces ability cooldowns by half its current bonus."
## Returns a positive fraction the cooldown dispatcher applies as (1.0 - sum).
func ability_cooldown_reduction(owner_node: Node, level: int, ability_id: String = "") -> float:
	var carry: float = 0.0
	var ac = owner_node.get("ability_component") if is_instance_valid(owner_node) else null
	if ac and ability_id != "" and ac.has_method("get_ability_upgrade_magnitude"):
		carry = ac.get_ability_upgrade_magnitude(ability_id, "bonus_cd_carryover")
	if carry <= 0.0:
		return 0.0
	return _reduction_magnitude(owner_node, level, ability_id) * carry


## Static helper for combat.gd: the Driving Wind (T3) full-Momentum damage bonus
## the cooldown hook stashed this frame (0.0 if not owned / not at full).
static func get_full_momentum_damage_bonus(owner_node: Node) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	if owner_node.has_meta(FULL_DMG_META):
		return float(owner_node.get_meta(FULL_DMG_META))
	return 0.0
