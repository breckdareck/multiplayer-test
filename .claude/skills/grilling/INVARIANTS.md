# The invariants you grill against

This is a Godot 4 server-authoritative multiplayer RPG with a Flask + Postgres
backend. Some answers are wrong by construction — flag them the same way you'd
flag a contradiction with the glossary: directly, with the rule named.

Full subsystem detail lives in the [CLAUDE.md hierarchy](../../../CLAUDE.md);
read the relevant subsystem guide before grilling its area.

## Step 0: is this a content-creation task in disguise?

Before grilling, check whether the plan is mostly a *new piece of content* the
repo already has a recipe for. If it is, **name the matching skill in your
opening response** — that's the load-bearing move; the user may not know the
skill exists. Then grill only the cross-cutting decisions the recipe won't make
for them (balance, integration with other systems, save-format implications,
what new infrastructure the content needs).

| If the plan is essentially… | …name this skill |
|---|---|
| A new active attack, passive, buff-on-cast, or any `AbilityData` | `add-ability` |
| A new buff or debuff status effect | `add-buff` |
| A new weapon, armor, or consumable | `add-item` |
| A new monster or hostile NPC | `add-enemy` |
| A new level/map scene | `add-map` |
| A new Flask route or DB model | `add-backend-endpoint` |

**Specifically: anything called a "skill" by the user is almost certainly an
ability** — the project has one progression system, not two. Surface
`add-ability` immediately, then ask the user to confirm they really mean a
parallel skill tree (they probably don't). Reuse the Ability Window UI.

If the plan straddles a content type *and* introduces new infrastructure (a new
stat, a new component, a new save field, a new server pathway), still name the
skill first — then grill the infrastructure question separately.

## Server authority

The server owns all critical state. Clients send *intent* via RPCs; the server
validates, mutates, and broadcasts the authoritative result back. Health, stats,
inventory, drops, abilities, and progression mutated on a client will be
overwritten.

For every behavior the plan introduces, ask:
- Where does the source-of-truth state live — client or server?
- What is the client sending — intent, or a finished result?
- What does the server broadcast back, and to whom (`call_local` vs
  `call_remote`)?

A plan that needs the client to "just keep working" if the server goes away
violates the model. Surface that contradiction immediately, before grilling
anything else.

## RPC shape & guards

Three shapes are legal (full reference:
[scripts/Networking/CLAUDE.md](../../../scripts/Networking/CLAUDE.md)):

- `@rpc("authority", "call_local", "reliable")` — server → all peers, an
  authoritative state update. `call_local` because the host is also a client and
  must run the update too.
- `@rpc("any_peer", "call_local", "reliable")` — client → server, intent.
  **Must** guard the body with `if not multiplayer.is_server(): return` (or
  `is_multiplayer_authority()` for per-entity authority).
- `@rpc("authority", "call_remote", "reliable")` — server → clients only; the
  server does not run the function itself.

If a proposed flow doesn't map onto one of these, ask why.

## Bots have no client

Bots have negative peer IDs and no networked client. A node-addressed RPC sent to
a bot will not resolve. Bot-related visuals must route through an autoload that
runs on every peer (typically `MapManager`). Detail in
[scripts/Bot/CLAUDE.md](../../../scripts/Bot/CLAUDE.md).

If the plan introduces new behavior, ask: does this need to work for bots? If
yes, what's the autoload path?

## Components, not new top-level scripts

Player and enemy characters are composed of `Node` components under the character
root: `Health`, `Stats`, `Combat`, `Ability`, `Buff`, `Equipment`, `Inventory`,
`Debug`. Detail in
[scripts/Components/CLAUDE.md](../../../scripts/Components/CLAUDE.md).

New character behavior almost always slots into an existing component. Before
accepting "we'll add a new system," ask which component owns it and why the
existing one isn't the right home.

## Data, not code

Abilities, buffs, items, and classes are `.tres` resources auto-loaded by
`ResourceManager` from `resources/Abilities/`, `resources/Buffs/`,
`resources/Items/`, and `resources/Player/Classes/`. Detail in
[scripts/Resources/CLAUDE.md](../../../scripts/Resources/CLAUDE.md).

**Enemies are the exception** — `EnemyData` is NOT auto-loaded; it's referenced
directly from the enemy scene via an exported `enemy_data`.

If the plan proposes new code for content that could be data, ask why. Custom
logic (e.g. `AL_*` ability scripts) is the exception, not the rule.

## `networked_entities` group

Everything network-spawned must join the `networked_entities` group so it's
cleared on disconnect / channel switch. If the plan spawns new things, ask how
they join the group.

## Autoload reuse

The autoloads listed in the root [CLAUDE.md](../../../CLAUDE.md) (`MapManager`,
`ResourceManager`, `SaveManager`, `PlayerManager`, `ChannelManager`, etc.) are
the seams where cross-cutting concerns live. New autoloads are almost never the
answer — ask whether an existing one already owns the responsibility.

## Persistence layer

Two layers, easy to confuse:

- **Account / character records** (login, character list, owned characters, the
  unique character name `username`) → Flask + Postgres. Schema and endpoint
  conventions in [backend/CLAUDE.md](../../../backend/CLAUDE.md).
- **In-game character state** (health, level, exp, abilities, buffs, equipment,
  inventory, monies) → `SaveManager` to the backend, debounced.

If the plan stores something new, pin down which layer, and whether the format is
forward-compatible with existing player saves.

## Channels vs maps

A **channel** is a port-switched server instance (`ChannelManager`). A **map** is
a scene loaded within a channel (`MapManager`). Players say "channel," "world,"
"map," and "server" interchangeably — pin it down.

## Probing technique

### Probe with concrete scenarios

Don't ask abstract questions. Invent a concrete scenario and walk it through. You
learn ten times more from one walked scenario than from ten yes/no questions.

> "Player A casts a 10-second damage-over-time on Player B while Bot C is in the
> same party on the same map. Player B disconnects two seconds in. Bot C stays.
> Walk me through: who computes the remaining ticks, what each peer sees, and
> what's in the save when Player B reconnects."

### Cross-reference with code

When the user states how something works, check the code. If you find a
contradiction, surface it directly:

> "You said abilities re-roll their cooldown on level-up, but
> `ability_component.gd` only resets cooldown on cast. Which is right?"

This matters more than usual in a server-authoritative codebase, because the
proposed plan is often the *client-side mental model* and doesn't match what the
server is actually doing.
