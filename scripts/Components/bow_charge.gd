class_name BowChargeComponent
extends Node

## PR 8 — Bow discipline's signature combat system: hold-to-charge Snap Shot.
##
## Bow identity: while wielding a BOW, HOLDING the Attack key builds a charge
## (server-timed). RELEASING fires one charged Snap Shot whose damage scales
## with the charge tier reached. A quick TAP releases at tier 0 — an ordinary
## shot, identical to the pre-PR-8 bow basic attack (×1.0 damage).
##
## This is the bow analogue of SwordComboComponent. Same structural rules:
## - Server-authoritative: every mutator early-returns unless multiplayer.is_server().
##   The owning client only ever learns the charge state through the
##   sync_charge_to_client RPC, which feeds its widget.
## - Bots have no client and no UI (and they fire via do_attack directly, never
##   through the charge input path) — the RPC is skipped for bot owners
##   (BotManager.is_bot check, same as SwordCombo / WeaponMastery / Ability).
## - Volatile per-session: charge state is never saved or synced through the
##   backend. A charge in progress at logout simply vanishes.
##
## Why server-timed (vs. the client measuring its own hold): the same reason
## the rest of combat is server-authoritative — the client could otherwise lie
## about how long it held to fake a max-tier shot. The client sends only two
## intents (bow_charge_start on press, bow_release on release) and the server
## owns the clock between them.

#region #################### Constants ####################

## Seconds of continuous hold required to REACH each tier. Index = tier.
## Tier 0 is instant (a tap), then 0.4s / 0.8s / 1.2s for tiers 1-3.
const CHARGE_TIER_TIMES: Array[float] = [0.0, 0.4, 0.8, 1.2]

## Damage multiplier applied to the fired Snap Shot per tier. Index = tier.
## Tier 0 = ×1.0 (a tap is exactly today's shot). Tier 3 = ×3.0.
const CHARGE_DAMAGE_MULT: Array[float] = [1.0, 1.5, 2.0, 3.0]

## Hard ceiling on hold time. Holding past this stays at the top tier — there's
## no overcharge penalty, the charge just caps. Mirrors CHARGE_TIER_TIMES' last
## entry; kept as its own constant so the widget can compute a 0-1 progress bar.
const CHARGE_MAX_SEC: float = 1.2

#endregion


#region #################### Signals ####################

## Emitted on both server and client whenever the charge state changes (start,
## tier-up, or reset/cancel). `tier` is the current integer tier (0-3) and
## `progress` is a 0-1 fraction of CHARGE_MAX_SEC for a smooth fill bar. When
## not charging, both are 0. The widget listens to this.
signal charge_changed(tier: int, progress: float)

#endregion


#region #################### State ####################

## True while a charge is in progress (between start_charge and
## release_and_fire / cancel_charge). Server-authoritative; the client mirror
## is driven by sync_charge_to_client.
var _is_charging: bool = false

## Server clock anchor — Time.get_ticks_msec() captured at start_charge. Only
## meaningful on the server (the client never times the charge itself).
var _charge_start_ms: int = 0

## Client-side mirror of the current tier, set from sync_charge_to_client. The
## server reads its tier live from elapsed time; the client can't (it doesn't
## time), so it caches the last synced tier for its widget paint.
var _client_tier: int = 0

## Drives the per-frame charge_changed emit on the SERVER so the widget bar
## fills smoothly and tier-up pulses fire as the charge crosses each threshold.
## A child Node Timer (freed with the component), not a tree-rooted one.
var _tick_timer: Timer

## Last tier the server emitted a tick for — so we only push a fresh RPC to the
## client when the integer tier actually changes (the smooth 0-1 progress fill
## is interpolated client-side from the tier, so we don't spam an RPC per frame).
var _last_emitted_tier: int = -1

#endregion


#region #################### Lifecycle ####################

func _ready() -> void:
	_tick_timer = Timer.new()
	_tick_timer.name = "ChargeTickTimer"
	_tick_timer.one_shot = false
	_tick_timer.wait_time = 0.05
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)

#endregion


#region #################### Public API ####################

## Server-only. Begins (or restarts) a charge: anchors the clock to now, flags
## charging, and starts the per-frame tick that drives widget updates. Idempotent
## restart is fine — pressing Attack again simply re-anchors from now.
func start_charge() -> void:
	if not multiplayer.is_server():
		return
	_is_charging = true
	_charge_start_ms = Time.get_ticks_msec()
	_last_emitted_tier = 0
	if is_instance_valid(_tick_timer):
		_tick_timer.start()
	_emit_and_sync(0, 0.0)


