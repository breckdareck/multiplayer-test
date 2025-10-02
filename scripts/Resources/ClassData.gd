class_name ClassData
extends Resource

@export var _class_name: String
@export var class_type: Constants.ClassType
@export var sprite_frames: Dictionary[int, SpriteFrames] = {} # level -> SpriteFrames resource path
@export var skills: Array[String] = []
@export var description: String = ""
@export var icon: Texture2D
@export var primary_stat: Constants.StatType
@export var secondary_stat: Constants.StatType
@export var base_stats: Dictionary[Constants.StatType, int] = {
	Constants.StatType.STRENGTH: 4,
	Constants.StatType.DEXTERITY: 4,
	Constants.StatType.INTELLIGENCE: 4,
	Constants.StatType.LUCK: 4
}
@export var stat_bonuses: Dictionary[Constants.StatType, int] = { }


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
