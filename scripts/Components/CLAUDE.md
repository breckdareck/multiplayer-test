# Character components

Player and enemy characters are **composed**, not inherited. A root character node
owns a set of single-responsibility `Node` components.

## Layout

The player root is `MultiplayerPlayerV2` (`scripts/Player/multiplayer_controller_v2.gd`,
scene `scenes/Player/player.tscn`). Components sit under a `Components` child node:

```
Player (MultiplayerPlayerV2)
└── Components/
    ├── Health     health.gd      - HP, invuln frames, regen, death/respawn
    ├── Mana       mana.gd        - MP, regen, consumption
    ├── Stats      stats.gd       - STR/DEX/INT/LUCK/CON aggregates ALL bonuses.
    │                               PR 7 attribute allocation (New World style):
    │                               a 5/level pool (ATTRIBUTE_POINTS_PER_LEVEL) is
    │                               MANUALLY spent into STR/DEX/INT/LUCK/CON
    │                               (_allocated_attributes), REPLACING the old auto
    │                               per-level discipline scaling (mastery scaling
    │                               stays auto). API: allocate_attribute(stat,n) /
    │                               respec_attributes() (client→RPC, server-auth) +
    │                               reconcile_attribute_points() on load (granted ==
    │                               spent + unused; default-allocates un-migrated
    │                               chars to the starting discipline's ratio so
    │                               existing stats are preserved). Each attribute
    │                               also feeds a secondary utility:
    │                               STR→Defense, DEX→accuracy (combat.gd hit-chance),
    │                               INT→Mana+MPregen, LUCK→CritChance, CON→HP+HPregen
    │                               (tunable *_TO_* consts). CON is StatType idx 15
    │                               (appended). Round-trips via save_attributes /
    │                               load_attributes (backend `attribute_points`
    │                               JSONB); synced via sync_attributes RPC.
    ├── Combat     combat.gd      - hitboxes, damage calc, crit
    ├── Ability    ability.gd     - learn/level/use abilities, cooldowns, passives.
    │                               Ability points are PER-DISCIPLINE (PR 4 — see
    │                               available_points_per_discipline dict). Points
    │                               are granted PER MASTERY LEVEL of the relevant
    │                               weapon (PR 4 fix 2026-05-27 — NOT per
    │                               character level). Trees the player never
    │                               masters never accumulate points.
    │                               Discipline-gating (PR 4 fix 2026-05-28):
    │                                 - Active-only PASSIVES: _foreach_learned_passive
    │                                   filters by active discipline, so Sword's
    │                                   HP Boost only applies while wielding a sword.
    │                                   Cascades to stat modifiers + procs + ability
    │                                   damage/cooldown/mana modifiers.
    │                                 - Cross-discipline CAST guard:
    │                                   _validate_ability_use rejects casts whose
    │                                   ability discipline doesn't match the wielded
    │                                   weapon. Hotbar binding still exists, just
    │                                   fails to fire until matching weapon equipped.
    │                               Character-creation init (PR 4 fix 2026-05-28):
    │                               ALL four tier-1 disciplines' starter abilities
    │                               are auto-leveled to 1 (Slash + Double Shot +
    │                               Magic Bolt + Double Stab), so a fresh character
    │                               has a usable basic ability the moment they
    │                               equip any of the four weapons. Returning
    │                               characters keep saved levels via the merge
    │                               (not clear) in load_abilities.
    │                               PR 6 ability upgrades: per-ability upgrade
    │                               purchases live in `_learned_upgrades`
    │                               ({ability_id: [upgrade_id,...]}). Public API:
    │                               has_upgrade / get_learned_upgrades /
    │                               can_purchase_upgrade (pure validation:
    │                               ability at MAX level + tier-gating +
    │                               variant-mutex + point cost) /
    │                               purchase_upgrade (client→RPC,
    │                               server-auth spend from the discipline pool).
    │                               Round-trips via save_abilities under
    │                               `learned_ability_upgrades` (backend column
    │                               of the same name, PR 6). Effect reads:
    │                               ability_has_upgrade_effect(id, effect_key)
    │                               + get_ability_upgrade_magnitude(id, key)
    │                               (per-ability) + get_total_upgrade_magnitude(
    │                               key) (player-wide). Generic effect_keys are
    │                               consumed by AbilityComponent itself
    │                               (e.g. "cooldown_flat_reduction" in
    │                               _consume_ability_resources); ability-specific
    │                               keys are read by AL_*.gd. See hook section.
    │                               Respec: respec_ability(id) /
    │                               respec_discipline(disc_key) / respec_all()
    │                               refund levels (above the free starter
    │                               baseline) + upgrade costs back to the
    │                               pool(s), reset levels/upgrades. Shared
    │                               _refund_ability + _finalize_respec helpers.
    │                               Server-auth via respec_*_request RPCs.
    │                               Reconcile guard (PR 6):
    │                               reconcile_ability_points() recomputes each
    │                               pool from first principles — granted
    │                               (mastery_level * ABILITY_POINTS_PER_MASTERY_LEVEL,
    │                               6 since the 2026-05-28 balance pass) minus
    │                               spent (levels above the free starter baseline
    │                               + owned upgrade costs) = unused — and corrects
    │                               any drift either way (so a grant-constant
    │                               change is retroactive on load). Called at end of
    │                               load_abilities (do_sync=false during load;
    │                               the post-load sync_all_abilities_to_client
    │                               carries the corrected pools to the client).
    │                               Server-authoritative; a no-op when matched.
    ├── WeaponMastery weapon_mastery.gd - Per-discipline mastery levels + XP (PR 2)
    │                                     mastery_data: {sword/bow/staff/dagger →
    │                                     {level, xp}}. Drives STR/DEX/INT/LUK
    │                                     scaling additively on top of class-level.
    │                                     Kill XP credits BOTH primary AND secondary
    │                                     equipped weapons (PR 4 fix 2026-05-28);
    │                                     cast XP only credits the ACTIVE weapon.
    │                                     Kill XP is level-scaled (PR 4 fix
    │                                     2026-05-28 rev 2): base = enemy_level,
    │                                     modifier = clamped (1 + diff * 0.15)
    │                                     between 0.10 and 2.5. See
    │                                     compute_kill_xp(enemy_level, player_level)
    │                                     and the KILL_XP_* tunable constants.
    │                                     Cast XP requires a LANDED HIT (PR 4
    │                                     fix 2026-05-28 rev 3) — granted in
    │                                     combat.gd._execute_hit, not at ability
    │                                     cast time. Spam-cast in empty area =
    │                                     0 XP. Self-targeted buffs/heals that
    │                                     never reach _execute_hit also = 0 XP.
    ├── SwordCombo sword_combo.gd - PR 5 sword signature: combo points (0-3).
    │                               Basic-attack HITS build 1; finishers
    │                               (Crescent Cleave / Sundering Blow) spend ALL
    │                               via spend_combo(). Persists across Tab-swap,
    │                               decays after 5s idle, resets if neither slot
    │                               is a sword. Server-authoritative; mirrored to
    │                               the owning client via sync_combo_to_client.
    ├── BowMomentum bow_momentum.gd - bow signature: the MOMENTUM gauge.
    │                               (Replaced the failed hold-to-charge Snap Shot.)
    │                               Every LANDED bow hit — the basic Snap Shot AND
    │                               any bow ability hit — builds 1 stack (cap 10,
    │                               MAX_STACKS) via add_momentum(), called from
    │                               combat._execute_hit once per landed hit while a
    │                               bow is wielded (NOT gated on ability != null, so
    │                               the whole kit feeds it). The gauge DECAYS to 0
    │                               when you stop firing (DECAY_DELAY_SEC 2s grace,
    │                               then -1 stack / DECAY_STEP_SEC 0.3s, on a
    │                               server-side tick Timer). While up it ramps BOTH:
    │                               (a) ALL bow damage by get_damage_bonus()
    │                               (DAMAGE_PER_STACK 0.035 → +35% at cap), applied
    │                               in combat.calculate_ability_damage gated on
    │                               _is_wielding_bow() so it never touches a
    │                               sword/staff/dagger ability; and (b) fire-rate /
    │                               attack speed by get_speed_bonus() (SPEED_PER_STACK
    │                               0.03 → +30% at cap), applied in attack.gd's
    │                               attack_speed_percent getter (BOW-gated, null-safe).
    │                               Needs NO new input — builds passively from hits
    │                               like the sword combo. reset() on death + on
    │                               swap-away-from-bow (multiplayer_controller_v2).
    │                               Constants are STARTING values (tunable). Volatile
    │                               (never saved); mirrored to the owning client via
    │                               sync_momentum_to_client (bot-skipped).
    ├── StaffElement staff_element.gd - PR 7 staff signature: the ELEMENT STANCE.
    │                               The WeaponSignature key (R) cycles the active
    │                               element FIRE→ICE→LIGHTNING (cycle_element, gated
    │                               to STAFF in multiplayer_input.gd; routed via
    │                               player_manager "staff_cycle_element"). The active
    │                               element adds an on-hit rider to staff SPELL hits:
    │                               FIRE = stacking burn DoT scaled off the
    │                               TRIGGERING HIT's damage (BURN_HIT_PCT, floor
    │                               BURN_MIN_PER_TICK — NOT raw MAGICATTACK, which
    │                               rounded to 1/tick early; own meta key
    │                               "staff_element_burn", stacks independently of
    │                               Immolate/bleeds), ICE = movement slow (reduces
    │                               EnemyBase.movement_speed directly — there is NO
    │                               movespeed StatType — restored on a timer), LIGHTNING
    │                               = a bonus shock to the target AND a chain arc to
    │                               up to LIGHTNING_CHAIN_MAX_TARGETS nearby same-map
    │                               enemies (via _nearby_enemies, map-filtered through
    │                               combat._is_on_same_map) — the crowd element. The
    │                               chain also fires a cosmetic bolt VFX threading
    │                               the struck+zapped enemies (MapManager.broadcast_
    │                               lightning_arc → scripts/VFX/lightning_arc.gd,
    │                               drawn per-peer under the visible map).
    │                               Applied by combat._execute_hit AFTER
    │                               the damage loop, STRICTLY gated (ability != null +
    │                               max_landed_damage > 0 + _is_wielding_staff()) so it
    │                               can NEVER affect a sword/bow/dagger hit. DoT/bonus
    │                               kills credit mastery XP + on_kill (mirrors
    │                               AL_Immolate). Volatile (defaults FIRE on spawn);
    │                               mirrored to the owning client via
    │                               sync_element_to_client (bot-skipped).
    ├── Shadowmeld shadowmeld.gd  - PR 7 dagger signature: SHADOWMELD stealth.
    │                               The WeaponSignature key (R) TOGGLES stealth
    │                               while wielding a DAGGER (toggle_shadowmeld,
    │                               gated to DAGGER in multiplayer_input.gd as its
    │                               own sibling `if`; routed via player_manager
    │                               "dagger_shadowmeld"). REUSES the existing
    │                               `is_invisible` meta (enemy AI already respects it,
    │                               set by Vanish/BL_DarkSight) + dims the sprite via
    │                               the player's existing sync_dark_sight_visual RPC.
    │                               The NEXT dagger hit from stealth is an AMBUSH:
    │                               combat._execute_hit raises ambush_mult to
    │                               AMBUSH_DAMAGE_MULT (×2) BEFORE the hit loop (gated
    │                               valid-component + _is_wielding_dagger() +
    │                               is_stealthed()), multiplies EVERY hit (incl. a
    │                               basic melee, ability == null — unlike the staff
    │                               rider), then calls break_stealth() ONCE after the
    │                               loop. 6s enter cooldown + 8s safety auto-exit.
    │                               COEXISTENCE GUARD: break/cancel only clears
    │                               `is_invisible` if the "Vanish" buff isn't active
    │                               (buff.has_buff), so it never strips a live Vanish.
    │                               Cancelled on death + on swap-away-from-dagger
    │                               (multiplayer_controller_v2). Volatile (resets on
    │                               spawn); synced via sync_shadowmeld_to_client
    │                               (bot-skipped). Multi-TARGET swings ambush only the
    │                               first target then break (single-target rogue feel).
    ├── Buff       buff.gd        - timed buffs/debuffs, stacking, custom logic
    ├── Class      class.gd       - current_class = STARTING weapon discipline
    │                               (does NOT change on weapon swap). Drives HP/MP
    │                               curves. For "what am I wielding right now", use
    │                               MultiplayerPlayerV2.get_active_discipline().
    │                               PR 7: NO class advancement (classes don't
    │                               exist, only weapons). The current_class setter
    │                               normalizes any legacy advanced class
    │                               (CRUSADER/RANGER/ARCHMAGE/ASSASSIN) back to its
    │                               tier-1 weapon discipline, so current_class is
    │                               ALWAYS one of SWORD/STAFF/BOW/DAGGER (+BEGINNER).
    │                               stats.gd no longer has advanced-class HP arms.
    ├── Leveling   level.gd       - experience and level-ups
    ├── Equipment  equipment.gd   - 6 slots after PR 3: head/chest/legs/feet/weapon
    │                               + secondary_weapon. active_weapon tracks which
    │                               weapon is current. Swap via request_weapon_swap_server.
    └── Inventory  inventory.gd   - item slots, stacking, drag-and-drop
```

