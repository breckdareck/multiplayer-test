extends Node

## Bulwark Stance — toggle defensive stance. While active:
##  - +250 flat DEFENSE (≈25% DR scaling with the defense formula)
##  - Drains MP per second; auto-removes when MP reaches 0
##  - Toggled off by recasting the ability (AL handles that path)
##
## T3 variants (mutex, stamped by AL_BulwarkStance at cast):
##  - Counter Stance:   reflect a % of damage taken back at the attacker
##  - Immovable:        take a flat fraction less damage while the stance holds
##  - Unyielding Vigil: the stance no longer drains MP

const MP_PER_SECOND: float = 2.0
const MP_TICK_INTERVAL: float = 1.0

## How long each Immovable DR stamp stays fresh. Longer than the tick cadence
## so the reduction never flickers off between ticks; short enough that
## dropping the stance ends it promptly.
const DR_REFRESH_MS: int = 1500

var _mp_accumulator: float = 0.0

## T3 variant parameters — set by AL_BulwarkStance from the owned upgrade's
## magnitude (all zero/false when no variant is owned).
var reflect_percentage: float = 0.0    ## Counter Stance: % of damage taken reflected
var damage_reduction: float = 0.0      ## Immovable: fraction of incoming damage removed
var mp_drain_disabled: bool = false    ## Unyielding Vigil: stance stops draining MP


func on_apply(_owner_node: Node, _active_buff) -> void:
	_mp_accumulator = 0.0


func on_tick(owner_node: Node, _active_buff, delta: float) -> void:
	if not owner_node.multiplayer.is_server():
		return

	# Immovable (T3): keep the shared incoming-DR channel stamped while the
	# stance holds. health.gd already reads these metas for Banner's Bulwark
	# Banner aura, so the damage path needs no new code — but only stamp when
	# we'd not weaken a stronger, still-fresh aura (e.g. standing in a
	# friendly Banner whose reduction is higher).
	if damage_reduction > 0.0:
		var banner_al := preload("res://scripts/Abilities/AL_Banner.gd")
		var now: int = Time.get_ticks_msec()
		var current: float = 0.0
		if owner_node.has_meta(banner_al.DR_AURA_META) and now < int(owner_node.get_meta(banner_al.DR_AURA_META)):
			current = float(owner_node.get_meta(banner_al.DR_AURA_AMT_META)) if owner_node.has_meta(banner_al.DR_AURA_AMT_META) else 0.0
		if damage_reduction >= current:
			owner_node.set_meta(banner_al.DR_AURA_AMT_META, damage_reduction)
			owner_node.set_meta(banner_al.DR_AURA_META, now + DR_REFRESH_MS)

	_mp_accumulator += delta
	if _mp_accumulator < MP_TICK_INTERVAL:
		return
	_mp_accumulator -= MP_TICK_INTERVAL

	# Unyielding Vigil (T3): the stance costs nothing to hold.
	if mp_drain_disabled:
		return

	var mana_comp = owner_node.get("mana_component")
	if mana_comp == null or not is_instance_valid(mana_comp):
		return

	if mana_comp.current_mana < MP_PER_SECOND:
		# Out of mana — drop the stance.
		mana_comp.current_mana = 0
		var buff_comp = owner_node.get("buff_component")
		if buff_comp:
			buff_comp.remove_buff(_active_buff_id())
		return

	# ManaComponent doesn't expose a consume_mana(); the setter on
	# current_mana clamps to [0, max_mana] so direct assignment is the
	# canonical way to deduct.
	mana_comp.current_mana -= int(MP_PER_SECOND)


## Counter Stance (T3): reflect a fraction of damage taken back at the
## attacker. Same shape as BL_IronRiposte.on_damaged — capped at half the
## attacker's max HP so reflect can never one-shot off a boss nuke.
func on_damaged(owner_node: Node, _active_buff, damage_amount: int, source: Node) -> void:
	if reflect_percentage <= 0.0 or source == null or not is_instance_valid(source):
		return
	if not owner_node.multiplayer.is_server():
		return

	var reflected_damage: int = roundi(damage_amount * (reflect_percentage / 100.0))
	var attacker_health_comp = source.get("health_component")
	if attacker_health_comp and "max_health" in attacker_health_comp:
		reflected_damage = mini(reflected_damage, int(attacker_health_comp.max_health / 2.0))
	if reflected_damage > 0 and attacker_health_comp:
		attacker_health_comp.take_damage(reflected_damage, owner_node, true)
		# Tell: damage dealt outside combat.gd's pipeline shows no number —
		# the reflect IS the upgrade, so name it at the attacker.
		EventJuice.proc(source, "COUNTER %d" % reflected_damage, EventJuice.COLOR_COUNTER)


func on_remove(_owner_node: Node, _active_buff) -> void:
	pass


func _active_buff_id() -> String:
	# Must match the key AL_BulwarkStance used in apply_buff() — that's
	# what BuffComponent._active_buffs is dictionary-keyed by, NOT the
	# resource's buff_id field. See [[feedback_applies_buff_is_metadata]].
	return "Bulwark Stance"
