class_name StaffElementComponent
extends WeaponSignatureComponent

const EnemyStatus := preload("res://scripts/Gameplay/enemy_status.gd")

## PR 7 — Staff discipline's signature combat system: the ELEMENT STANCE.
##
## Staff identity: while wielding a STAFF, a key (WeaponSignature) cycles the
## active element FIRE -> ICE -> LIGHTNING -> FIRE. The active element adds an
## on-hit rider to EVERY staff SPELL hit (ability hits while a staff is wielded):
##  - FIRE      -> stacking BURN DoT, scaled off the TRIGGERING HIT's damage (so
##                 it stays meaningful at every level — the focused-damage element).
##  - ICE       -> SLOW: a temporary movement-speed reduction (the control element).
##  - LIGHTNING -> bonus shock on the hit AND a chain arc to nearby enemies (the
##                 crowd/burst element — clears clusters before AoE is unlocked).
##
## This is the staff analogue of SwordComboComponent / BowMomentumComponent. Same
## structural rules:
## - Server-authoritative: every mutator early-returns unless multiplayer.is_server().
##   The owning client only learns the active element through the
##   sync_element_to_client RPC, which feeds its widget.
## - Bots have no client and no UI — the RPC is skipped for bot owners
##   (BotManager.is_bot check, same as SwordCombo / BowMomentum / WeaponMastery).
## - Volatile per-session: the active element is never saved or synced through
##   the backend. It resets to FIRE on each spawn.
##
## The on-hit effects are applied by CombatComponent._execute_hit, which calls
## apply_element_on_hit(target, base_damage) AFTER the damage loop — but only
## when the wielded weapon is a staff AND the landed hit was a staff ability, so
## the element can NEVER bleed onto a sword / bow / dagger hit.

#region #################### Element enum ####################

## Active element identity. Int values are stable (widget colors + the volatile
## cycle index depend on them). Append new elements; never reorder.
enum Element {
	FIRE = 0,
	ICE = 1,
	LIGHTNING = 2,
}

## How many elements the cycle walks through. cycle_element() advances mod this.
const ELEMENT_COUNT: int = 3

#endregion


#region #################### Tunable constants ####################

## FIRE — stacking burn. Mirrors AL_Immolate's burn pattern (meta-tracked DOT
## with a chained Timer, since enemies carry no BuffComponent) but uses its OWN
## meta key so an element-stance burn stacks INDEPENDENTLY of an Immolate burn,
## a bow bleed, or a sword bleed rather than overwriting them.
## Per tick per stack = BURN_HIT_PCT of the TRIGGERING HIT's damage (NOT raw
## MAGICATTACK). The old MATK-% version rounded to "1/tick" at low levels and felt
## pointless; scaling off the actual hit keeps it proportional at every level. The
## floor keeps a SINGLE stack worth applying, so you don't need to stack 3 (or have
## AoE) to get value. (Tuning: raise BURN_HIT_PCT for a stronger DoT.)
const BURN_HIT_PCT: float = 0.12
const BURN_MIN_PER_TICK: int = 2
const BURN_TICK_INTERVAL: float = 1.0
const BURN_DURATION: float = 4.0
const BURN_MAX_STACKS: int = 3
const BURN_META: String = "staff_element_burn"

## ICE — slow. A flat fraction shaved off the enemy's movement_speed for a
## window. movement_speed is a plain field on EnemyBase (NOT a StatData), read
## live by enemy_chase / enemy_patrol every physics frame, so the slow is applied
## by reducing that field directly and restoring it on a timer — the same
## save/restore/meta idiom CombatComponent._apply_enemy_debuff uses for stat
## debuffs. 0.4 = enemy moves at 60% speed while chilled.
const SLOW_PCT: float = 0.4
const SLOW_DURATION: float = 2.5
const SLOW_META: String = "staff_element_chill"

