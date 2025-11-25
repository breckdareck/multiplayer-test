extends Node
class_name StateMachine

@export var starting_state: State
@export var state_label: Label
var current_state: State

var _is_being_cleaned_up: bool = false

func init(parent: CharacterBody2D, animations: AnimatedSprite2D) -> void:
	# Add validation
	if !parent:
		push_error("StateMachine: Parent node is null")
		return
	if !animations:
		push_error("StateMachine: Animations node is null")
		return
	
	for child in get_children():
		child.parent = parent
		child.animations = animations
		
	if multiplayer.is_server():
		change_state(starting_state)

func change_state(new_state: State) -> void:
	if not multiplayer.is_server():
		return
	if current_state == new_state:
		return
	
	# 1. Always update locally on the server (since we are the authority)
	_set_state_rpc(new_state.name)
	
	# 2. Only apply map-based filtering for NON-PLAYER entities
	# Players have their own visibility filters on InputSynchronizer
	var parent_node = get_parent()
	if parent_node and not parent_node is MultiplayerPlayerV2:
		# For enemies/map entities, send to players on the same map
		var map_node = parent_node.get_parent()
		# Find which map this entity belongs to
		while map_node and not map_node.is_in_group("map_base"):
			map_node = map_node.get_parent()
		
		if map_node and map_node.is_in_group("map_base"):
			# Get map name (e.g., "Map_game")
			var map_name = map_node.name.replace("Map_", "")
			var players_on_this_map = MapManager.get_players_on_map(map_name)
			
			# Send RPC only to REMOTE players on this map
			for peer_id in players_on_this_map:
				if peer_id != 1: # Skip server (already updated locally)
					_set_state_rpc.rpc_id(peer_id, new_state.name)
			return
	
	# For players or fallback: broadcast to all REMOTE peers
	# (We already updated locally, so we don't want call_local to trigger again if we used rpc())
	# Actually, _set_state_rpc has "call_local", so rpc() would call it again.
	# We should use rpc_id to others or just loop all peers.
	
	for peer_id in multiplayer.get_peers():
		_set_state_rpc.rpc_id(peer_id, new_state.name)

func sync_state_to_peer(peer_id: int) -> void:
	"""
	Sends the current state to a specific peer. This is useful for when
	a new client joins and needs to be brought up-to-date.
	This should only be called on the server.
	"""
	if not multiplayer.is_server() or not current_state:
		return
	
	_set_state_rpc.rpc_id(peer_id, current_state.name)

@rpc("authority", "call_local", "reliable")
func _set_state_rpc(state_name: String) -> void:
	var new_state: Node = get_node_or_null(state_name)
	if new_state:
		# This check prevents re-running the logic if we're already in the target state.
		if current_state == new_state:
			return

		if current_state:
			current_state.exit()
			#print("Changing from %s to %s" % [current_state.animation_name, new_state.animation_name])

		current_state = new_state
		state_label.text = current_state.animation_name
		current_state.enter()
	
func process_input(event: InputEvent) -> void:
	if _is_being_cleaned_up:
		return
	if !current_state:
		return
	var new_state: State = current_state.process_input(event)
	if new_state:
		change_state(new_state)

func process_physics(delta: float) -> void:
	if _is_being_cleaned_up:
		return
	if !current_state:
		return
	var new_state: State = current_state.process_physics(delta)
	if new_state:
		change_state(new_state)
		
func process_frame(delta: float) -> void:
	if _is_being_cleaned_up:
		return
	if !current_state:
		return
	var new_state: State = current_state.process_frame(delta)
	if new_state:
		change_state(new_state)


func cleanup():
	_is_being_cleaned_up = true
	set_process(false)
	set_physics_process(false)
