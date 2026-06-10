extends Node

## Challenging Shout (sword active) — AoE WEAKEN. Replaces Iron Riposte
## (2026-06-10 roster-audit rework: reflect required standing there getting
## hit, which the no-dodge potion-survival model never rewards, and it had
## the worst mana efficiency in the sword kit). The vanguard bellows: a
## burst of damage around the caster, and every struck enemy deals
## WEAKEN_PCT less damage for WEAKEN_DURATION_SEC — defense by debuffing
## the pack. Scales with enemy count where reflect didn't, and helps the
## whole party (weakened enemies hit everyone softer).
##
## The weaken rides the same attacker-side metas health.gd already reads
## for Smoke Bomb's Choking Smoke / Hailstorm's Suppressing Fire (the
## generic "weakened attacker" channel) — max-wins on overlap so stacked
## sources never dilute each other.
##
## Upgrade keys (read here, literal for the dead-upgrade test):
##   weaken_potency_bonus  — extra outgoing-damage fraction removed
##   weaken_duration_bonus — extra seconds of weaken

const WEAKEN_PCT: float = 0.15
const WEAKEN_DURATION_SEC: float = 6.0


func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(_target):
		return

	var weaken_pct: float = WEAKEN_PCT
	var duration: float = WEAKEN_DURATION_SEC
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		weaken_pct += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "weaken_potency_bonus")
		duration += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "weaken_duration_bonus")

	var smoke_al := preload("res://scripts/Abilities/AL_SmokeBomb.gd")
	var now: int = Time.get_ticks_msec()
	var expire_at: int = now + int(duration * 1000.0)
	var cur_pct: float = 0.0
	if _target.has_meta(smoke_al.SMOKE_CHOKE_EXPIRE_META) and now < int(_target.get_meta(smoke_al.SMOKE_CHOKE_EXPIRE_META)):
		cur_pct = float(_target.get_meta(smoke_al.SMOKE_CHOKE_PCT_META)) if _target.has_meta(smoke_al.SMOKE_CHOKE_PCT_META) else 0.0
	if weaken_pct >= cur_pct:
		_target.set_meta(smoke_al.SMOKE_CHOKE_PCT_META, weaken_pct)
		_target.set_meta(smoke_al.SMOKE_CHOKE_EXPIRE_META, expire_at)
