# Resource editor discovers ability-upgrade effect_keys by scanning source, not a central registry

## Status

accepted

## Context

`AbilityUpgradeData.effect_key` is a free-text string. An upgrade only does
something if a consumer reads that exact key: the two *generic* keys
(`cooldown_flat_reduction`, `combo_cap_bonus`) are interpreted in
`ability.gd` / `combat.gd`, and every ability-specific key is read by that
ability's `AL_*.gd` via `get_ability_upgrade_magnitude(id, "key")` or
`ability_has_upgrade_effect(id, "key")`. A typo'd key is a **silent no-op** —
no error at author time or run time. As we author the bow/staff/dagger upgrade
trees, that footgun gets pulled dozens of times.

The resource-editor addon needs to validate `effect_key` at author time. Two
ways to know the legal keys:

1. **Central registry** — a `Constants.UPGRADE_EFFECT_KEYS` the field becomes a
   hard dropdown over, and every AL script is refactored to read its keys from.
2. **Scan source** — the editor greps the AL scripts + `ability.gd`/`combat.gd`
   for the string literals passed to the two lookup helpers, and builds the
   known-key set from that.

## Decision

The editor **scans source**. The `effect_key` field is an *editable* combo box
seeded from the scan (this ability's own `active_behavior.logic_script` keys
first, then the generic keys, then all other keys found in the codebase). Free
entry is still allowed so an upgrade can be authored *before* its handler
exists; a live chip turns amber ("no consumer found in code") until a matching
literal appears. We deliberately did **not** add a central registry.

Rationale: a registry would force a key to be registered before its upgrade
could be authored (wrong order for our design-first workflow) and would require
touching ~40 `AL_*.gd` scripts to read from it — churn with no gameplay value.
The scan keeps the AL scripts as the single source of truth and stays correct
with zero maintenance as handlers are added.

## Consequences

The scan assumes effect_keys appear as **string literals** in the two lookup
helper calls. If an AL script ever builds a key from a variable, the scan can't
see it and the "no consumer" chip will false-alarm for any upgrade using that
key. That is the one convention the tooling imposes on the game code; if we
ever need computed keys, revisit with a registry (option 1) for just those.
