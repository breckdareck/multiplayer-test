extends Node

## Glacial Spike — ICE-stance reaction. Glacial Spike is the staff's heavy
## single-target ice strike. On a normal hit the generic element rider (when the
## ICE stance is active) already applies a soft slow. This logic_script ESCALATES
## that under the ICE stance into a hard FREEZE/ROOT: the struck enemy's
## movement_speed is pinned to 0 for a short window, then restored on a timer.
##
## This mirrors StaffElementComponent._apply_slow's exact save/restore/meta/tint
## idiom — movement_speed is a plain EnemyBase field (read live by enemy_chase /
## enemy_patrol every physics frame), NOT a StatData, so we pin it directly and
## restore it from a saved meta value on a Timer. Re-applying while already frozen
## is a no-op (guard on the meta), so repeated hits don't compound or write back a
## wrong base on restore.
##
## Off-ICE this does nothing — the generic rider handles whatever baseline effect
## the active element provides.

## How long the enemy stays rooted (movement_speed pinned to 0).
const FREEZE_DURATION: float = 1.5
## Own meta key — independent of the soft-slow's "staff_element_chill" so the two
## never clobber each other's saved base speed.
const FREEZE_META: String = "glacial_freeze"


## Returns true if the player's StaffElement signature is currently ICE.
## Element.ICE == 1 in StaffElementComponent (stable enum). Safe on a missing
## component — the reaction simply doesn't apply.
func _is_ice_active(owner_node: Node) -> bool:
	var sec = owner_node.get("staff_element_component")
	if sec == null or not is_instance_valid(sec) or not sec.has_method("get_current_element"):
		return false
	return sec.get_current_element() == 1


func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(_target):
		return
	# Only EnemyBase carries the plain movement_speed field we freeze.
	if not (_target is EnemyBase):
		return
	# Permafrost (T3): the hard freeze fires in ANY stance.
	if not _is_ice_active(_owner_node) and not _reaction_any_stance(_owner_node, _ability):
		return  # off-ICE: generic rider handles the baseline; no hard freeze

	var enemy := _target as EnemyBase
	# No point freezing a corpse — the strike may have already killed it.
	var hc = enemy.get("health_component")
	if hc != null and is_instance_valid(hc) and hc.is_dead:
		return
	# Already frozen — no-op. Re-applying would pin the (already 0) speed and the
	# restore timer would then write back 0 as the "original," permanently rooting
	# the enemy. Let the existing freeze run out its own timer.
	if enemy.has_meta(FREEZE_META):
		return

	var original_speed: float = enemy.movement_speed
	enemy.movement_speed = 0.0
	enemy.set_meta(FREEZE_META, original_speed)

	# Deeper-blue tint than the soft chill so a hard freeze reads distinctly.
	if enemy.animated_sprite and is_instance_valid(enemy.animated_sprite):
		enemy.animated_sprite.modulate = Color(0.4, 0.6, 1.0, 1.0)

	# `enemy.get_tree()` not `get_tree()` — logic_scripts are instantiated via
	# `ability.active_behavior.logic_script.new()` in combat.gd and are NOT
	# added to the scene tree, so `self.get_tree()` returns null. The enemy
	# IS in the tree, so use its tree to schedule the restore. (Same pattern
	# every other AL_*.gd uses for create_timer.)
	enemy.get_tree().create_timer(FREEZE_DURATION).timeout.connect(
		func():
			if not is_instance_valid(enemy):
				return
			# Restore from the saved value rather than assuming — robust against
			# movement_speed having been reassigned elsewhere meanwhile.
			if enemy.has_meta(FREEZE_META):
				enemy.movement_speed = enemy.get_meta(FREEZE_META)
				enemy.remove_meta(FREEZE_META)
			if enemy.animated_sprite and is_instance_valid(enemy.animated_sprite):
				enemy.animated_sprite.modulate = Color.WHITE
	)


## Stance-breaker T3 ("reaction_any_stance"): true when the owned variant lets
## this ability's element reaction fire regardless of the active stance.
func _reaction_any_stance(owner_node: Node, ability: AbilityData) -> bool:
	var ability_comp = owner_node.get("ability_component")
	if ability_comp == null or ability == null or not ability_comp.has_method("get_ability_upgrade_magnitude"):
		return false
	return ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "reaction_any_stance") > 0.0
