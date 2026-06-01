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
func conditional_damage_mult(owner_node: Node, _target: Node, level: int, ability: AbilityData = null) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	if ability == null or ability.ability_id == "":
		return 0.0
	var sec = owner_node.get("staff_element_component")
	if sec == null or not is_instance_valid(sec) or not sec.has_method("get_current_element"):
		return 0.0
	var element: int = int(sec.get_current_element())

	var matched: bool = false
	match element:
		0:  # FIRE
			matched = ability.ability_id in FIRE_ABILITY_IDS
		1:  # ICE
			matched = ability.ability_id in ICE_ABILITY_IDS
		2:  # LIGHTNING
			matched = ability.ability_id in LIGHTNING_ABILITY_IDS
	if not matched:
		return 0.0

	return BONUS_AT_MAX * (float(level) / float(MAX_LEVEL))
