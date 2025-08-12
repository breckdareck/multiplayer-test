extends Node

var score = 0

func add_point():
	score += 1
	print(score)


func host_game():
	MultiplayerManager.host_game()


func join_game():
	MultiplayerManager.join_game()
	
		
func disconnect_from_server():
	multiplayer.multiplayer_peer.close()
