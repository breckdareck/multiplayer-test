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
