extends CanvasLayer
class_name LocalPlayerUI

## Persistent local-player UI layer (ADR 0009 Stage B). Lifted out of the player
## body so the body can reparent cleanly (unblocks host/remote map-carry). One
## instance per client lives under /root for the whole session; it (re)binds its
## widgets to the local body on MapManager.local_player_changed — every spawn and
## every map change — instead of riding the body's one-shot _ready.
##
## Binding is PULL: on bind we hand each widget the body via bind_player(body),
## and the widgets ask the body's components for their model + connect the
## component change signals (the model already lives in the components — ADR 0009
## Stage A inverted the view wiring).

# Filled out in the next step.
func _ready() -> void:
	pass
