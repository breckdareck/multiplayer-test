class_name DodgeGate
extends RefCounted

## Server-authoritative gate for the ACTIVE DODGE (the deepened roll).
##
## The roll/slide state gives the player a quick evasive lunge. On its own that's
## just movement — anyone (including a hacked client) can enter the state. The
## *invulnerability* and the *cooldown* that make the dodge a real defensive verb
## live HERE, and this object is only ever mutated on the SERVER (see
## MultiplayerPlayerV2.request_dodge / health.gd take_damage). A client cannot grant
## itself i-frames: the server is the sole writer of `_invulnerable_until_ms` and
## `_cooldown_until_ms`, so entering the roll without the server's blessing yields
## the motion but no immunity.
##
## Why a standalone RefCounted instead of inline fields on the player:
## - It is PURE and clock-injectable, so the cooldown/i-frame logic is unit-testable
##   headless without a scene, a multiplayer peer, or the StateMachine (which is
##   unreachable in the test harness). The player node owns one instance and
##   delegates; health.gd asks the player `is_invulnerable()`, which forwards here.
##
## Clock: anchored on Time.get_ticks_msec() (the engine monotonic clock, same one
## ShadowmeldComponent's enter-cooldown uses) — NOT wall-clock. The `now_ms`
## parameter on every method lets tests feed a deterministic clock; production
## callers pass Time.get_ticks_msec().

## Invulnerability window granted by one successful dodge. Roughly the roll's
## active duration so immunity lines up with the readable roll motion.
const IFRAME_SECONDS: float = 0.35

## Minimum time between dodges. Server-enforced so dodge can't be spammed for free
## perma-immunity.
const DODGE_COOLDOWN: float = 1.2

## Server clock anchor (ms): the player is invulnerable while now < this. 0 = never
## dodged / not currently invulnerable. Server-owned.
var _invulnerable_until_ms: int = 0

## Server clock anchor (ms): a new dodge is rejected while now < this. 0 = ready.
## Server-owned.
var _cooldown_until_ms: int = 0


## True iff a dodge is allowed to start at `now_ms` (off cooldown). Pure read.
func is_off_cooldown(now_ms: int) -> bool:
	return now_ms >= _cooldown_until_ms


## Attempt to start a dodge at `now_ms`. SERVER-ONLY semantics (the caller must
## already be on the server). Returns true and arms the i-frame + cooldown windows
## if off cooldown; returns false and changes nothing if still on cooldown. This is
## the single place both windows are set, so immunity can NEVER outlast/decouple
## from the cooldown gate that authorized it.
func try_start_dodge(now_ms: int) -> bool:
	if not is_off_cooldown(now_ms):
		return false
	_invulnerable_until_ms = now_ms + int(round(IFRAME_SECONDS * 1000.0))
	_cooldown_until_ms = now_ms + int(round(DODGE_COOLDOWN * 1000.0))
	return true


## True while the i-frame window is open at `now_ms`. health.gd take_damage reads
## this (via the player's is_invulnerable forwarder) to no-op incoming damage.
func is_invulnerable(now_ms: int) -> bool:
	return now_ms < _invulnerable_until_ms


## Remaining cooldown in seconds at `now_ms` (0 when ready). For an optional UI
## countdown / dimmed dodge indicator.
func cooldown_remaining(now_ms: int) -> float:
	if now_ms >= _cooldown_until_ms:
		return 0.0
	return float(_cooldown_until_ms - now_ms) / 1000.0


## Clear both windows (e.g. on death / respawn) so a stale i-frame anchor can't
## carry across a life. Safe to call any time.
func reset() -> void:
	_invulnerable_until_ms = 0
	_cooldown_until_ms = 0
