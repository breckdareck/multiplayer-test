---
name: improve-codebase-architecture
description: >-
  Scan this Godot multiplayer RPG for deepening opportunities, present them as a
  visual HTML report, then grill through whichever one you pick. Informed by the
  domain language in CONTEXT.md and the decisions in docs/adr/. Use when the user
  wants to improve architecture, find refactoring opportunities, consolidate
  tightly-coupled modules, or make the codebase more testable and AI-navigable.
disable-model-invocation: true
---

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities** — refactors
that turn shallow modules into deep ones. The aim is testability and
AI-navigability.

This command is _informed_ by the project's domain model and built on a shared
design vocabulary:

- Run the `/codebase-design` skill for the architecture vocabulary (**module**,
  **interface**, **depth**, **seam**, **adapter**, **leverage**, **locality**) and
  its principles (the deletion test, "the interface is the test surface", "one
  adapter = hypothetical seam, two = real", "in server-authoritative code the seam
  is the wire"). Use these terms exactly in every suggestion — don't drift into
  "service," "API," or "boundary," and reserve **Component** for the domain term.
- The domain language in `CONTEXT.md` gives names to good seams; ADRs in
  `docs/adr/` record decisions this command should not re-litigate. Run the
  `/domain-modeling` skill to keep both current as the design crystallises.

## Process

### 1. Explore

Read the project's domain glossary ([CONTEXT.md](../../../CONTEXT.md)) and any
ADRs in [docs/adr/](../../../docs/adr/) whose title touches the area you're
reviewing, plus the relevant subsystem `CLAUDE.md` (see the table in the root
[CLAUDE.md](../../../CLAUDE.md)).

Then use the Agent tool with `subagent_type=explorer` (this project's read-only
Godot subsystem mapper) to walk the codebase. Fall back to
`subagent_type=Explore` for non-domain searches. Don't follow rigid heuristics —
explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small
  modules?
- Where are modules **shallow** — interface nearly as complex as the
  implementation?
- Where have pure functions been extracted just for testability, but the real
  bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their current
  interface?

Apply the **deletion test** to anything you suspect is shallow: would deleting it
concentrate complexity, or just move it? A "yes, concentrates" is the signal you
want.

#### Friction patterns common to this codebase

Godot + server-authoritative multiplayer produces its own characteristic
shallowness. Watch for these:

- **Bag-of-stuff autoloads.** An autoload that started as one concern and grew
  cross-cutting siblings (a `Manager` doing spawning + UI + persistence + buff
  timers). Often a deepening candidate: split the concern that has its own
  lifecycle, fold the rest into a deeper core. See the autoload list in the root
  [CLAUDE.md](../../../CLAUDE.md).
- **Shallow RPC guards repeated everywhere.** Many functions starting with `if not
  multiplayer.is_server(): return` and doing one tiny mutation each. Often a sign
  the *intent* (a verb the player issued) is being smeared across N call sites
  instead of living in one deep module.
- **Component leaks.** A `Component` whose interface forces every caller to reach
  into another component to do its job (e.g. `Combat` callers reading `Stats`
  directly to compute hit chance). The Combat interface is shallow — the leverage
  is missing.
- **".tres" data that's actually behavior.** Resource fields that switch on string
  keys to pick a code path, custom `logic_script` chains, proc handler fan-out. If
  the resource is just a dispatch table for hand-written code, the data/code seam
  is in the wrong place — see
  [scripts/Resources/CLAUDE.md](../../../scripts/Resources/CLAUDE.md).
- **Bot vs player divergence.** Two parallel code paths for the same verb because
  bots have no client. The deep shape is usually *one* server-side module that
  doesn't care whether the caller is a peer or a bot brain. Bot-specific routing
  belongs at the visualisation seam (autoload broadcast), not the gameplay seam.
  See [scripts/Bot/CLAUDE.md](../../../scripts/Bot/CLAUDE.md).
- **Save-format vs runtime-format mismatches at every read site.** If every call
  site converts between `player_{username}.json` shape and the runtime shape, you
  have a shallow loader and a wide leak. Deep shape: one loader module, runtime
  values everywhere else.
- **Map / channel confusion at the seam.** Functions that take both a `map_id` and
  a peer-list and have to figure out which channel the recipient is on. The
  shallowness is at the addressing interface.

These are heuristics, not rules. The deletion test is still the arbiter.

### 2. Present candidates as an HTML report

Write a self-contained HTML file to the OS temp directory so nothing lands in the
repo. On this Windows / PowerShell setup, resolve the temp dir from `$env:TEMP`
and write to `<tmpdir>\architecture-review-<timestamp>.html` so each run gets a
fresh file. Open it with `Start-Process <path>` and tell the user the absolute
path. (Non-Windows: `$TMPDIR` → `/tmp`; `open` on macOS, `xdg-open` on Linux.)

For each candidate, render a card with **Files**, **Problem**, **Solution**,
**Benefits** (in terms of locality and leverage, and how tests would improve), a
custom **Before / After diagram**, and a **Recommendation strength** badge
(`Strong` / `Worth exploring` / `Speculative`). End with a **Top recommendation**
section. Be visual — Tailwind + Mermaid via CDN, mixing Mermaid graphs with
hand-built editorial diagrams.

**Use [CONTEXT.md](../../../CONTEXT.md) vocabulary for the domain, and the
`/codebase-design` vocabulary for the architecture.** If `CONTEXT.md` defines
"Pet," talk about "the Pet lifecycle module" — not "the PetManager helper," and
not "the pet service."

**ADR conflicts**: if a candidate contradicts an existing ADR in
[docs/adr/](../../../docs/adr/), only surface it when the friction is real enough
to warrant revisiting the ADR. Mark it clearly in the card (a warning callout:
_"contradicts ADR-0001 — but worth reopening because…"_). Don't list every
theoretical refactor an ADR forbids.

See [HTML-REPORT.md](HTML-REPORT.md) for the full HTML scaffold, diagram patterns,
and styling guidance.

Do NOT propose interfaces yet. After the file is written, ask the user: "Which of
these would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, run the `/grilling` skill to walk the design tree
with them — constraints, dependencies, the shape of the deepened module, what sits
behind the seam, what tests survive.

Side effects happen inline as decisions crystallize — run the `/domain-modeling`
skill to keep the domain model current as you go:

- **Naming a deepened module after a concept not in
  [CONTEXT.md](../../../CONTEXT.md)?** Add the term (domain-modeling owns the
  format). Create the file lazily if it doesn't exist (this repo already has one).
- **Sharpening a fuzzy term during the conversation?** Update `CONTEXT.md` right
  there. Don't batch.
- **User rejects the candidate with a load-bearing reason?** Offer an ADR, framed
  as: _"Want me to record this as an ADR so future architecture reviews don't
  re-suggest it?"_ Only offer when the reason would actually be needed by a future
  explorer to avoid re-suggesting the same thing — skip ephemeral and self-evident
  reasons. ADRs live in [docs/adr/](../../../docs/adr/), sequentially numbered.
- **Want to explore alternative interfaces for the deepened module?** Run the
  `/codebase-design` skill and use its
  [DESIGN-IT-TWICE.md](../codebase-design/DESIGN-IT-TWICE.md) parallel-sub-agent
  pattern.

### 4. Server-authority sanity check

Before recommending any deepening that touches gameplay state (health, stats,
inventory, drops, abilities, buffs, progression, equipment, currency, pets), run
it past the project's invariants — the same set `/grilling` grills against (see
[../grilling/INVARIANTS.md](../grilling/INVARIANTS.md)):

- The server owns the state; clients send intent.
- The three legal RPC shapes.
- Bots have negative peer IDs and no client; visuals route through autoloads.
- Networked spawns join the `networked_entities` group.
- Persistence has two layers: **character record** (Postgres) and **player save**
  (JSON via `SaveManager`).

A "deepening" that violates server authority is not a deepening — it's a
regression. If a candidate would require client-authoritative state to be viable,
drop it (or surface it as an ADR-worthy decision instead).
