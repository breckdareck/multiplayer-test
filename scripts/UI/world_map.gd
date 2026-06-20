extends Control
## Full-screen informational world map (toggle with M). Draws every map as a node
## on a hand-authored regional layout, edges from the real portal graph, and the
## player's current location highlighted. All locations are shown (no fog); hover
## a map for a tooltip with its recommended level, the enemies that live there
## (with levels), and each enemy's drop table with drop %.
##
## Pure client-side: content comes from the static catalog config/world_map_data.json
## (built by tools/dump_world_map.gd from the same scenes/portals the game uses).
## No RPCs, no state mutation.

const CATALOG_PATH := "res://config/world_map_data.json"

## TWO-VIEW radial world map (MapleStory-style drill-down). The WORLD view is the rim + spokes +
## Emberwatch with a synthetic "The Core" gateway at centre; clicking it opens the CORE view (the
## deep descent Emberwatch → … → Warlord) with a "↑ Surface" gateway back. Normalized [0..1]
## positions within the content rect; edges come from the real connection graph (drawn only between
## maps in the active view). Generated/retuned by tools/preview_world_map.py — re-run + paste here.
## ADD EVERY NEW MAP to the right view's layout, or it won't render.
## CROSSWAY world view (opt7 FISHBONE x3): three town arms radiate from the centred Emberwatch.
## Each arm = a town in the MIDDLE of a fishbone — a CLIMB runs inward to Emberwatch, the branchy
## LOW FRONTIER of dead-end grinding pockets hangs out past the town. All three are parallel Lv2-48
## routes. Lantern's = upper-right, Wickmoor = left, Hollowmere = lower-right; Core gate below centre.
## Baked from tools/preview_world_map.py (keep the two in lockstep). Nodes/edges draw only for maps
## present here (edges from the real portal catalog), so the back-half (Core view) maps are excluded.
const LAYOUT_WORLD := {
	"emberwatch":      Vector2(0.500, 0.500),
	# --- Lantern's Rest arm (upper-right) ---
	"lanterns_rest":   Vector2(0.628, 0.212),
	"near_wilds":      Vector2(0.644, 0.176),
	"glimmerfen":      Vector2(0.661, 0.139),
	"tinderfields":    Vector2(0.677, 0.103),
	"ember_meadows":   Vector2(0.693, 0.066),
	"firefly_hollow":  Vector2(0.587, 0.158),
	"meadow_path":     Vector2(0.534, 0.141),
	"brackenway":      Vector2(0.713, 0.170),
	"bramble_downs":   Vector2(0.760, 0.198),
	"lanternwood":     Vector2(0.619, 0.085),
	"watchers_ruin":   Vector2(0.567, 0.068),
	"hollow_warren":   Vector2(0.745, 0.097),
	"beacon_rise":     Vector2(0.793, 0.125),
	"old_causeway":    Vector2(0.612, 0.249),
	"ruins":           Vector2(0.596, 0.285),
	"thornroot":       Vector2(0.579, 0.322),
	"old_battlefield": Vector2(0.563, 0.358),
	"the_reliquary":   Vector2(0.547, 0.395),
	"embergate":       Vector2(0.531, 0.431),
	# --- Wickmoor arm (left) ---
	"wickmoor":        Vector2(0.187, 0.533),
	"reedmire":        Vector2(0.147, 0.537),
	"sodden_flats":    Vector2(0.107, 0.541),
	"heatherreach":    Vector2(0.067, 0.545),
	"blackpeat":       Vector2(0.028, 0.550),
	"glowmoss_burrow": Vector2(0.160, 0.596),
	"peat_steps":      Vector2(0.172, 0.650),
	"the_brackens":    Vector2(0.108, 0.481),
	"gorse_downs":     Vector2(0.108, 0.426),
	"willowmere":      Vector2(0.081, 0.604),
	"drowned_shrine":  Vector2(0.092, 0.658),
	"mudwarren":       Vector2(0.028, 0.489),
	"bogbeacon":       Vector2(0.029, 0.434),
	"long_ford":       Vector2(0.227, 0.529),
	"the_sluice":      Vector2(0.266, 0.525),
	"mirewarren":      Vector2(0.306, 0.520),
	"bonemarsh":       Vector2(0.346, 0.516),
	"the_oubliette":   Vector2(0.386, 0.512),
	"marshgate":       Vector2(0.425, 0.508),
	# --- Hollowmere arm (lower-right) ---
	"hollowmere":      Vector2(0.685, 0.755),
	"the_shallows":    Vector2(0.709, 0.787),
	"craghollow":      Vector2(0.732, 0.820),
	"echo_downs":      Vector2(0.756, 0.852),
	"greymoor":        Vector2(0.779, 0.884),
	"pebble_warren":   Vector2(0.753, 0.746),
	"cairn_steps":     Vector2(0.794, 0.709),
	"gullstone_bluffs":Vector2(0.680, 0.849),
	"windward_downs":  Vector2(0.631, 0.877),
	"mistfield":       Vector2(0.800, 0.811),
	"sunken_hall":     Vector2(0.841, 0.774),
	"hollow_deep":     Vector2(0.727, 0.914),
	"beacon_crag":     Vector2(0.679, 0.941),
	"stone_span":      Vector2(0.662, 0.722),
	"riftway":         Vector2(0.638, 0.690),
	"gravewarren":     Vector2(0.615, 0.658),
	"shattercliffs":   Vector2(0.591, 0.625),
	"deepshaft":       Vector2(0.568, 0.593),
	"hollowgate":      Vector2(0.544, 0.561),
}
const LAYOUT_CORE := {
	# Inward spiral descent (spread out): entry at the rim -> Warlord at the centre.
	"emberwatch":      Vector2(0.500, 0.060),    # entry (also shown in world view)
	"deep_woods":      Vector2(0.817, 0.219),
	"keep":            Vector2(0.901, 0.513),
	"mustering_fields":Vector2(0.742, 0.746),
	"the_scorchline":  Vector2(0.478, 0.795),
	"emberscar":       Vector2(0.283, 0.667),
	"cinderwaste":     Vector2(0.258, 0.477),
	"weave":           Vector2(0.375, 0.353),
	"the_unraveling":  Vector2(0.523, 0.351),
	"ashvigil":        Vector2(0.601, 0.433),
	"warlord":         Vector2(0.500, 0.500),
}
## Synthetic gateway nodes (not real maps): id, normalized pos, label, the view it switches to.
const CORE_GATE := {"id": "__core__", "pos": Vector2(0.500, 0.605), "label": "The Core  ▾", "to": "core"}
const SURFACE_GATE := {"id": "__surface__", "pos": Vector2(0.085, 0.090), "label": "↑  The Surface", "to": "world"}
const GATE_R := 18.0
## Core-only maps (used to auto-open the right view from the current location).
const CORE_ONLY := ["deep_woods", "keep", "mustering_fields", "the_scorchline", "emberscar",
	"cinderwaste", "weave", "the_unraveling", "ashvigil", "warlord"]

