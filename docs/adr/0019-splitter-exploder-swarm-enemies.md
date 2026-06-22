# AoE-axis enemy patterns: splitter, exploder, swarm

Status: accepted (splitter + exploder + swarm built)

## Context

The attack-pattern set (ADRs 0016-0018) covers ranged, vertical-follow, and a
defensive guard, but nothing pressured the **AoE vs single-target** axis — nothing
rewarded staff stances / sword cleave / bow multi-shot or punished single-target
chip. Three multi-bodied patterns fill that slot: splitter, exploder, swarm.

## Decision

**Splitter** (`is_splitter` on `EnemyData`): when the enemy dies it spawns
`split_count` (2) smaller, weaker copies of **its own scene** (`scene_file_path`),
each scaled to `split_child_scale` and with HP × `split_child_health_mult`. A
runtime `_split_gen_left` decrements per generation and seeds from
`split_generations` (1 = parent splits, children don't), so the cascade is bounded.
Children are added under the dying enemy's container in `_maybe_split` (called from
the death handler, server-only); the map's `MultiplayerSpawner` — which auto-
replicates children whose scene is spawnable — handles the network copy, and the
host renders them regardless. The base **Slime** is the first splitter (chosen so
dev_test's slime spawner replicates the children for free).

**Exploder** (`is_exploder`): on death it bursts a circular AoE (`explode_radius`,
`explode_damage_mult`) around the death position via the same death hook, plus an
explosion VFX. Pairs with `is_aggressive` so it rushes in — punishes meleeing it /
being adjacent when it dies, rewards killing it from range. The **FireSlime**
(Lv73, aggressive) is the first. The radius damage is done **inline** (not via
`deal_boss_special_damage`) because that helper bails when the attacker is dead —
and an exploder is dead exactly when it bursts. The burst is dealt with
`ignore_invuln = true` so it goes through i-frames (a one-shot positional punish —
dodged by spacing, not by a lucky contact graze's invuln window).

**Swarm**: not a new mechanic — a fast, low-HP `GLASS` mob (`attack_mult` toned
down so the threat is *numbers*, not per-hit spikes) placed in a cluster. The
**Feral Hare** (a dedicated aggressive variant reusing the Bunny sprite, so base
bunnies stay passive) is the first; six are clustered in dev_test. Rewards AoE /
punishes single-target by being many bodies from the start (vs the splitter's
many-bodies-on-death).

## Consequences

- Making the base Slime a splitter is **global** — every slime now splits on death.
  Chosen for zero new content + free child replication in any map that spawns
  slimes. If that's unwanted in some zones, a dedicated splitter variant is the
  alternative (its children would need adding to a spawner's `_spawnable_scenes`
  to replicate in multiplayer).
- Split children are NOT pool-managed (they're spawned ad-hoc, `respawnable` false),
  so they free on death and don't refill — they're a one-off per kill, bounded by
  `split_count` × `split_generations`.
- Children inherit the parent's aggression. The base Slime is passive, so its
  children are too; an aggressive splitter (to actually *punish* single-target with
  a swarm) wants `is_aggressive` set — a per-variant call.
