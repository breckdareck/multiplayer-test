class_name HealthComponent
extends Node

# Emitted when health changes, useful for updating UI.
signal health_changed(current_health, max_health)
# Emitted on the server when the character dies.
signal died(killer)
# Emitted when this entity takes damage. Includes the source node if provided.
signal damaged(amount, source)


@export var damage_number_origin: Node2D
@export var max_health: int = 100:
	set(value):
		max_health = value
		health_changed.emit(current_health, max_health)
@export_category("UI")
@export var health_bar_path: NodePath

var _stats_component: StatsComponent

var is_dead: bool = false
var is_invulnerable: bool = false
var _last_damage_source: Node = null

# The setter automatically handles clamping and emitting signals.
@onready var current_health: int = max_health:
	set(value):
		var previous_health: int = current_health
		current_health = clamp(value, 0, max_health)
		if current_health != previous_health:
			if current_health == 0 and not is_dead and multiplayer.is_server():
				die.rpc()
			health_changed.emit(current_health, max_health)
@onready var health_bar: ProgressBar = get_node_or_null(health_bar_path)
@onready var invulnerability_timer: Timer = Timer.new()
@onready var regen_timer: Timer = Timer.new()


func _ready() -> void:
	if not health_bar:
		push_warning("HealthComponent has no HealthBar assigned.")
		return
		
	_stats_component = get_parent().get_node_or_null("Stats")

	# Invulnerability timer setup
	invulnerability_timer.name = "InvulnTimer"
	invulnerability_timer.one_shot = true
	invulnerability_timer.wait_time = 1
	add_child(invulnerability_timer)

	# Regeneration timer setup
	regen_timer.name = "RegenTimer"
	regen_timer.one_shot = false
	regen_timer.autostart = true
	regen_timer.wait_time = 10
	add_child(regen_timer)

	# The component now directly controls its own UI.
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_changed.connect(_on_health_changed)
	
	if not multiplayer.is_server():
		return

	invulnerability_timer.timeout.connect(_on_invulnerability_timer_timeout)
	
	var _owner = get_owner()
	if _owner is MultiplayerPlayerV2:
		_owner = _owner as MultiplayerPlayerV2
		_owner.stats_component.stats_changed.connect(_on_stats_changed)
		_owner.level_component.leveled_up.connect(_on_leveled_up)
		regen_timer.timeout.connect(_on_regen_timer_timeout)


func _on_stats_changed():
	max_health = _stats_component.stats.get(Constants.StatType.HEALTH).total_value
	print("HealthComponent: StatsChanged, new max health: %d" % max_health)
	if current_health > max_health:
		current_health = max_health


func _on_leveled_up(_new_level: int):
	max_health = _stats_component.stats.get(Constants.StatType.HEALTH).total_value
	print("HealthComponent: StatsChanged, new max health: %d" % max_health)
	current_health = max_health


func _on_health_changed(new_health: int, _max_health: int) -> void:
	"""Updates the ProgressBar value when health changes."""
	health_bar.max_value = _max_health
	health_bar.value = new_health


func _on_invulnerability_timer_timeout() -> void:
	is_invulnerable = false

	
func _on_regen_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
	if is_dead:
		return
	if current_health < max_health:
		var regen: int = 10
		if _stats_component:
			regen = _stats_component.stats[Constants.StatType.HPREGEN].total_value
		heal_damage(regen, self.owner)

	
@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, source: Node = null, ignore_invuln: bool = false, is_crit: bool = false, show_number: bool = true) -> void:
	if not multiplayer.is_server():
		return
		
	var source_str = "unknown"
	if source:
		source_str = str(source)
	
	_last_damage_source = source
	
	var is_player = (owner is MultiplayerPlayerV2)
	
	if show_number:
		get_node("/root/MainMenu/Level/Game").get_node("%DmgNumberSpawner").display_number(amount, damage_number_origin.global_position, is_crit, is_player)
	
	if is_player:
		# Assuming 'player_hit.wav' is the correct SFX.
		AudioManager.rpc("play_sfx_rpc", "res://assets/sounds/player_hit.wav", get_owner().global_position)
	
	
	print("HealthComponent: Owner '%s' took %s damage from '%s'." % [get_owner().name, amount, source_str])
	damaged.emit(amount, source)
	
	if is_invulnerable and not ignore_invuln or is_dead:
		return
	
	self.current_health -= amount
	if not ignore_invuln:
		is_invulnerable = true
		invulnerability_timer.start()

	# Screen shake for player characters on big hits
	if is_player:
		var player_owner: MultiplayerPlayerV2 = owner as MultiplayerPlayerV2
		var shake_intensity: float = clampf(float(amount) / float(max_health) * 12.0, 2.0, 8.0)
		if player_owner.has_method("screen_shake"):
			# Shake on server (if host is the player)
			player_owner.screen_shake(shake_intensity)
			# Also shake on the owning client
			if player_owner.player_id != 1:
				_trigger_screen_shake.rpc_id(player_owner.player_id, shake_intensity)


@rpc("authority", "call_local", "reliable")
func _trigger_screen_shake(intensity: float) -> void:
	var player_owner = get_owner()
	if player_owner is MultiplayerPlayerV2 and player_owner.has_method("screen_shake"):
		player_owner.screen_shake(intensity)


@rpc("any_peer", "call_local", "reliable")
func heal_damage(amount: int, source: Node = null) -> void:
	# This function can be called from anywhere, but only the server will process it.
	if not multiplayer.is_server():
		return
	var source_str = "unknown"
	if source:
		source_str = str(source.name)

	print("HealthComponent: Owner '%s' healed %s damage from '%s'." % [get_owner().name, amount, source_str])
	self.current_health += amount


@rpc("authority", "call_local", "reliable")
func die() -> void:
	# Guard clauses to ensure this only runs once on the server.
	if is_dead or not multiplayer.is_server():
		return

	is_dead = true
	died.emit(_last_damage_source) # Pass the killer/source to the signal
	print("HealthComponent: Owner '%s' has died." % get_owner().name)


func respawn() -> void:
	assert(multiplayer.is_server(), "HealthComponent.respawn() should only be called on the server.")
	is_dead = false
	self.current_health = max_health
	
	var is_player = (owner is MultiplayerPlayerV2)
	
	if is_player:
		owner.mana_component.current_mana = owner.mana_component.max_mana
	
	is_invulnerable = true
	invulnerability_timer.start()
	# print("HealthComponent: Owner '%s' has respawned." % get_owner().name)