## LIGHTNING — chain shock. The struck target takes an extra
## (base * LIGHTNING_BONUS_MULT) as a separate shock tick, AND the bolt CHAINS in
## SEQUENCE: it hops to the nearest un-hit enemy within LIGHTNING_CHAIN_RADIUS px,
## RE-CENTERS on that enemy and hops again, up to LIGHTNING_CHAIN_MAX_HOPS times
## (each hop deals base * LIGHTNING_CHAIN_MULT). Re-centering each hop lets the bolt
## thread down a line / across a cluster instead of being trapped in one radius
## bubble around the first enemy — so it reliably clears packs even when you strike
## one at the edge. This is lightning's crowd/burst identity, and lets a
## single-target spell clear a group before AoE abilities are unlocked.
## (Tuning: hops / per-hop radius / arc damage below.)
const LIGHTNING_BONUS_MULT: float = 0.5
const LIGHTNING_CHAIN_MAX_HOPS: int = 3
const LIGHTNING_CHAIN_RADIUS: float = 180.0
const LIGHTNING_CHAIN_MULT: float = 0.4

#endregion


#region #################### Signals ####################

## Emitted on both server and client whenever the active element changes
## (cycle, or reset-to-FIRE on spawn). Carries the new Element value. The widget
## listens to this to repaint.
signal element_changed(element: int)

#endregion


#region #################### State ####################

## The currently active element. Volatile — never saved. Mirrored to the owning
## client via sync_element_to_client; the server is authoritative. Defaults to
## FIRE on spawn (locked design: element state is volatile, default FIRE).
var _current_element: int = Element.FIRE

#endregion


#region #################### Public API ####################

## Server-only. Advances the active element one step (FIRE -> ICE -> LIGHTNING
## -> FIRE) and syncs to the owning client. Called from PlayerManager.player_input
## when the local player presses WeaponSignature while wielding a staff.
func cycle_element() -> void:
	if not multiplayer.is_server():
		return
	_current_element = (_current_element + 1) % ELEMENT_COUNT
	_emit_and_sync()


## Read-only accessor for the widget / combat hook. Safe on both peers — the
## client's mirror is kept in step via sync_element_to_client.
func get_current_element() -> int:
	return _current_element


# --- WeaponSignature interface ---
# The element stance is intentionally PERSISTENT: it survives weapon swaps and
# death (it only resets to FIRE on a fresh spawn). So this signature overrides
# only signature_discipline() and inherits the no-op weapon-state / death hooks.
func signature_discipline() -> int:
	return Constants.ClassType.STAFF


## Server-only. Applies the active element's on-hit rider to `target`. Called by
## CombatComponent._execute_hit AFTER the damage loop, and only when the caller
## has already verified the wielded weapon is a staff and the hit was a staff
## ability — so this never fires for another weapon.
##
## `base_damage` is the representative per-hit damage the combat hook computed
## (used to scale the LIGHTNING bonus). The caller passes the owning player node
## as `attacker` so DOT / bonus damage is attributed correctly for aggro + XP.
func apply_element_on_hit(attacker: Node, target: Node, base_damage: int) -> void:
	if not multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return
	# Do NOT bail when the target is already dead. This runs AFTER _execute_hit's
	# damage loop, so the spell's main hit may have just KILLED the target — but a
	# LIGHTNING chain must still arc off the dying enemy to nearby living ones (the
	# "shock doesn't work when the enemy dies" bug). Each element handles a dead
	# primary itself: FIRE/ICE no-op on a corpse, LIGHTNING skips the
	# bonus-to-target but still chains.
	match _current_element:
		Element.FIRE:
			_apply_burn(attacker, target, base_damage)
		Element.ICE:
			_apply_slow(target)
		Element.LIGHTNING:
			_apply_lightning_bonus(attacker, target, base_damage)

#endregion


#region #################### FIRE — stacking burn ####################

