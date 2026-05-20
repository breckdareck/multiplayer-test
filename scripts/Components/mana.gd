class_name ManaComponent
extends Node

signal mana_changed(current_mana, max_mana)

var _stats_component: StatsComponent
var _health_component: HealthComponent

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
	max_mana = _stats_component.stats.get(Constants.StatType.MANA).total_value
	#print("HealthComponent: StatsChanged, new max health: %d" % max_mana)
	if current_mana > max_mana:
		current_mana = max_mana


func _on_leveled_up(_new_level: int):
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


@rpc("any_peer", "call_local", "reliable")
func regain_mana(amount: int, source: Node = null) -> void:
	# This function can be called from anywhere, but only the server will process it.
	if not multiplayer.is_server():
		return
	var source_str = "unknown"
	if source:
		source_str = str(source.name)

	#print("ManaComponent: Owner '%s' regained %s mana from '%s'." % [get_owner().name, amount, source_str])
	self.current_mana += amount