## Server-only. Ends the charge, computes the tier reached from elapsed hold
## time, stages the matching damage multiplier on the CombatComponent, and fires
## ONE Snap Shot through the normal basic-attack pathway (do_attack -> attack
## state -> _try_use_arrow_shot). Resets charge state afterward.
##
## A tap (released before CHARGE_TIER_TIMES[1]) yields tier 0 / ×1.0, i.e. the
## exact pre-PR-8 shot. No-op if not currently charging (e.g. a stray release).
func release_and_fire() -> void:
	if not multiplayer.is_server():
		return
	if not _is_charging:
		return

	var elapsed_sec: float = float(Time.get_ticks_msec() - _charge_start_ms) / 1000.0
	var tier: int = get_tier_for_elapsed(elapsed_sec)
	var mult: float = CHARGE_DAMAGE_MULT[tier]

	# Reset charge state BEFORE firing so the widget clears immediately and a
	# re-press during the shot's animation cleanly starts a fresh charge.
	_reset_state()

	var root := get_owner()
	if root == null:
		return

	# Stage the charge multiplier on the CombatComponent. It reads + consumes
	# this when calculating the Snap Shot's damage (gated to the Snap Shot
	# ability so it can never bleed into another weapon's ability — see
	# CombatComponent.calculate_ability_damage). A tier-0 tap stages 1.0, which
	# is a no-op, so the un-charged shot is byte-identical to today's.
	var combat_comp = root.get("combat_component")
	if combat_comp != null and is_instance_valid(combat_comp):
		combat_comp.charge_damage_mult = mult

	# Fire via the standard basic-attack trigger. Setting do_attack flips the
	# player into the attack state next server tick, which for a bow routes
	# through Snap Shot — reusing the existing projectile path rather than
	# duplicating it. The attack state consumes do_attack on entry.
	if "do_attack" in root:
		root.do_attack = true


## Server-only. Clears any in-progress charge without firing. Called on
## weapon-swap-away-from-bow and on death so a held charge doesn't survive a
## context where it no longer makes sense. Safe to call when not charging.
func cancel_charge() -> void:
	if not multiplayer.is_server():
		return
	if not _is_charging:
		return
	_reset_state()


## Pure helper (safe on both peers). Maps an elapsed hold time in seconds to the
## highest tier whose CHARGE_TIER_TIMES threshold it has met. Clamped to the top
## tier — holding past CHARGE_MAX_SEC stays maxed.
func get_tier_for_elapsed(elapsed_sec: float) -> int:
	var tier: int = 0
	for i in range(CHARGE_TIER_TIMES.size()):
		if elapsed_sec >= CHARGE_TIER_TIMES[i]:
			tier = i
		else:
			break
	return tier


## Read-only accessor for the widget. On the server it reflects live charging
## state; on the client it returns the last synced tier.
func is_charging() -> bool:
	return _is_charging


## Read-only accessor for the widget. Server computes live from elapsed time;
## client returns the cached synced tier.
func get_current_tier() -> int:
	if multiplayer.is_server() and _is_charging:
		var elapsed_sec: float = float(Time.get_ticks_msec() - _charge_start_ms) / 1000.0
		return get_tier_for_elapsed(elapsed_sec)
	return _client_tier

#endregion


#region #################### Internals ####################

func _reset_state() -> void:
	_is_charging = false
	_charge_start_ms = 0
	_last_emitted_tier = -1
	if is_instance_valid(_tick_timer):
		_tick_timer.stop()
	_emit_and_sync(0, 0.0)


## Server tick. Recomputes tier + progress from the live clock and pushes an
## update. Progress is emitted every tick (smooth bar fill); a fresh client RPC
## is only sent when the integer tier changes (cheap — the client interpolates
## its own bar between syncs).
func _on_tick() -> void:
	if not multiplayer.is_server() or not _is_charging:
		return
	var elapsed_sec: float = float(Time.get_ticks_msec() - _charge_start_ms) / 1000.0
	var tier: int = get_tier_for_elapsed(elapsed_sec)
	var progress: float = clampf(elapsed_sec / CHARGE_MAX_SEC, 0.0, 1.0)
	_emit_and_sync(tier, progress)


## Server-side: emit locally for the host's widget, then push to the owning
## client when the tier crossed a threshold. Skips the RPC for bot owners
## (no client, no UI) — same gate SwordCombo uses.
func _emit_and_sync(tier: int, progress: float) -> void:
	charge_changed.emit(tier, progress)
	if not multiplayer.is_server():
		return
	# Only RPC the client on a tier change (incl. start=0 and reset=0). The
	# per-frame progress fill is reconstructed client-side from the tier.
	if tier == _last_emitted_tier:
		return
	_last_emitted_tier = tier
	var root := get_owner()
	if root == null or not "player_id" in root:
		return
	if BotManager.is_bot(root.player_id):
		return
	sync_charge_to_client.rpc_id(root.player_id, _is_charging, tier)

#endregion


#region #################### RPCs ####################

## Server -> owning client. Mirrors the authoritative charging flag + tier so
## the client's widget renders the matching fill. call_local is harmless — the
## body early-returns on the server, which already drove its own widget through
## the local signal path in _emit_and_sync.
@rpc("authority", "call_local", "reliable")
func sync_charge_to_client(charging: bool, tier: int) -> void:
	if multiplayer.is_server():
		return
	_is_charging = charging
	_client_tier = tier
	var progress: float = 0.0
	if charging and tier > 0:
		# Reconstruct an approximate progress fraction from the tier threshold so
		# the client bar lands at the right spot the instant a tier-up arrives.
		progress = clampf(CHARGE_TIER_TIMES[tier] / CHARGE_MAX_SEC, 0.0, 1.0)
	elif charging:
		progress = 0.0
	charge_changed.emit(tier, progress)

#endregion
