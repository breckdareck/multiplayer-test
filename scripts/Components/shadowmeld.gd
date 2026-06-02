class_name ShadowmeldComponent
extends WeaponSignatureComponent

## PR 7 — Dagger discipline's signature combat system: SHADOWMELD.
##
## Dagger identity: while wielding a DAGGER, a key (WeaponSignature) TOGGLES
## stealth on/off. While stealthed the player is invisible to enemy AI and the
## NEXT dagger hit landed — a basic melee swing OR any dagger ability hit — is an
## AMBUSH (all hits of that one attack ×AMBUSH_DAMAGE_MULT), after which stealth
## breaks exactly once. An entry cooldown stops it being spammed, and a max-stealth
## safety timer auto-exits if the player never attacks.
##
## This is the dagger analogue of SwordComboComponent / BowMomentumComponent /
## StaffElementComponent. Same structural rules:
## - Server-authoritative: every mutator early-returns unless multiplayer.is_server().
##   The owning client only learns the stealth state through the
##   sync_shadowmeld_to_client RPC, which feeds its widget. The sprite-dim visual
##   is pushed to ALL peers via the player node's existing sync_dark_sight_visual
##   RPC (reused from Vanish) so remote players see the dagger fade out too.
## - Bots have no client and no UI — the client-sync RPC is skipped for bot owners
##   (BotManager.is_bot check, same gate SwordCombo / BowMomentum / StaffElement use).
## - Volatile per-session: stealth state is never saved or synced through the
##   backend. It resets to NOT-stealthed on each spawn; a stealth in progress at
##   logout simply vanishes.
##
## PR 11 (2026-05-31): Vanish was REMOVED as a stealth ability — it duplicated
## this signature. The slot is now Killing Edge, a non-stealth crit-burst buff.
## Shadowmeld is the sole stealth provider for dagger. The `is_invisible` meta
## is owned exclusively by this component; break_stealth() can clear it
## unconditionally (no more cross-system coordination check).
##
## The ambush multiplier is applied by CombatComponent._execute_hit, which checks
## is_stealthed() (gated to a wielded dagger) BEFORE its damage loop, multiplies
## every hit, then calls break_stealth() once AFTER the loop. Unlike the staff
## element rider, the dagger ambush DOES apply to a basic melee hit (ability ==
## null) — landing from stealth is the whole point.

#region #################### Tunable constants ####################

## Damage multiplier applied to ALL hits of the one attack that breaks stealth.
## 2.0 = a clean ambush hits for double. Read by CombatComponent._execute_hit.
const AMBUSH_DAMAGE_MULT: float = 2.0

## Seconds after ENTERING stealth before it can be entered again. Anchored on the
## server clock (Time.get_ticks_msec) so the client can't fake an early re-entry.
## A manual un-stealth (toggle off) or an ambush break both leave this cooldown
## running — you commit to a window each time you cloak. 6s.
const ENTER_COOLDOWN_SEC: float = 6.0

## Safety ceiling: if the player enters stealth and never attacks, it auto-exits
## after this long so an idle cloak doesn't persist forever. 8s. (A held stealth
## is meant to be a brief pre-strike window, not a permanent state — that's what
## the Vanish escape ability is for.)
const MAX_STEALTH_SEC: float = 8.0

## Sprite alpha while stealthed. Dimmer than full but lighter than Vanish's 0.3
## so the two read slightly differently. Restored to 1.0 on break/cancel.
const STEALTH_SPRITE_ALPHA: float = 0.5

#endregion


#region #################### Signals ####################

## Emitted on both server and client whenever stealth state changes (enter,
## break, cancel). Carries the new stealthed flag. The widget listens to this to
## repaint STEALTHED / READY / cooldown.
signal shadowmeld_changed(stealthed: bool)

#endregion


#region #################### State ####################

## True while stealthed. Server-authoritative; the client mirror is driven by
## sync_shadowmeld_to_client. Volatile — never saved; defaults to false on spawn.
var _is_stealthed: bool = false

