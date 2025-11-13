extends Node2D
class_name MapBase

# This script should be attached to the root node of every map scene.
# It's responsible for initializing the map's own components, like its PlayerSpawner.

@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner


func _ready():
	# This function runs on the server AND on all clients, because the map
	# scene is replicated to everyone.
	add_to_group("map_base")

	if not player_spawner:
		push_error("This map scene is missing a MultiplayerSpawner node named 'PlayerSpawner' as a direct child.")
		return

	# Set the spawn function on ALL peers.
	# On the server (authority), this function is called to create the initial instance.
	# On clients, this function is called to create a placeholder instance which is then
	# updated with the server's data.
	player_spawner.spawn_function = _spawn_player_instance


func _spawn_player_instance(data: Dictionary) -> Node:
	"""
	This function is called by this map's MultiplayerSpawner to get a new player instance.
	It loads the player scene, instantiates it, and returns it to the spawner.
	"""
	var char_scene = load("res://scenes/Player/player.tscn")
	if not char_scene:
		push_error("MapBase: Failed to load player scene at 'res://scenes/Player/player.tscn'!")
		return null
	
	var player_char = char_scene.instantiate()
	
	# Set the name from the data passed to spawn(). This is critical for replication.
	if data and "id" in data:
		player_char.name = str(data["id"])
		player_char.player_id = str(data["id"])
		
	return player_char
