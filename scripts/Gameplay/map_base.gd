extends Node2D
class_name MapBase

# This script should be attached to the root node of every map scene.
# Maps now use manual spawning for both the map itself and players.

func _ready():
	# Add to group so MapManager can identify maps
	add_to_group("map_base")
	print("Map '%s' initialized" % name)