## Server clock anchor — Time.get_ticks_msec() at the END of the last stealth
## window (when it was entered, since entering starts the cooldown). The enter
## cooldown is measured from when stealth was last ENTERED. 0 means never entered.
## Only meaningful on the server.
var _last_enter_ms: int = 0

## Safety timer that auto-exits stealth after MAX_STEALTH_SEC if the player never
## attacks. A child Node Timer (freed with the component), restarted on each enter
## and stopped on each break/cancel. Server-only use.
var _max_stealth_timer: Timer

#endregion


#region #################### Lifecycle ####################

func _ready() -> void:
	_max_stealth_timer = Timer.new()
	_max_stealth_timer.name = "MaxStealthTimer"
	_max_stealth_timer.one_shot = true
	_max_stealth_timer.wait_time = MAX_STEALTH_SEC
	_max_stealth_timer.timeout.connect(_on_max_stealth_timeout)
	add_child(_max_stealth_timer)

#endregion


#region #################### Public API ####################

## Server-only. Toggles stealth: turns it ON if currently off AND off cooldown,
## or OFF (a manual un-stealth, no ambush) if currently on. Called from
## PlayerManager.player_input when the local player presses WeaponSignature while
## wielding a dagger. The input branch that sends this is already gated on the
## DAGGER discipline client-side; this is_server guard is the authoritative gate.
func toggle_shadowmeld() -> void:
	if not multiplayer.is_server():
		return
	if _is_stealthed:
		# Manual un-stealth — same teardown as an ambush break, but no ambush is
		# granted because the combat hook only multiplies while is_stealthed().
		break_stealth()
		return
	# Entering: respect the enter cooldown so it can't be spammed.
	if not _is_off_cooldown():
		return
	_enter_stealth()


## Read-only accessor for the combat hook + widget. Safe on both peers — the
## client's mirror is kept in step via sync_shadowmeld_to_client.
func is_stealthed() -> bool:
	return _is_stealthed


## Read-only accessor for the widget. True when stealth can be entered (not
## stealthed and off cooldown). On the client this reflects the synced state +
## the synced cooldown anchor, so a host and a remote owner agree.
func is_ready() -> bool:
	return not _is_stealthed and _is_off_cooldown()


## Read-only accessor for the widget: remaining enter-cooldown in seconds (0 when
## ready). Lets the widget show a countdown / dim while it recharges.
func get_cooldown_remaining() -> float:
	if _last_enter_ms == 0:
		return 0.0
	var elapsed_sec: float = float(Time.get_ticks_msec() - _last_enter_ms) / 1000.0
	return maxf(0.0, ENTER_COOLDOWN_SEC - elapsed_sec)


## Server-only. Ends stealth and grants nothing further — the AMBUSH multiplier
## is applied by CombatComponent._execute_hit BEFORE it calls this, so by the time
## we run, the bonus damage has already been dealt. Called by the combat hook once
## after the hit loop of the attack that landed from stealth.
##
## COEXISTENCE GUARD: only clear the `is_invisible` meta + restore the sprite when
## the player is NOT currently under the Vanish buff. Vanish (BL_DarkSight) owns
## the same meta/alpha for its own timed window; if Shadowmeld broke while Vanish
## was active it would prematurely reveal the player and undo Vanish's effect.
func break_stealth() -> void:
	if not multiplayer.is_server():
		return
	if not _is_stealthed:
		return
	_is_stealthed = false
	if is_instance_valid(_max_stealth_timer):
		_max_stealth_timer.stop()

	_restore_visibility()
	_emit_and_sync()


## Server-only. Clears stealth WITHOUT any ambush (functionally identical to
## break_stealth here — break grants no bonus itself, the combat hook does — but
## kept as a distinct entry point with intent-revealing name). Called on death and
## on weapon-swap-away-from-dagger, mirroring BowMomentumComponent.reset.
## Safe to call when not stealthed.
func cancel_stealth() -> void:
	if not multiplayer.is_server():
		return
	if not _is_stealthed:
		return
	_is_stealthed = false
	if is_instance_valid(_max_stealth_timer):
		_max_stealth_timer.stop()

	_restore_visibility()
	_emit_and_sync()

#endregion


