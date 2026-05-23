---
name: grill-with-docs
description: >-
  Socratic interview that stress-tests an architectural plan against this Godot
  multiplayer RPG's server-authoritative invariants, component model, .tres-driven
  content layer, RPC patterns, and documented domain terminology. Sharpens fuzzy
  language, cross-references the plan against actual code, updates CONTEXT.md
  inline as terms crystallise, and records hard-to-reverse decisions as ADRs. Use
  whenever the user wants to grill, stress-test, pressure-test, pre-mortem, or
  "poke holes in" a plan, design, proposal, or feature idea — especially anything
  touching networking, server authority, components, content (.tres), bots, or
  persistence. Trigger even if the user doesn't say the word "grill" — phrases
  like "tear this apart", "what's wrong with this plan", "before I build X, what
  am I missing" all qualify.
---

<what-to-do>

Interview the user relentlessly about every aspect of this plan until you reach
a shared understanding. Walk down each branch of the design tree, resolving
dependencies between decisions one at a time. For each question you ask, offer
your recommended answer so the user can react to a proposal instead of staring
at a blank page.

Ask one question at a time. Wait for the user's reply before continuing. A
question dump is the opposite of grilling — it lets the user skip the hard ones.

If a question can be answered by exploring the codebase, explore the codebase
instead. Don't ask the user to recite something that's already in the repo.

</what-to-do>

<supporting-info>

## The invariants you grill against

This is a Godot 4 server-authoritative multiplayer RPG with a Flask + Postgres
backend. Some answers are wrong by construction — flag them the same way you'd
flag a contradiction with the glossary: directly, with the rule named.

Full subsystem detail lives in the [CLAUDE.md hierarchy](../../../CLAUDE.md);
read the relevant subsystem guide before grilling its area.

### Server authority
The server owns all critical state. Clients send *intent* via RPCs; the server
validates, mutates, and broadcasts the authoritative result back. Health,
stats, inventory, drops, abilities, and progression mutated on a client will
be overwritten.

For every behavior the plan introduces, ask:
- Where does the source-of-truth state live — client or server?
- What is the client sending — intent, or a finished result?
- What does the server broadcast back, and to whom (`call_local` vs
  `call_remote`)?

A plan that needs the client to "just keep working" if the server goes away
violates the model. Surface that contradiction immediately, before grilling
anything else.

### RPC shape & guards
Three shapes are legal (full reference:
[scripts/Networking/CLAUDE.md](../../../scripts/Networking/CLAUDE.md)):

- `@rpc("authority", "call_local", "reliable")` — server → all peers, an
  authoritative state update. `call_local` because the host is also a client
  and must run the update too.
- `@rpc("any_peer", "call_local", "reliable")` — client → server, intent.
  **Must** guard the body with `if not multiplayer.is_server(): return` (or
  `is_multiplayer_authority()` for per-entity authority).
- `@rpc("authority", "call_remote", "reliable")` — server → clients only; the
  server does not run the function itself.

If a proposed flow doesn't map onto one of these, ask why.

### Bots have no client
Bots have negative peer IDs and no networked client. A node-addressed RPC sent
to a bot will not resolve. Bot-related visuals must route through an autoload
that runs on every peer (typically `MapManager`). Detail in
[scripts/Bot/CLAUDE.md](../../../scripts/Bot/CLAUDE.md).

If the plan introduces new behavior, ask: does this need to work for bots? If
yes, what's the autoload path?

### Components, not new top-level scripts
Player and enemy characters are composed of `Node` components under the
character root: `Health`, `Stats`, `Combat`, `Ability`, `Buff`, `Equipment`,
`Inventory`, `Debug`. Detail in
[scripts/Components/CLAUDE.md](../../../scripts/Components/CLAUDE.md).

New character behavior almost always slots into an existing component. Before
accepting "we'll add a new system," ask which component owns it and why the
existing one isn't the right home.

### Data, not code
Abilities, buffs, items, and classes are `.tres` resources auto-loaded by
`ResourceManager` from `resources/Abilities/`, `resources/Buffs/`,
`resources/Items/`, and `resources/Player/Classes/`. Detail in
[scripts/Resources/CLAUDE.md](../../../scripts/Resources/CLAUDE.md).

**Enemies are the exception** — `EnemyData` is NOT auto-loaded; it's
referenced directly from the enemy scene via an exported `enemy_data`.

Content additions usually mean a new `.tres`, not new code. Custom logic
exists (e.g. `AL_*` ability scripts), but it's the exception. If the plan
proposes new code for content that could be data, ask why.

The repo has dedicated skills for each content type: `add-ability`,
`add-buff`, `add-item`, `add-enemy`, `add-map`, `add-backend-endpoint`. If the
plan falls inside one of these, surface the skill rather than re-deriving the
recipe in the conversation.

### `networked_entities` group
Everything network-spawned must join the `networked_entities` group so it's
cleared on disconnect / channel switch. If the plan spawns new things, ask
how they join the group.