var _view := "world"   # "world" | "core"

func _active_layout() -> Dictionary:
	return LAYOUT_CORE if _view == "core" else LAYOUT_WORLD

func _active_gate() -> Dictionary:
	return SURFACE_GATE if _view == "core" else CORE_GATE

func _gate_pos(content: Rect2) -> Vector2:
	return content.position + (_active_gate()["pos"] as Vector2) * content.size
# Hearth (safe town) maps come from MapManager.HEARTH_MAPS — single source of
# truth shared with Hearthstone/Town-Scroll teleport targeting.

const C_BG := Color(0.03, 0.04, 0.07, 0.92)
const C_EDGE := Color(0.55, 0.5, 0.35, 0.7)
const C_TOWN := Color(1.0, 0.82, 0.3)
const C_VISITED := Color(0.5, 0.78, 0.55)
const C_BOSS := Color(0.95, 0.4, 0.4)
const C_FOG := Color(0.22, 0.23, 0.28)
const C_CURRENT := Color(0.45, 0.85, 1.0)
const C_HUB := Color(1.0, 0.62, 0.25)    # ember glow pooled at the centred hub
const C_FLOW := Color(1.0, 0.86, 0.55)   # energy motes drifting along the roads
const C_RING := Color(0.5, 0.42, 0.3)    # faint concentric wheel guides
const NODE_R := 13.0