#region #################### WeaponSignature interface ####################

func signature_discipline() -> int:
	return Constants.ClassType.DAGGER


## Stealth is dagger-only: swapping (or re-equipping) away from a dagger cancels
## it so the cloak never carries onto a non-dagger weapon. (Was hand-coded twice
## on the player root before the WeaponSignature unification.)
func on_weapon_state_changed(active_discipline: int, _equipped_disciplines: Array) -> void:
	if active_discipline != Constants.ClassType.DAGGER:
		cancel_stealth()


## Stealth shouldn't survive death.
func on_owner_died() -> void:
	cancel_stealth()

#endregion


#region #################### Internals ####################

## Server-side. Flags stealthed, sets the invisibility meta (reused by enemy AI),
## dims the sprite on every peer, anchors the enter cooldown, and starts the
## safety auto-exit timer.
func _enter_stealth() -> void:
	_is_stealthed = true
	_last_enter_ms = Time.get_ticks_msec()

	var root := get_owner()
	if root != null:
		root.set_meta("is_invisible", true)
		_set_sprite_alpha(root, STEALTH_SPRITE_ALPHA)

	if is_instance_valid(_max_stealth_timer):
		_max_stealth_timer.start(MAX_STEALTH_SEC)

	_emit_and_sync()


## True when the enter cooldown has elapsed (or stealth has never been entered).
func _is_off_cooldown() -> bool:
	if _last_enter_ms == 0:
		return true
	var elapsed_sec: float = float(Time.get_ticks_msec() - _last_enter_ms) / 1000.0
	return elapsed_sec >= ENTER_COOLDOWN_SEC


## Safety auto-exit: the player entered stealth and never attacked. Treat exactly
## like a manual un-stealth (no ambush). Guarded — runs only on the server and
## only if still stealthed.
func _on_max_stealth_timeout() -> void:
	if not multiplayer.is_server():
		return
	if not _is_stealthed:
		return
	cancel_stealth()


## Clears the invisibility meta + restores the sprite. PR 11: Vanish was
## removed, so there's no longer a parallel buff owning `is_invisible` —
## Shadowmeld can clear unconditionally.
func _restore_visibility() -> void:
	var root := get_owner()
	if root == null:
		return
	root.set_meta("is_invisible", false)
	_set_sprite_alpha(root, 1.0)


## Dims/restores the player sprite on EVERY peer. Reuses the player node's
## existing sync_dark_sight_visual RPC (authored for Vanish) so the visual is
## consistent and we don't duplicate the alpha-sync plumbing. Falls back to a
## direct local set if the RPC isn't available.
func _set_sprite_alpha(root: Node, alpha: float) -> void:
	if root.has_method("sync_dark_sight_visual"):
		root.sync_dark_sight_visual.rpc(alpha)
		return
	var sprite := root.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite:
		sprite.modulate.a = alpha


## Server-side: emit locally for the host's widget, then push to the owning
## client. Skips the RPC for bot owners (no client, no UI) — same gate SwordCombo
## / BowMomentum / StaffElement use.
func _emit_and_sync() -> void:
	shadowmeld_changed.emit(_is_stealthed)
	if not multiplayer.is_server():
		return
	var root := get_owner()
	if root == null or not "player_id" in root:
		return
	if BotManager.is_bot(root.player_id):
		return
	sync_shadowmeld_to_client.rpc_id(root.player_id, _is_stealthed)

#endregion


#region #################### RPCs ####################

## Server -> owning client. Mirrors the authoritative stealth flag so the client's
## widget renders STEALTHED / READY. call_local is harmless — the body
## early-returns on the server, which already drove its own widget through the
## local signal path in _emit_and_sync. (The sprite-dim visual rides the separate
## sync_dark_sight_visual RPC, broadcast to all peers, not this one.)
@rpc("authority", "call_local", "reliable")
func sync_shadowmeld_to_client(stealthed: bool) -> void:
	if multiplayer.is_server():
		return
	if _is_stealthed == stealthed:
		return
	_is_stealthed = stealthed
	shadowmeld_changed.emit(_is_stealthed)

#endregion
