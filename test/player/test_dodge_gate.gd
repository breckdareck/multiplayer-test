# Suite for the active-dodge server gate (scripts/Player/dodge_gate.gd).
#
# The gate is the server-authoritative i-frame + cooldown logic for the deepened
# roll. It's a pure RefCounted with an injectable clock (now_ms), so we exercise
# the full gate behaviour headless WITHOUT a scene, a multiplayer peer, or the
# StateMachine (none of which are reachable in this harness). We also exercise the
# health.gd-style "ignore damage while invulnerable" decision against the gate so
# the take_damage no-op contract is covered without the full Health/RPC path.
extends "res://test/test_case.gd"

const DodgeGateScript = preload("res://scripts/Player/dodge_gate.gd")

var gate

func before_each() -> void:
	gate = DodgeGateScript.new()


# A dodge while off cooldown succeeds, arms invulnerability, and starts the cooldown.
func test_dodge_off_cooldown_arms_iframes_and_cooldown() -> void:
	var t0: int = 1000
	var ok: bool = gate.try_start_dodge(t0)
	assert_true(ok, "dodge off cooldown should succeed")
	assert_true(gate.is_invulnerable(t0), "should be invulnerable immediately after a blessed dodge")
	assert_false(gate.is_off_cooldown(t0), "cooldown should be running right after a dodge")


# A second dodge during the cooldown window is rejected and grants no new immunity.
func test_second_dodge_during_cooldown_is_rejected() -> void:
	var t0: int = 1000
	assert_true(gate.try_start_dodge(t0), "first dodge succeeds")

	# Try again 200ms later — still well inside the 1.2s cooldown.
	var t1: int = t0 + 200
	var ok2: bool = gate.try_start_dodge(t1)
	assert_false(ok2, "dodge during cooldown must be rejected")

	# The i-frame window must NOT have been re-extended by the rejected attempt:
	# the first dodge's 0.35s window expires 350ms after t0, i.e. before t0+400.
	var after_first_iframe: int = t0 + 400
	assert_false(gate.is_invulnerable(after_first_iframe),
		"rejected dodge must not extend immunity past the original window")


# is_invulnerable is true within the i-frame window and false after it.
func test_invulnerable_within_window_then_false_after() -> void:
	var t0: int = 5000
	gate.try_start_dodge(t0)
	# IFRAME_SECONDS = 0.35 -> 350ms window.
	assert_true(gate.is_invulnerable(t0 + 100), "invulnerable mid-window")
	assert_true(gate.is_invulnerable(t0 + 349), "invulnerable just before window ends")
	assert_false(gate.is_invulnerable(t0 + 350), "no longer invulnerable at window end")
	assert_false(gate.is_invulnerable(t0 + 1000), "not invulnerable long after")


# After the full cooldown elapses, a fresh dodge is allowed again.
func test_dodge_allowed_again_after_cooldown() -> void:
	var t0: int = 0
	assert_true(gate.try_start_dodge(t0), "first dodge")
	# DODGE_COOLDOWN = 1.2s -> 1200ms.
	assert_false(gate.is_off_cooldown(t0 + 1199), "still on cooldown at 1199ms")
	assert_true(gate.is_off_cooldown(t0 + 1200), "off cooldown at exactly 1200ms")
	assert_true(gate.try_start_dodge(t0 + 1200), "dodge succeeds again after cooldown")


# Models health.gd take_damage's decision: damage is a no-op while invulnerable,
# and applies normally otherwise. Mirrors the early-return the component does.
func test_take_damage_noop_while_invulnerable() -> void:
	var hp: int = 100
	var t0: int = 2000
	gate.try_start_dodge(t0)

	# Incoming hit DURING the i-frame window -> ignored (no-op), like take_damage's
	# `if owner.is_invulnerable(): return`.
	var now_during: int = t0 + 100
	if not gate.is_invulnerable(now_during):
		hp -= 30
	assert_eq(hp, 100, "damage must be ignored while invulnerable")

	# Incoming hit AFTER the window -> applies.
	var now_after: int = t0 + 500
	if not gate.is_invulnerable(now_after):
		hp -= 30
	assert_eq(hp, 70, "damage must apply once the i-frame window has expired")


# A fresh gate (e.g. a bot, or a player who never dodged) is never invulnerable and
# is always off cooldown — the bot-safe / default path.
func test_fresh_gate_is_inert() -> void:
	assert_false(gate.is_invulnerable(0), "fresh gate not invulnerable at t=0")
	assert_false(gate.is_invulnerable(999999), "fresh gate not invulnerable later")
	assert_true(gate.is_off_cooldown(0), "fresh gate is off cooldown")
	assert_eq(gate.cooldown_remaining(0), 0.0, "fresh gate has no cooldown remaining")


# reset() clears both windows so immunity can't carry across a life/respawn.
func test_reset_clears_windows() -> void:
	var t0: int = 3000
	gate.try_start_dodge(t0)
	assert_true(gate.is_invulnerable(t0 + 50), "invulnerable before reset")
	gate.reset()
	assert_false(gate.is_invulnerable(t0 + 50), "not invulnerable after reset")
	assert_true(gate.is_off_cooldown(t0 + 50), "off cooldown after reset")
	assert_true(gate.try_start_dodge(t0 + 50), "can dodge immediately after reset")
