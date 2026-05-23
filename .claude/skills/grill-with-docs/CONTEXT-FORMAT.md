# CONTEXT.md Format

## Structure

```md
# multiplayer-test — domain glossary

The shared language of this Godot multiplayer RPG. Keep each entry tight:
define what the term IS, not what it does. Implementation lives in the code
and in the CLAUDE.md hierarchy.

## Language

**Ability**:
A castable or passive effect owned by a `Player` or `Bot`, defined as
`AbilityData` (`.tres`) under `resources/Abilities/<Class>/` and resolved
server-side. Single progression system — there is no separate "Skill".
_Avoid_: Skill, spell, technique, power.

**Bot**:
A server-side AI participant with a negative peer ID and no networked client.
Joins parties, fights enemies, casts abilities. Driven by `bot_brain.gd`.
_Avoid_: AI player, NPC.

**Channel**:
A port-switched server instance, managed by `ChannelManager`. Players move
between channels to balance load or instance content.
_Avoid_: World, shard, server (when used loosely), realm.

**Map**:
A scene loaded within a channel, managed by `MapManager`. Has spawn points,
enemies, transitions to other maps.
_Avoid_: Level (unless naming the scene file), zone, area.

**Enemy**:
A hostile non-player monster, defined as `EnemyData` (`.tres`, NOT
auto-loaded — referenced directly from the enemy scene) and spawned via
`enemy_spawner`. Lives in the global `Enemies` group; filter by map when
iterating.
_Avoid_: NPC, mob, creature, monster (when used loosely).

**Networked entity**:
Any node spawned through `PlayerManager` / `MapManager` that must be cleaned
up on disconnect or channel switch. Added to the global `networked_entities`
group.
_Avoid_: Actor, networked actor, replicated node.

**Component**:
A `Node` child of the character root that owns a single concern: `Health`,
`Stats`, `Combat`, `Ability`, `Buff`, `Equipment`, `Inventory`, `Debug`. New
character behavior slots into one of these.
_Avoid_: System, module, subsystem.

**Player save**:
The per-character in-game state (health, level, exp, abilities, buffs,
equipment, inventory, monies). JSON, written to the backend by
`SaveManager`, debounced.
_Avoid_: Save file, character data, profile.

**Character record**:
The per-character account-layer row in Postgres (login, character list,
owned characters, the unique `username`). Lives behind the Flask API.
_Avoid_: Account, profile, user record.
```

## Rules

- **Be opinionated.** When multiple words exist for the same concept, pick the
  best one and list the others as aliases to avoid.
- **Flag conflicts explicitly.** If a term is used ambiguously, call it out
  under "Flagged ambiguities" with a clear resolution.
- **Keep definitions tight.** One or two sentences max. Define what it IS,
  not what it does.
- **Show relationships.** Use bold term names and express cardinality where
  obvious ("A `Party` has 1–6 `Player`s and 0+ `Bot`s.").
- **Only include terms specific to this project.** General programming
  concepts (timeouts, error types, generic patterns) don't belong even if the
  codebase uses them extensively. Before adding a term, ask: is this a
  concept unique to this game, or to programming in general? Only the former
  belongs.
- **Group terms under subheadings** when natural clusters emerge — e.g.
  "Networking", "Content", "Progression". If everything fits in one cohesive
  area, a flat list is fine.
- **Don't duplicate CLAUDE.md.** The CLAUDE.md hierarchy explains *how* things
  work; `CONTEXT.md` defines *what* terms mean. If you find yourself writing
  procedure, you're in the wrong file.

## Single-context repo

This repo is single-context: one game, one glossary. There is no
`CONTEXT-MAP.md` and you should not create one.

Lazy-create `CONTEXT.md` at the repo root only when the first term is
genuinely resolved. A grilling session that resolves no terms produces no
file.