## Mirrors AL_Immolate.on_hit's meta-tracked stacking DOT, with this component's
## own BURN_META key so it stacks independently of Immolate / bleeds.
func _apply_burn(attacker: Node, target: Node, base_damage: int) -> void:
	# No point igniting a corpse — the spell's main hit may have already killed it
	# (the top-level rider no longer guards on this so LIGHTNING can still chain).
	var hc = target.get("health_component")
	if hc == null or not is_instance_valid(hc) or hc.is_dead:
		return
	# Scale per-tick off the TRIGGERING HIT (not raw MAGICATTACK) so it stays
	# proportional to real damage at every level; the floor keeps one stack worth
	# applying. Each (re)application refreshes per_tick to the latest hit's value.
	var per_tick: int = maxi(BURN_MIN_PER_TICK, roundi(base_damage * BURN_HIT_PCT))

	if target.has_meta(BURN_META):
		var existing: Dictionary = target.get_meta(BURN_META)
		existing["stacks"] = mini(BURN_MAX_STACKS, int(existing.get("stacks", 1)) + 1)
		existing["remaining"] = BURN_DURATION
		existing["per_tick"] = per_tick  # refresh to latest applier's damage
		existing["applier"] = attacker
		target.set_meta(BURN_META, existing)
		EnemyStatus.register(target, EnemyStatus.TAG_BURN, BURN_META, attacker)
		return

	var fresh: Dictionary = {
		"stacks": 1,
		"remaining": BURN_DURATION,
		"per_tick": per_tick,
		"applier": attacker,
	}
	target.set_meta(BURN_META, fresh)
	_schedule_burn_tick(target)
	EnemyStatus.register(target, EnemyStatus.TAG_BURN, BURN_META, attacker)


func _schedule_burn_tick(target: Node) -> void:
	if not is_instance_valid(target):
		return
	target.get_tree().create_timer(BURN_TICK_INTERVAL).timeout.connect(
		func():
			_on_burn_tick(target)
	)


func _on_burn_tick(target: Node) -> void:
	if not is_instance_valid(target):
		return
	if not target.has_meta(BURN_META):
		return

	var state: Dictionary = target.get_meta(BURN_META)
	var health_comp = target.get("health_component")
	if health_comp == null or not is_instance_valid(health_comp) or health_comp.is_dead:
		target.remove_meta(BURN_META)
		return

	var damage: int = int(state.get("per_tick", 1)) * int(state.get("stacks", 1))
	if damage > 0:
		var applier = state.get("applier", null)
		if not is_instance_valid(applier):
			applier = null
		# Burn bypasses enemy i-frames (the 1s tick would otherwise line up with
		# the 1s invuln from each hit and lose half its ticks). show_number=true.
		var was_alive: bool = not health_comp.is_dead
		health_comp.take_damage(damage, applier, true, false, true)
		if target.has_method("play_dot"):
			target.play_dot("burn")

		# If the burn tick downed the enemy, credit the same kill events a direct
		# hit would — mastery XP + on_kill passives. Mirrors AL_Immolate's
		# _credit_burn_kill (kept inline here so the component is self-contained).
		if was_alive and health_comp.is_dead:
			_credit_dot_kill(applier, target)

	state["remaining"] = float(state.get("remaining", 0.0)) - BURN_TICK_INTERVAL
	if state["remaining"] <= 0.0:
		target.remove_meta(BURN_META)
		return

	target.set_meta(BURN_META, state)
	_schedule_burn_tick(target)

#endregion


#region #################### ICE — slow ####################

