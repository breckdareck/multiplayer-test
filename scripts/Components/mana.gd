class_name ManaComponent
extends Node

signal mana_changed(current_mana, max_mana)

var _stats_component: StatsComponent
var _health_component: HealthComponent
var _loading_mode: bool = false

@export var max_mana: int = 100:
	set(value):
		max_mana = value
		mana_changed.emit(current_mana, max_mana)

@onready var current_mana: int = max_mana:
	set(value):
		var previous_mana: int = current_mana
		current_mana = clamp(value, 0, max_mana)
		if current_mana != previous_mana:
			mana_changed.emit(current_mana, max_mana)

func _ready() -> void:
	_stats_component = get_parent().get_node_or_null("Stats")
	_health_component = get_parent().get_node_or_null("Health")

	if not multiplayer.is_server():
		return
	
	var _owner = get_owner()
	if _owner is MultiplayerPlayerV2:
		_owner = _owner as MultiplayerPlayerV2
		_owner.stats_component.stats_changed.connect(_on_stats_changed)
		_owner.level_component.leveled_up.connect(_on_leveled_up)
		_health_component.regen_timer.timeout.connect(_on_regen_timer_timeout)


func _on_stats_changed():
	# Ignore stats_changed while a save is loading (mirrors HealthComponent): the
	# stats dict still holds level-1 spawn values (e.g. 50 MP) when _load_data
	# emits this, and acting on it overwrites the just-loaded max_mana and clamps
	# current_mana down. max_mana is set directly from the save during load.
	if _loading_mode:
		return
	max_mana = _stats_component.stats.get(Constants.StatType.MANA).total_value
	#print("HealthComponent: StatsChanged, new max health: %d" % max_mana)
	if current_mana > max_mana:
		current_mana = max_mana


func _on_leveled_up(_new_level: int):
	# Skip the level-up full-heal while a save is loading (mirrors HealthComponent).
	# _load_data replays leveled_up to refresh UI before attribute points rebuild
	# max MP, so the saved current_mana must survive — otherwise a map transfer
	# resets the player to base mana (50). _on_stats_changed sets the real max.
	if _loading_mode:
		return
	max_mana = _stats_component.stats.get(Constants.StatType.MANA).total_value
	#print("HealthComponent: StatsChanged, new max health: %d" % max_mana)
	current_mana = max_mana


func _on_regen_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
	if _health_component.is_dead:
		return
	if current_mana < max_mana:
		var regen: int = 10
		if _stats_component:
			regen = _stats_component.stats[Constants.StatType.MPREGEN].total_value
		regain_mana(regen, self.owner)


func set_loading_mode(enabled: bool) -> void:
	_loading_mode = enabled


@rpc("any_peer", "call_local", "reliable")
func regain_mana(amount: int, _source: Node = null) -> void:
	# This function can be called from anywhere, but only the server will process it.
	if not multiplayer.is_server():
		return

	#print("ManaComponent: Owner '%s' regained %s mana." % [get_owner().name, amount])
	self.current_mana += amount
