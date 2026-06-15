extends Control

## Top-center boss HP bar (HUD widget).
##
## Hidden by default. Polls the local peer's currently-visible map for an enemy
## whose enemy_data.is_boss is true (the "Enemies" group + is_ancestor_of filter
## that bot_manager uses), binds to that boss's replicated HealthComponent, and
## paints its current/max health + title. Hides on boss death or when no boss is
## present on the visible map.
##
## DISCOVERY is by group-scan, NOT by RPC. The boss is a normal
## MultiplayerSpawner-replicated enemy that joins the "Enemies" group on every
## peer, and its Health (current/max/is_dead) replicates via the scene's
## SceneReplicationConfig. So every peer — including a bot HOST, which has no
## client to receive a node-addressed RPC — finds and reads the boss the same
## way, with no networking added. This widget never mutates state; it only reads.
##
## No `class_name` and no hard EnemyBase/EnemyData/HealthComponent type
## annotations on purpose: this widget is only ever instanced from
## boss_hp_bar.tscn, and adding another `class_name` with cross-references into the
## enemy/component graph risks a global-class-cache resolution cycle (the same
## circular-preload class of failure documented elsewhere in the repo). Duck-typed
## property reads keep it out of that cycle.
##
## Layout lives in boss_hp_bar.tscn (panel + title label + progress bar). This
## script only resolves the authored nodes by name and fills them.

#region #################### Constants ####################

## How often (seconds) to re-scan for a boss on the visible map. The scan is cheap
## (a small group with an ancestor check) so a few times a second is plenty.
const RESCAN_INTERVAL: float = 0.5

#endregion


#region #################### State ####################

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var subtitle_label: Label = $Panel/VBox/SubtitleLabel
@onready var health_bar: ProgressBar = $Panel/VBox/HealthBar
@onready var value_label: Label = $Panel/VBox/HealthBar/ValueLabel

## The boss currently bound to (an EnemyBase node), or null when none is shown.
var _boss: Node = null
## The boss's HealthComponent node (duck-typed).
var _boss_health: Node = null
var _rescan_accum: float = 0.0

## Boss combat music: started on bind, swapped at the enrage threshold, and the
## map's normal BGM restored on unbind. Client-side (music is never networked).
var _boss_music_on: bool = false
var _boss_enrage_music: bool = false

#endregion


#region #################### Lifecycle ####################

func _ready() -> void:
	visible = false
	# Don't block clicks through the HUD.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	# Re-scan periodically: a boss may spawn, the player may change maps, or the
	# bound boss may despawn.
	_rescan_accum += delta
	if _rescan_accum >= RESCAN_INTERVAL:
		_rescan_accum = 0.0
		_rescan()

	# If we have a live binding, refresh the bar every frame from replicated HP.
	if _boss != null and is_instance_valid(_boss) and _boss_health != null and is_instance_valid(_boss_health):
		if _boss_health.is_dead:
			_unbind()
			return
		_refresh_bar()
		_maybe_swap_enrage()
	elif visible:
		# Binding went stale (boss freed) — hide.
		_unbind()

#endregion


#region #################### Discovery + binding ####################

## Scans the local peer's visible map for a live boss and (re)binds to it.
func _rescan() -> void:
	var map_node: Node = MapManager.get_current_visible_map()
	if not is_instance_valid(map_node):
		if visible:
			_unbind()
		return

	# Keep the current binding if it's still valid and on this map.
	if _boss != null and is_instance_valid(_boss) and map_node.is_ancestor_of(_boss):
		if _boss_health != null and is_instance_valid(_boss_health) and not _boss_health.is_dead:
			return

	var found: Node = _find_boss_on_map(map_node)
	if found == null:
		if visible:
			_unbind()
		return
	if found != _boss:
		_bind(found)


## First live boss enemy under `map_node`, or null. Mirrors the bot_manager
## convention: iterate the global "Enemies" group, keep nodes whose ancestor is
## this map, with is_boss enemy_data and not dead. Duck-typed (no EnemyBase cast)
## to stay out of the class-resolution graph.
func _find_boss_on_map(map_node: Node) -> Node:
	for node in get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(node):
			continue
		if not map_node.is_ancestor_of(node):
			continue
		var ed = node.get("enemy_data")
		if ed == null or not ed.is_boss:
			continue
		var hc: Node = node.get_node_or_null("Health")
		if hc == null or hc.is_dead:
			continue
		return node
	return null


func _bind(boss: Node) -> void:
	_boss = boss
	_boss_health = boss.get_node_or_null("Health")
	if _boss_health == null:
		_unbind()
		return
	var ed = boss.get("enemy_data")
	var title: String = ""
	var subtitle: String = ""
	if ed != null:
		title = ed.boss_title if ed.boss_title != "" else ed.monster_name
		subtitle = ed.get("boss_subtitle") if ed.get("boss_subtitle") is String else ""
	if is_instance_valid(title_label):
		title_label.text = title
	if is_instance_valid(subtitle_label):
		subtitle_label.text = subtitle
		subtitle_label.visible = subtitle != ""
	visible = true
	_start_boss_music(ed)
	_refresh_bar()


func _unbind() -> void:
	if _boss_music_on:
		_boss_music_on = false
		_boss_enrage_music = false
		var map_node: Node = MapManager.get_current_visible_map()
		if is_instance_valid(map_node):
			var mp = map_node.get("bgm_path")
			if mp is String and not mp.is_empty():
				AudioManager.play_song(mp)
	_boss = null
	_boss_health = null
	visible = false


## Start this boss's combat track (client-side). Restored to the map BGM on unbind.
func _start_boss_music(ed) -> void:
	if ed == null:
		return
	var v = ed.get("boss_bgm")
	var combat: String = v if v is String else ""
	if combat.is_empty():
		return
	_boss_music_on = true
	_boss_enrage_music = false
	AudioManager.play_song(combat)


## At/below the boss's swap-health fraction, swap to its enrage track (once).
func _maybe_swap_enrage() -> void:
	if not _boss_music_on or _boss_enrage_music or not is_instance_valid(_boss):
		return
	var ed = _boss.get("enemy_data")
	if ed == null:
		return
	var v = ed.get("enrage_bgm")
	var enrage: String = v if v is String else ""
	if enrage.is_empty():
		return
	var swap_at: float = 0.5
	var sv = ed.get("boss_bgm_swap_health")
	if sv is float or sv is int:
		swap_at = float(sv)
	var maximum: float = float(maxi(1, _boss_health.max_health))
	if float(_boss_health.current_health) / maximum <= swap_at:
		_boss_enrage_music = true
		AudioManager.play_song(enrage)

#endregion


#region #################### Paint ####################

func _refresh_bar() -> void:
	if not is_instance_valid(health_bar) or _boss_health == null:
		return
	var cur: int = _boss_health.current_health
	var maximum: int = maxi(1, _boss_health.max_health)
	health_bar.max_value = maximum
	health_bar.value = clampi(cur, 0, maximum)
	if is_instance_valid(value_label):
		value_label.text = "%d / %d" % [clampi(cur, 0, maximum), maximum]

#endregion
