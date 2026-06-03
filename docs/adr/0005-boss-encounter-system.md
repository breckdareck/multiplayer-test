# 5. Boss encounter system (data-driven flags on EnemyData)

Date: 2026-06-02

## Status

Accepted

## Context

Every enemy is the same `EnemyBase` CharacterBody2D composed with `Health` /
`Stats` components and a patrol/chase/slash state machine, configured entirely
from an `EnemyData` `.tres`. The "Eternal Warlord" — the level-100 capstone enemy
that drops the Eternal weapon set — was just a reskinned goblin with a big stat
block. The GDD flagged "no `is_boss` flag, no boss mechanics" as a content gap:
there was no way to author a fight that reads differently from a trash mob.

We want a lightweight boss layer — phase transitions, an enrage, and a
telegraphed AoE special that gives players a dodge beat — without breaking the
server-authority invariant (the server owns enemy HP, AI, and damage; clients
only see replicated results) and without breaking the bot-safety invariant (bots
have negative peer IDs and no client, so they can never be node-addressed by an
RPC).

## Decision

**Boss state lives as data flags on `EnemyData`, not as a subclass or a
per-boss scene.** A new `@export_category("Boss")` block adds: `is_boss`,
`boss_title`, `phase_health_thresholds: Array[float]`, `enrage_health_threshold`
+ `enrage_damage_mult` + `enrage_attack_speed_mult`, and the special-attack tuning
(`special_attack_cooldown`, `special_telegraph_time`, `special_attack_radius`,
`special_attack_damage_mult`). All new fields are appended at the end of their
category — never reordered — because resource fields are positional.

**All boss logic is server-authoritative and gated by `enemy_data.is_boss`**, so
plain enemies are completely unaffected (every boss branch early-returns when
`is_boss` is false). In `enemy_base.gd`:

- **Phase transitions** hook the existing `HealthComponent.health_changed` signal
  (server-only connection). A monotonic tracker `_boss_phase_idx` records the
  highest threshold already passed, so each phase fires exactly once and a
  heal-then-redamage never re-fires it. A phase bump raises an internal
  `_boss_damage_mult` (+15%) and `_boss_attack_speed_mult` (+10% faster), emits a
  `boss_phase_changed(idx)` signal, and broadcasts a cosmetic roar flash. The
  crossing math is factored into a dependency-free helper
  (`scripts/Enemy/boss_phase_logic.gd`: `compute_phase_index()` /
  `should_enrage()`) so it is unit-testable in isolation, without dragging in the
  whole `EnemyBase` compile graph (whose `dot_visuals.gd` preload can transiently
  fail to resolve under a fresh `--script` boot).
- **Enrage** is independent: once HP drops to/below `enrage_health_threshold` it
  applies `enrage_damage_mult` + `enrage_attack_speed_mult` once.
- **Telegraphed special**: a server-side timer (`special_attack_cooldown`) fires
  only when a player is in aggro range. It broadcasts a growing telegraph ring to
  all peers for `special_telegraph_time` seconds, then on the server deals an AoE
  hit (`special_attack_damage_mult` × the boss's scaled attack, also subject to
  phase/enrage mults) to every player within `special_attack_radius`, reusing the
  same `HealthComponent.take_damage` path the normal enemy attack uses. The damage
  is independent of whether any client rendered the telegraph.
- The boss's **normal attack** damage is multiplied by the same phase/enrage
  factor in `damage_on_overlap`.

**The telegraph and roar are cosmetic-on-all-peers and route through
`MapManager`, NOT a node-addressed RPC.** We reuse the existing
`MapManager.broadcast_ground_zone(map_id, pos, radius, duration, color)` seam
(the same one chain-lightning and ground-zone abilities use). MapManager is an
autoload that resolves on every peer, so a bot HOST renders the telegraph too —
whereas a node-addressed RPC to a clientless bot would be invalid. No new
autoload or sync field was invented. We did NOT add a replicated
`_special_telegraphing` bool to the boss's `SceneReplicationConfig` (the
documented fallback), because the MapManager broadcast already exists and is the
established pattern.

