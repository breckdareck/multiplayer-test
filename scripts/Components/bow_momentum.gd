class_name BowMomentumComponent
extends Node

## Bow discipline's signature combat system: MOMENTUM.
##
## Bow identity: the bow is a RHYTHM weapon. Every landed bow hit (the basic
## Snap Shot AND any bow ability hit) builds one stack of Momentum, up to a cap.
## Stop firing and the gauge DECAYS back to zero. While Momentum is up it grants:
##   - a ramping bonus to ALL bow damage   (applied in CombatComponent.calculate_ability_damage)
##   - a ramping ATTACK SPEED / fire-rate   (applied in attack.gd's attack_speed_percent getter)
## so the longer you keep the pressure on, the faster and harder you shoot — and
## the moment you disengage, you bleed it all back.
##
## Why a gauge that pervades the whole kit (vs. one charged button): a signature
## must touch the ENTIRE discipline, not a single ability. Momentum scales the
## basic shot, every active, and the fire-rate at once, so it IS the bow's feel
## rather than a mode you toggle. (No "Frenzy" / spend-the-bar mechanic in v1 —
## that is a deliberate omission; v1 is the build-and-ramp loop only.)
##
## This is the bow analogue of SwordComboComponent / StaffElementComponent. Same
## structural rules:
## - Server-authoritative: every mutator early-returns unless multiplayer.is_server().
##   The owning client only ever learns the stack count through the
##   sync_momentum_to_client RPC, which feeds its widget AND the client-side
##   reads in attack.gd (the client predicts its own animation speed off the
##   synced mirror).
## - Bots have no client and no UI (and they never need the widget) — the RPC is
##   skipped for bot owners (BotManager.is_bot check, same as SwordCombo /
##   StaffElement / WeaponMastery).
## - Volatile per-session: stack count is never saved or synced through the
##   backend. Momentum built up at logout simply vanishes.
##
## The build hook lives in CombatComponent._execute_hit (add_momentum() once per
## landed hit while a bow is wielded); the decay is owned here on a server-side
## tick Timer.

#region #################### Constants (tunable — these are STARTING values) ####################

## Maximum stacks the gauge can hold. The damage / speed ceilings below are
## expressed per-stack, so MAX_STACKS sets the top-end payoff.
const MAX_STACKS: int = 10

## Stacks gained per landed hit. 1 means a clean linear ramp — ten landed shots
## to cap. Bumping this lets fast weapons ramp quicker without changing the cap.
const MOMENTUM_PER_HIT: int = 1

## Bow-damage bonus per stack (multiplicative add on top of base, like the sword
## combo's per-point bonus). 0.035 * 10 = +35% damage at max stacks.
const DAMAGE_PER_STACK: float = 0.035

## Attack-speed bonus per stack. Feeds attack.gd's attack_speed_percent, which
## drives both the animation FPS and the re-attack gate. 0.03 * 10 = +30% attack
## speed at max stacks.
const SPEED_PER_STACK: float = 0.03

## Seconds of NO landed hit before the gauge starts decaying. A short grace so
## reloading aim / repositioning between shots doesn't immediately bleed stacks.
const DECAY_DELAY_SEC: float = 2.0

## Once decaying, how many seconds between each -1 stack. Fast enough that
## walking away from a fight visibly drains the bar, slow enough that a brief
## pause doesn't wipe a full ramp.
const DECAY_STEP_SEC: float = 0.3

## How often the server tick wakes to evaluate decay. Cheap (only does work once
## DECAY_DELAY_SEC has elapsed, and stops itself when stacks hit 0).
const TICK_INTERVAL: float = 0.1

#endregion


#region #################### Signals ####################

## Emitted on both server and client whenever the stack count changes (build,
## decay, or reset). The widget listens to this to repaint its fill / label.
## `max_stacks` is carried so the widget needn't import the constant.
signal momentum_changed(stacks: int, max_stacks: int)

#endregion


#region #################### State ####################

## Current Momentum stacks. Volatile — never saved. Mirrored to the owning client
## via sync_momentum_to_client; the server is authoritative.
var _stacks: int = 0

## Server clock anchor — Time.get_ticks_msec() of the most recent landed hit.
## Only meaningful on the server (drives the decay-delay check). 0 = never hit.
var _last_hit_ms: int = 0

## Server clock anchor — Time.get_ticks_msec() of the most recent decay decrement,
## so we drop at most one stack per DECAY_STEP_SEC even though the tick fires
## faster than that. Server-only.
var _last_decay_ms: int = 0

## Server-side decay tick. A child Node Timer (freed with this component), not a
## tree-rooted one. Runs only while there are stacks to bleed; stopped at 0.
var _decay_timer: Timer

#endregion


#region #################### Lifecycle ####################

