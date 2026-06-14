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

# Channeled-cast state (ActiveBehaviorData.channel_mode). WINDUP_RELEASE defers
# the release (logic_script.execute + hitbox) until the wind-up elapses; HOLD
# releases immediately but keeps the caster rooted for the channel duration.
# The countdown runs in physics_update on EVERY peer (peer-local clocks — the
# server's release is the only authoritative one; client copies no-op inside
# the AL's is_server guard). Force-exiting the state (death) before the release
# fires cancels it with no resource refund.
const CHANNEL_NONE: int = 0
const CHANNEL_WINDUP_RELEASE: int = 1
const CHANNEL_HOLD: int = 2
## Hitbox window passed to combat at the moment a wind-up releases.
const WINDUP_RELEASE_WINDOW: float = 0.3
var _windup_pending: bool = false
var _windup_remaining: float = 0.0

## Channels are TAP-OR-HOLD (risk/reward). Releasing the hotbar key early:
##   HOLD zones (Sky Volley / Stormcall) — the channel ends, the registered
##   zone (player meta "active_channel_zone") is cut short, you un-root.
##   WINDUP casts (Onslaught / Spellweave) — the release fires IMMEDIATELY at
##   reduced power: charge fraction = elapsed/full wind-up, floored at
##   CHARGE_FLOOR. Hold to full for 100%. The fraction scales combat's
##   pending multiplier AND is published as player meta "channel_charge"
##   for ALs whose release damage doesn't route through calculate_ability_
##   damage (Spellweave's stance releases).
## A minimum hold stops a tap from being a zero-cost cancel: you always
## commit at least this long.
const MIN_HOLD_SEC: float = 0.35
const CHARGE_FLOOR: float = 0.5
var _hold_active: bool = false
var _hold_elapsed: float = 0.0
var _windup_total: float = 0.0

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

func _play_animation(anim_name: String, speed_override: float = -1.0) -> void:
	if (not multiplayer.is_server() || MultiplayerManager.host_mode_enabled) and not anim_name.is_empty():
		if animation_player:
			animation_player.play(anim_name)
		else:
			if anim_name in animations.sprite_frames.get_animation_names():
				var speed: float = speed_override if speed_override > 0.0 else attack_speed_percent
				animations.play(anim_name, speed)

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
	var duration: float = _get_animation_duration(anim_name)
	#print("Ability Attack: %s, Animation: %s, Duration: %f" % [_current_ability.ability_name, anim_name, duration])

	var channel_mode: int = _current_ability.active_behavior.channel_mode
	if channel_mode != CHANNEL_NONE and not use_anim_duration:
		_start_channeled_attack(channel_mode, anim_name, duration)
		return

	_play_animation(anim_name)

	var buffer: float = 0.02
	attack_state_timer.start(max(duration - buffer, 0.01))

	# Server handles the combat component
	if multiplayer.is_server():
		if player.combat_component:
			if use_anim_duration:
				player.combat_component.process_ability_hit(_current_ability, _current_level_stats, duration)
			else:
				player.combat_component.process_ability_hit(_current_ability, _current_level_stats)


func _start_channeled_attack(channel_mode: int, anim_name: String, anim_duration: float) -> void:
	"""Channeled cast: the state persists for the channel duration (cast_time
	minus any owned channel_time_reduction), rooting the caster. WINDUP_RELEASE
	defers the release to the end of the wind-up; HOLD releases immediately."""
	var channel_duration: float = _current_level_stats.cast_time
	var ac = player.get("ability_component")
	if ac != null and is_instance_valid(ac) and ac.has_method("get_ability_upgrade_magnitude"):
		channel_duration -= float(ac.get_ability_upgrade_magnitude(_current_ability.ability_id, "channel_time_reduction"))
	channel_duration = maxf(channel_duration, 0.2)

	var state_duration: float = channel_duration
	if channel_mode == CHANNEL_WINDUP_RELEASE:
		state_duration += WINDUP_RELEASE_WINDOW
		_windup_pending = true
		_windup_remaining = channel_duration
		_windup_total = channel_duration
	elif channel_mode == CHANNEL_HOLD:
		pass
	if channel_mode != CHANNEL_NONE:
		# Both channel kinds watch for an early key release (tap-or-hold).
		_hold_active = true
		_hold_elapsed = 0.0
		# Clear any stale release intent so a previous tap can't insta-end
		# this fresh channel.
		if "channel_release_requested" in player:
			player.channel_release_requested = false
	attack_state_timer.start(state_duration)

	# Stretch the attack animation across the channel so the wind-up/hold is
	# visible instead of the anim finishing in a fraction of the rooted window.
	var stretch_speed: float = -1.0
	if anim_duration > 0.0 and state_duration > anim_duration:
		stretch_speed = attack_speed_percent * (anim_duration / state_duration)
	_play_animation(anim_name, stretch_speed)

	if channel_mode == CHANNEL_HOLD and multiplayer.is_server():
		# Release up front; the rooted state carries the "channel" feel while
		# the ability's own zone/effect runs. Hitbox window stays cast_time-
		# driven inside process_ability_hit, matching the rooted duration.
		if player.combat_component:
			player.combat_component.process_ability_hit(_current_ability, _current_level_stats)


