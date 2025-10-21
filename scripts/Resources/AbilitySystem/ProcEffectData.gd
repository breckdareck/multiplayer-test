class_name ProcEffectData
extends Resource

## Chance to trigger (0.0 to 1.0, e.g., 0.02 = 2%)
@export_range(0.0, 1.0, 0.01) var proc_chance: float = 0.0

## Damage percentage if this proc deals damage (100 = 100% of base damage)
@export var damage_percent: int = 100

## Execute this ability when proc triggers
@export var execute_ability: AbilityData = null

## Apply this buff when proc triggers
@export var apply_buff: BuffData = null

## Cooldown before this proc can trigger again (0 = no cooldown)
@export var cooldown: float = 0.0

## Animation to play when proc triggers
@export var animation_name: String = ""

## Sound effect to play when proc triggers
@export var sfx_path: String = ""

## Custom logic script for complex proc behavior
## Should have: can_proc(owner, target, context) -> bool
##              on_proc(owner, target, context) -> void
@export var logic_script: Script

## Additional data that can be used by logic scripts
@export var custom_data: Dictionary = {}


## Helper to check if proc triggers (handles chance and cooldown)
func try_proc(last_proc_time: float = 0.0) -> bool:
	if proc_chance <= 0.0:
		return false
	
	# Check cooldown
	if cooldown > 0.0 and (Time.get_ticks_msec() / 1000.0 - last_proc_time) < cooldown:
		return false
	
	# Roll for proc
	return randf() < proc_chance
