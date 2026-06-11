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
    │                               (tunable *_TO_* consts). SOFT-CAP: allocated
    │                               points per stat keep full value up to
    │                               ATTR_SOFT_CAP_KNEE (300) then ×ATTR_SOFT_CAP_SLOPE
    │                               (0.4) beyond (_effective_allocation) — reins in
    │                               pure-primary mono-stacking (was +27-43% DPS) while
    │                               leaving default/split builds (primary ~297 < knee)
    │                               untouched. Accounting tracks RAW spent, not
    │                               effective. CON is StatType idx 15
    │                               (appended). PR 13 appended ACCURACY (idx 16)
    │                               and EVASIONCHANCE (idx 17) — both new stat
    │                               types are read in combat.gd's hit-chance
    │                               formula (attacker ACCURACY adds, target
    │                               EVASIONCHANCE subtracts). Bow's Marksman's
    │                               Focus grants ACCURACY; dagger's Evasion
    │                               grants EVASIONCHANCE. Round-trips via
    │                               save_attributes / load_attributes (backend
    │                               `attribute_points` JSONB); synced via
    │                               sync_attributes RPC.
    ├── Combat     combat.gd      - hitboxes, damage calc, crit. PR 13 hit-
    │                               chance formula:
    │                                 clamp(95
    │                                   + (char_lvl - mob_lvl) * 3
    │                                   + DEX * DEX_TO_ACCURACY
    │                                   + attacker.ACCURACY
    │                                   - target.EVASION
    │                                   - max(0, mob_lvl - weapon_lvl) * 2,
    │                                   5, 100)
    │                               Level-diff scalar raised 2→3 so above-level
    │                               fights demand accuracy invest. Weapon
    │                               underlevel: -2% per level the wielded weapon
    │                               is below the target (MapleStory-style — the
    │                               gear-upgrade loop matters; equal-or-overlevel
    │                               weapon = 0 penalty). Equipment access for
    │                               weapon_lvl via _equipment_component.
    │                               BL_ShadowPartner.gd mirrors the formula
    │                               (caught diverged in PR 12 audit).
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
    │                               Character-creation init (PR 8 2026-05-31):
    │                               no more free discipline starter abilities —
    │                               all abilities start at level 0. Fresh chars
    │                               are bootstrapped to mastery level 1 in their
    │                               chosen discipline by
    │                               AbilityComponent.bootstrap_fresh_character_if_needed
    │                               so the player has 1 ability point to spend
    │                               on their first pick. Returning characters
    │                               keep saved levels via the merge (not clear)
    │                               in load_abilities.
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
    │                               refund levels + upgrade costs back to the
    │                               pool(s), reset levels/upgrades. Shared
    │                               _refund_ability + _finalize_respec helpers.
    │                               Server-auth via respec_*_request RPCs.
    │                               Reconcile guard (PR 6):
    │                               reconcile_ability_points() recomputes each
    │                               pool from first principles — granted
    │                               (mastery_level * ABILITY_POINTS_PER_MASTERY_LEVEL,
    │                               1 since the PR 8 2026-05-31 redesign) minus
    │                               spent (every level + owned upgrade costs)
    │                               = unused — and corrects
    │                               any drift either way (so a grant-constant
    │                               change is retroactive on load). Called at end of
    │                               load_abilities (do_sync=false during load;
    │                               the post-load sync_all_abilities_to_client
    │                               carries the corrected pools to the client).
    │                               Server-authoritative; a no-op when matched.
    │                               Skill-tree layout: AbilityData carries tree_path
    │                               (0/1, -1=unplaced) + tree_depth (row). Gating
    │                               history: points-in-path tier gate -> active
    │                               prerequisite CHAIN -> (f2d69b8, 2026-05-30)
    │                               REMOVED. is_tree_node_unlocked() now returns true
    │                               for ALL nodes — fully FREE-PICK (scarcity = points
    │                               only) for playtest. _get_active_chain_parent() /
    │                               active_chain_prereq_name() kept (commented
    │                               re-enable in is_tree_node_unlocked). Legacy
    │                               prerequisite_abilities all stripped. Rendered by
    │                               scripts/UI/skill_tree_canvas.gd as a one-path-at-a-
    │                               time D4 tree (upgrades = branching nodes).
    ├── WeaponMastery weapon_mastery.gd - Per-discipline mastery levels + XP (PR 2)
    │                                     mastery_data: {sword/bow/staff/dagger →
    │                                     {level, xp}}. Drives STR/DEX/INT/LUK
    │                                     scaling (weapon-pure: attribute pool +
    │                                     mastery, no class-level STR).
    │                                     ADR 0004 (2026-06-02): ALSO owns the
    │                                     character's primary_discipline pointer —
    │                                     the absorbed ClassComponent role. Set once
    │                                     at spawn via set_primary_discipline()
    │                                     (+_rpc, emits primary_discipline_changed);
    │                                     persisted via the existing character_type
    │                                     save field. Provides get_primary_discipline/
    │                                     get_primary_abilities/get_base_stats/
    │                                     get_class_bonuses/get_discipline_name. The
    │                                     setter normalizes legacy advanced classes
    │                                     (CRUSADER/RANGER/ARCHMAGE/ASSASSIN) → tier-1.
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
    │                                     WIELDED IDENTITY (moved off the player
    │                                     root): get_active_discipline() (active
    │                                     weapon's discipline, falls back to
    │                                     primary_discipline) + get_equipped_
    │                                     disciplines() (both slots, de-duped).
    │                                     WeaponMastery is the single owner of
    │                                     weapon identity; the player root keeps
    │                                     thin forwarders for its duck-typed callers.
    │   The four signature components below (SwordCombo / BowMomentum /
    │   StaffElement / Shadowmeld) share the WeaponSignatureComponent base
    │   (weapon_signature.gd): a single interface — signature_discipline() /
    │   on_weapon_state_changed(active, equipped) / on_owner_died() — the player
    │   root notifies on every weapon swap, equip edit, and death. Each signature
    │   owns its OWN deactivation rule (sword combo clears when no sword is in
    │   either slot; bow Momentum / dagger Shadowmeld clear when no longer wielded;
    │   staff element persists). Adding a fifth signature needs no player-root edits.
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
    │                               like the sword combo. PERSISTS across weapon swaps:
    │                               slot-gated like Sword Combo (reset() only on death +
    │                               when a bow leaves BOTH weapon slots). While the bow is
    │                               SHEATHED (equipped but not wielded) the ramp HOLDS for
    │                               SHEATHE_HOLD_SEC (3s, _sheathed_at_ms) then decays
    │                               normally — long enough to swap to the off-hand and use
    │                               the Momentum (e.g. Staff+Bow spells) without being
    │                               permanent. (Was active-gated: any swap zeroed it.)
    │                               ABILITY SYNERGIES: Snipe SPENDS all Momentum for a
    │                               burst then reset() (combat.calculate_ability_damage,
    │                               gated ability_name=="Snipe"); Hailstorm/Skyfall build
    │                               2/attack via add_momentum(amount); Steady Aim freezes
    │                               decay for its buff duration (pause_decay, AL_Focus).
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
    │                               Immolate/bleeds). NOTE: bleed/poison/burn-pool
    │                               DoTs (Hemorrhage, Barbed Shot, Envenom, Pyre
    │                               Burst, Immolate) follow the same principle via
    │                               CombatComponent.dot_scaling_base(ability) — per-
    │                               tick = FRAC × the ability's max hit (max_range ×
    │                               damage%/100), NOT a flat % of WEAPONATTACK/
    │                               MAGICATTACK, so DoTs scale with attributes +
    │                               mastery + ability level + gear like direct
    │                               damage (was a ~146× endgame shortfall). ICE = movement slow (reduces
    │                               EnemyBase.movement_speed directly — there is NO
    │                               movespeed StatType — restored on a timer), LIGHTNING
    │                               = a bonus shock to the target AND a SEQUENTIAL
    │                               chain that hops to the nearest un-hit enemy,
    │                               re-centers on it, and hops again up to
    │                               LIGHTNING_CHAIN_MAX_HOPS times (_nearest_chain_target,
    │                               map-filtered via combat._is_on_same_map) — the
    │                               crowd element. Fires even when the strike KILLS
    │                               the primary (apply_element_on_hit no longer bails
    │                               on a dead target — it arcs off the dying enemy;
    │                               FIRE/ICE self-guard to no-op on a corpse). The
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
    │                               PER-ABILITY ELEMENT REACTIONS (ALs read
    │                               get_current_element()): Immolate+FIRE = 2 stacks/hit
    │                               + bigger ticks + tick splash; Pyre Burst+FIRE = own
    │                               burn DoT ("pyre_burst_burn"); Glacial Spike+ICE =
    │                               hard freeze/root (movement_speed→0); Arcane Lance+
    │                               LIGHTNING = bonus chain-shock. Off-element = baseline.
    ├── Shadowmeld shadowmeld.gd  - PR 7 dagger signature: SHADOWMELD stealth.
    │                               The WeaponSignature key (R) TOGGLES stealth
    │                               while wielding a DAGGER (toggle_shadowmeld,
    │                               gated to DAGGER in multiplayer_input.gd as its
    │                               own sibling `if`; routed via player_manager
    │                               "dagger_shadowmeld"). REUSES the existing
    │                               `is_invisible` meta (enemy AI already respects it,
    │                               set by (legacy — Vanish removed)) + dims the sprite via
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
    │                               (bot-skipped). Multi-TARGET swings now ambush EVERY
    │                               target (×2 + crit + Staff+Dagger element on all):
    │                               _execute_hit only FLAGS the attack (_attack_ambushed),
    │                               and _consume_ambush() breaks stealth ONCE after the
    │                               whole melee target loop — so stealth persists across
    │                               all of a multi-target swing's targets (was: broke
    │                               inside the first target's hit, leaving the rest
    │                               un-ambushed). PROJECTILE abilities (Fan of Knives,
    │                               is_projectile) land across multiple frames, so the
    │                               ambush is captured at the THROW (_compute_dagger_ambush
    │                               in the projectile-spawn branch), stealth breaks there
    │                               ONCE, and each projectile carries an is_ambush flag
    │                               (projectile.gd → process_projectile_hit forced_ambush →
    │                               _execute_hit projectile_ambush 0/1) so every knife
    │                               ambushes regardless of land frame. Still one ambush per
    │                               cloak. Both paths feed the Staff+Dagger synergy element
    │                               to ALL targets (it gates on ambush_mult>1.0).
    │                               AMBUSH SYNERGIES: the ambush GUARANTEES a crit
    │                               (combat forces is_crit when ambush_mult>1.0); it
    │                               also triggers from the Vanish buff (not just the
    │                               Shadowmeld toggle) — the strike consumes Vanish
    │                               (break_stealth then remove_buff("Vanish")). Eviscerate
    │                               from stealth = execute bonus on targets ≤35% HP
    │                               (AL_Eviscerate).
    ├── WeaponPairSynergy weapon_pair_synergy.gd - CROSS-GAUGE synergy layer.
    │                               Extends WeaponSignatureComponent (auto-discovered;
    │                               signature_discipline() returns -1 — it's the PAIR
    │                               layer, not a single gauge). AUTOMATIC-on-equip like
    │                               spellblade: when a specific PAIR of weapon
    │                               disciplines is equipped, a cross-gauge effect fires.
    │                               combat._execute_hit calls on_hit_landed(owner,
    │                               target, hit_dmg, ability, did_ambush) once per
    │                               target after the loop (beside the staff/bow riders;
    │                               did_ambush = ambush_mult>1.0). GIVER/RECEIVER model
    │                               from the gauge gating: persistent Combo/Stance feed
    │                               the wielded weapon. Now SYMMETRIC (every weapon
    │                               benefits from every pairing). Staff OFF-HAND → active
    │                               weapon's hit carries the stance element (Sword/Bow
    │                               active, Dagger ambush). Dagger OFF-HAND → active
    │                               weapon's hit applies POISON (_imbue_with_poison via
    │                               BleedDot "synergy_poison"; Sword/Bow/Staff active) —
    │                               the mirror of the element imbue. STAFF-MAIN reciprocals
    │                               (spell hits): Staff+Sword spell SPENDS Combo for a magic
    │                               burst (hit×combo×0.5); Staff+Bow spell rides Momentum
    │                               (hit×get_damage_bonus). Sword+Bow = bow hits
    │                               add_combo_point (Combo persists, spend on sword);
    │                               Sword+Dagger/Staff+Sword spend Combo; Bow+Dagger = bow
    │                               hits charge `_bd_charge` (cap 10, swap-surviving) AND
    │                               poison, dagger ambush spends it ×0.15. Reads other gauges via
    │                               owner.get("<x>_component") (both-peer-safe read API);
    │                               server-only mutators. Emits synergy_proc(pair_key)
    │                               on server + owning client (call_local RPC, bot/no-id
    │                               skip) for the (pending) synergy widget. Volatile,
    │                               no save. Tuning = the *_MULT consts.
    ├── Buff       buff.gd        - timed buffs/debuffs, stacking, custom logic
    │  (Class/class.gd REMOVED — ADR 0004, 2026-06-02. The "starting/primary
    │   discipline" pointer it owned is now WeaponMastery.primary_discipline; it
    │   still drives HP/MP curves + base stats, does NOT change on weapon swap, and
    │   is ALWAYS one of SWORD/STAFF/BOW/DAGGER (+BEGINNER) after the advanced-class
    │   normalization. For "what am I wielding right now", use get_active_discipline().)
    ├── Leveling   level.gd       - experience and level-ups
    ├── Equipment  equipment.gd   - 6 slots after PR 3: head/chest/legs/feet/weapon
    │                               + secondary_weapon. active_weapon tracks which
    │                               weapon is current. Swap via request_weapon_swap_server.
    ├── Inventory  inventory.gd   - item slots, stacking, drag-and-drop
    └── Appearance appearance.gd  - owns ALL sprite/appearance application: the
                                    single apply path (discipline+level ->
                                    AnimatedSprite2D frames), the weapon-swap
                                    transition FX, and the sprite-state RPCs
                                    (change_sprite_rpc / request_sprite_change /
                                    request_all_sprite_states). Server decides the
                                    discipline+level and broadcasts; clients apply;
                                    bots route through MapManager. Asks the player
                                    root (-> WeaponMastery) for the wielded
                                    discipline rather than re-deriving it. The
                                    player root keeps an apply_appearance forwarder
                                    so MapManager's bot-appearance calls still land,
                                    and the swap INPUT lock stays on the root (an
                                    input concern); only the swap VISUALS moved here.
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
  actual `buff_component.apply_buff()` call must be made here. To make a buff's
  flat stat scale with ability level (apply_buff has no magnitude param), call
  `BuffComponent.scale_buff_stat(buff_id, stat_type, flat)` (server-side) right
  after apply — it deep-duplicates the active buff's buff_data, overrides the
  modifier, recalcs, and broadcasts to clients via `sync_buff_stat_modifiers`.
  Used by AL_BulwarkStance (Defense 100→250) and AL_Banner (aura Defense, once
  per ally — REFRESH keeps the scaled data across ticks). Added 2026-06-02.
