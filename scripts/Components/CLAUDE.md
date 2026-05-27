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
    ├── Stats      stats.gd       - STR/DEX/INT/LUCK/... aggregates ALL bonuses
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
    ├── WeaponMastery weapon_mastery.gd - Per-discipline mastery levels + XP (PR 2)
    │                                     mastery_data: {sword/bow/staff/dagger →
    │                                     {level, xp}}. Drives STR/DEX/INT/LUK
    │                                     scaling additively on top of class-level.
    │                                     Kill XP credits BOTH primary AND secondary
    │                                     equipped weapons (PR 4 fix 2026-05-28);
    │                                     cast XP only credits the ACTIVE weapon.
    ├── Buff       buff.gd        - timed buffs/debuffs, stacking, custom logic
    ├── Class      class.gd       - current_class = STARTING discipline (does NOT
    │                               change on weapon swap). Drives HP/MP curves.
    │                               For "what am I wielding right now", use
    │                               MultiplayerPlayerV2.get_active_discipline().
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
