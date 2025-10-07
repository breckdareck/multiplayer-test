@tool
class_name AbilityData
extends Resource

@export var ability_id: String:
	set(value):
		if value.is_empty():
			ability_id = generate_uuid()
		else:
			ability_id = value
@export var ability_name: String = ""
@export var description: String = ""
@export var ability_icon: Texture2D

@export var damage_data: DamageData
@export var active_behavior: ActiveBehaviorData
@export var passive_effect: PassiveEffectData


func _init():
	# Only generate a UUID if one doesn't already exist.
	if ability_id.is_empty():
		ability_id = generate_uuid()


func generate_uuid() -> String:
	var id = []
	for i in range(32):
		id.append(str(int(randf() * 16)).to_upper())
	return "%s-%s-%s-%s-%s" % [
		"".join(id.slice(0, 8)),
		"".join(id.slice(8, 12)),
		"".join(id.slice(12, 16)),
		"".join(id.slice(16, 20)),
		"".join(id.slice(20, 32))
	]
