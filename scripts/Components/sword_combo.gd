class_name SwordComboComponent
extends WeaponSignatureComponent

## PR 5 — Sword discipline's signature combat system: combo points.
##
## Sword identity: every basic-attack HIT while wielding a sword builds 1 combo
## point (max 3). The Slash ability consumes ALL current combo points on cast
## and amplifies its damage by +100% per point spent (4x at 3 points) - see
## COMBO_DAMAGE_PER_POINT below for the tuning history.
##
## Combo points:
## - PERSIST across Tab-swaps. Build 3 combo, Tab-swap to bow, back to sword →
##   combo still there. The player owns their built-up state.
## - RESET on item-swap to a non-Sword loadout. If neither slot has a sword,
##   combo points clear. Equipment listener in equipment-change handler.
## - DECAY after 5 seconds of no basic-attack activity. Resets the decay timer
##   on every basic-attack hit.
## - VOLATILE per-session. Not saved, not synced through the backend. A combo
##   built up at logout vanishes — small UX cost for a much simpler save shape.
##
## Server-authoritative: only the server mutates state; the owning client
## receives updates via sync_combo_to_client RPC so its UI can react. Bots have
## no client and no UI — RPCs are skipped for bot owners (BotManager.is_bot
## check, same as WeaponMastery/Ability/etc.).

#region #################### Constants ####################

## Maximum combo points the player can hold. Mirrors the locked design: small
## enough to read on a glance via 3 hotbar pips.
const COMBO_CAP: int = 3

## Seconds of basic-attack inactivity before combo points decay to zero.
## Industry-standard combo decay window — slow enough to chain through
## ability casts, fast enough that walking away from combat clears state.
const COMBO_DECAY_SECONDS: float = 5.0

## Damage bonus per combo point spent (multiplicative add on top of base).
## 1.0 = +100% per point, so 3 points = +300% damage on top of base (4.0×).
## Bumped through 0.25 → 0.50 → 1.0 in successive PR 5 polish passes because
## the combo-build cycle (3 basic attacks or 1-2 Steel Flurry casts) needs a
## finisher payoff that beats spam-casting any single ability. Power Strike
## overrides this locally in AL_PowerStrike.gd (+200%/pt, 3-combo = 7×) for
## the single-target burst path.
const COMBO_DAMAGE_PER_POINT: float = 1.0

#endregion


#region #################### Signals ####################

## Emitted on both server and client whenever the combo count changes
## (build, spend, decay, or reset). UI listeners refresh their pip display.
signal combo_changed(new_count: int)

## Emitted on both server and client when an ability consumes the current
## combo total. Carries the spent count for any consumer that wants to react
## (e.g. a VFX system flashing harder for a 3-combo finisher).
signal combo_consumed(spent: int)

#endregion


#region #################### State ####################

## Current combo total. Volatile — never saved. Mirrored to the owning client
## via sync_combo_to_client; the server is authoritative.
var _combo_points: int = 0

## One-shot decay timer. Restarted on every build; freed when the parent
## component is freed (it's a child Node, not a tree-rooted Timer).
var _decay_timer: Timer

## Overcharge window (Crashing Vault): temporary cap bonus + its expiry.
## Volatile server-side state; clients see it indirectly through the synced
## combo count (the widget grows a pip when the count exceeds the base cap).
var _overcharge_extra: int = 0
var _overcharge_until_ms: int = 0

#endregion


#region #################### Lifecycle ####################

func _ready() -> void:
	_decay_timer = Timer.new()
	_decay_timer.name = "DecayTimer"
	_decay_timer.one_shot = true
	_decay_timer.wait_time = COMBO_DECAY_SECONDS
	_decay_timer.timeout.connect(_on_decay_timeout)
	add_child(_decay_timer)
	# _process only runs while an overcharge window is open (see
	# grant_overcharge / the expiry below).
	set_process(false)


## Overcharge expiry watcher — clamp surplus points back to the base cap the
## moment the window closes, then go back to sleep.
func _process(_delta: float) -> void:
	if _overcharge_extra <= 0:
		set_process(false)
		return
	if Time.get_ticks_msec() < _overcharge_until_ms:
		return
	_overcharge_extra = 0
	_overcharge_until_ms = 0
	set_process(false)
	if _combo_points > COMBO_CAP:
		_combo_points = COMBO_CAP
	_emit_and_sync()

#endregion


#region #################### Public API ####################

## Server-only. Builds one combo point if not already at the cap, and resets
## the decay timer. No-op past the cap (locked design: "stop adding once at
## 3, no overflow"). Called from CombatComponent._execute_hit when the active
## weapon is a sword and the hit came from the basic-attack pathway.
func add_combo_point() -> void:
	if not multiplayer.is_server():
		return
	if _combo_points >= get_combo_cap():
		# Even at cap, restart the decay timer — the player is still actively
		# fighting, so the cap shouldn't tick down out from under them.
		_restart_decay_timer()
		return
	_combo_points += 1
	_restart_decay_timer()
	_emit_and_sync()


