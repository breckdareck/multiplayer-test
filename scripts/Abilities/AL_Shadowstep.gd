extends Node

## Shadowstep — the Dagger discipline's REPOSITION blink. Finds the FURTHEST
## enemy in front of the player within targeting range, teleports the player
## just BEHIND that enemy, and flips facing so the player lands facing into the
## target — set up for a Backstab. Deals NO damage (the .tres has no hitbox);
## the payoff is the position + the brief backstab window it grants.
##
## Reworked 2026-06-02 (was a forward velocity-dash that "jumped and slid").
## Now a server-set `global_position` teleport (synced via the
## PlayerSynchronizer) — no velocity, no slide. 2026-06-03: damage + hitbox
## removed per design — Shadowstep is pure repositioning; Backstab is the
## damage half of the combo. Cooldown now scales DOWN to 0 (every other
## level) and mana scales UP to 15 — see A_Shadowstep.tres.
##
## Teleport-to-a-DETECTED-ENEMY (not a mouse reticle) is a legitimate 2D
## platformer pattern — the constraint in [[feedback_abilities_designed_for_2d_platformer]]
## is about leap-to-RETICLE / ground-target, which this is not.
##
## The i-frame handling matches AL_VaultStrike / AL_Disengage: set
## is_invulnerable directly and schedule a one-shot clear that only fires if WE
## still own the flag (so a take_damage() during the blink keeps its own,
## longer window).

## Targeting range — how far in front the blink will reach for a target. Larger
## than the 90px damage hitbox so Shadowstep functions as a real gap-closer.
const SEARCH_RANGE: float = 110.0
## Max vertical delta between player and target — keeps the blink from
## snapping to an enemy on a different platform / floor.
const MAX_HEIGHT_DELTA: float = 60.0
## Where behind the enemy the player lands (px past the enemy on the far side).
## Small enough that the re-pointed hitbox (90px wide @ +45 offset) still
## covers the enemy after the facing flip.
const BEHIND_OFFSET: float = 34.0
## Fallback blink distance when there's no enemy in range — a clean short
## hop forward so the ability is still a mobility tool with nothing to target.
const NO_TARGET_BLINK: float = 120.0

## I-frame window after the blink (mirrors AL_VaultStrike / AL_Disengage).
const IFRAME_DURATION: float = 0.3

## How long (ms) after blinking behind a target a Backstab still counts as
## "from behind" (the designed combo). Read by AL_Backstab. 1.5s is generous
## enough to chain Shadowstep → Backstab without being so long it rewards a
## stale window.
const BACKSTAB_WINDOW_MS: int = 1500

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

	var facing: int = int(_owner_node.facing_direction) if "facing_direction" in _owner_node else 1
	if facing == 0:
		facing = 1

	# PR 6 upgrade reads (Shadowstep's tree is pure-utility now — no damage):
	#   blink_range_bonus    (Lengthened Shadow) → reach further for a target
	#   backstab_window_bonus(Lingering Shadow)  → longer Shadowstep→Backstab combo window (s)
	#   iframe_duration_bonus(Phantom Guard)     → longer evade window (s)
	#   stealth_seconds      (Vanishing Step)    → become invisible for N s after the blink
	var range_bonus: float = 0.0
	var window_bonus_s: float = 0.0
	var iframe_bonus: float = 0.0
	var stealth_seconds: float = 0.0
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		range_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "blink_range_bonus")
		window_bonus_s = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "backstab_window_bonus")
		iframe_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "iframe_duration_bonus")
		stealth_seconds = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "stealth_seconds")

	var target: Node = _find_furthest_enemy_in_front(_owner_node, facing, SEARCH_RANGE + range_bonus)

	# Stop any residual velocity so the teleport is a clean blink, not a slide.
	_owner_node.velocity = Vector2.ZERO

	if target != null:
		# Land just BEHIND the target (on the far side relative to approach).
		# Align the player's Y to the TARGET's Y so the blink keeps them on the
		# same ground plane as the enemy (the player and a grounded enemy share
		# a floor; using the player's old Y could leave them floating or clipped
		# if they were mid-jump / on a different micro-elevation when casting).
		var behind_x: float = target.global_position.x + float(facing) * BEHIND_OFFSET
		_owner_node.global_position = Vector2(behind_x, target.global_position.y)
		# Flip to face into the target — set up to Backstab from behind.
		_owner_node.facing_direction = -facing
		# Grant a brief BACKSTAB window — Backstab cast within this window counts
		# as "from behind" even though the enemy (facing tracks velocity) turns
		# to face the player almost immediately after the blink. Makes the
		# designed Shadowstep → Backstab combo reliably land its bonus.
		_owner_node.set_meta("backstab_window_until_ms",
			Time.get_ticks_msec() + BACKSTAB_WINDOW_MS + int(window_bonus_s * 1000.0))
	else:
		# No target in range — short clean blink forward (still a mobility tool).
		_owner_node.global_position += Vector2(float(facing) * NO_TARGET_BLINK, 0.0)

	# Vanishing Step (upgrade) — become invisible to enemy AI for a moment
	# after the blink (the is_invisible meta enemy targeting respects, same as
	# Smoke Bomb / Shadowmeld). A clean disengage. Cleared on a timer unless
	# Shadowmeld is actively stealthing the player (it owns the meta then).
	if stealth_seconds > 0.0:
		_apply_vanishing_step(_owner_node, stealth_seconds)

	# Resolve any minor overlap from the teleport without re-introducing slide
	# (velocity is zero, so this only depenetrates).
	_owner_node.move_and_slide()

	# Brief i-frames for the blink (+ Phantom Guard upgrade). Mirrors
	# AL_VaultStrike: only clear the flag if WE still own it (the
	# invulnerability_timer is stopped), so a take_damage() during the blink
	# keeps its own window.
	var health_comp = _owner_node.get("health_component")
	if health_comp != null and is_instance_valid(health_comp):
		health_comp.is_invulnerable = true
		_owner_node.get_tree().create_timer(IFRAME_DURATION + iframe_bonus).timeout.connect(
			func():
				if is_instance_valid(health_comp):
					if not health_comp.invulnerability_timer.is_stopped():
						return
					health_comp.is_invulnerable = false
		)


