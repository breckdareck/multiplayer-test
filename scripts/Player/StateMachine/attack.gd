extends State

var player

@export var idle_state: State
@export var fall_state: State

var attack_speed_percent: float:
	get():
		# PR 3: route attack speed through the ACTIVE weapon so a swap to a
		# faster/slower weapon takes effect immediately. Reads through the
		# active_weapon_data accessor so the inactive slot's stats don't
		# bleed in.
		var active_weapon: WeaponData = parent.equipment_component.active_weapon_data
		if active_weapon == null:
			return 1.0
		var base: float = float(100.0 / ((20.0 - active_weapon.weapon_attack_speed) / 16.0)) / 100
		# Bow signature — MOMENTUM fire-rate ramp. While wielding a BOW, the built-up
		# gauge speeds up the attack animation AND the re-attack gate by
		# get_speed_bonus() (+SPEED_PER_STACK per stack). Null-safe: the field is
		# null on non-bow players and during teardown; non-bow weapons never apply
		# it. The component returns the synced mirror on the client, so the local
		# animation speed matches what the server is timing.
		if active_weapon.weapon_type == Constants.WeaponType.BOW \
				and parent.bow_momentum_component != null \
				and is_instance_valid(parent.bow_momentum_component):
			base *= (1.0 + parent.bow_momentum_component.get_speed_bonus())
		# v1 Wind Rider (bow passive) — attack-cooldown reduction scaling with
		# Momentum stacks. Returns 1.0 + sum(negative bonuses); when the passive
		# is active and Momentum is built, this multiplies `base` by < 1.0,
		# reducing the cooldown between basic attacks (= faster effective fire
		# rate). 1.0 when no Wind Rider passive is learned.
		var ac = parent.get("ability_component") if is_instance_valid(parent) else null
		if ac != null and is_instance_valid(ac) and ac.has_method("get_attack_cooldown_mult"):
			var cd_mult: float = float(ac.get_attack_cooldown_mult())
			if cd_mult != 1.0:
				# Negative bonuses (-0.25) → cd_mult = 0.75 → faster attacks.
				# We divide rather than multiply so a negative mult scales the
				# cycle DOWN: `base` is roughly "attacks per second-ish" already
				# from the formula above, so dividing by cd_mult inverts the
				# reduction into a speed-up.
				base /= cd_mult
		return base

var _was_on_floor: bool = false

# Attack type tracking
enum AttackType { BASIC, ABILITY }
var _current_attack_type: AttackType = AttackType.BASIC

# Per-discipline basic-attack swing SFX (generated palette — see
# tools/gen_ability_sfx.py). Played via play_sfx_for_map, which no-ops on
# clients, so the server broadcasts exactly one sound per swing.
const _BASIC_ATTACK_SFX := {
	Constants.ClassType.SWORD: "res://assets/sounds/generated/attack_sword.wav",
	Constants.ClassType.BOW: "res://assets/sounds/generated/attack_bow.wav",
	Constants.ClassType.STAFF: "res://assets/sounds/generated/attack_staff.wav",
	Constants.ClassType.DAGGER: "res://assets/sounds/generated/attack_dagger.wav",
}

# Basic attack data
var _current_attack_name: String = ""

# Ability attack data
var _current_ability: AbilityData = null
var _current_level_stats: AbilityLevelData = null

@onready var animation_player: AnimationPlayer = owner.get_node_or_null("../../AnimationPlayer")
@onready var attack_state_timer: Timer = $"../../AttackStateTimer"

func enter() -> void:
	super()
	allow_flip = false
	if parent is MultiplayerPlayerV2:
		player = parent
	player.do_attack = false

	_was_on_floor = parent.is_on_floor()
	if parent.is_on_floor():
		parent.velocity.x = 0

	# Determine which type of attack to execute
	if _current_ability and _current_level_stats:
		_current_attack_type = AttackType.ABILITY
		_start_ability_attack()
	else:
		_current_attack_type = AttackType.BASIC
		if _current_attack_name.is_empty():
			_current_attack_name = "attack_1" # Default basic attack animation
		_start_basic_attack()

func _play_animation(anim_name: String) -> void:
	if (not multiplayer.is_server() || MultiplayerManager.host_mode_enabled) and not anim_name.is_empty():
		if animation_player:
			animation_player.play(anim_name)
		else:
			if anim_name in animations.sprite_frames.get_animation_names():
				animations.play(anim_name, attack_speed_percent)

