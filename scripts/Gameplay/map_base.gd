extends Node2D
class_name MapBase

# This script should be attached to the root node of every map scene.
# Maps now use manual spawning for both the map itself and players.

## Path to the background music track for this map (e.g. "res://assets/music/gameplay.mp3").
## Leave empty to keep playing whatever is currently playing.
@export_file("*.mp3", "*.ogg", "*.wav") var bgm_path: String = ""

func _ready():
	# Add to group so MapManager can identify maps
	add_to_group("map_base")
	print("Map '%s' initialized" % name)
