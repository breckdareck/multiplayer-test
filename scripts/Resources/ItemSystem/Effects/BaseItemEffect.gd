@abstract
class_name BaseItemEffect
extends RefCounted

# A reference to the player who used the item.
var user: MultiplayerPlayerV2
# A reference to the item that was used.
var source_item: ConsumableData

# This function is called to execute the effect.
# It should be overridden by specific effect scripts.
func execute():
	push_warning("BaseItemEffect.execute() was called but not overridden!")
