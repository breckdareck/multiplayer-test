# Status-tag synergy layer and derived duo nodes

Cross-discipline ability synergy needs enemy statuses (bleed/poison/burn/chill/
mark) to be *queryable and consumable* by abilities that didn't apply them.
We decided to build that as a **query layer over the existing per-ability meta
keys** — a static `EnemyStatus` helper (BleedDot-style) that maintains a
per-enemy tag index registered at apply time — rather than unifying storage,
and to make the pair-identity payoffs (**duo nodes**) stateless derived
unlocks rather than purchasable upgrades. Full design + locked decisions:
[docs/ability_synergy_research.md](../ability_synergy_research.md) §3;
glossary terms (status tag, escalation rule, duo node, channeled ability) in
[CONTEXT.md](../../CONTEXT.md).

## The decisions

1. **Tags are a query surface, not a storage change.** Per-ability meta keys
   (`hemorrhage_bleed`, `envenom_poison`, …) keep their independent
   stacking/tick math — the documented convention in `bleed_dot.gd`.
   `EnemyStatus.has/stack_count(enemy, tag)` aggregates across sources
   (stack counts SUM). Consumers and escalation rules key off tags only.
2. **Tag state is enemy-global.** Reads and spends ignore applier identity —
   any participant (player or bot) can consume any participant's stacks.
   Consistent with the FFA party philosophy (loot, aggro, no trinity); GW2
   ships cross-player combos as a feature. Per-key tick/kill credit keeps its
   existing last-refresher behavior.
3. **Duo nodes are derived, never purchased or persisted.** Active while both
   equipped disciplines have ≥ threshold points spent. A purchasable
   pair-scoped upgrade would force the per-discipline point pools, the
   respec refund path, and `reconcile_ability_points()` to learn about
   purchases that belong to two disciplines at once — touching the
   most invariant-sensitive code in progression ("a player must never
   randomly gain/lose ability points") for 6 nodes. Derived unlocks need no
   save field, no backend column, deactivate automatically on respec, and
   work for bots with zero wiring.

## Considered options

- **Collapse statuses to shared per-enemy channels with stack caps** — simpler
  queries, but changes balance (sources compete for cap space) and reverses
  the per-source stacking convention.
- **Give enemies a BuffComponent and apply statuses as debuffs** — rejected
  for v1. BuffComponent is built for players (stat modifiers, save
  persistence, client sync, buff-bar UI, REFRESH/STACK/IGNORE semantics that
  contradict per-source stacking); enemy DoTs need only what `BleedDot`
  already does. With all maps resident (ADR 0007), per-enemy buff machinery
  is weight on hundreds of mostly-sleeping nodes. The registry API is the
  seam: if enemies ever get a real BuffComponent, it can become the backing
  store behind `EnemyStatus` without any consumer changing.
- **Purchased duo nodes** (split cost, one pool, or a synthetic pair-ability)
  — all variants touch the reconcile guard and the backend
  `learned_ability_upgrades` format; rejected as risk without payoff.

## Consequences

- Upgrade re-authors must reference tags/gauges, never per-ability meta keys
  and never "your other equipped weapon" slot (it can be empty or
  same-discipline → dead purchase). Slot-pair flavor lives on duo nodes only.
- The existing Toxicology/Vendetta hardcode of `envenom_poison` becomes a bug
  fixed by re-targeting to the poison tag (caltrops/synergy poison currently
  feed nothing).
- "Channel" is a banned word for tags — it collides with channeled
  (cast-over-time) abilities and port-switched server channels.
- Swap-trigger ICDs and tag indexes are transient server state — nothing in
  this layer is ever persisted.
