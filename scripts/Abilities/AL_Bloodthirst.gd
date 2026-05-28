extends Node

## Bloodthirst — passive heal-on-enemy-kill. Each kill restores
## (1 + level) percent of the wielder's Max HP. Class-neutral per
## [[project_passives_class_neutral]] — applies whenever the character
## scores a kill, regardless of which weapon was active.
##
## Invoked by CombatComponent's kill pathway via
## AbilityComponent.dispatch_passive_event_on_kill, which iterates all
## learned passive abilities and calls on_kill on those whose
## active_behavior.logic_script defines the method.

## PR 6 follow-up: original 1% + 1%/lvl (10% at L10) was way too generous
## per playtest — a maxed Bloodthirst made the character functionally
## unkillable in a kill-chain. Tuned down to ~3.2% at L10, modeled after
## MapleStory Demon Avenger's HP-recovery trickle (small per-kill, real
## but not build-defining sustain).
##
##   L1:   0.5% Max HP per kill
##   L5:   1.7% Max HP per kill
##   L10:  3.2% Max HP per kill   (was 10%)
const BASE_HEAL_PCT: float = 0.5
const PER_LEVEL_HEAL_PCT: float = 0.3


func on_kill(_owner_node: Node, _target: Node, _ability_level: int) -> void:
	if not _owner_node.multiplayer.is_server():
		return

	var health_comp = _owner_node.get("health_component")
	if health_comp == null or not is_instance_valid(health_comp):
		return
	if health_comp.is_dead:
		return

	var heal_pct: float = BASE_HEAL_PCT + PER_LEVEL_HEAL_PCT * float(_ability_level - 1)
	var heal_amount: int = maxi(1, roundi(float(health_comp.max_health) * heal_pct / 100.0))
	health_comp.heal_damage(heal_amount, _owner_node)
