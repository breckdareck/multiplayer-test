extends Node

## Disengage — the Bow discipline's kite tool. A brief BACKWARD hop that looses
## an arrow as the archer retreats, with a short window of i-frames.
##
## This is the mirror of AL_VaultStrike (sword's gap-closer): same minimal,
## platformer-friendly approach per [[feedback_abilities_designed_for_2d_platformer]]
## — a one-shot velocity injection run from inside the standard attack state,
## NOT a leap-to-point or a new state machine state. The difference is the
## sign of the dash velocity: Disengage pushes AWAY from the facing direction
## so the archer backs off while the projectile (configured on the ability's
## active_behavior) flies forward at the target.
##
## i-frames last DASH_DURATION so contact damage / knockback can't cancel the
## retreat — this is the whole point of the ability (the playtest pain point on
## Vault Strike was getting bumped mid-dash). We set is_invulnerable directly
## and schedule a one-shot clear, matching AL_VaultStrike's pattern exactly so
## we don't stomp a take_damage() call that fired its own (longer) invuln.

const DASH_SPEED: float = 260.0
const DASH_DURATION: float = 0.3


func execute(_owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(_owner_node):
		return

	# Push AWAY from the facing direction (the archer keeps facing/shooting the
	# target while sliding backward). Attack state's enter() has already zeroed
	# velocity.x on floor, so setting it after enter() runs persists the hop
	# until the attack state's natural exit.
	var facing: int = int(_owner_node.facing_direction) if "facing_direction" in _owner_node else 1
	if facing == 0:
		facing = 1
	_owner_node.velocity.x = float(-facing) * DASH_SPEED

	# Brief i-frames for the duration of the retreat. Mirrors AL_VaultStrike:
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
