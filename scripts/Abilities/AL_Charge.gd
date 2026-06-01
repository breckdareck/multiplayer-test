extends Node

## Charge! (sword active) — LINE-DASH + COMBO BUILDER. A horizontal-line
## rush forward in the caster's facing direction; deals damage to enemies
## in the path; each enemy hit grants +1 combo point. Distinct from Vault
## Strike (leap-arc, gap-closer landing on a single target) and from
## Vanguard's Onslaught (channel + pierce — single big release after a
## charge-up).
##
## Implementation: a one-shot velocity injection in the facing direction
## from inside the standard attack state — same pattern as AL_VaultStrike
## and AL_Shadowstep (no leap-to-point, no new state machine state). The
## hitbox is on the ability's active_behavior and sweeps with the player
## as they dash. Brief i-frames cover the dash window so contact damage
## doesn't cancel it.

const DASH_SPEED: float = 320.0
const DASH_DURATION: float = 0.35
const COMBO_PER_ENEMY_HIT: int = 1


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	# Dash in the facing direction. Attack state's enter() has already zeroed
	# velocity.x on floor, so setting it after enter() runs persists the
	# lunge until the attack state's natural exit.
	var facing: int = int(owner_node.facing_direction) if "facing_direction" in owner_node else 1
	if facing == 0:
		facing = 1
	owner_node.velocity.x = float(facing) * DASH_SPEED

	# Brief i-frames for the dash window. Same pattern as AL_VaultStrike /
	# AL_Shadowstep — only clear if WE still own the flag.
	var health_comp = owner_node.get("health_component")
	if health_comp != null and is_instance_valid(health_comp):
		health_comp.is_invulnerable = true
		owner_node.get_tree().create_timer(DASH_DURATION).timeout.connect(
			func():
				if is_instance_valid(health_comp):
					if not health_comp.invulnerability_timer.is_stopped():
						return
					health_comp.is_invulnerable = false
		)


## Combo-build payoff per enemy struck. The dash's hitbox sweeps multiple
## enemies — each landed hit grants +1 combo via the canonical
## SwordComboComponent.add_combo path so it's accounted the same as
## Steel Flurry / Vault Strike builds.
func on_hit(owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	var combo_comp = owner_node.get("sword_combo_component")
	if combo_comp == null or not is_instance_valid(combo_comp) or not combo_comp.has_method("add_combo"):
		return
	combo_comp.add_combo(COMBO_PER_ENEMY_HIT)
