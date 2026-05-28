@tool
class_name AbilityUpgradeData
extends Resource

## PR 6 — Per-ability upgrade resource. Each AbilityData carries an array of
## these. Players spend ability points (from the discipline's pool) to
## purchase upgrades, which AL_*.gd scripts read at runtime to apply effects.
##
## Three tiers per ability (Diablo 4 Lord-of-Hatred shape):
##   T1 (1 pt): broad modifier (cooldown, duration, range, mana cost)
##   T2 (1 pt): mechanical augment (combo cap bonus, defense pen, target count)
##   T3 (2 pt): variant — pick 1 of 3 build-defining transformations
##
## T3 variants share a `variant_group` so the purchase API enforces mutex
## (you can only own one variant in a group). T1/T2 leave `variant_group`
## empty — they stack with each other (you can own both).
##
## Design rationale lives in [[project_ability_tree_references]] and
## [[project_passives_class_neutral]] (memory).

## Stable identifier for save/load. Convention: `<ability_short>_t<tier>_<slug>`
## e.g. `cc_t1_razor_edge` (Crescent Cleave tier-1 Razor Edge upgrade).
@export var upgrade_id: String

## Display name shown in the AbilityWindow upgrade panel.
@export var upgrade_name: String = ""

## BBCode-allowed description shown in the tooltip / purchase confirmation.
@export_multiline var description: String = ""

## Ability points spent to purchase this upgrade. Drawn from the per-discipline
## pool shared with ability leveling. Tier 1/2 default 1 pt; tier 3 (variants)
## default 2 pt — adjust per upgrade if needed.
@export var point_cost: int = 1

## Tier band the upgrade belongs to (1-3). Used for tier-gating: T2 unlocks
## once any T1 in the same ability is owned; T3 unlocks once any T2 is owned.
## Keeps the buy order intuitive even though point_cost is uniform within
## a tier.
@export_range(1, 3) var tier: int = 1

## For T3 variants: shared identifier across mutually-exclusive options.
## E.g. all three of Crescent Cleave's T3 variants share variant_group =
## "cc_finisher_variant". The purchase API blocks owning more than one
## upgrade in the same variant_group.
## Empty string = stacks freely with any other (T1, T2, and most passives).
@export var variant_group: String = ""

## Effect identifier the AL_*.gd scripts dispatch on. The script's effect
## handler reads `has_upgrade(ability_id, upgrade_id)` and conditionally
## applies behavior matching this key.
##
## Convention: lowercase snake_case, scoped by ability where ambiguous.
## Examples:
##   "cooldown_minus_1s", "combo_cap_plus_1", "defense_pen_15",
##   "bloodletting_aoe_bleed", "razor_wind_combo_coefficient_double",
##   "decapitate_low_hp_execute", "vampire_basic_lifesteal"
##
## Picking a clear set of effect_keys early avoids string-match drift across
## AL scripts later.
@export var effect_key: String = ""


func _init() -> void:
	pass


## Returns a plain-text tooltip for this upgrade. Shown when the player
## hovers an unpurchased upgrade slot in the AbilityWindow side panel.
func get_tooltip_text(owned: bool = false) -> String:
	var lines: Array[String] = []
	lines.append(upgrade_name)

	var tier_str: String = "Tier %d" % tier
	if not variant_group.is_empty():
		tier_str += " (Variant)"
	if owned:
		tier_str += " — Owned"
	else:
		tier_str += " — %d pt" % point_cost
	lines.append(tier_str)

	if not description.is_empty():
		lines.append("")
		lines.append(description)

	return "\n".join(lines)
