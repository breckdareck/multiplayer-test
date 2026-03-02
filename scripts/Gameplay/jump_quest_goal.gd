extends Area2D
class_name JumpQuestGoal

## Placed at the end of a jump quest map. Awards a reward when a player reaches it.
## Each player can only claim the reward once per server session.

@export var reward_title: String = "Platformer"
@export var reward_coins: int = 5000
@export var return_map_id: String = "game"
@export var return_spawn_point: String = ""

var _claimed_players: Dictionary = {}  # player_id -> true

func _ready():
	if not multiplayer.is_server():
		return
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D):
	if not multiplayer.is_server():
		return
	if not body is MultiplayerPlayerV2:
		return

	var player: MultiplayerPlayerV2 = body as MultiplayerPlayerV2
	if _claimed_players.has(player.player_id):
		return

	_claimed_players[player.player_id] = true

	# Award coins
	if reward_coins > 0 and is_instance_valid(player.player_inventory):
		player.player_inventory.monies_amount += reward_coins
		player.player_inventory.set_monies_rpc.rpc(player.player_inventory.monies_amount)

	# Notify the player
	ChatManager.add_system_message.rpc_id(player.player_id,
		"Jump Quest Complete! You earned %d coins!" % reward_coins, Color.GOLD)

	print("JumpQuestGoal: Player '%s' completed the jump quest." % player.username)

	# Teleport back after a short delay
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(player):
			MapManager.request_map_change(player.player_id, return_map_id, return_spawn_point)
	)
