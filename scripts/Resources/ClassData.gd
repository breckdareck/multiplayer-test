class_name ClassData
extends Resource

@export var _class_name: String
@export var class_type: Constants.ClassType
@export var sprite_frames: Dictionary[int, SpriteFrames] = {} # level -> SpriteFrames resource path
@export var skills: Array[String] = []
@export var description: String = ""
@export var icon: Texture2D
@export var base_stats: Dictionary[Constants.StatType, int] = {
	Constants.StatType.STRENGTH: 10,
	Constants.StatType.DEXTERITY: 10,
	Constants.StatType.INTELLIGENCE: 10,
	Constants.StatType.LUCK: 10
}
@export var stat_bonuses: Dictionary[Constants.StatType, int] = {
	Constants.StatType.STRENGTH: 10,
	Constants.StatType.DEXTERITY: 10,
	Constants.StatType.INTELLIGENCE: 10,
	Constants.StatType.LUCK: 10
}


func get_sprite_for_level(level: int) -> SpriteFrames:
	var highest_available = 1
	for sprite_level in sprite_frames.keys():
		if level >= sprite_level and sprite_level > highest_available:
			highest_available = sprite_level
	
	if sprite_frames.has(highest_available):
		var sprite_path = sprite_frames[highest_available]
		if sprite_path is String:
			return load(sprite_path)
		else:
			return sprite_path
	
	return null

func get_stat_bonus(stat_type: Constants.StatType) -> int:
	return stat_bonuses.get(stat_type, 0)

func has_skill(skill_name: String) -> bool:
	return skill_name in skills