## Temporarily reduces the enemy's movement_speed by SLOW_PCT, restoring it on a
## timer. movement_speed is a plain EnemyBase field (read live by the chase /
## patrol states), not a StatData — so CombatComponent._apply_enemy_debuff (which
## only touches stats_component.stats) can't slow movement. This mirrors that
## helper's save/restore/meta/tint idiom directly on movement_speed.
func _apply_slow(target: Node) -> void:
	if not (target is EnemyBase):
		return
	var enemy := target as EnemyBase
	# No point chilling a corpse — the strike may have already killed it (the
	# top-level rider no longer guards on this so LIGHTNING can still chain).
	var hc = enemy.get("health_component")
	if hc != null and is_instance_valid(hc) and hc.is_dead:
		return
	# Already chilled — no-op (don't re-apply). Re-applying would compound the
	# reduction off the already-reduced base and the restore would then write
	# back a wrong value, so the existing slow simply runs out its own timer.
	if enemy.has_meta(SLOW_META):
		return

	var original_speed: float = enemy.movement_speed
	enemy.movement_speed = original_speed * (1.0 - SLOW_PCT)
	enemy.set_meta(SLOW_META, original_speed)
	# No attacker context here — Thermal Shock credits the consumed burn's
	# own applier instead (see EnemyStatus._thermal_shock).
	EnemyStatus.register(enemy, EnemyStatus.TAG_CHILL, SLOW_META, null)

	if enemy.animated_sprite and is_instance_valid(enemy.animated_sprite):
		enemy.animated_sprite.modulate = Color(0.6, 0.8, 1.0, 1.0)

	get_tree().create_timer(SLOW_DURATION).timeout.connect(
		func():
			if not is_instance_valid(enemy):
				return
			# Restore from the saved value rather than dividing back out — robust
			# against movement_speed having been reassigned elsewhere meanwhile.
			if enemy.has_meta(SLOW_META):
				enemy.movement_speed = enemy.get_meta(SLOW_META)
				enemy.remove_meta(SLOW_META)
			if enemy.animated_sprite and is_instance_valid(enemy.animated_sprite):
				enemy.animated_sprite.modulate = Color.WHITE
	)

#endregion


#region #################### LIGHTNING — bonus damage ####################

## Applies a flat-% follow-up shock to the same target. Separate take_damage so
## it shows as its own number and bypasses i-frames (otherwise the just-landed
## hit's invuln would swallow it). Attributed to the attacker for aggro / XP.
func _apply_lightning_bonus(attacker: Node, target: Node, base_damage: int) -> void:
	var applier = attacker if is_instance_valid(attacker) else null

	# Bonus shock to the struck target — ONLY if it's still alive. This rider runs
	# after the spell's damage loop, which may have already killed it; in that case
	# we skip the (impossible) bonus but STILL chain off it below to nearby enemies.
	var health_comp = target.get("health_component")
	if health_comp != null and is_instance_valid(health_comp) and not health_comp.is_dead:
		var bonus: int = maxi(1, roundi(base_damage * LIGHTNING_BONUS_MULT))
		health_comp.take_damage(bonus, applier, true, false, true)
		if health_comp.is_dead:
			_credit_dot_kill(applier, target)

	# Chain the shock in SEQUENCE: hop to the nearest un-hit enemy within range,
	# re-center on it, hop again — up to LIGHTNING_CHAIN_MAX_HOPS times. Re-centering
	# each hop lets the bolt thread a line/cluster rather than being stuck in one
	# radius bubble around the first enemy. Each hop deals LIGHTNING_CHAIN_MULT of
	# the base hit. zapped_positions records the hop order for the bolt VFX.
	var chain_dmg: int = maxi(1, roundi(base_damage * LIGHTNING_CHAIN_MULT))
	var zapped_positions: PackedVector2Array = PackedVector2Array()
	var visited: Dictionary = {target.get_instance_id(): true}
	var current: Node = target
	for _hop in range(LIGHTNING_CHAIN_MAX_HOPS):
		var next_enemy: Node = _nearest_chain_target(attacker, current, LIGHTNING_CHAIN_RADIUS, visited)
		if next_enemy == null:
			break  # no un-hit enemy in range of the current link — chain ends
		visited[next_enemy.get_instance_id()] = true
		var nh = next_enemy.get("health_component")
		var n_alive: bool = not nh.is_dead
		nh.take_damage(chain_dmg, applier, true, false, true)
		if n_alive and nh.is_dead:
			_credit_dot_kill(applier, next_enemy)
		zapped_positions.append(next_enemy.global_position)
		current = next_enemy  # re-center: the next hop searches from THIS enemy

	# Cosmetic chain-bolt VFX: thread from the struck target through each enemy we
	# actually zapped. Server-only trigger; MapManager broadcasts it to every
	# client viewing this map (+ the host). No gameplay effect.
	if not zapped_positions.is_empty() and is_instance_valid(attacker) and "player_id" in attacker:
		var map_id: String = MapManager.get_player_map(attacker.player_id)
		if map_id != "":
			var arc_points: PackedVector2Array = PackedVector2Array([target.global_position])
			arc_points.append_array(zapped_positions)
			MapManager.broadcast_lightning_arc(map_id, arc_points)

