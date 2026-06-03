extends Node

## Hemorrhage — single-target bleed-setter. On hit, applies (or refreshes
## and stacks) a bleed DOT on the target. Each stack ticks 5% of the
## applier's WEAPONATTACK per second for 6 seconds. Max 3 stacks.
##
## Enemies don't yet have a full BuffComponent (PR 6 scope keeps that
## deferred). Bleed is implemented via direct meta-tracking on the
## EnemyBase node — a self-contained pattern that doesn't require
## extending the global buff system. If/when enemies grow a BuffComponent,
## this can be migrated to use B_Bleed.tres + BL_Bleed.gd cleanly.

const MAX_STACKS: int = 3
const TICK_INTERVAL: float = 1.0
const DURATION_SECONDS: float = 6.0
## PR 6 follow-up: bumped from 0.05 → 0.20 because at low WPN_ATK the bleed
## rounded down to 1/tick — invisible against enemy HP pools. 20% gives a
## noticeable DOT (e.g. WPN_ATK 20 → 4/tick/stack → 12/tick at 3-stack
## → 72 total over 6s, well above a basic hit). Tunable per playtest.
# Per tick per stack = this fraction of the ability's MAX hit (max_range × dmg%),
# via CombatComponent.dot_scaling_base — so the bleed scales with attributes +
# mastery + ability level + gear like direct damage (project_dot_scaling_divergence).
# Was 0.20 × raw WEAPONATTACK, which omitted the (primary×4+sec) multiplier and
# collapsed to ~0 relative damage at endgame.
const DAMAGE_PER_STACK_FRAC: float = 0.10

const BLEED_META: String = "hemorrhage_bleed"


func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(_target):
		return

	var stats_comp = _owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.WEAPONATTACK):
		return
	var wpn_attack: int = int(stats_comp.stats[Constants.StatType.WEAPONATTACK].total_value)

	# PR 6 upgrade reads (Hemorrhage tree):
	#  bleed_potency_bonus   → +% per-tick damage (Hemophilia)
	#  bleed_max_stack_bonus → +max stacks (Deep Gash)
	#  bleed_duration_bonus  → +seconds (Exsanguinate)
	var potency_bonus: float = 0.0
	var stack_bonus: int = 0
	var duration_bonus: float = 0.0
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		potency_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bleed_potency_bonus")
		stack_bonus = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bleed_max_stack_bonus"))
		duration_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bleed_duration_bonus")

	var combat = _owner_node.get("combat_component")
	var dot_base: int = combat.dot_scaling_base(_ability) if combat != null and combat.has_method("dot_scaling_base") else maxi(1, wpn_attack)
	var per_tick: int = maxi(1, roundi(dot_base * DAMAGE_PER_STACK_FRAC * (1.0 + potency_bonus)))
	var max_stacks: int = MAX_STACKS + stack_bonus
	var duration: float = DURATION_SECONDS + duration_bonus

	if _target.has_meta(BLEED_META):
		# Existing bleed — increment stack count (capped) and refresh duration.
		var existing: Dictionary = _target.get_meta(BLEED_META)
		existing["stacks"] = mini(max_stacks, int(existing.get("stacks", 1)) + 1)
		existing["remaining"] = duration
		existing["per_tick"] = per_tick  # refresh to latest applier's damage
		_target.set_meta(BLEED_META, existing)
		return

	# Fresh bleed — set up state and start the tick timer.
	var fresh: Dictionary = {
		"stacks": 1,
		"remaining": duration,
		"per_tick": per_tick,
		"applier": _owner_node,
	}
	_target.set_meta(BLEED_META, fresh)
	_schedule_bleed_tick(_target)


## When a bleed tick downs an enemy, the regular combat-kill pathway
## (combat.gd._execute_hit) never runs — so mastery XP and on_kill passive
## events don't fire. This mirrors that logic locally for bleed kills,
## crediting the applier the same way a direct hit would.
func _credit_bleed_kill(applier, target: Node) -> void:
	if applier == null or not is_instance_valid(applier):
		return
	if target == null or not is_instance_valid(target):
		return

	# Mastery XP — credit both equipped weapons per the same rule
	# combat.gd uses for at-the-moment-of-kill XP.
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

	# Bloodthirst / future on-kill passives.
	var ability_comp = applier.get("ability_component")
	if ability_comp and ability_comp.has_method("dispatch_passive_event_on_kill"):
		ability_comp.dispatch_passive_event_on_kill(target)


func _schedule_bleed_tick(target: Node) -> void:
	if not is_instance_valid(target):
		return
	target.get_tree().create_timer(TICK_INTERVAL).timeout.connect(
		func():
			_on_bleed_tick(target)
	)


func _on_bleed_tick(target: Node) -> void:
	if not is_instance_valid(target):
		return
	if not target.has_meta(BLEED_META):
		return

	var state: Dictionary = target.get_meta(BLEED_META)
	var health_comp = target.get("health_component")
	if health_comp == null or not is_instance_valid(health_comp) or health_comp.is_dead:
		target.remove_meta(BLEED_META)
		return

	var damage: int = int(state.get("per_tick", 1)) * int(state.get("stacks", 1))
	if damage > 0:
		# Attribute the bleed back to the original applier so enemy aggro,
		# damage-by-player tallies, and any source-dependent UI fire
		# correctly. The applier may have despawned (player disconnected,
		# died, etc.) — fall back to null in that case; enemy_base now
		# null-guards the source path.
		var applier = state.get("applier", null)
		if not is_instance_valid(applier):
			applier = null
		# PR 6 follow-up: bleed must bypass enemy i-frames (otherwise the
		# 1s tick interval lines up with the 1s invuln from each Hemorrhage
		# hit and half the ticks get absorbed). show_number=true so the
		# DOT is visible — previously hidden, which read as "no damage."
		var was_alive: bool = not health_comp.is_dead
		health_comp.take_damage(damage, applier, true, false, true)
		if target.has_method("play_dot"):
			target.play_dot("bleed")

		# PR 6 fix: if the bleed tick downed the enemy, fire the same kill
		# events that combat.gd._execute_hit fires for normal hit kills:
		# mastery XP grant and passive on_kill dispatch (Bloodthirst etc.).
		# Character-level XP / quest credit are driven by the enemy's own
		# death handler reading damage_by_player, so they work for free.
		if was_alive and health_comp.is_dead:
			_credit_bleed_kill(applier, target)

	state["remaining"] = float(state.get("remaining", 0.0)) - TICK_INTERVAL
	if state["remaining"] <= 0.0:
		target.remove_meta(BLEED_META)
		return

	target.set_meta(BLEED_META, state)
	# Schedule next tick.
	_schedule_bleed_tick(target)