## Effective cap: COMBO_CAP, temporarily raised while an OVERCHARGE window is
## open (Vault Strike's Crashing Vault T3: landing a vault lets you hold an
## extra point for a few seconds). Deliberately TEMPORARY — a permanent cap
## raise would be passive-territory, not an ability upgrade; the overcharge
## is a play beat: vault in, spend the 4th point before it fades.
func get_combo_cap() -> int:
	var cap: int = COMBO_CAP
	if _overcharge_extra > 0 and Time.get_ticks_msec() < _overcharge_until_ms:
		cap += _overcharge_extra
	return cap


## Server-only. Opens (or refreshes) an overcharge window: the cap rises by
## `extra` for `duration_sec`. When the window closes, any points above the
## base cap are LOST (_process clamps them) — spend the surge or waste it.
func grant_overcharge(extra: int, duration_sec: float) -> void:
	if not multiplayer.is_server():
		return
	_overcharge_extra = maxi(1, extra)
	_overcharge_until_ms = Time.get_ticks_msec() + int(duration_sec * 1000.0)
	set_process(true)
	_emit_and_sync()


## Server-only. Returns the current combo total and clears it to zero. The
## caller (Slash's AL script) uses the return value to scale damage. Emits
## combo_consumed and combo_changed so listeners react.
func spend_combo() -> int:
	if not multiplayer.is_server():
		return 0
	var spent: int = _combo_points
	_combo_points = 0
	if is_instance_valid(_decay_timer):
		_decay_timer.stop()
	combo_consumed.emit(spent)
	_emit_and_sync()
	return spent


## Server-only. Explicitly clears combo to zero. Used when the equipment
## change removes Sword from both slots — no carrying combo around without
## the weapon that built it.
func reset_combo() -> void:
	if not multiplayer.is_server():
		return
	if _combo_points == 0:
		return
	_combo_points = 0
	if is_instance_valid(_decay_timer):
		_decay_timer.stop()
	_emit_and_sync()


## Read-only accessor for the UI / AL_SlashBlast. Safe on both server and
## client — the client's mirror is updated via sync_combo_to_client.
func get_combo_count() -> int:
	return _combo_points

#endregion


#region #################### WeaponSignature interface ####################

func signature_discipline() -> int:
	return Constants.ClassType.SWORD


## Combo PERSISTS across a Tab-swap (build with a sword, swap to bow, swap back —
## the combo is still there). It only clears when NEITHER weapon slot holds a
## sword, since you can't stockpile combo without a sword in your loadout. This
## rule moved here from EquipmentComponent._reset_combo_if_sword_unequipped in
## the WeaponSignature unification — same condition, now owned by the signature.
func on_weapon_state_changed(_active_discipline: int, equipped_disciplines: Array) -> void:
	if not equipped_disciplines.has(Constants.ClassType.SWORD):
		reset_combo()

# on_owner_died is intentionally NOT overridden — combo is left to decay on its
# own timer rather than wiped on death (preserves the pre-unification behavior).

#endregion


#region #################### Internals ####################

func _restart_decay_timer() -> void:
	if not is_instance_valid(_decay_timer):
		return
	_decay_timer.stop()
	_decay_timer.start(COMBO_DECAY_SECONDS)


## Server timer callback. Called after COMBO_DECAY_SECONDS of no basic-attack
## activity. Wipes combo to zero and notifies the owning client.
func _on_decay_timeout() -> void:
	if not multiplayer.is_server():
		return
	if _combo_points == 0:
		return
	_combo_points = 0
	_emit_and_sync()


## Server-side: emit locally for the host's UI, then push to the owning
## client. Skips the RPC for bot owners (no client, no UI).
func _emit_and_sync() -> void:
	combo_changed.emit(_combo_points)
	if not multiplayer.is_server():
		return
	var root := get_owner()
	if root == null or not "player_id" in root:
		return
	if BotManager.is_bot(root.player_id):
		return
	sync_combo_to_client.rpc_id(root.player_id, _combo_points)

#endregion


#region #################### RPCs ####################

## Server -> owning client. Mirrors the authoritative combo total so the
## client's UI can render the matching pip fill. `call_local` is safe — the
## body is idempotent (just sets _combo_points and emits) so the server
## running this against itself would be a redundant overwrite. We avoid it
## anyway by routing the server-side emit through _emit_and_sync's direct
## signal call and using rpc_id(owner.player_id) which targets the client
## peer for a non-host player. For the host (peer 1), the rpc_id targets
## peer 1 — call_local handles that case.
@rpc("authority", "call_local", "reliable")
func sync_combo_to_client(new_count: int) -> void:
	# Server already wrote the value through the local path; this is a no-op
	# fallthrough that keeps the host's RPC contract clean.
	if multiplayer.is_server():
		return
	if _combo_points == new_count:
		return
	_combo_points = new_count
	combo_changed.emit(_combo_points)

#endregion