#endregion


#region #################### Shared helpers ####################

## Returns the single NEAREST living enemy within `radius` of `from_node`'s
## position that is NOT already in `visited` (a set of instance_ids), or null if
## none qualifies. The chain calls this once per hop, re-centering `from_node` on
## the last enemy, so the bolt threads enemy-to-enemy. Map-scoped: the "Enemies"
## group is GLOBAL across maps (SubViewport-per-map architecture), so we filter via
## the CombatComponent's cached _is_on_same_map (the attacker always has one — the
## chain runs from combat._execute_hit) to avoid zapping a coordinate-overlapping
## enemy on another map.
func _nearest_chain_target(attacker: Node, from_node: Node, radius: float, visited: Dictionary) -> Node:
	if not is_instance_valid(from_node):
		return null
	var combat = attacker.get("combat_component") if is_instance_valid(attacker) else null
	var from_pos: Vector2 = from_node.global_position
	var best: Node = null
	var best_dist: float = radius  # only enemies within radius qualify
	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(enemy) or visited.has(enemy.get_instance_id()):
			continue
		if combat != null and combat.has_method("_is_on_same_map") and not combat._is_on_same_map(enemy):
			continue
		var hc = enemy.get("health_component")
		if hc == null or not is_instance_valid(hc) or hc.is_dead:
			continue
		var d: float = enemy.global_position.distance_to(from_pos)
		if d <= best_dist:
			best_dist = d
			best = enemy
	return best


## When a DOT / bonus tick lands the killing blow, the normal combat-kill
## pathway (combat.gd._execute_hit) never runs — so mastery XP and on_kill
## passive events wouldn't fire. This credits the applier the same way a direct
## hit would. Mirrors AL_Immolate._credit_burn_kill.
func _credit_dot_kill(applier, target: Node) -> void:
	if applier == null or not is_instance_valid(applier):
		return
	if target == null or not is_instance_valid(target):
		return

	var mastery_comp = applier.get("weapon_mastery_component")
	var combat_comp = applier.get("combat_component")
	if mastery_comp and combat_comp and "monster_level" in target and applier.level_component:
		var kill_xp: int = WeaponMasteryComponent.compute_kill_xp(
			target.monster_level,
			applier.level_component.level
		)
		var kill_disc: int = combat_comp._active_weapon_discipline()
		if kill_disc != -1:
			mastery_comp.grant_mastery_xp_server(kill_disc, kill_xp)
		var sec_disc: int = combat_comp._secondary_weapon_discipline()
		if sec_disc != -1 and sec_disc != kill_disc:
			mastery_comp.grant_mastery_xp_server(sec_disc, kill_xp)

	var ability_comp = applier.get("ability_component")
	if ability_comp and ability_comp.has_method("dispatch_passive_event_on_kill"):
		ability_comp.dispatch_passive_event_on_kill(target)


## Server-side: emit locally for the host's UI, then push to the owning client.
## Skips the RPC for bot owners (no client, no UI) — same gate SwordCombo /
## BowMomentum use.
func _emit_and_sync() -> void:
	element_changed.emit(_current_element)
	if not multiplayer.is_server():
		return
	var root := get_owner()
	if root == null or not "player_id" in root:
		return
	if BotManager.is_bot(root.player_id):
		return
	sync_element_to_client.rpc_id(root.player_id, _current_element)

#endregion


#region #################### RPCs ####################

## Server -> owning client. Mirrors the authoritative active element so the
## client's widget renders the matching color/label. call_local is harmless —
## the body early-returns on the server, which already drove its own widget
## through the local signal path in _emit_and_sync.
@rpc("authority", "call_local", "reliable")
func sync_element_to_client(element: int) -> void:
	if multiplayer.is_server():
		return
	if _current_element == element:
		return
	_current_element = element
	element_changed.emit(_current_element)

#endregion
