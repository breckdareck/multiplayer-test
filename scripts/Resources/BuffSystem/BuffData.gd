@tool
class_name BuffData
extends Resource

enum StackBehavior {
	REFRESH,  ## Reset duration when reapplied
	STACK,    ## Add a stack and reset duration
	IGNORE    ## Keep existing buff, ignore new application
}

@export var buff_id: String:
	set(value):
		if value.is_empty():
			buff_id = generate_uuid()
		else:
			buff_id = value

@export var buff_name: String = ""
@export_multiline var description: String = ""
@export var buff_icon: Texture2D

## Duration in seconds (0 = permanent until manually removed)
@export var duration: float = 10.0

## Whether this is a beneficial buff or harmful debuff
@export var is_debuff: bool = false

## Whether this is an aura/stance rather than a "legit" player buff. Auras are
## environmental or maintained effects (e.g. standing in a Banner) that the
## player should NOT be able to manually cancel — they show on the buff bar with
## their own styling but are not right-click removable. Mutually meaningful with
## is_debuff: an aura is treated as locked regardless of debuff status.
@export var is_aura: bool = false

## How the buff behaves when reapplied
@export var stack_behavior: StackBehavior = StackBehavior.REFRESH

## Maximum number of stacks (only used if stack_behavior is STACK)
@export var max_stacks: int = 1

## Stat modifiers applied by this buff (multiplied by stack count)
@export var stat_modifiers: Dictionary[Constants.StatType, StatData] = {}

## Optional custom logic script for special buff behavior
## Script should have methods: on_apply(owner, active_buff), on_remove(owner, active_buff),
## on_tick(owner, active_buff, delta), on_damaged(owner, active_buff, amount, source)
@export var logic_script: Script


func _init():
	if buff_id.is_empty():
		buff_id = generate_uuid()


func generate_uuid() -> String:
	var id = []
	for i in range(32):
		id.append(str(int(randf() * 16)).to_upper())
	return "%s-%s-%s-%s-%s" % [
		"".join(id.slice(0, 8)),
		"".join(id.slice(8, 12)),
		"".join(id.slice(12, 16)),
		"".join(id.slice(16, 20)),
		"".join(id.slice(20, 32)),
	]