func _ready() -> void:
	_decay_timer = Timer.new()
	_decay_timer.name = "MomentumDecayTimer"
	_decay_timer.one_shot = false
	_decay_timer.wait_time = TICK_INTERVAL
	_decay_timer.timeout.connect(_on_decay_tick)
	add_child(_decay_timer)

#endregion


#region #################### Public API ####################

## Server-only. Builds MOMENTUM_PER_HIT stack(s) (clamped to the cap) and refreshes
## the no-hit clock so the decay delay restarts. Ensures the decay tick is running
## so the gauge will start bleeding once the player stops firing. Called from
## CombatComponent._execute_hit once per landed hit while a bow is wielded.
func add_momentum() -> void:
	if not multiplayer.is_server():
		return
	# Refresh the activity clock on EVERY landed hit, even at the cap — the player
	# is still actively fighting, so the cap shouldn't start ticking down.
	_last_hit_ms = Time.get_ticks_msec()
	# Keep the tick alive so decay kicks in DECAY_DELAY_SEC after the last hit.
	if is_instance_valid(_decay_timer) and _decay_timer.is_stopped():
		_decay_timer.start()

	var before: int = _stacks
	_stacks = mini(MAX_STACKS, _stacks + MOMENTUM_PER_HIT)
	if _stacks != before:
		_emit_and_sync()


## Server-only. Wipes Momentum to zero. Called on death and on swap-away from a
## bow (multiplayer_controller_v2) so a ramp doesn't survive a context where it
## no longer makes sense. Safe to call when already at zero (no-op).
func reset() -> void:
	if not multiplayer.is_server():
		return
	if is_instance_valid(_decay_timer):
		_decay_timer.stop()
	if _stacks == 0:
		return
	_stacks = 0
	_emit_and_sync()


## Read-only accessor. Safe on BOTH peers — the client's mirror is kept in step
## via sync_momentum_to_client.
func get_stacks() -> int:
	return _stacks


## The bow-damage bonus to add (multiplicative, e.g. 0.21 = +21%). Safe on both
## peers. CombatComponent reads this to ramp damage; the client reads it only for
## any predictive display.
func get_damage_bonus() -> float:
	return _stacks * DAMAGE_PER_STACK


## The attack-speed bonus to add (multiplicative, e.g. 0.18 = +18%). Safe on both
## peers — attack.gd reads it on the client too so the local animation speed
## matches what the server is timing.
func get_speed_bonus() -> float:
	return _stacks * SPEED_PER_STACK


## 0-1 fill fraction for the widget bar. Safe on both peers.
func get_fill_fraction() -> float:
	return float(_stacks) / float(MAX_STACKS)

#endregion


#region #################### Internals ####################

## Server decay tick. Once DECAY_DELAY_SEC has elapsed since the last landed hit,
## drops one stack every DECAY_STEP_SEC. Stops the tick when the gauge empties so
## it isn't spinning while idle at zero.
func _on_decay_tick() -> void:
	if not multiplayer.is_server():
		return
	if _stacks <= 0:
		# Nothing to bleed — park the timer until the next add_momentum restarts it.
		if is_instance_valid(_decay_timer):
			_decay_timer.stop()
		return

	var now: int = Time.get_ticks_msec()
	# Still within the grace window after the last hit — don't decay yet.
	if now - _last_hit_ms <= int(DECAY_DELAY_SEC * 1000.0):
		return
	# Rate-limit decrements to one per DECAY_STEP_SEC.
	if now - _last_decay_ms < int(DECAY_STEP_SEC * 1000.0):
		return

	_last_decay_ms = now
	_stacks = maxi(0, _stacks - 1)
	_emit_and_sync()

	if _stacks == 0 and is_instance_valid(_decay_timer):
		_decay_timer.stop()


## Server-side: emit locally for the host's widget, then push the new stack count
## to the owning client. Skips the RPC for bot owners (no client, no UI) — same
## gate SwordCombo / StaffElement use. Only RPCs because we already gate the
## callers on an actual integer change.
func _emit_and_sync() -> void:
	momentum_changed.emit(_stacks, MAX_STACKS)
	if not multiplayer.is_server():
		return
	var root := get_owner()
	if root == null or not "player_id" in root:
		return
	if BotManager.is_bot(root.player_id):
		return
	sync_momentum_to_client.rpc_id(root.player_id, _stacks)

#endregion


#region #################### RPCs ####################

## Server -> owning client. Mirrors the authoritative stack count so the client's
## widget renders the matching fill and attack.gd computes the matching local
## animation speed. call_local is harmless — the body early-returns on the
## server, which already drove its own widget through the local signal path in
## _emit_and_sync.
@rpc("authority", "call_local", "reliable")
func sync_momentum_to_client(stacks: int) -> void:
	if multiplayer.is_server():
		return
	if _stacks == stacks:
		return
	_stacks = stacks
	momentum_changed.emit(_stacks, MAX_STACKS)

#endregion
