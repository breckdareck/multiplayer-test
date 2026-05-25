class_name Effect_TeachPetCommand
extends BaseItemEffect

## Teaches a pet command to the user's currently summoned pet.
##
## The PetSkillBookData's effect_properties carries {"command_id": "..."}
## matching one of PetManager.CMD_*. If the player has no summoned pet, or
## the pet already knows the command, the book is refunded.

func execute() -> void:
	if not multiplayer.is_server():
		return
	if not is_instance_valid(user):
		return
	if not source_item:
		return

	var props: Dictionary = source_item.effect_properties
	var command_id: String = props.get("command_id", "")
	if command_id.is_empty():
		push_warning("Effect_TeachPetCommand: effect_properties missing 'command_id'.")
		_refund()
		return

	var username: String = user.username
	var summoned: Array = PetManager.get_summoned_ids(username)
	if summoned.is_empty():
		PetManager.notify_book_use_failed(username, "Summon a pet first.")
		_refund()
		return

	# v1: one summoned pet. Teach it the command.
	var pet_uuid: String = summoned[0]
	var record := PetManager.find_pet(username, pet_uuid)
	if record.is_empty():
		_refund()
		return
	var learned: Array = record.get(PetManager.KEY_LEARNED, [])
	if learned.has(command_id):
		# Already knows it — refund so the player doesn't waste the book.
		_refund()
		return

	learned.append(command_id)
	record[PetManager.KEY_LEARNED] = learned
	PetManager.notify_command_learned(username, pet_uuid, command_id)


func _refund() -> void:
	if is_instance_valid(user) and is_instance_valid(user.inventory_component) and source_item:
		user.inventory_component.server_add_item(source_item.item_id)