func _start_basic_attack():
	"""Executes a basic melee attack, or Snap Shot for the wielded weapon's
	discipline. Uses the player's CURRENTLY-WIELDED discipline (via
	get_active_discipline), not the starting class — so a Swordsman who swapped
	to a bow correctly fires arrows, and a Mage who picked up a sword swings."""
	var is_archer := false
	var swing_sfx: String = ""
	if player.has_method("get_active_discipline"):
		var cls: int = player.get_active_discipline()
		is_archer = cls == Constants.ClassType.BOW or cls == Constants.ClassType.RANGER
		swing_sfx = _BASIC_ATTACK_SFX.get(cls, "")
	if not swing_sfx.is_empty():
		AudioManager.play_sfx_for_map(MapManager.get_player_map(player.player_id), swing_sfx, player.global_position)

	if is_archer and _try_use_arrow_shot():
		return

	var anim_name: String = _current_attack_name
	_play_animation(anim_name)

	var duration: float = _get_animation_duration(anim_name)
	#print("Basic Attack: %s, Duration: %f" % [anim_name, duration])

	var buffer: float = 0.02
	attack_state_timer.start(max(duration - buffer, 0.01))

	# Server handles the combat component
	if multiplayer.is_server():
		if player.combat_component:
			player.combat_component.perform_attack(_current_attack_name, duration)


func _try_use_arrow_shot() -> bool:
	"""For archers, route basic attack through Snap Shot ability at base level"""
	var arrow_shot: AbilityData = ResourceManager.get_ability_data("Snap Shot")
	if not arrow_shot:
		return false

	var level_stats := arrow_shot.get_level_stats(1)
	if not level_stats:
		return false

	_current_ability = arrow_shot
	_current_level_stats = level_stats
	_current_attack_type = AttackType.ABILITY
	_start_ability_attack(true)
	return true

func _start_ability_attack(use_anim_duration: bool = false):
	"""Executes an ability attack"""
	if not _current_ability or not _current_level_stats:
		return

	var anim_name: String = _current_ability.active_behavior.animation_name
	_play_animation(anim_name)

	var duration: float = _get_animation_duration(anim_name)
	#print("Ability Attack: %s, Animation: %s, Duration: %f" % [_current_ability.ability_name, anim_name, duration])

	var buffer: float = 0.02
	attack_state_timer.start(max(duration - buffer, 0.01))

	# Server handles the combat component
	if multiplayer.is_server():
		if player.combat_component:
			if use_anim_duration:
				player.combat_component.process_ability_hit(_current_ability, _current_level_stats, duration)
			else:
				player.combat_component.process_ability_hit(_current_ability, _current_level_stats)

func _get_animation_duration(anim_name: String) -> float:
	var sprite_frames: SpriteFrames = player.animated_sprite.sprite_frames
	if not sprite_frames.has_animation(anim_name):
		return 0.0

	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	var anim_fps: float = sprite_frames.get_animation_speed(anim_name) * attack_speed_percent
	
	if frame_count == 0 or anim_fps <= 0.0:
		return 0.0

	var total_duration: float = 0.0
	for i in range(frame_count):
		var frame_duration: float = sprite_frames.get_frame_duration(anim_name, i)
		total_duration += frame_duration / anim_fps

	if player.animated_sprite.speed_scale > 0.0:
		total_duration /= player.animated_sprite.speed_scale

	return total_duration

func physics_update(delta: float) -> State:
	# Apply gravity so the player falls if attacking mid-air
	var now_on_floor = parent.is_on_floor()
	if not _was_on_floor and now_on_floor:
		parent.velocity.x = 0
	_was_on_floor = now_on_floor
	parent.velocity.y += gravity * delta
	parent.move_and_slide()

	if multiplayer.is_server():
		# Consume inputs during attack to prevent buffering
		if player.do_attack:
			player.do_attack = false
		if player.do_jump:
			player.do_jump = false

		# Check if attack animation is finished
		if attack_state_timer.is_stopped():
			# Return to appropriate state
			return idle_state if parent.is_on_floor() else fall_state

	return null

func exit() -> void:
	super()
	# Clear attack data when leaving state
	_current_attack_name = ""
	_current_ability = null
	_current_level_stats = null
	_current_attack_type = AttackType.BASIC

# Called by ability component to set ability data before entering this state
func set_ability_data(ability: AbilityData, level_stats: AbilityLevelData) -> void:
	_current_ability = ability
	_current_level_stats = level_stats

# Called for basic attacks (can be called before entering state or uses default)
func set_basic_attack(attack_name: String = "attack_1") -> void:
	_current_attack_name = attack_name
	_current_ability = null
	_current_level_stats = null