(Dev-only `heal`, `damage`, `revive`, `level`, `give`, `gold`, `tp` actions
were previously a separate `Debug` component with its own right-side panel;
they're now console commands in the backtick `DebugPanel` autoload.)

Enemies (`EnemyBase`, `scripts/Enemy/enemy_base.gd`) reuse a subset — `Health` and
`Stats` — wired through exported references on the enemy scene.

## Conventions

- **Wiring**: the player root exposes typed accessors (`health_component`,
  `stats_component`, `ability_component`, …). Components find each other as
  siblings: `get_parent().get_node_or_null("Stats")`. A component that needs a
  sibling should `push_error` and disable itself if it is missing — keep that
  pattern when adding components.
- **`owner`** inside a component is the root character node. Reach a component on
  *another* character with `node.get_node_or_null("Components/Buff")`.
- **Server authority**: gameplay logic runs on the server. Components begin their
  `_process` / `_physics_process` with `if not multiplayer.is_server(): return`,
  apply the change, then RPC-sync it. Clients keep a mirror copy for the UI only.
- **Stats aggregation**: `StatsComponent` is the single source of truth for final
  stats — it sums base + class + equipment + buff + passive-ability bonuses. After
  changing any of those inputs, call `stats_component.mark_stats_dirty()` instead of
  editing a stat value directly.
- **Save/load**: stateful components expose `save_*()` / `load_*()` that
  return/take a `Dictionary`. `set_loading_mode(true)` suppresses side effects
  (damage, signals, re-saves) while persisted state is restored.
- **Bots**: a bot frees its entire UI subtree on spawn. Component code must guard
  UI-node access (`is_instance_valid(hotbar)`) and skip client-facing buff/ability
  sync RPCs for bot-owned characters (`BotManager.is_bot(owner.player_id)`).

## Ability logic-script hooks (`AL_*.gd`)

Per-ability behavior rides on optional methods of
`AbilityData.active_behavior.logic_script` (and buff `BL_*.gd` on
`BuffData.logic_script`) rather than new fields on the shared schemas — see
the `logic_script_not_schema_field` memory. `CombatComponent` / `AbilityComponent`
duck-type these methods (`has_method` before calling), so an AL script only
implements the hooks it needs:

- **`execute(owner, ability, level_stats)`** — fires once on cast, server-side.
  Used for buff application (AL_PowerGuard, AL_BulwarkStance), combo spend
  (AL_Slash, AL_PowerStrike), dash velocity (AL_VaultStrike). Note:
  `AbilityData.applies_buff` is **metadata only** (UI/bots/pets read it) — the
  actual `buff_component.apply_buff()` call must be made here.
- **`on_hit(owner, target, ability)`** — fires per landed ability hit in
  `combat.gd._execute_hit` (post-miss-check). Misses don't fire it. Used by
  AL_Brandish (build combo per hit), AL_Hemorrhage (apply bleed), AL_VaultStrike.
- **`on_kill(owner, target, ability_level, ability_id)`** — fires for learned
  PASSIVES when an enemy dies, dispatched by
  `AbilityComponent.dispatch_passive_event_on_kill` (called from `combat.gd`'s
  kill pathway). Used by AL_Bloodthirst (heal on kill; reads its heal_pct_bonus
  upgrade via ability_id).
- **`on_proc(owner, target, context)`** — proc-effect handler (ProcEffectData).

### PR 6 upgrade effect_keys (the full vocabulary)
Generic — consumed by Combat/Ability with NO per-AL code:
  `cooldown_flat_reduction` (sec, _consume_ability_resources),
  `mana_flat_reduction` (MP, _consume_ability_resources),
  `bonus_damage_mult` (additive %, calculate_ability_damage),
  `bonus_targets` / `bonus_hits` (int, combat target/hit loops),
  `passive_stat_percent_bonus` (% on the passive's stat — for large-base stats
  like HP/STR/Mana; get_passive_effect_modifiers),
  `passive_stat_flat_bonus` (PR 8 — FLAT points on the passive's stat, for
  percentage-style stats CritChance/CritDamage or base-0 Defense where a percent
  bonus is meaningless; same function).
Ability-specific — read in the named AL via `ability_has_upgrade_effect` /
`get_ability_upgrade_magnitude`:
  `combo_coefficient_override` (AL_Slash, AL_PowerStrike),
  `combo_per_hit_bonus` (AL_Brandish),
  `bleed_potency_bonus` / `bleed_max_stack_bonus` / `bleed_duration_bonus`
  (AL_Hemorrhage),
  `buff_duration_bonus` (AL_PowerGuard / AL_MapleWarrior / AL_BulwarkStance),
  `reflect_bonus` (AL_PowerGuard), `vow_stat_bonus` (AL_MapleWarrior),
  `heal_pct_bonus` (AL_Bloodthirst).
Adding a new generic key = one wire-in + reuse everywhere; a new ability-specific
key = a read in that ability's AL.

**DOT kills** (e.g. Hemorrhage's bleed) bypass `_execute_hit`, so the AL script
must replicate the kill side-effects itself (mastery XP + `on_kill` dispatch) —
see `AL_Hemorrhage._credit_bleed_kill`. Character XP / quest credit come free via
the enemy's own death handler reading `damage_by_player`, **provided the damage
source is attributed** (pass the applier, not `null`, to `take_damage`).
