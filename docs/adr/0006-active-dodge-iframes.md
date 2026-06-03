# 6. Active dodge — server-authoritative i-frames + cooldown on the roll

Date: 2026-06-02

## Status

Accepted

## Context

The game had no **active defensive verb**. Survival was purely stat-checked:
you out-leveled, out-geared, or out-healed incoming damage, but there was no
moment-to-moment input that let a skilled player *avoid* a hit they saw coming.
The design (no dedicated tank role; roles are emergent from weapon identity)
needs a universal "get out of the way" answer that every discipline shares —
a GW2-style dodge.

A roll already existed in code: `scripts/Player/StateMachine/slide.gd` is a
quick directional lunge with jump/attack cancels. But in the weapon-identity
overhaul branch it had decayed into orphaned WIP — its controller plumbing
(`do_slide`, `slide_timer`, `slide_speed_boost`, `start_slide_effects`/
`end_slide_effects`, `coming_from_slide`) referenced members that no longer
existed on `MultiplayerPlayerV2`, the `slide` state node and a `SlideTimer` were
absent from `player.tscn`, and nothing in the input path ever set `do_slide`. So
the roll was un-enterable and had **no i-frames and no cooldown** — it was pure
movement, not a defensive verb.

The decision was to **deepen the existing roll into an active dodge** rather than
build a new state: reconnect the roll, and layer invulnerability + a cooldown
onto it so it becomes the counter-play to telegraphed damage.

The crux is *authority*. Movement in this codebase is server-simulated: the
StateMachine only changes state on the server (`state_machine.change_state` guards
`is_server`) and broadcasts the state **name** to remote peers for animation;
position replicates via `MultiplayerSynchronizer`. Critically, **damage is applied
by the server** in `health.gd take_damage`. So if invulnerability were a
client-side decision ("I'm rolling, therefore I'm immune"), a hacked client could
simply hold the roll state and ignore all damage. Immunity has to be decided where
damage is decided: on the server.

## Decision

Make the dodge's **invulnerability and cooldown server-authoritative**; the client
only sends *intent* and (visually) sees the roll motion.

- **A pure, testable gate.** The i-frame/cooldown logic lives in a standalone
  `DodgeGate` (`scripts/Player/dodge_gate.gd`, a clock-injectable `RefCounted`)
  holding two server-clock anchors: `_invulnerable_until_ms` and
  `_cooldown_until_ms`. `IFRAME_SECONDS = 0.35` (aligned to the roll's
  `SlideTimer` duration so immunity matches the readable roll motion) and
  `DODGE_COOLDOWN = 1.2`. `try_start_dodge(now)` is the **single** writer of both
  windows — immunity can never decouple from the cooldown that authorized it.
  Being a plain object with an injected clock, the whole gate is unit-tested
  headless (`test/player/test_dodge_gate.gd`) without a scene, peer, or the
  StateMachine (none reachable in the harness).

- **The flow.** The owning client presses the dodge key →
  `multiplayer_input.gd` sends `player_input(..., "dodge")` →
  `PlayerManager.player_input` (server, guarded) calls the player node's
  `request_dodge()`. `request_dodge` is the authoritative gate: it rejects if
  dead / mid-weapon-swap / not on floor, then asks `_dodge_gate.try_start_dodge`.
  **Only on success** does it arm the i-frame window, enter the roll state on the
  server (which broadcasts to peers), and `confirm_dodge.rpc()` so all peers
  (host included) can play a brief cosmetic flash. If on cooldown it does nothing
  — a client may still visually roll but gains **no immunity** (the server never
  armed the window). That negative case is the security property.

- **The damage check.** At the top of `health.gd take_damage`, in server context,
  if the target is a player and `owner.is_invulnerable()` (which forwards to the
  gate), the hit is ignored entirely — no HP loss, no damage number, no combat
  invuln start, no SFX. The check is skipped for the `ignore_invuln` channel
  (DoTs / true damage that must always land), so dodge i-frames gate only normal
  hits.

- **Reuses the existing `Slide` input action** (already bound to **Shift** in
  `project.godot`) — no new action, no clobbering. `Slide` existed but no code
  read it; the dodge wiring gives it a purpose. Only the owning client emits the
  intent (the input synchronizer runs only for the authority peer).

- **Bot-safe.** `is_invulnerable()` returns false for any entity whose gate was
  never armed (bots never call `request_dodge`), so bots in the roll state or
  passed to the damage check just take damage normally. No bot dodge AI (out of
  scope).

## Consequences

- **Correct under a hostile client, at the cost of one RPC round-trip.** A client
  can't grant itself i-frames; immunity is real only after the server arms it.
  The trade-off vs. pure client-side i-frames (simpler, but cheatable) is ~one
  round-trip of latency before immunity is "real". Acceptable: the roll's motion
  is the readable tell, and the design's telegraphed boss specials wind up over
  hundreds of milliseconds, so a dodge initiated on the telegraph still lands its
  immunity inside the danger window.

- **This is the counter-play to the (designed) boss-telegraph feature.** Telegraphs
  give the *signal*; the dodge is the *answer*. Together they convert
  "stat-checked survival" into "readable, dodgeable danger" — the no-tank design
  resolution. The telegraph feature itself is not yet built (it lives in the GDD);
  this PR ships the defensive half.

- **The roll is functional again.** `player.tscn` gains a `SlideTimer` and a
  `slide` StateMachine node (wired to idle/move/fall/jump/attack); the controller
  regains the slide plumbing the overhaul branch had orphaned. The dodge enters
  the roll directly via `change_state` from a grounded interruptible state, so the
  source states didn't need new `slide_state` exports.

- **Deliberate no-op collision swap.** `start_slide_effects`/`end_slide_effects`
  exist (slide.gd's contract) but don't shrink the collision shape — the overhaul's
  standing shape is a tiny circle where a slide-shrink adds little and risks
  getting stuck. A real shape swap can drop in later without touching this design.

- **Gate reset on respawn.** `respawn()` calls `_dodge_gate.reset()` so a stale
  i-frame/cooldown anchor can't carry across a life.