## Vanishing Step upgrade — set `is_invisible` (the meta enemy AI targeting
## respects) for `seconds` after the blink, then clear it unless Shadowmeld is
## actively stealthing the player (Shadowmeld owns the meta in that case, so we
## must not strip its cover early).
func _apply_vanishing_step(owner_node: Node, seconds: float) -> void:
	owner_node.set_meta("is_invisible", true)
	owner_node.get_tree().create_timer(seconds).timeout.connect(
		func():
			if not is_instance_valid(owner_node):
				return
			var sm = owner_node.get("shadowmeld_component")
			var still_stealthed: bool = false
			if sm != null and is_instance_valid(sm) and sm.has_method("is_stealthed"):
				still_stealthed = sm.is_stealthed()
			if not still_stealthed:
				owner_node.set_meta("is_invisible", false)
	)


## Returns the living enemy FURTHEST in front of the player (in the facing
## direction) within `max_range` and within MAX_HEIGHT_DELTA vertically, on
## the same map. null if none qualifies. Map-filtered because the Enemies
## group is GLOBAL across maps (SubViewport-per-map architecture).
func _find_furthest_enemy_in_front(owner_node: Node, facing: int, max_range: float = SEARCH_RANGE) -> Node:
	if owner_node.get_tree() == null:
		return null
	var origin: Vector2 = owner_node.global_position

	# Resolve the owner's map node so we only consider same-map enemies.
	var owner_map: Node = null
	for map_id in MapManager.active_maps.keys():
		var inst = MapManager.active_maps[map_id].get("scene_instance")
		if is_instance_valid(inst) and inst.is_ancestor_of(owner_node):
			owner_map = inst
			break

	var best: Node = null
	var best_dist: float = 0.0
	for enemy in owner_node.get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(enemy):
			continue
		if owner_map != null and not owner_map.is_ancestor_of(enemy):
			continue
		var hc = enemy.get("health_component")
		if hc == null or not is_instance_valid(hc) or hc.is_dead:
			continue
		var dx: float = enemy.global_position.x - origin.x
		# Only enemies in the facing direction (strictly in front).
		if facing > 0 and dx <= 0.0:
			continue
		if facing < 0 and dx >= 0.0:
			continue
		var dist: float = absf(dx)
		if dist > max_range:
			continue
		if absf(enemy.global_position.y - origin.y) > MAX_HEIGHT_DELTA:
			continue
		# Furthest wins (the user wants to blink past the whole line to the
		# enemy at the back).
		if dist > best_dist:
			best_dist = dist
			best = enemy
	return best