### Autoload reuse
The autoloads listed in the root [CLAUDE.md](../../../CLAUDE.md) (`MapManager`,
`ResourceManager`, `SaveManager`, `PlayerManager`, `ChannelManager`, etc.) are
the seams where cross-cutting concerns live. New autoloads are almost never
the answer — ask whether an existing one already owns the responsibility.

### Persistence layer
Two layers, easy to confuse:

- **Account / character records** (login, character list, owned characters,
  the unique character name `username`) → Flask + Postgres. Schema and
  endpoint conventions in [backend/CLAUDE.md](../../../backend/CLAUDE.md).
- **In-game character state** (health, level, exp, abilities, buffs,
  equipment, inventory, monies) → `SaveManager` to the backend, debounced.

If the plan stores something new, pin down which layer, and whether the
format is forward-compatible with existing player saves.

### Channels vs maps
A **channel** is a port-switched server instance (managed by
`ChannelManager`). A **map** is a scene loaded within a channel (managed by
`MapManager`). Players say "channel," "world," "map," and "server"
interchangeably — pin it down.

### One overloaded term to always challenge: Skill = Ability
The progression system is unified. There is no parallel skill tree separate
from abilities. If the user proposes "skills" alongside "abilities," push
back before any other questioning — usually they mean "abilities organised
into a UI view," not a new system. The Ability Window already exists; reuse it.

## Domain awareness

Before grilling, scan for existing project documentation.

### File structure

```
/
├── CONTEXT.md                ← project glossary (lazy-created)
├── CLAUDE.md                 ← root project guide
├── docs/
│   └── adr/                  ← architecture decision records (lazy-created)
│       ├── 0001-…md
│       └── 0002-…md
├── scripts/
│   ├── Networking/CLAUDE.md
│   ├── Components/CLAUDE.md
│   ├── Bot/CLAUDE.md
│   └── Resources/CLAUDE.md
└── backend/CLAUDE.md
```

This repo is **single-context** — one game. Don't look for a `CONTEXT-MAP.md`.

Create `CONTEXT.md` lazily — only when the first term is genuinely resolved.
Same for `docs/adr/`. A grill that produces neither file is a valid outcome.

The `CLAUDE.md` files are how-to / convention guides, *not* the glossary. If
the user describes a term that's already defined in a CLAUDE.md, cite that
definition, then move the canonical version into `CONTEXT.md` if it's
glossary-shaped (a noun, a domain concept) rather than how-to.

## During the session

### Challenge against the glossary
When the user uses a term that conflicts with `CONTEXT.md` (or a definition in
a CLAUDE.md), call it out immediately:

> "The CLAUDE.md hierarchy says a 'bot' is a server-side AI participant with a
> negative peer ID. You're using 'bot' to mean a quest NPC that walks a
> pre-set path. Which is it?"

### Sharpen fuzzy language
Propose a precise canonical term:

- "account" → Customer account? Character?
- "skill" → Ability? Player input action? Crafting recipe?
- "channel" → ENet channel? Server instance? Chat channel?
- "world" → Map? Server? Game state snapshot?
- "save" → Player save (JSON, backend)? Character record (Postgres)? Local
  config (`user://`)?
- "enemy" → Hostile monster (`EnemyData`)? Hostile player?
- "spawn" → Network-spawn (`PlayerManager.spawn_*`)? Add to scene tree?

### Probe with concrete scenarios
Don't ask abstract questions. Invent a concrete scenario and walk it through.
You learn ten times more from one walked scenario than from ten yes/no
questions.

> "Player A casts a 10-second damage-over-time on Player B while Bot C is in
> the same party on the same map. Player B disconnects two seconds in. Bot C
> stays. Walk me through: who computes the remaining ticks, what each peer
> sees, and what's in the save when Player B reconnects."

### Cross-reference with code
When the user states how something works, check the code. If you find a
contradiction, surface it directly:

> "You said abilities re-roll their cooldown on level-up, but
> `ability_component.gd` only resets cooldown on cast. Which is right?"

This matters more than usual in a server-authoritative codebase, because the
proposed plan is often the *client-side mental model* and doesn't match what
the server is actually doing.

### Update CONTEXT.md inline
When a term is resolved, update `CONTEXT.md` immediately. Don't batch.
Format: [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` is a glossary only — never a spec, never an implementation log,
never a scratchpad.

### Offer ADRs sparingly
Only offer an ADR when all three are true:

1. **Hard to reverse** — changing your mind later carries real cost.
2. **Surprising without context** — a future reader will wonder *why*.
3. **A real trade-off** — there were genuine alternatives.

In this codebase, ADR-worthy decisions usually live at the seams:

- The server-authority boundary for a new system (what's authoritative on
  which peer).
- The .tres-vs-code choice for a new content type.
- The persistence-layer choice (Flask/Postgres vs `SaveManager` JSON) for a
  new piece of state.
- The bot-routing strategy when a system needs to behave for clientless
  participants.
- Adding (or deliberately refusing to add) an autoload singleton.
- Save-format migrations.

Pure within-component refactors and "small additions in the obvious place"
are not ADR-worthy.

Format: [ADR-FORMAT.md](./ADR-FORMAT.md).

</supporting-info>
