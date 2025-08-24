extends Window

@onready var inventory_window: Window = $"."

var player: MultiplayerPlayerV2

func _ready() -> void:
	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2

func _process(delta: float) -> void:
	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenInventoryWindow"):
			inventory_window.visible = !inventory_window.visible
