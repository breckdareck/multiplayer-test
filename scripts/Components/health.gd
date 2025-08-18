class_name HealthComponent
extends Node

# Emitted when health changes, useful for updating UI.
signal health_changed(current_health, max_health)
# Emitted on the server when the character dies.
signal died(killer)
# Emitted when this entity takes damage. Includes the source node if provided.
signal damaged(amount, source)

@export var max_health: int = 100:
	set(value):
		max_health = value
		health_changed.emit(current_health, max_health)
@export_category("UI")
@export var health_bar_path: NodePath

var is_dead: bool = false
var is_invulnerable: bool = false
var _last_damage_source: Node = null

# The setter automatically handles clamping and emitting signals.
@onready var current_health: int = max_health:
	set(value):
		var previous_health: int = current_health
		current_health = clamp(value, 0, max_health)
		if current_health != previous_health:
			# If health reached zero, the server initiates the death sequence.
			if current_health == 0 and not is_dead and multiplayer.is_server():
				die.rpc()
			# Let everyone know the health changed. This is now primarily for the UI.
			health_changed.emit(current_health, max_health)

@onready var health_bar: ProgressBar = get_node_or_null(health_bar_path)
@onready var invulnerability_timer: Timer = Timer.new()
@onready var regen_timer: Timer = Timer.new()


func _ready() -> void:
	if not health_bar:
		push_warning("HealthComponent has no HealthBar assigned.")
		return

	# Invulnerability timer setup
	invulnerability_timer.name = "InvulnTimer"
	invulnerability_timer.one_shot = true
	invulnerability_timer.wait_time = .5
	invulnerability_timer.timeout.connect(_on_invulnerability_timer_timeout)
	add_child(invulnerability_timer)

	# Regeneration timer setup
	regen_timer.name = "RegenTimer"
	regen_timer.one_shot = false
	regen_timer.autostart = true
	regen_timer.wait_time = 5
	regen_timer.timeout.connect(_on_regen_timer_timeout)
	add_child(regen_timer)

	# The component now directly controls its own UI.
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_changed.connect(_on_health_changed)
	
	var _owner = get_owner()
	if _owner is MultiplayerPlayer:
		_owner = _owner as MultiplayerPlayer
		_owner.level_component.leveled_up.connect(_on_player_leveled)


func _on_player_leveled(new_level: int):
	max_health = int(max_health * pow(1.12, new_level - 1))
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
		heal_damage(round(float(max_health)/10.0))

	
@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, source: Node = null, ignore_invuln: bool = false) -> void:
	# This function can be called from anywhere, but only the server will process it.
	if not multiplayer.is_server():
		return
	var source_str = "unknown"
	if source:
		source_str = str(source)
	if is_invulnerable and not ignore_invuln:
		return

	_last_damage_source = source

	print("Owner '%s' took %s damage from '%s'." % [get_owner().name, amount, source_str])
	self.current_health -= amount
	damaged.emit(amount, source)
	if not ignore_invuln:
		is_invulnerable = true
		invulnerability_timer.start()


@rpc("any_peer", "call_local", "reliable")
func heal_damage(amount: int, source: Node = null) -> void:
	# This function can be called from anywhere, but only the server will process it.
	if not multiplayer.is_server():
		return
	var source_str = "unknown"
	if source:
		source_str = str(source)

	print("Owner '%s' healed %s damage from '%s'." % [get_owner().name, amount, source_str])
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
	print("HealthComponent: Owner '%s' has respawned." % get_owner().name)
