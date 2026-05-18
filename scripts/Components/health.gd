class_name HealthComponent
extends Node

# Emitted when health changes, useful for updating UI.
signal health_changed(current_health, max_health)
# Emitted on the server when the character dies.
signal died(killer)
# Emitted when this entity takes damage. Includes the source node if provided.
signal damaged(amount, source)


var _loading_mode: bool = false
@export var damage_number_origin: Node2D
@export var max_health: int = 100:
	set(value):
		max_health = value
		if not _loading_mode:
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
				die()

				var entity = get_owner()
				var map_name = ""

				if entity is MultiplayerPlayerV2:
					var map_node = MapManager.get_player_map_node(entity.player_id)
					if map_node: map_name = map_node.name.replace("Map_", "")
				else:
					var parent = entity.get_parent()
					while parent:
						if parent.name.begins_with("Map_"):
							map_name = parent.name.replace("Map_", "")
							break
						parent = parent.get_parent()

				if map_name != "":
					var players = MapManager.get_real_players_on_map(map_name)
					for pid in players:
						if pid != 1:
							die.rpc_id(pid)
				elif entity is MultiplayerPlayerV2 and entity.player_id != 1:
					die.rpc_id(entity.player_id)
			if not _loading_mode:
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
	#print("HealthComponent: StatsChanged, new max health: %d" % max_health)
	if current_health > max_health:
		current_health = max_health


func _on_leveled_up(_new_level: int):
	max_health = _stats_component.stats.get(Constants.StatType.HEALTH).total_value
	#print("HealthComponent: StatsChanged, new max health: %d" % max_health)
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
	var source_str = "unknown"
	if source:
		source_str = str(source)
	
	var is_player = (owner is MultiplayerPlayerV2)
	
	#print("HealthComponent.take_damage: amount=%d, show_number=%s, is_player=%s, is_server=%s" % [amount, show_number, is_player, multiplayer.is_server()])
	
	# --- Visual/Audio Effects ---
	if show_number:
		var dmg_spawner = null
		var map_to_spawn_on: Node = null

		if multiplayer.is_server():
			# --- Server-side: Find the correct map to spawn the number on ---
			var entity = get_owner()
			
			if source and source.owner is MultiplayerPlayerV2:
				# If source is a player, use their map
				map_to_spawn_on = MapManager.get_player_map_node(source.owner.player_id)
				#print("HealthComponent: Using source player's map: %s" % map_to_spawn_on)
			elif entity is MultiplayerPlayerV2:
				# If entity being hit is a player, use their map
				map_to_spawn_on = MapManager.get_player_map_node(entity.player_id)
				#print("HealthComponent: Using target player's map: %s" % map_to_spawn_on)
			else:
				# If it's an enemy being hit by a non-player, find the enemy's map
				#print("HealthComponent: Searching for enemy's map...")
				for map_id in MapManager.active_maps.keys():
					var map_instance = MapManager.active_maps[map_id].scene_instance
					if is_instance_valid(map_instance) and map_instance.is_ancestor_of(entity):
						map_to_spawn_on = map_instance
						#print("HealthComponent: Found enemy's map: %s" % map_to_spawn_on)
						break
		else:
			# --- Client-side: Use the client's currently visible map ---
			if get_owner().visible:
				map_to_spawn_on = MapManager.get_current_visible_map()
				#print("HealthComponent: Client using visible map: %s" % map_to_spawn_on)

		if is_instance_valid(map_to_spawn_on):
			dmg_spawner = map_to_spawn_on.find_child("DmgNumberSpawner", true, false)
			#print("HealthComponent: Found dmg_spawner: %s" % dmg_spawner)

		if dmg_spawner:
			#print("HealthComponent: Calling display_number on spawner")
			dmg_spawner.display_number(amount, damage_number_origin.global_position, is_crit, is_player)

	
	if is_player:
		# Filter SFX to players on the same map
		var map_node = MapManager.get_player_map_node(get_owner().player_id)
		if map_node:
			var map_name = map_node.name.replace("Map_", "")
			var players_on_map = MapManager.get_real_players_on_map(map_name)

			for peer_id in players_on_map:
				if peer_id != 1:
					AudioManager.play_sfx_rpc.rpc_id(peer_id, "res://assets/sounds/player_hit.wav", get_owner().global_position)
			
			# Play on server too if needed
			AudioManager.play_sfx("res://assets/sounds/player_hit.wav", get_owner().global_position)
		else:
			# Fallback
			AudioManager.rpc("play_sfx_rpc", "res://assets/sounds/player_hit.wav", get_owner().global_position)
	
	# --- Server-side game logic ---
	if multiplayer.is_server():
		_last_damage_source = source
		
		#print("HealthComponent: Owner '%s' took %s damage from '%s'." % [get_owner().name, amount, source_str])
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

	#print("HealthComponent: Owner '%s' healed %s damage from '%s'." % [get_owner().name, amount, source_str])
	self.current_health += amount


@rpc("authority", "call_local", "reliable")
func die() -> void:
	if is_dead:
		return

	is_dead = true
	died.emit(_last_damage_source)


func set_loading_mode(enabled: bool) -> void:
	_loading_mode = enabled


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
