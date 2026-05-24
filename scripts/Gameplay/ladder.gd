extends Area2D
class_name Ladder

# A vertical climbable zone. Place these in a map to let players climb past
# otherwise-solid tiles and traverse vertical sections. Detection is server-
# authoritative: only the server mutates per-player ladder state.

func _ready() -> void:
	add_to_group("ladders")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if not ("player_id" in body):
		return
	if body.has_method("enter_ladder"):
		body.enter_ladder(self)

func _on_body_exited(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if not ("player_id" in body):
		return
	if body.has_method("exit_ladder"):
		body.exit_ladder(self)
