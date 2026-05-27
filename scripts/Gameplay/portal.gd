extends Area2D
class_name Portal

@export var target_map_id: String = ""
@export var target_spawn_point_name: String = ""

@onready var interaction_label: Label = $InteractionLabel

func _ready():
	# Ensure the label is hidden by default, especially for clients
	if not multiplayer.is_server():
		interaction_label.visible = false

func _on_body_entered(body: Node2D):
	if body.player_id:
		var player_id = body.player_id
		if player_id != 0:
			interaction_label.visible = true
			# Inform the player that they are in a portal
			if body.has_method("set_current_portal"):
				body.set_current_portal(self)
			#print("Player %d entered portal to map '%s' at spawn '%s'" % [player_id, target_map_id, target_spawn_point_name])

func _on_body_exited(body: Node2D):
	if body.player_id:
		var player_id = body.player_id
		if player_id != 0:
			interaction_label.visible = false
			# Inform the player that they have left the portal
			if body.has_method("clear_current_portal"):
				body.clear_current_portal()
			#print("Player %d exited portal." % player_id)

func interact(player_id: int):
	if not multiplayer.is_server():
		return

	var overlapping_bodies = get_overlapping_bodies()
	var player_in_portal = false
	for body in overlapping_bodies:
		if body.player_id == player_id:
			player_in_portal = true
			break

	if player_in_portal:
		#print("Player %d activated portal to map '%s' at spawn '%s'" % [player_id, target_map_id, target_spawn_point_name])
		# Route through the player's change_to_map so save data is flushed
		# before the transition (buff durations, health, mana, etc.).
		var player_node = PlayerManager.get_player_node(player_id)
		if is_instance_valid(player_node) and player_node.has_method("change_to_map"):
			player_node.call_deferred("change_to_map", target_map_id, target_spawn_point_name)
		else:
			MapManager.call_deferred("request_map_change", player_id, target_map_id, target_spawn_point_name)
	else:
		push_warning("Player %d tried to interact with portal but is no longer overlapping." % player_id)
