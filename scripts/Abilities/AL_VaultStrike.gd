extends Node

## Vault Strike — short horizontal dash with a sweeping hitbox.
##
## Per [[feedback_abilities_designed_for_2d_platformer]] this is NOT a
## leap-to-point — it's a brief velocity-injection in the player's facing
## direction, run from inside the standard attack state. The wider hitbox
## defined on A_Vault_Strike's active_behavior sweeps the area covered by
## the dash because the hitbox is parented to the player and moves with it.
##
## v1 keeps it minimal: no i-frames, no new state machine state. The dash
## ends naturally when the attack animation finishes. T3 variants
## (Cyclone Drop / Predator's Bound / Twin Vault) layer on top later.
##
## Also builds 2 combo points on a successful hit (vs the 1 from a basic
## attack), giving sword's combo loop a fast ramp option that requires
## committing to forward motion.

const DASH_SPEED: float = 250.0
const DASH_DURATION: float = 0.3
const COMBO_PER_HIT: int = 2


func execute(_owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(_owner_node):
		return

	# Apply dash velocity in facing direction. Attack state's enter() has
	# already zeroed velocity.x on floor — by setting after enter() runs,
	# the dash velocity persists until the attack state's natural exit.
	var facing: int = int(_owner_node.facing_direction) if "facing_direction" in _owner_node else 1
	if facing == 0:
		facing = 1
	_owner_node.velocity.x = float(facing) * DASH_SPEED

	# Brief i-frames during the dash so enemy contact / knockback doesn't
	# interrupt the momentum (was the playtest pain point on first feel).
	# We set is_invulnerable directly and schedule a one-shot clear so the
	# duration matches the dash, independent of the global invulnerability
	# timer's wait_time (which is tuned for hit-stun and would be too long).
	var health_comp = _owner_node.get("health_component")
	if health_comp != null and is_instance_valid(health_comp):
		health_comp.is_invulnerable = true
		_owner_node.get_tree().create_timer(DASH_DURATION).timeout.connect(
			func():
				if is_instance_valid(health_comp):
					# Only clear if WE set it — don't stomp a take_damage()
					# call that fired its own invuln during the dash.
					if not health_comp.invulnerability_timer.is_stopped():
						return
					health_comp.is_invulnerable = false
		)


func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	# Vault Strike grants 2 combo per hit (vs basic attack's 1) so it doubles
	# as a strong ramp ability for builds that want fast combo build.
	var combo_comp = _owner_node.get("sword_combo_component")
	if combo_comp == null or not is_instance_valid(combo_comp):
		return
	# Crashing Vault (T3): each struck enemy builds extra combo points on top
	# of the innate 2 (same read as Charge's Battlecry).
	var extra: int = 0
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		extra = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_combo_per_hit"))
	# Iterate add_combo_point — the component caps at COMBO_CAP internally.
	for i in range(COMBO_PER_HIT + extra):
		combo_comp.add_combo_point()