var _catalog: Dictionary = {}
var _font: Font
var _tip: PanelContainer        # styled tooltip card
var _tip_scroll: ScrollContainer  # caps card height; scrolls when content is tall
var _tip_body: VBoxContainer    # rebuilt per hovered map
var _tip_tween: Tween
var _sf_cache: Dictionary = {}  # sprite-frames path -> first-frame Texture2D
var _icon_cache: Dictionary = {}  # item icon path -> Texture2D
var _hovered: String = ""
var _pulse: float = 0.0

# Editable WORLD-view scene (background image + draggable pins). Core view stays runtime-drawn.
@onready var _map_area: TextureRect = get_node_or_null("MapArea")
@onready var _pins_holder: Control = get_node_or_null("MapArea/Pins")
@onready var _edges: Control = get_node_or_null("MapArea/Edges")
var _pins: Dictionary = {}   # map_id -> MapPin node (from the scene)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_font = ThemeDB.fallback_font
	_load_catalog()

	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.custom_minimum_size = Vector2(320, 0)
	_tip.z_index = 20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.12, 0.98)
	sb.border_color = Color(0.95, 0.85, 0.45, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 10
	_tip.add_theme_stylebox_override("panel", sb)
	# A scroll wrapper caps the card height so a drop-heavy map can't run off the
	# screen; it only scrolls when the content exceeds the cap (see _update_hover).
	_tip_scroll = ScrollContainer.new()
	_tip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tip_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(_tip_scroll)
	_tip_body = VBoxContainer.new()
	_tip_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip_body.add_theme_constant_override("separation", 8)
	_tip_scroll.add_child(_tip_body)
	_tip.visible = false
	add_child(_tip)
	# Join the standard window group so player_hud's Esc / death handlers close it
	# like every other window. Closing may happen via .visible (player_hud) OR
	# toggle() (M key), so the open/close side-effects live in _on_visibility_changed.
	add_to_group("ui_window")
	visibility_changed.connect(_on_visibility_changed)
	MapManager.population_counts_received.connect(_on_population_counts)
	# Index the scene's editable pins by map_id; hide the image layer until the world view opens.
	if _pins_holder:
		for c in _pins_holder.get_children():
			var mid = c.get("map_id")
			if mid != null and str(mid) != "":
				_pins[str(mid)] = c
	if _map_area:
		_map_area.visible = false
	set_process(false)


func _load_catalog() -> void:
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("world_map: missing %s — run tools/dump_world_map.gd" % CATALOG_PATH)
		return
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_catalog = parsed.get("maps", {})


func toggle() -> void:
	visible = not visible


func _on_visibility_changed() -> void:
	set_process(visible)
	if visible:
		_pulse = 0.0
		# Open straight to the view that contains the player (Core view if they're deep in).
		_view = "core" if MapManager.current_map_id in CORE_ONLY else "world"
		_hovered = ""
		move_to_front()
		_apply_view()
		# One population snapshot per open (ADR 0012) — counts players + bots.
		if multiplayer.has_multiplayer_peer():
			MapManager.request_population_counts.rpc_id(1)
	else:
		_hovered = ""
		_tip.visible = false
		if _map_area:
			_map_area.visible = false


## Show/hide the painted world image + refresh the pins for the active view.
func _apply_view() -> void:
	var is_world := _view == "world"
	if _map_area:
		_map_area.visible = is_world and visible
	if is_world:
		_refresh_pins()
	queue_redraw()


## Push live label / level / colour / current-location state onto each editable pin.
func _refresh_pins() -> void:
	for mid in _pins:
		var pin = _pins[mid]
		if mid == "__core__":
			pin.configure("The Core  ▾", "", Color(0.62, 0.4, 0.72), false, false, true)
			continue
		var info: Dictionary = _catalog.get(mid, {})
		var dname: String = MapManager.MAP_DISPLAY_NAMES.get(mid, info.get("display_name", mid))
		var is_town: bool = mid in MapManager.HEARTH_MAPS or info.get("is_town", false)
		var is_boss := false
		for e in info.get("enemies", []):
			if e.get("is_boss", false):
				is_boss = true
		var lvl := ""
		if not is_town:
			var lo = info.get("min_level"); var hi = info.get("max_level")
			if lo != null:
				lvl = ("Lv %d" % lo) if lo == hi else ("Lv %d-%d" % [lo, hi])
		var col: Color = C_TOWN if is_town else (C_BOSS if is_boss else C_VISITED)
		pin.configure(dname, lvl, col, is_town, mid == MapManager.current_map_id, false)
	if _edges and _edges.has_method("refresh"):
		_edges.refresh()


## Per-map occupant counts (players + bots), refreshed each time the map opens.
var _population: Dictionary = {}

func _on_population_counts(counts: Dictionary) -> void:
	_population = counts
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	# M toggles the map open/closed. (Esc-to-close is handled by player_hud via the
	# "ui_window" group, the same as every other window; this is just a fallback.)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M and not InputManager.is_locked():
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			visible = false
			get_viewport().set_input_as_handled()


## Maps the player has revealed: server-saved visited set + the live current map.
## All locations are shown on the world map (no fog) — every map is discoverable
## at a glance. (The current location is still highlighted in _draw.)
func _revealed() -> Dictionary:
	var s := {}
	for map_id in _catalog:
		s[map_id] = true
	return s


func _content_rect() -> Rect2:
	var m := 70.0
	return Rect2(m, m + 24.0, size.x - m * 2.0, size.y - m * 2.0 - 24.0)


func _node_pos(map_id: String, content: Rect2) -> Vector2:
	var n: Vector2 = _active_layout().get(map_id, Vector2(0.5, 0.5))
	return content.position + n * content.size


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse += delta
	_update_hover()
	queue_redraw()


func _update_hover() -> void:
	var content := _content_rect()
	var mouse := get_local_mouse_position()
	var found := ""
	if _view == "world":
		# Hit-test the editable scene pins (CoreGate pin has map_id "__core__").
		var mg := get_global_mouse_position()
		for mid in _pins:
			if mg.distance_to(_pins[mid].global_position) <= MapPin.R + 5.0:
				found = mid
				break
	else:
		for map_id in _active_layout():
			if not _catalog.has(map_id):
				continue
			if mouse.distance_to(_node_pos(map_id, content)) <= NODE_R + 4.0:
				found = map_id
				break
		if found == "" and mouse.distance_to(_gate_pos(content)) <= GATE_R + 4.0:
			found = String(_active_gate()["id"])   # hovering the synthetic gateway
	if found != _hovered:
		_hovered = found
		if found == "" or found.begins_with("__"):
			_tip.visible = false   # gateways have no catalog tooltip; their label says it all
		else:
			_build_tip(found)
	if _tip.visible:
		# Size the scroll area to its content, capped at the available screen height
		# (so a drop-heavy map scrolls instead of overflowing). Then shrink the card
		# to that and clamp near the cursor.
		var content_h: float = _tip_body.get_combined_minimum_size().y
		var max_h: float = maxf(120.0, size.y - 24.0)
		_tip_scroll.custom_minimum_size.y = minf(content_h, max_h)
		_tip.reset_size()
		var pos := mouse + Vector2(20, 14)
		pos.x = clampf(pos.x, 8.0, maxf(8.0, size.x - _tip.size.x - 8.0))
		pos.y = clampf(pos.y, 8.0, maxf(8.0, size.y - _tip.size.y - 8.0))
		_tip.position = pos


## The card ignores the mouse (so hovering it doesn't drop the node hover), so we
## route wheel scrolling to it here while it's showing and taller than its cap.
func _gui_input(event: InputEvent) -> void:
	# Left-click the gateway to drill in/out (World <-> Core). In world view that's the
	# CoreGate pin; in core view it's the synthetic "Surface" gateway.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit_gate := false
		if _view == "world":
			if _pins.has("__core__") and get_global_mouse_position().distance_to(_pins["__core__"].global_position) <= MapPin.R + 6.0:
				hit_gate = true; _view = "core"
		elif get_local_mouse_position().distance_to(_gate_pos(_content_rect())) <= GATE_R + 5.0:
			hit_gate = true; _view = String(_active_gate()["to"])
		if hit_gate:
			_hovered = ""
			_tip.visible = false
			_apply_view()
			accept_event()
			return
	if not _tip.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_tip_scroll.scroll_vertical += 36
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_tip_scroll.scroll_vertical -= 36
			accept_event()


## Rebuild the tooltip card for a map and pop it in.
func _build_tip(map_id: String) -> void:
	for c in _tip_body.get_children():
		_tip_body.remove_child(c)
		c.queue_free()

	var info: Dictionary = _catalog.get(map_id, {})
	var dname: String = MapManager.MAP_DISPLAY_NAMES.get(map_id, info.get("display_name", map_id))
	var is_town: bool = (map_id in MapManager.HEARTH_MAPS) or info.get("is_town", false)
	var has_boss := false
	for e in info.get("enemies", []):
		if e.get("is_boss", false):
			has_boss = true

	# Header: title + level / SAFE badge.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var title := _label(("★ " if has_boss else "") + dname, 20, Color(1.0, 0.9, 0.62))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	if is_town:
		header.add_child(_badge("SAFE", Color(0.45, 0.4, 0.16)))
	else:
		header.add_child(_badge("Lv %d" % int(info.get("avg_level", 0)),
			Color(0.65, 0.32, 0.32) if has_boss else Color(0.18, 0.46, 0.6)))
	_tip_body.add_child(header)

	if not is_town:
		var sub := _label("Recommended  ·  enemies Lv %d–%d" % [int(info.get("min_level", 0)), int(info.get("max_level", 0))],
			12, Color(0.6, 0.65, 0.72))
		_tip_body.add_child(sub)
	_tip_body.add_child(_hsep())

	if is_town:
		_tip_body.add_child(_label("A safe hearth — no enemies here.", 14, Color(1.0, 0.85, 0.45)))
	else:
		for e in info.get("enemies", []):
			_tip_body.add_child(_make_enemy_row(e))

	_tip_scroll.scroll_vertical = 0
	_tip.visible = true
	_pop_in()


func _make_enemy_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# Sprite thumbnail in a soft framed box.
	var frame := PanelContainer.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0, 0, 0, 0.28)
	fsb.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(46, 46)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex := _enemy_tex(e.get("sf", ""))
	if tex:
		tex_rect.texture = tex
	frame.add_child(tex_rect)
	row.add_child(frame)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	var boss_tag: String = "  [color=#ff7676]BOSS[/color]" if e.get("is_boss", false) else ""
	col.add_child(_rich("[b]%s[/b]  [color=#8a93a0]Lv %d[/color]%s" % [e.get("name", "?"), int(e.get("level", 0)), boss_tag], 14))
	# Item drops (Coin omitted — it's not interesting loot).
	var loot := []
	for d in e.get("drops", []):
		if String(d.get("item", "")) != "Coin":
			loot.append(d)
	if loot.is_empty():
		col.add_child(_rich("[color=#666]no item drops[/color]", 12))
	else:
		for d in loot:
			col.add_child(_make_drop_row(d))
	row.add_child(col)
	return row


