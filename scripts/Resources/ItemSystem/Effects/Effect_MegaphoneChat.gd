class_name Effect_MegaphoneChat
extends BaseItemEffect

func execute():
	if not is_instance_valid(user):
		print("Megaphone Effect: Invalid user.")
		return

	# Enable megaphone mode on ChatManager for this player's next message
	ChatManager.enable_megaphone(user.player_id, user.username)
	print("Megaphone activated for player '%s'." % user.username)
