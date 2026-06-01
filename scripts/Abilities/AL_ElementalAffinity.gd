extends Node

## Elemental Affinity (staff passive) — CONDITIONAL damage: while in a
## stance, +bonus damage to spells whose element matches. Specifically:
##   - FIRE stance:      Pyre Burst, Immolate, Arcane Bolt (Fire-flavored)
##   - ICE stance:       Glacial Spike, Frost Patch
##   - LIGHTNING stance: Arcane Lance, Stormcall
## Spellweave is element-agnostic and never gets the bonus (it BECOMES the
## matched element on cast). Generic staff spells (Aether Ward, Phase Step,
## Communion, Mana Surge) don't deal damage and so don't benefit.
##
## Implementation: defines `conditional_damage_mult(owner, target, level)`
## with an extra `ability` lookup — combat.gd dispatches passives WITH the
## casting ability so this can check the ability_id against per-stance
## tables. Class-neutral (stacks from both equipped weapon slots).
##
## See AL_Aggression for the conditional_damage_mult contract (returns the
## bonus FRACTION; combat applies 1 + total).

const BONUS_AT_MAX: float = 0.12   # +12% at max passive level
const MAX_LEVEL: int = 5

## Per-stance ability lists. Matched by the .tres ability_id string. Keep
## these stable across renames — fold any future-renamed ability ids into
## the appropriate stance bucket as they land.
const FIRE_ABILITY_IDS: Array[String] = [
	"pyre_burst", "immolate", "arcane_bolt",
]
const ICE_ABILITY_IDS: Array[String] = [
	"glacial_spike", "frost_patch",
]
const LIGHTNING_ABILITY_IDS: Array[String] = [
	"arcane_lance", "stormcall",
]


## Returns the additive damage fraction this passive grants for a given
## ability cast in the current stance. Reads:
##   1. The owner's StaffElementComponent to get the active stance
##   2. The `ability.ability_id` to check the per-stance table
## Returns 0.0 if no stance match or no Staff Element component.
##
## The signature mirrors AL_Aggression / AL_Tailwind, with the extra
## ability param so the per-id check can run. combat.gd's passive dispatch
## will pass the ability through to this hook.
## True if `ability_id` belongs to `element`'s stance bucket.
static func _matches_element(ability_id: String, element: int) -> bool:
	match element:
		0:
			return ability_id in FIRE_ABILITY_IDS
		1:
			return ability_id in ICE_ABILITY_IDS
		2:
			return ability_id in LIGHTNING_ABILITY_IDS
	return false


## The element that precedes `element` in the stance cycle (FIRE←LIGHTNING,
## ICE←FIRE, LIGHTNING←ICE) — used by Crossover Affinity (T3).
static func _previous_element(element: int) -> int:
	match element:
		0: return 2   # FIRE's predecessor is LIGHTNING
		1: return 0   # ICE's predecessor is FIRE
		2: return 1   # LIGHTNING's predecessor is ICE
	return element


## 5-arg form: dispatcher passes the cast ability (element match) AND this
## passive's own ability_id (its upgrade reads: potency, crossover, at-full-mp).
func conditional_damage_mult(owner_node: Node, _target: Node, level: int, ability: AbilityData = null, passive_id: String = "") -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	if ability == null or ability.ability_id == "":
		return 0.0
	var sec = owner_node.get("staff_element_component")
	if sec == null or not is_instance_valid(sec) or not sec.has_method("get_current_element"):
		return 0.0
	var element: int = int(sec.get_current_element())

	var level_scale: float = float(level) / float(MAX_LEVEL)
	# Base bonus comes from the shared .tres damage_percent_formula — the same
	# value the $[damage_percent] tooltip shows (already level-scaled). Upgrade
	# potency adds on top, scaled the same way. Single source of truth with the
	# description; falls back to the constant ramp if the formula can't resolve.
	var self_data: AbilityData = ResourceManager.get_ability_data(passive_id) if passive_id != "" else null
	var base_scaled: float = self_data.get_damage_percent_fraction(level, BONUS_AT_MAX * level_scale) if self_data else BONUS_AT_MAX * level_scale
	var crossover: float = 0.0
	var at_full_mp: float = 0.0
	var ac = owner_node.get("ability_component")
	if ac and passive_id != "" and ac.has_method("get_ability_upgrade_magnitude"):
		base_scaled += ac.get_ability_upgrade_magnitude(passive_id, "bonus_passive_potency") * level_scale
		crossover = ac.get_ability_upgrade_magnitude(passive_id, "bonus_carryover")
		at_full_mp = ac.get_ability_upgrade_magnitude(passive_id, "bonus_at_full_mp")

	var bonus: float = 0.0
	if _matches_element(ability.ability_id, element):
		bonus = base_scaled
	elif crossover > 0.0 and _matches_element(ability.ability_id, _previous_element(element)):
		# Crossover Affinity (T3): a smaller flat bonus to previous-cycle spells.
		bonus = crossover * level_scale
	if bonus <= 0.0:
		return 0.0

	# Mighty Affinity (T3): the bonus is amplified while at full mana.
	if at_full_mp > 0.0:
		var mc = owner_node.get("mana_component")
		if mc != null and is_instance_valid(mc) and "current_mana" in mc and "max_mana" in mc:
			if int(mc.current_mana) >= int(mc.max_mana):
				bonus *= (1.0 + at_full_mp)
	return bonus


## Sustained Affinity (T3): fractional MP-cost reduction for spells that match
## the current stance. bonus_mp_reduction is unique to this ability, so get_total
## is unambiguous. Called from ability.gd's cost path. Returns 0.0 if not owned
## or the cast spell doesn't match the stance.
static func get_mana_reduction(owner_node: Node, cast_ability_id: String) -> float:
	if owner_node == null or not is_instance_valid(owner_node) or cast_ability_id == "":
		return 0.0
	var ac = owner_node.get("ability_component")
	if ac == null or not ac.has_method("get_total_upgrade_magnitude"):
		return 0.0
	var reduction: float = ac.get_total_upgrade_magnitude("bonus_mp_reduction")
	if reduction <= 0.0:
		return 0.0
	var sec = owner_node.get("staff_element_component")
	if sec == null or not is_instance_valid(sec) or not sec.has_method("get_current_element"):
		return 0.0
	if _matches_element(cast_ability_id, int(sec.get_current_element())):
		return reduction
	return 0.0
