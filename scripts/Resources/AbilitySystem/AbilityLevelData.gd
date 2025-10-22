@tool
class_name AbilityLevelData
extends Resource

@export var level: int = 1
@export var mana_cost: int = 0
@export var cooldown_time: float = 0.0
@export var damage_percent: int = 100
@export var max_targets: int = 1
@export var max_hits: int = 1
@export var cast_time: float = 0.0

## Additional level-specific properties
@export var status_effect_chance: float = 0.0
@export var status_effect_duration: float = 0.0
@export var range_multiplier: float = 1.0
@export var knockback_force: float = 0.0

## For passive skills that give stat bonuses
@export var stat_bonuses: Dictionary[Constants.StatType, StatData]

@export_group("Ability Modifiers")
## Modifies damage of other abilities by ability_id
## Example: {"power_strike_id": 1.12, "slash_blast_id": 1.07} for +12% and +7%
@export var ability_damage_modifiers: Dictionary = {}

## Modifies cooldown of other abilities by ability_id (multiplier)
## Example: {"fireball_id": 0.8} for 20% faster cooldown
@export var ability_cooldown_modifiers: Dictionary = {}

## Modifies mana cost of other abilities by ability_id (multiplier)
## Example: {"heal_id": 0.5} for 50% mana cost
@export var ability_mana_modifiers: Dictionary = {}

## Modifies range of other abilities by ability_id (multiplier)
@export var ability_range_modifiers: Dictionary = {}

## Modifies cast time of other abilities by ability_id (multiplier)
@export var ability_cast_time_modifiers: Dictionary = {}

@export_group("Proc Effects")
## Proc effects triggered on various combat events
@export var on_hit_proc: ProcEffectData = null
@export var on_crit_proc: ProcEffectData = null
@export var on_kill_proc: ProcEffectData = null
@export var on_damaged_proc: ProcEffectData = null
@export var on_dodge_proc: ProcEffectData = null
@export var on_ability_cast_proc: ProcEffectData = null

@export_group("Aura Effects")
## Aura effects (buffs applied to nearby allies/enemies)
@export var aura_radius: float = 0.0
@export var aura_buff: BuffData = null
@export var aura_affects_allies: bool = true
@export var aura_affects_enemies: bool = false

@export_group("Custom Logic")
## Custom passive logic script for complex behaviors
## Should have: on_passive_acquired(owner, level_data)
##              on_passive_removed(owner, level_data)
##              process(owner, level_data, delta)
@export var passive_logic_script: Script

func _init(p_level: int = 1):
	level = p_level

## Gets the total modifier for a specific ability's damage
func get_ability_damage_modifier(ability_id: String) -> float:
	return ability_damage_modifiers.get(ability_id, 1.0)


## Gets the total modifier for a specific ability's cooldown
func get_ability_cooldown_modifier(ability_id: String) -> float:
	return ability_cooldown_modifiers.get(ability_id, 1.0)


## Gets the total modifier for a specific ability's mana cost
func get_ability_mana_modifier(ability_id: String) -> float:
	return ability_mana_modifiers.get(ability_id, 1.0)


## Gets the total modifier for a specific ability's range
func get_ability_range_modifier(ability_id: String) -> float:
	return ability_range_modifiers.get(ability_id, 1.0)


## Gets the total modifier for a specific ability's cast time
func get_ability_cast_time_modifier(ability_id: String) -> float:
	return ability_cast_time_modifiers.get(ability_id, 1.0)


## Checks if any proc should trigger for a given event type
func try_proc_event(event_type: String, last_proc_times: Dictionary = {}) -> ProcEffectData:
	var proc: ProcEffectData = null
	
	match event_type:
		"on_hit":
			proc = on_hit_proc
		"on_crit":
			proc = on_crit_proc
		"on_kill":
			proc = on_kill_proc
		"on_damaged":
			proc = on_damaged_proc
		"on_dodge":
			proc = on_dodge_proc
		"on_ability_cast":
			proc = on_ability_cast_proc
	
	if proc and proc.try_proc(last_proc_times.get(event_type, 0.0)):
		return proc
	
	return null