func _make_drop_row(d: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(20, 20)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tex := _item_icon(d.get("icon", ""))
	if tex:
		ic.texture = tex
	h.add_child(ic)
	var pct: float = float(d.get("chance", 0.0)) * 100.0
	var pct_str: String = ("%.1f%%" % pct) if pct < 10.0 else ("%d%%" % int(round(pct)))
	var lvl: int = int(d.get("ilvl", 0))
	var lvl_str: String = ("  [color=#7a8190]Lv %d[/color]" % lvl) if lvl > 0 else ""
	h.add_child(_rich("[color=#c2cee0]%s[/color]%s   [color=#7fd0a0]%s[/color]" % [d.get("item", "?"), lvl_str, pct_str], 12))
	return h


func _item_icon(path: String) -> Texture2D:
	if path == "":
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	var t = load(path)
	var tex: Texture2D = t if t is Texture2D else null
	_icon_cache[path] = tex
	return tex


func _enemy_tex(sf_path: String) -> Texture2D:
	if sf_path == "":
		return null
	if _sf_cache.has(sf_path):
		return _sf_cache[sf_path]
	var tex: Texture2D = null
	var sf = load(sf_path)
	if sf is SpriteFrames:
		var anim := ""
		for cand in ["idle", "default", "walk"]:
			if sf.has_animation(cand):
				anim = cand
				break
		if anim == "" and sf.get_animation_names().size() > 0:
			anim = sf.get_animation_names()[0]
		if anim != "" and sf.get_frame_count(anim) > 0:
			tex = sf.get_frame_texture(anim, 0)
	_sf_cache[sf_path] = tex
	return tex


func _label(text: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l


func _rich(bb: String, sz: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", sz)
	r.add_theme_font_size_override("bold_font_size", sz)
	r.text = bb
	return r


func _badge(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(text, 13, Color(1, 1, 1, 0.95)))
	return p


func _hsep() -> Control:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.12)
	c.custom_minimum_size = Vector2(0, 1)
	return c


func _pop_in() -> void:
	if _tip_tween and _tip_tween.is_valid():
		_tip_tween.kill()
	_tip.pivot_offset = Vector2.ZERO
	_tip.modulate.a = 0.0
	_tip.scale = Vector2(0.95, 0.95)
	_tip_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
	_tip_tween.tween_property(_tip, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_SINE)
	_tip_tween.tween_property(_tip, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK)


## The synthetic portal node linking Emberwatch to the other view (World <-> Core).
func _draw_gateway(content: Rect2) -> void:
	var gate: Dictionary = _active_gate()
	var gp := _gate_pos(content)
	var pulse: float = 0.5 + 0.5 * sin(_pulse * 3.0)
	if _active_layout().has("emberwatch"):
		var ep := _node_pos("emberwatch", content)
		draw_line(ep, gp, Color(0.55, 0.5, 0.78, 0.18), 5.0)
		draw_line(ep, gp, Color(0.6, 0.55, 0.85, 0.85), 2.0)
		var gf: float = fposmod(_pulse * 0.3, 1.0)
		draw_circle(ep.lerp(gp, gf), 2.6, Color(0.85, 0.78, 1.0, 0.7 * sin(gf * PI)))
	# Portal aura.
	draw_circle(gp, GATE_R + 12.0, Color(0.5, 0.36, 0.72, 0.08 + 0.10 * pulse))
	draw_circle(gp, GATE_R + 6.0, Color(0.5, 0.36, 0.72, 0.12 + 0.12 * pulse))
	draw_circle(gp, GATE_R, Color(0.42, 0.30, 0.62))
	draw_arc(gp, GATE_R, 0, TAU, 32, Color(0.85, 0.78, 1.0, 0.9), 2.0)
	draw_arc(gp, GATE_R - 6.0, 0, TAU, 28, Color(0.88, 0.8, 1.0, 0.35 + 0.45 * pulse), 2.0)
	if _hovered == String(gate["id"]):
		draw_arc(gp, GATE_R + 3.0, 0, TAU, 32, Color.WHITE, 1.5)
	if _font:
		draw_string(_font, gp + Vector2(-90, GATE_R + 17), String(gate["label"]),
			HORIZONTAL_ALIGNMENT_CENTER, 180, 14, Color(0.86, 0.79, 1.0))


func _draw() -> void:
	var content := _content_rect()
	if _view == "world":
		# WORLD view: the painted map image (MapArea child) + the Edges layer + the pins all
		# render themselves. Here we just lay a dark surround behind the centred image + the title.
		draw_rect(Rect2(Vector2.ZERO, size), C_BG, true)
		_draw_title(content)
		return

	# CORE view: legacy runtime drawing (the descent spiral + nodes + the "Surface" gateway).
	_draw_backdrop(content)
	var revealed := _revealed()
	var layout := _active_layout()
	if layout.has("emberwatch"):
		_draw_hub_glow(_node_pos("emberwatch", content))
	_draw_title(content)
	var drawn := {}
	for map_id in _catalog:
		if not layout.has(map_id):
			continue
		for tgt in _catalog[map_id].get("connections", []):
			if not layout.has(tgt):
				continue
			var key: String = map_id + "|" + tgt if map_id < tgt else tgt + "|" + map_id
			if drawn.has(key):
				continue
			drawn[key] = true
			var both_seen: bool = revealed.has(map_id) and revealed.has(tgt)
			_draw_edge(_node_pos(map_id, content), _node_pos(tgt, content), both_seen, key)
	_draw_gateway(content)
	for map_id in layout:
		if not _catalog.has(map_id):
			continue
		_draw_map_node(map_id, _node_pos(map_id, content), revealed.has(map_id))


func _draw_title(content: Rect2) -> void:
	if not _font:
		return
	var title: String = "World Map — The Core" if _view == "core" else "World Map — The Emberwilds"
	draw_string(_font, Vector2(content.position.x + 1, 51), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.6))
	draw_string(_font, Vector2(content.position.x, 50), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.9, 0.6))
	draw_string(_font, Vector2(content.position.x, content.end.y + 36), "[M] or [Esc] to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.6, 0.65))


## Flat base + a soft warm pool of light toward the centre (stacked translucent
## circles, darkening to the corners) so the map has depth instead of a flat field.
func _draw_backdrop(content: Rect2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG, true)
	var c := size * 0.5
	var maxr := size.length() * 0.5
	for i in range(8):
		var t := float(i) / 8.0
		draw_circle(c, lerp(maxr * 0.72, 48.0, t), Color(0.11, 0.08, 0.06, 0.045))


## Faint concentric ellipses centred on the hub — echoes the rim radius (RX=0.44,
## RY=0.42 of the content rect, matching the generator) and its inner fractions.
func _draw_wheel_guides(content: Rect2) -> void:
	var c := content.position + content.size * 0.5
	for f in [1.0, 0.72, 0.44, 0.2]:
		var pts := _ellipse_pts(c, content.size.x * 0.44 * f, content.size.y * 0.42 * f, 72)
		draw_polyline(pts, Color(C_RING.r, C_RING.g, C_RING.b, 0.10), 1.5, true)


func _ellipse_pts(center: Vector2, rx: float, ry: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Pulsing ember aura behind Emberwatch — the heart of the wheel.
func _draw_hub_glow(p: Vector2) -> void:
	var pulse: float = 0.5 + 0.5 * sin(_pulse * 2.0)
	for i in range(5):
		var t := float(i) / 5.0
		var rr: float = lerp(48.0, 16.0, t) + pulse * 4.0
		draw_circle(p, rr, Color(C_HUB.r, C_HUB.g, C_HUB.b, 0.05 + 0.05 * (1.0 - t)))


## A road between two maps: a soft underglow, a bright core, and energy motes that
## drift along it (revealed roads only — fog roads stay dim and still).
func _draw_edge(a: Vector2, b: Vector2, both_seen: bool, key: String) -> void:
	if both_seen:
		draw_line(a, b, Color(C_EDGE.r, C_EDGE.g, C_EDGE.b, 0.16), 5.0)
		draw_line(a, b, C_EDGE, 2.0)
		var phase := float(abs(key.hash()) % 1000) / 1000.0
		for k in range(2):
			var frac: float = fposmod(_pulse * 0.22 + phase + float(k) * 0.5, 1.0)
			var fade: float = sin(frac * PI)
			draw_circle(a.lerp(b, frac), 2.6, Color(C_FLOW.r, C_FLOW.g, C_FLOW.b, 0.65 * fade))
	else:
		draw_line(a, b, Color(C_FOG.r, C_FOG.g, C_FOG.b, 0.45), 2.0)


## One map marker: type aura (towns/bosses), current-location pulse, a body with an
## inner highlight + crisp rim, a hover ring, label with shadow, and a pop badge.
func _draw_map_node(map_id: String, p: Vector2, seen: bool) -> void:
	var info: Dictionary = _catalog[map_id]
	var is_current: bool = (map_id == MapManager.current_map_id)
	var is_town: bool = (map_id in MapManager.HEARTH_MAPS) or info.get("is_town", false)
	var has_boss := false
	for e in info.get("enemies", []):
		if e.get("is_boss", false):
			has_boss = true
	var col: Color = C_FOG
	if seen:
		if is_town:
			col = C_TOWN
		elif has_boss:
			col = C_BOSS
		else:
			col = C_VISITED
	var r: float = NODE_R + (2.0 if (is_town or has_boss) else 0.0)

	# Type aura — towns and bosses pulse so they read at a glance (boss faster).
	if seen and (is_town or has_boss):
		var aura: float = 0.5 + 0.5 * sin(_pulse * (3.2 if has_boss else 2.0))
		draw_circle(p, r + 10.0, Color(col.r, col.g, col.b, 0.08 + 0.10 * aura))
		draw_circle(p, r + 5.0, Color(col.r, col.g, col.b, 0.13 + 0.12 * aura))

	# Current location — cyan pulse halo + expanding ring.
	if is_current:
		var glow: float = 0.5 + 0.5 * sin(_pulse * 4.0)
		draw_circle(p, r + 13.0, Color(C_CURRENT.r, C_CURRENT.g, C_CURRENT.b, 0.10 + 0.16 * glow))
		draw_arc(p, r + 6.0 + glow * 2.0, 0, TAU, 40, Color(C_CURRENT, 0.45 + 0.5 * glow), 3.0)

	# Body + inner highlight (sheen, upper-left) + crisp rim.
	draw_circle(p, r, col)
	draw_circle(p - Vector2(r, r) * 0.32, r * 0.4, Color(1, 1, 1, 0.18 if seen else 0.05))
	draw_arc(p, r, 0, TAU, 32, Color(0, 0, 0, 0.65), 1.5)
	if seen:
		draw_arc(p, r, 0, TAU, 32, Color(col.lightened(0.35), 0.9), 1.5)

	# Hover — a bright expanding ring.
	if _hovered == map_id:
		var hp: float = 0.5 + 0.5 * sin(_pulse * 6.0)
		draw_arc(p, r + 3.0 + hp * 3.0, 0, TAU, 32, Color(1, 1, 1, 0.5 + 0.4 * hp), 1.5)

	if not _font:
		return
	if seen:
		var dname: String = MapManager.MAP_DISPLAY_NAMES.get(map_id, info.get("display_name", map_id))
		draw_string(_font, p + Vector2(-60, r + 15), dname,
			HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(0, 0, 0, 0.7))
		draw_string(_font, p + Vector2(-60, r + 14), dname,
			HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(0.94, 0.94, 0.97))
		# Population badge (ADR 0012) — revealed maps only, so fog of war doesn't
		# leak where the action is.
		var pop: int = int(_population.get(map_id, 0))
		if pop > 0:
			draw_circle(p + Vector2(r + 5, -r - 2), 7.0, Color(0.12, 0.3, 0.16, 0.95))
			draw_arc(p + Vector2(r + 5, -r - 2), 7.0, 0, TAU, 16, Color(0.5, 1.0, 0.6, 0.8), 1.0)
			draw_string(_font, p + Vector2(r + 5 - 8, -r + 2), str(pop),
				HORIZONTAL_ALIGNMENT_CENTER, 16, 10, Color(0.7, 1.0, 0.72))
	else:
		draw_string(_font, p + Vector2(-5, 5), "?",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.6, 0.65))