**The boss HP bar discovers its boss by group-scan, not RPC.** A new HUD widget
(`scenes/UI/boss_hp_bar.tscn` + `scripts/UI/boss_hp_bar.gd`, instanced under
`CanvasLayer/PlayerHUD` like the other gauge widgets) polls the local peer's
visible map for an `EnemyBase` in the global `Enemies` group whose
`enemy_data.is_boss` is true (the `is_ancestor_of` map filter that
`bot_manager` uses), binds to its `HealthComponent`, and paints
current/max + title. HP replicates via the **existing**
`Health:current_health/max_health/is_dead` entries already in the boss scene's
`SceneReplicationConfig` — **no new sync field**. Because discovery is a local
group scan reading replicated HP, it works identically on every peer, including a
bot host, with zero networking added.

## Consequences

- Authoring a new boss is pure `.tres` editing (flip `is_boss`, set the
  thresholds/specials) — no code, no subclass, no bespoke scene. The Eternal
  Warlord was upgraded in place: `is_boss = true`, phases `[0.66, 0.33]`, enrage
  at `0.2`, an 8s / 1.3s-telegraph / 140px / ×2.5 special.
- Boss tuning (damage step per phase, attack-speed step, roar colors) is a small
  set of constants in `enemy_base.gd`; the per-fight numbers are on the resource.
- The phase/enrage crossing logic is covered by a focused unit suite
  (`test/boss/test_boss_phases.gd`): each phase fires once in order, no re-fire on
  heal, big single drops fire all passed phases, enrage boundaries, and that a
  default (non-boss) `EnemyData` triggers nothing.
- **Trade-off considered:** a boss subclass (`BossEnemy extends EnemyBase`) or a
  scene-per-boss would localize boss code, but it would fork the spawner/pooling
  path, duplicate the component wiring, and move tuning out of the
  designer-editable `.tres` layer. We chose data flags for reuse and
  `.tres`-authorability, accepting that `enemy_base.gd` carries a (well-guarded)
  boss section.
- **The telegraphed special is an AI state, not a `_process` scheduler.** The
  windup/telegraph/AoE lives in `enemy_boss_special.gd` (`extends EnemyState`),
  injected at runtime only for bosses via `_ensure_boss_special_state()` —
  mirroring `_ensure_chase_state()`, so generic enemies never carry it. All that
  remains in `_process` is a tiny readiness gate (`_boss_special_tick`) that hands
  control to the state. This makes the windup frame-driven and interruptible
  (death cancels it via the base `State.process_physics` death check), and it is
  hit-stagger-immune (the special is committed once telegraphed). It is the
  established seam for any *future bespoke* boss mechanic: a new AI state and/or a
  component, never an inheritance fork.
- **Special attacks are authored as `BossAttackData` resources** (`.tres`),
  carried on `EnemyData.special_attacks: Array[BossAttackData]`. Each holds shape
  (RECT/CIRCLE/CONE), forward offset, reach/band, **windup + hit timing**, an
  **animation mode** (STRETCH the clip to the hit / HOLD a frame until the hit /
  FREE), movement (NONE/DASH), damage mult, cooldown, and an optional
  `logic_script: Script` hook (`on_windup_start`/`on_hit`/`on_recover`, mirroring
  `ActiveBehaviorData.logic_script`) for fully bespoke attacks (a dragon's fire
  breath = a CONE attack + a small logic script, *no new state code*). The
  `enemy_boss_special` state is a **generic executor** that runs any
  `BossAttackData`; bosses differ purely by editing resources in the inspector,
  and a boss can have several distinct attacks (each with its own cooldown), the
  gate picking the first off-cooldown, in-range one. **Back-compat:** when
  `special_attacks` is empty, `EnemyData.get_special_attacks()` synthesises one
  dash-slam from the legacy `special_attack_*` fields, so bosses that predate the
  resource (the Eternal Warlord) keep working unchanged — and gain the STRETCH
  anim-sync for free. **Decision:** chose a data resource + `logic_script` hook
  (not a hardcoded per-boss state, nor an `AnimationPlayer` timeline) to stay
  consistent with the `.tres`-driven content + `logic_script` patterns already in
  the codebase; the inspector is the authoring surface, with a resource_editor
  custom GUI as a possible follow-up.
- Pooled/respawned bosses reset their phase/enrage/special state in `pool_reset`
  so a re-spawn starts the fight clean.
- **Not yet verified in a live multiplayer session.** The phase/enrage logic and
  the `.tres`/scene parse are validated (unit suite + headless class-cache
  refresh). The end-to-end beat — telegraph rendering on a remote client and a
  bot host, the AoE landing, the HP bar appearing/binding/hiding — should be
  smoke-tested in-engine before relying on it.
