extends Node

## Killing Spree (passive, replaces the old primary-stat% auto-take) — CONDITIONAL
## damage: +bonus for WINDOW_MS after any kill (refreshed on each kill). A
## clear-speed passive — strong while chaining trash, does nothing against a single
## tough target. Class-neutral. The kill window is tracked as a meta deadline on the
## owner so it survives the per-hit logic_script.new() (fresh instance each call).
##
## Two hooks: on_kill (dispatched by AbilityComponent.dispatch_passive_event_on_kill)
## stamps the window; conditional_damage_mult (per hit) reads it. Returns the bonus
## FRACTION; combat applies 1 + total.

const WINDOW_MS: int = 4000          # 4s of bonus after a kill
const BONUS_AT_MAX: float = 0.30     # +30% at passive level 10 (scales linearly)
const MAX_LEVEL: int = 5
const META_KEY: String = "killing_spree_until_ms"


func on_kill(owner_node: Node, _target: Node, _ability_level: int, _ability_id: String) -> void:
	if owner_node != null and is_instance_valid(owner_node):
		owner_node.set_meta(META_KEY, Time.get_ticks_msec() + WINDOW_MS)


func conditional_damage_mult(owner_node: Node, _target: Node, level: int, _cast_ability: AbilityData = null, passive_id: String = "") -> float:
	if owner_node == null or not is_instance_valid(owner_node) or not owner_node.has_meta(META_KEY):
		return 0.0
	if Time.get_ticks_msec() > int(owner_node.get_meta(META_KEY)):
		return 0.0
	return _level_bonus(passive_id, level)


## Per-level bonus FRACTION read from this passive's damage_percent_formula
## (single source of truth with the $[damage_percent] tooltip). Falls back to
## the constant ramp only if the ability/formula can't be resolved.
func _level_bonus(passive_id: String, level: int) -> float:
	var data: AbilityData = ResourceManager.get_ability_data(passive_id) if passive_id != "" else null
	if data:
		return data.get_damage_percent_fraction(level, BONUS_AT_MAX * float(level) / float(MAX_LEVEL))
	return BONUS_AT_MAX * float(level) / float(MAX_LEVEL)
