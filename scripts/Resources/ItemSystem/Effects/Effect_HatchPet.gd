class_name Effect_HatchPet
extends BaseItemEffect

## Hatches a pet from a Pet Egg. The egg's effect_properties dict specifies
## which pet variety to hatch (pet_data_id) and the default name. Phase 2:
## the pet is created and auto-summoned with the default name; renaming is
## handled in the Pet management UI (Phase 3).

func execute() -> void:
	# This effect runs server-side because InventoryComponent.request_use_item
	# is server-gated. BaseItemEffect extends RefCounted, so we cannot reference
	# the `multiplayer` Node-only global directly here — trust the caller.
	if not is_instance_valid(user):
		return
	if not source_item or not source_item is ConsumableData:
		push_warning("Effect_HatchPet: missing source_item.")
		return

	var props: Dictionary = source_item.effect_properties
	var pet_data_id: String = props.get("pet_data_id", "")
	if pet_data_id.is_empty():
		push_warning("Effect_HatchPet: effect_properties missing 'pet_data_id'.")
		return
	var default_name: String = props.get("default_name", "Pet")

	PetManager.hatch_pet_server(user.username, pet_data_id, default_name)
