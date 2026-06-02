# 4. Remove ClassComponent; fold weapon-identity into WeaponMasteryComponent

Date: 2026-06-02

## Status

Accepted

## Context

The weapon-identity overhaul replaced the legacy 9-class system with four weapon
disciplines (Sword/Bow/Staff/Dagger). After PR 7 removed job advancement and
moved primary-stat scaling onto the manually-allocated attribute pool,
`ClassComponent` (`scripts/Components/class.gd`) had decayed into a thin wrapper
that still owned three responsibilities:

1. **The "primary discipline" pointer** (`current_class`) — the default-identity
   answer for unarmed fallback, sprite selection, bot identity, the save's
   `character_type` field, and the starting-ability seed. ~14 call sites read it.
2. **Base-stat baseline + HP/MP curve selection**, keyed by `current_class`.
3. **Display name** + a legacy-class normalization shim (CRUSADER→SWORD, etc.).

"Classes" no longer exist as a concept, yet a whole component, a scene node, and
an `@export` NodePath persisted to model one. `WeaponMasteryComponent` already
owned the per-discipline mastery levels — the natural home for the one remaining
piece of weapon-identity state.

## Decision

Delete `ClassComponent` entirely and **fold its surviving role into
`WeaponMasteryComponent`** as a `primary_discipline` field, with wrapper methods
(`get_primary_abilities/get_base_stats/get_class_bonuses/get_discipline_name`)
and a `set_primary_discipline()` + `set_primary_discipline_rpc` /
`primary_discipline_changed` signal trio that mirrors the old
`change_class`/`change_class_rpc`/`class_changed` shape exactly.

- **Stat scaling stays weapon-pure.** No class-level STR scaling is
  reintroduced — primary stats already come from the attribute pool + mastery
  (PR 7). `StatsComponent` now sources its base-stat baseline and HP/MP curve
  from `primary_discipline` (identical data, identical enum — loss-free).
- **Persistence reuses the existing `character_type` save field** (→ backend
  `character_class` column). `primary_discipline` is set once at spawn from
  `character_type` and saved back through it. **No new save field and no backend
  change.** Job advancement is gone, so it never changes mid-session.
- The legacy advanced-class normalization shim moves onto the
  `primary_discipline` setter, so old CRUSADER/RANGER/ARCHMAGE/ASSASSIN saves
  still revert to their tier-1 discipline on load.

## Consequences

- One fewer component, scene node, and `@export` NodePath. The
  `node_paths` PackedStringArray on `player.tscn`'s root had `class_component`
  removed alongside the `Components/Class` node and its `ext_resource` — these
  must move together or the scene fails to load (validated: scene instantiates,
  `weapon_mastery_component` export resolves).
- `WeaponMasteryComponent` is now the single owner of weapon identity (levels +
  primary pointer). Server-authoritative: `set_primary_discipline` is
  server-driven and broadcast via an `authority/call_local` RPC; clients keep a
  mirror for UI.
- Forward-compatible: existing player saves load unchanged (same
  `character_type` int, same disciplines).
- Validated at the static level (84/84 unit tests, headless scene load). An
  in-engine multiplayer playtest of spawn → stats → combat → sprite is still
  recommended before relying on it in a live session.