func _fire_windup_release() -> void:
	"""End of a WINDUP_RELEASE channel: open the hitbox and run the ability's
	logic script. Runs on every peer (the AL's is_server guard makes the
	server's release the only authoritative one). Never reached if the state
	was force-exited first — exit() clears the pending flag."""
	if not _current_ability or not _current_level_stats:
		return

	if multiplayer.is_server() and player.combat_component:
		player.combat_component.process_ability_hit(_current_ability, _current_level_stats, WINDUP_RELEASE_WINDOW)

	var behavior: ActiveBehaviorData = _current_ability.active_behavior
	if behavior and behavior.logic_script:
		var logic = behavior.logic_script.new()
		if logic.has_method("execute"):
			logic.execute(player, _current_ability, _current_level_stats)

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

	# Channeled wind-up countdown — runs on every peer (peer-local clocks);
	# deliberately NOT a SceneTreeTimer (the ~70ms jitter lesson from the boss
	# special-attack work).
	if _windup_pending:
		_windup_remaining -= delta
		if _windup_remaining <= 0.0:
			_windup_pending = false
			_fire_windup_release()

	if multiplayer.is_server():
		# Consume inputs during attack to prevent buffering
		if player.do_attack:
			player.do_attack = false
		if player.do_jump:
			player.do_jump = false
		# Consume do_drop too, so a drop set during an air-attack doesn't leak to
		# the next landing and drop the player through the platform.
		if player.do_drop:
			player.do_drop = false

		# Channel — honor an early release after the minimum hold.
		# HOLD zones: cut the registered zone short + stop the state timer so
		# the rooted state exits below. WINDUP casts: fire the release NOW at
		# the charged fraction (elapsed/full, floored), then keep the state
		# alive just long enough for the release hitbox window.
		if _hold_active:
			_hold_elapsed += delta
			if _hold_elapsed >= MIN_HOLD_SEC and bool(player.get("channel_release_requested")):
				player.channel_release_requested = false
				_hold_active = false
				if _windup_pending:
					var fraction: float = 1.0
					if _windup_total > 0.0:
						fraction = clampf(1.0 - (_windup_remaining / _windup_total), CHARGE_FLOOR, 1.0)
					_windup_pending = false
					_windup_remaining = 0.0
					# Publish the charge: combat's pending multiplier scales
					# the hitbox damage rolls; the meta lets AL releases
					# (Spellweave) scale their own bases. Both are cleaned up
					# by end_ability_attack / exit() respectively.
					if fraction < 1.0:
						player.set_meta("channel_charge", fraction)
						if player.combat_component:
							player.combat_component.pending_ability_damage_multiplier = fraction
					_fire_windup_release()
					attack_state_timer.start(WINDUP_RELEASE_WINDOW)
				else:
					_end_registered_channel_zone()
					attack_state_timer.stop()

		# Check if attack animation is finished
		if attack_state_timer.is_stopped():
			# Return to appropriate state
			return idle_state if parent.is_on_floor() else fall_state

	return null

func exit() -> void:
	super()
	# Clear attack data when leaving state. A still-pending wind-up dies here
	# (death / forced state change cancels the release, no resource refund).
	_windup_pending = false
	_windup_remaining = 0.0
	# HOLD channel bookkeeping: drop the zone registration (a naturally-ended
	# channel's zone expires on its own; a force-exit — death — cuts it short)
	# and clear any unconsumed release intent.
	if _hold_active and multiplayer.is_server():
		_end_registered_channel_zone()
	_hold_active = false
	_hold_elapsed = 0.0
	if player != null and is_instance_valid(player) and "channel_release_requested" in player:
		player.channel_release_requested = false
	if player != null and is_instance_valid(player) and player.has_meta("active_channel_zone"):
		player.remove_meta("active_channel_zone")
	if player != null and is_instance_valid(player) and player.has_meta("channel_charge"):
		player.remove_meta("channel_charge")
	_windup_total = 0.0
	_current_attack_name = ""
	_current_ability = null
	_current_level_stats = null
	_current_attack_type = AttackType.BASIC


## Server-side: cut the channel's registered ground zone short (the ability's
## AL stored it on the player as "active_channel_zone" at spawn).
func _end_registered_channel_zone() -> void:
	if player == null or not is_instance_valid(player) or not player.has_meta("active_channel_zone"):
		return
	var zone = player.get_meta("active_channel_zone")
	player.remove_meta("active_channel_zone")
	if zone != null and is_instance_valid(zone) and zone.has_method("end_early"):
		zone.end_early()

# Called by ability component to set ability data before entering this state
func set_ability_data(ability: AbilityData, level_stats: AbilityLevelData) -> void:
	_current_ability = ability
	_current_level_stats = level_stats

# Called for basic attacks (can be called before entering state or uses default)
func set_basic_attack(attack_name: String = "attack_1") -> void:
	_current_attack_name = attack_name
	_current_ability = null
	_current_level_stats = null
