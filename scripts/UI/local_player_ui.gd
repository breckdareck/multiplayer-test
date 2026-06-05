extends CanvasLayer
class_name LocalPlayerUI

## Persistent local-player UI layer (ADR 0009 Stage B). Lifted out of the player
## body so the body can reparent cleanly (unblocks host/remote map-carry). One
## instance per client lives under /root for the whole session (created lazily by
## MapManager._ensure_local_ui, freed in reset_client_state); it (re)binds its
## widgets to the local body on MapManager.local_player_changed — every spawn and
## every map change — instead of riding the body's one-shot _ready.
##
## Binding is PULL: each widget exposes bind_player(body)/unbind_player() and asks
## the body's components for their model + connects the component change signals.
## Body-component signal connections are auto-cleaned when the body frees (Stage B
## recreates the local body on map change), so per-bind reconnection is safe;
## connections to PERSISTENT nodes are made once in each widget's _ready.

const GAME_MENU_SCENE = preload("res://scenes/UI/game_menu.tscn")

@onready var player_hud: Control = $PlayerHUD

var _body: Node = null
var _bindables: Array = []        # cached descendants exposing bind_player()
var _game_menu: GameMenu = null   # one-time; injected into the body each bind
var _quest_tracker: QuestTracker = null
var _mobile_conns: Array = []     # [[button, signal_name, Callable], ...]

# from player.tscn's authored [connection]s — preserved verbatim, including the
# (intentional or not) LeftButton.button_up -> _on_right_button_button_up wiring.
const _MOBILE_WIRING := [
	["LeftButton", "button_down", "_on_left_button_button_down"],
	["LeftButton", "button_up", "_on_right_button_button_up"],
	["RightButton", "button_down", "_on_right_button_button_down"],
	["RightButton", "button_up", "_on_right_button_button_up"],
	["AttackButton", "pressed", "_on_attack_button_pressed"],
	["JumpButton", "pressed", "_on_jump_button_pressed"],
]


func _ready() -> void:
	_collect_bindables(self)
	# GameMenu is body-independent (its tutorial overlay parents to player_hud;
	# everything else routes through autoloads). Build it once.
	_game_menu = GAME_MENU_SCENE.instantiate()
	player_hud.add_child(_game_menu)
	MapManager.local_player_changed.connect(_on_local_player_changed)
	# Created lazily right before the identify emit, so we normally bind via the
	# signal; bind now if a body somehow already exists.
	if is_instance_valid(MapManager.my_player_node) \
			and MapManager.my_player_node.player_id == multiplayer.get_unique_id():
		bind(MapManager.my_player_node)


func _collect_bindables(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("bind_player"):
			_bindables.append(child)
		_collect_bindables(child)


func _on_local_player_changed(body: Node) -> void:
	if body == null:
		unbind()
	else:
		bind(body)


func bind(body: Node) -> void:
	if _body == body:
		return
	if is_instance_valid(_body):
		unbind()
	_body = body
	if not is_instance_valid(body):
		return

	for w in _bindables:
		if is_instance_valid(w):
			w.bind_player(body)

	_wire_mobile_buttons(body)

	# Inject the hotbar into the ability component (AFTER hotbar.bind_player set
	# its component refs) so a returning character's bar gets repopulated.
	var hotbar = player_hud.get_node_or_null("Hotbar")
	if is_instance_valid(body.ability_component) and body.ability_component.has_method("set_hotbar"):
		body.ability_component.set_hotbar(hotbar)

	# GameMenu: hand the body its reference so the body's _input still forwards
	# events to it (it parents here, not on the body).
	if is_instance_valid(_game_menu):
		body.game_menu = _game_menu

	# QuestTracker: re-point at the new body (same logical player across maps).
	if not is_instance_valid(_quest_tracker):
		_quest_tracker = QuestTracker.new()
		player_hud.add_child(_quest_tracker)
	_quest_tracker.setup(body)

	# Zone-entry banner — shown briefly when the local player (re)spawns into a map.
	_show_zone_banner(body)

	player_hud.show()


func unbind() -> void:
	_unwire_mobile_buttons()
	for w in _bindables:
		if is_instance_valid(w) and w.has_method("unbind_player"):
			w.unbind_player()
	_body = null


## The local body changed maps WITHOUT being recreated (a live-node reparent —
## ADR 0009 Stage C). The widget bindings are unchanged (same body), so only the
## per-map UI needs refreshing: show the new map's zone banner.
func notify_map_arrival() -> void:
	if is_instance_valid(_body):
		_show_zone_banner(_body)


func _show_zone_banner(body: Node) -> void:
	var players_node := body.get_parent()
	var map_root := players_node.get_parent() if is_instance_valid(players_node) else null
	if map_root and map_root is MapBase and not (map_root as MapBase).display_name.is_empty():
		var banner := ZoneBanner.new()
		player_hud.add_child(banner)
		banner.show_zone((map_root as MapBase).display_name)


func _wire_mobile_buttons(body: Node) -> void:
	_unwire_mobile_buttons()
	var input_sync = body.input_synchronizer if "input_synchronizer" in body else null
	if not is_instance_valid(input_sync):
		return
	var mb := player_hud.get_node_or_null("MobileButtons")
	if mb == null:
		return
	for w in _MOBILE_WIRING:
		var btn = mb.get_node_or_null(w[0])
		if btn == null or not input_sync.has_method(w[2]):
			continue
		var cb := Callable(input_sync, w[2])
		btn.connect(w[1], cb)
		_mobile_conns.append([btn, w[1], cb])


func _unwire_mobile_buttons() -> void:
	for c in _mobile_conns:
		var btn = c[0]
		var cb: Callable = c[2]
		if is_instance_valid(btn) and is_instance_valid(cb.get_object()) and btn.is_connected(c[1], cb):
			btn.disconnect(c[1], cb)
	_mobile_conns.clear()
