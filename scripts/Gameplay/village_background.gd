extends ParallaxBackground

## Hide the parallax when the local client isn't viewing this map.
##
## ParallaxBackground extends CanvasLayer, and CanvasLayers render globally on
## their viewport regardless of which map node sits "around" them in the scene
## tree. On the server-host, every loaded map exists simultaneously (e.g. a bot
## in `game` forces `Map_game` into the host's tree even while the host walks
## around `town`) — without this guard, the host sees `game`'s parallax bleed
## through into `town`, and the layer "pops in" the instant a bot loads its
## map.
##
## The check compares the map_id derived from this background's MapBase
## ancestor against `MapManager.current_map_id` (the local client's current
## map). When they match, the parallax is visible; otherwise hidden.

var _my_map_id: String = ""


func _ready() -> void:
	_my_map_id = _resolve_my_map_id()
	_update_visibility()


func _process(_delta: float) -> void:
	_update_visibility()


func _update_visibility() -> void:
	if _my_map_id.is_empty():
		return
	visible = (MapManager.current_map_id == _my_map_id)


## Walk up to the map root. At runtime MapManager renames each loaded map node
## to "Map_<id>" (e.g. "Map_game"), so strip the prefix; in the editor or any
## not-yet-renamed context, fall back to the lowercase node name.
func _resolve_my_map_id() -> String:
	var node: Node = get_parent()
	while node:
		if node is MapBase:
			var n: String = node.name
			if n.begins_with("Map_"):
				return n.substr(4)
			return n.to_lower()
		node = node.get_parent()
	return ""