- **`on_hit(owner, target, ability)`** — fires per landed ability hit in
  `combat.gd._execute_hit` (post-miss-check). Misses don't fire it. Used by
  AL_Steel_Flurry (build combo per hit), AL_Hemorrhage (apply bleed), AL_VaultStrike.
- **`on_kill(owner, target, ability_level, ability_id)`** — fires for learned
  PASSIVES when an enemy dies, dispatched by
  `AbilityComponent.dispatch_passive_event_on_kill` (called from `combat.gd`'s
  kill pathway). Used by AL_Bloodthirst (heal on kill; reads its heal_pct_bonus
  upgrade via ability_id).
- **`on_proc(owner, target, context)`** — proc-effect handler (ProcEffectData).
- **`conditional_damage_mult(owner, target, level) -> float`** — situational damage
  passive hook. Returns the bonus FRACTION (e.g. 0.3) based on the target's HP/state,
  the attacker's HP/mana, a recent kill, stealth, or momentum. `AbilityComponent.
  get_conditional_damage_modifier` sums it across equipped-discipline passives;
  `combat.gd._execute_hit` applies ×(1+total) per hit. When a passive's condition is
  MET (returns >0), the modifier ALSO adds that passive's owned `conditional_damage_bonus`
  upgrades (see vocabulary below), so its upgrade tree scales the bonus. Implemented by
  the **10** conditional passives (bare `extends Node` ALs, path-resolved, MAX_LEVEL=5 since PR 9)
  that replaced the old always-on stat auto-takes: Aggression (sword, vs >90% HP),
  Last Stand (sword, owner <35% HP), Execution (bow, vs <30% HP), Tailwind (bow, scales
  with Momentum stacks), Killing Spree (staff, 4s after a kill — its `on_kill` stamps an
  owner meta deadline), Overload (staff, owner mana >50%), Composure (dagger, owner
  >80% HP), Toxicology (dagger, target envenom-poisoned), Opportunist (dagger, stealthed),
  **Predator's Patience** (dagger, ambush damage scales with time-since-last-ambush; v1).
  v1 NOTE: the dispatcher probes each AL's `conditional_damage_mult` arg count and passes
  extra params when the AL accepts them: a **4th** param = the cast `ability` (Elemental
  Affinity uses it for per-stance ability_id matching); a **5th** param = the passive's
  OWN ability_id (so the passive can read its own upgrade tree — potency/carryover/
  at-full — for shared effect_keys that get_total would double-count). Existing 3-arg ALs
  are unaffected. (Wired 2026-06-02 for ELA + Predator's Patience.)
- **`conditional_damage_taken_mult(owner, source, level [, passive_id]) -> float`** — v1
  incoming-damage passive hook (Vanguard's Resolve). Returns a NEGATIVE fraction (e.g.
  -0.16 = -16%) representing damage REDUCTION. `AbilityComponent.get_incoming_damage_modifier`
  sums across equipped-discipline passives; `health.gd.take_damage` (on a player target)
  applies the resulting `(1.0 + total)` BEFORE HP deduction. Enemy-on-player damage doesn't
  route through `combat.gd._execute_hit` so this is the only integration site. The dispatcher
  passes the passive's OWN ability_id as a **4th** param when the AL accepts it (same
  arg-count probe) so it can read its own potency/cap/carryover upgrades (wired 2026-06-02).
- **`attack_cooldown_mult(owner, level [, ability_id]) -> float`** — v1 basic-attack speed
  passive hook (Wind Rider). Returns a NEGATIVE fraction (e.g. -0.25 = -25% delay) representing
  cooldown REDUCTION. `AbilityComponent.get_attack_cooldown_mult` sums across equipped-
  discipline passives; `scripts/Player/StateMachine/attack.gd`'s `attack_speed_percent`
  getter divides `base` by the resulting mult so a negative bonus speeds up the
  basic-attack cycle. Layered on top of `BowMomentumComponent.get_speed_bonus` (Momentum
  speed ramp) so they stack distinctly. The dispatcher passes the passive's OWN ability_id
  as a **3rd** param when accepted (arg-count probe) for its upgrade reads (2026-06-02).
- **`ability_cooldown_reduction(owner, level, ability_id) -> float`** — v1 passive
  ability-cooldown hook (Wind Rider's Twin Wind T3). Returns a positive FRACTION;
  `AbilityComponent.get_passive_ability_cooldown_mult` sums across passives and returns
  `clamp(1.0 - sum, 0.1, 1.0)`, applied to every ability cooldown in
  `_consume_ability_resources` (2026-06-02).
- **`modify_cast_resources(owner) -> Dictionary`** — v1 pre-cast resource hook
  (AL_Shadowstep). Returns `{"mp_mult": float, "cd_mult": float}` to scale this cast's
  MP cost and cooldown BEFORE the existing flat-reduction / per-ability-modifier paths
  run. Called in `AbilityComponent._consume_ability_resources` after probing the ability's
  `active_behavior.logic_script` for the method; defaults to `{1.0, 1.0}` (no-op) when
  absent. AL_Shadowstep returns `{0.0, 0.5}` when the caster is in Shadowmeld stealth
  so a stealthed reposition doesn't burn the ambush slot.

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
  bonus is meaningless; same function),
  `conditional_damage_bonus` (FLAT fraction added to a conditional passive's bonus
  while its condition is met; summed in get_conditional_damage_modifier — the upgrade
  tree for every `conditional_damage_mult` passive points here),
  `bonus_damage_vs_bleed` / `_vs_poison` / `_vs_burn` / `_vs_chill` / `_vs_mark`
  (ADR 0013 — additive % applied per TARGET in _execute_hit when the enemy carries
  the status tag, ANY source's; the 2026-06-10 re-author pointed ~34 formerly-bare
  T1/T2 damage/CD/mana nodes on actives here),
  `combo_cap_bonus` (player-wide sum via get_total_upgrade_magnitude — raises the
  sword combo gauge's cap; SwordComboComponent.get_combo_cap; the combo widget
  grows pips dynamically),
  `bonus_per_combo_held` (+% damage per combo point HELD, not spent —
  calculate_ability_damage; the anti-spender play),
  `combo_refund_on_kill` (a kill with the owning sword ability refunds N combo —
  _execute_hit kill block, mirrors bonus_momentum_on_kill),
  `bonus_ramp_per_target` (pierce crescendo: each additional enemy struck by the
  same cast takes +% more — _execute_hit, counter reset in turn_on_hitbox).
  GAUGE-MATH RULE (2026-06-10 signature audit): never author +combo-per-hit or
  +targets on a sword BUILDER — one cast of any builder already fills the
  3-point gauge (Steel Flurry 2×3, Vault 2×2, Charge 1×3, Onslaught 1×6), so
  such nodes are DEAD on arrival. Bow momentum (cap 10) has real headroom —
  bonus_momentum_* keys are fine there.
Ability-specific — read in the named AL via `ability_has_upgrade_effect` /
`get_ability_upgrade_magnitude`:
  `combo_coefficient_override` (AL_Slash, AL_PowerStrike),
  `combo_per_hit_bonus` (AL_Steel_Flurry),
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

### Mark + payoff static-helper pattern (v1)

The four v1 mark abilities (DeathMark, MarkOfTheHunt, SentinelsMark, ManaSurge)
use a different dispatch shape from the conditional-damage passives above. A mark
is per-TARGET state (a meta on the enemy with an absolute server-clock expiry)
rather than per-PASSIVE-LEVEL, so combat invokes them as static methods rather
than iterating learned passives:

- `is_marked(target) -> bool` — lazy-expiry check. Each AL clears its own expired
  meta on read, so no per-mark Timer is needed.
- `get_crit_bonus(target) -> float` — DeathMark (additive crit chance).
- `get_damage_bonus(target) -> float` — SentinelsMark / ManaSurge (multiplicative).
- `consume_mark(target) -> void` — MarkOfTheHunt (clears on auto-crit consume).
- `roll_refund(attacker, target) -> void` — SentinelsMark (combo refund chance).
- `consume_and_refund(caster, target, mp_cost) -> void` — ManaSurge (clears + MP refund).

`combat.gd._execute_hit` invokes these via `preload(...).method()` at the
appropriate point in the per-hit pipeline: get_damage_bonus before the defense
formula, get_crit_bonus before the crit roll, consume helpers after take_damage.
Marks are applied by the casting ability's `on_hit` (each AL writes its own meta
key, e.g. `death_mark_remaining`, with `Time.get_ticks_msec() + duration_ms`).

A lighter-weight variant — **direct per-target meta reads without static helpers**
— is used by Smoke Bomb's base effect + T3 upgrades. AL_SmokeBomb writes
per-target metas in its ground-zone tick callbacks:
- `smoke_evasion_expire_at_ms` + `smoke_evasion_chance` on allies inside
  (base ability — health.gd rolls `randf() < chance` and early-returns on
  a dodge; no health-deduction, no invuln, no screen-shake)
- `smoke_choke_expire_at_ms` + `smoke_choke_pct` on enemies inside (Choking
  Smoke T3 — health.gd scales incoming damage by `1 - smoke_choke_pct`)
- `smoke_inside_crit_until_ms` on allies inside (Shadow Smoke T3 — combat.gd
  forces `is_crit=true` on attacks while the meta is fresh)

All three use the expire-timestamp refresh pattern (each tick bumps the
timestamp forward; metas fade naturally when ticks stop). None of them
consume the meta on a hit — the meta IS the window. Use this lighter
pattern when the effect doesn't need an attacker-side static helper or a
dispatch loop; a one-line meta check is enough.

### Cross-ability infrastructure: GroundZone (v1)

`scripts/Gameplay/ground_zone.gd` is a shared persistent-area helper used by 9 v1
abilities (Earthsplitter, Banner, Caltrops, Sky Volley, Smoke Bomb, Frost Patch,
Stormcall, Pyre Burst Fire pool, Spellweave Fire). Each spawning AL calls
`load("res://scripts/Gameplay/ground_zone.gd").spawn_server(...)` (CIRCLE) or
`spawn_server_rect(...)` (RECT) — backward-compat circle and explicit-rect entry
points wrap a common `spawn_server_shaped` lowest-level helper. The zone joins
`networked_entities`, runs a server-only tick that iterates Enemies (and
optionally Players via `on_ally_tick_callback`) with shape-aware overlap
testing, and broadcasts a damage-less visual mirror to remote clients via
`MapManager.broadcast_ground_zone_shaped` / `client_show_ground_zone_shaped`.
Shape is `GroundZone.Shape` enum (`CIRCLE` = 0, `RECT` = 1). For ground-rect
abilities in the 2D platformer, prefer the wide-x / short-y rect (~30–65 px tall)
that hugs the floor and overlaps enemy hitboxes without towering above them —
the `/zone <name>` debug command spawns each configured zone at the player's
feet for visual inspection, and `docs/ground_zone_preview.html` shows every
shape at 1:1 scale.
