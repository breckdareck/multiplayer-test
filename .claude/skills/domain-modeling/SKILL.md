---
name: domain-modeling
description: >-
  Build and sharpen this Godot multiplayer RPG's domain model. Use when the user
  wants to pin down domain terminology or a ubiquitous language, sharpen a fuzzy
  term, record an architectural decision (ADR), or when another skill (grilling,
  improve-codebase-architecture) needs to maintain the glossary and decision
  records as it goes.
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the
*active* discipline — challenging terms, inventing edge-case scenarios, and
writing the glossary and decisions down the moment they crystallise. (Merely
*reading* `CONTEXT.md` for vocabulary is not this skill — that's a one-line habit
any skill can do. This skill is for when you're changing the model, not just
consuming it.)

## File structure

This is a **single-context repo** — one game, one glossary.

```
/
├── CONTEXT.md                ← project glossary (lazy-created)
├── CLAUDE.md                 ← root project guide (how-to, not glossary)
├── docs/adr/                 ← architecture decision records (lazy-created)
└── scripts/.../CLAUDE.md     ← subsystem how-to guides
```

There is no `CONTEXT-MAP.md` and you should not create one. Create `CONTEXT.md`
and `docs/adr/` lazily — only when there's something concrete to write. A session
that produces neither file is a valid outcome.

The `CLAUDE.md` files are how-to / convention guides, *not* the glossary. If the
user describes a term already defined in a `CLAUDE.md`, cite that definition, then
move the canonical version into `CONTEXT.md` if it's glossary-shaped (a noun, a
domain concept) rather than how-to.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with `CONTEXT.md` (or a definition in a
`CLAUDE.md`), call it out immediately:

> "The CLAUDE.md hierarchy says a 'bot' is a server-side AI participant with a
> negative peer ID. You're using 'bot' to mean a quest NPC that walks a pre-set
> path. Which is it?"

### Sharpen fuzzy language

When the user uses a vague or overloaded term, propose a precise canonical term:

- "account" → Customer account? Character record?
- "skill" → **Ability.** There is no separate skill system — one progression
  system. Surface `add-ability` if they mean to create one.
- "channel" → ENet channel? Server instance? Chat channel?
- "world" → Map? Server? Game-state snapshot?
- "save" → Player save (JSON, backend)? Character record (Postgres)? Local config
  (`user://`)?
- "enemy" → Hostile monster (`EnemyData`)? Hostile player?
- "spawn" → Network-spawn (`PlayerManager.spawn_*`)? Add to scene tree?

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific
scenarios. Invent scenarios that probe edge cases and force the user to be precise
about the boundaries between concepts (party + bot + disconnect interactions, map
vs channel residency, save-layer ownership).

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you
find a contradiction, surface it: "You said abilities re-roll cooldown on
level-up, but `ability_component.gd` only resets cooldown on cast — which is
right?" This matters more in a server-authoritative codebase, because the stated
plan is often the client-side mental model and doesn't match what the server does.

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch — capture
terms as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` is a glossary only — never a spec, never an implementation log, never
a scratchpad. Don't duplicate `CLAUDE.md`: the CLAUDE.md hierarchy explains *how*
things work; `CONTEXT.md` defines *what* terms mean.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful.
2. **Surprising without context** — a future reader will wonder *why* it was done
   this way.
3. **The result of a real trade-off** — there were genuine alternatives and you
   picked one for specific reasons.

In this codebase, ADR-worthy decisions usually live at the seams: the
server-authority boundary for a new system, the .tres-vs-code choice for a new
content type, the persistence-layer choice (Postgres vs `SaveManager` JSON), the
bot-routing strategy for clientless participants, adding (or refusing) an
autoload, and save-format migrations. Pure within-component refactors and "small
additions in the obvious place" are not ADR-worthy.

If any of the three conditions is missing, skip the ADR. Use the format in
[ADR-FORMAT.md](./ADR-FORMAT.md).
