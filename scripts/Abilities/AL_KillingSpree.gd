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
const MAX_LEVEL: int = 10
const META_KEY: String = "killing_spree_until_ms"


func on_kill(owner_node: Node, _target: Node, _ability_level: int, _ability_id: String) -> void:
	if owner_node != null and is_instance_valid(owner_node):
		owner_node.set_meta(META_KEY, Time.get_ticks_msec() + WINDOW_MS)


func conditional_damage_mult(owner_node: Node, _target: Node, level: int) -> float:
	if owner_node == null or not is_instance_valid(owner_node) or not owner_node.has_meta(META_KEY):
		return 0.0
	if Time.get_ticks_msec() > int(owner_node.get_meta(META_KEY)):
		return 0.0
	return BONUS_AT_MAX * (float(level) / float(MAX_LEVEL))
