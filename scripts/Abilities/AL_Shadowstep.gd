extends Node

## Shadowstep — the Dagger discipline's gap-closer. A brief FORWARD dash that
## blinks the rogue through the shadows and strikes, with a short window of
## i-frames so contact damage / knockback can't cancel the lunge.
##
## This is the mirror of AL_VaultStrike (sword's gap-closer): a one-shot
## velocity injection in the facing direction, run from inside the standard
## attack state — NOT a leap-to-point or a new state machine state, per
## [[feedback_abilities_designed_for_2d_platformer]]. The sweeping hitbox on
## A_Shadowstep's active_behavior covers the dashed distance because the hitbox
## is parented to the player and moves with it.
##
## Unlike Vault Strike it does NOT build combo points — combo is the sword's
## signature, not the dagger's. The i-frame handling matches AL_VaultStrike /
## AL_Disengage exactly: set is_invulnerable directly and schedule a one-shot
## clear that only fires if WE still own the flag (so a take_damage() during the
## dash keeps its own, longer window).

const DASH_SPEED: float = 270.0
const DASH_DURATION: float = 0.3

## Stealth-modified MP/CD (v1 design grilling 2026-05-31, medium dagger fix):
## while in Shadowmeld stealth, Shadowstep costs 0 MP and has its cooldown
## halved. Lets you reposition without burning the ambush window — gives
## stealth one more meaningful in-window decision beyond "swing big once."
const STEALTH_MP_MULT: float = 0.0
const STEALTH_CD_MULT: float = 0.5


## Pre-cast resource modifier hook. Called by AbilityComponent's
## _consume_ability_resources before mana deduction and cooldown start.
## Returns a Dictionary {"mp_mult": float, "cd_mult": float}; the consumer
## multiplies the base mana_cost and cooldown_time by these. Returning
## {"mp_mult": 1.0, "cd_mult": 1.0} (the default) is a no-op.
##
## For Shadowstep specifically, when the user is currently in Shadowmeld
## stealth we return {0.0, 0.5} — free cast + half CD. Outside stealth we
## return the no-op defaults so the normal cost applies.
func modify_cast_resources(owner_node: Node) -> Dictionary:
	if owner_node == null or not is_instance_valid(owner_node):
		return {"mp_mult": 1.0, "cd_mult": 1.0}
	var sm = owner_node.get("shadowmeld_component")
	if sm == null or not is_instance_valid(sm) or not sm.has_method("is_stealthed"):
		return {"mp_mult": 1.0, "cd_mult": 1.0}
	if not sm.is_stealthed():
		return {"mp_mult": 1.0, "cd_mult": 1.0}
	return {"mp_mult": STEALTH_MP_MULT, "cd_mult": STEALTH_CD_MULT}


func execute(_owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(_owner_node):
		return

	# Dash in the facing direction (toward the target — a gap-closer). Attack
	# state's enter() has already zeroed velocity.x on floor, so setting it after
	# enter() runs persists the lunge until the attack state's natural exit.
	var facing: int = int(_owner_node.facing_direction) if "facing_direction" in _owner_node else 1
	if facing == 0:
		facing = 1
	_owner_node.velocity.x = float(facing) * DASH_SPEED

	# Brief i-frames for the duration of the lunge. Mirrors AL_VaultStrike:
	# only clear the flag if WE still own it (the invulnerability_timer is
	# stopped), so a take_damage() during the dash keeps its own window.
	var health_comp = _owner_node.get("health_component")
	if health_comp != null and is_instance_valid(health_comp):
		health_comp.is_invulnerable = true
		_owner_node.get_tree().create_timer(DASH_DURATION).timeout.connect(
			func():
				if is_instance_valid(health_comp):
					if not health_comp.invulnerability_timer.is_stopped():
						return
					health_comp.is_invulnerable = false
		)
