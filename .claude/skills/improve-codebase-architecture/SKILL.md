---
name: improve-codebase-architecture
description: >-
  Find deepening opportunities in this Godot multiplayer RPG, informed by the
  domain language in CONTEXT.md and the decisions in docs/adr/. Use when the
  user wants to improve architecture, find refactoring opportunities,
  consolidate tightly-coupled modules, or make the codebase more testable and
  AI-navigable. Trigger phrases: "what's shallow here", "find refactors",
  "where can we deepen", "review the architecture", "what would I tackle first".
---

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities** —
refactors that turn shallow modules into deep ones. The aim is testability and
AI-navigability.

## Glossary

Use these terms exactly in every suggestion. Consistent language is the point —
don't drift into "component," "service," "API," or "boundary." Full
definitions in [LANGUAGE.md](LANGUAGE.md).

- **Module** — anything with an interface and an implementation (function,
  class, package, slice, autoload, component, scene).
- **Interface** — everything a caller must know to use the module: types,
  invariants, error modes, ordering, config. Not just the type signature.
- **Implementation** — the code inside.
- **Depth** — leverage at the interface: a lot of behaviour behind a small
  interface. **Deep** = high leverage. **Shallow** = interface nearly as
  complex as the implementation.
- **Seam** — where an interface lives; a place behaviour can be altered
  without editing in place. (Use this, not "boundary.")
- **Adapter** — a concrete thing satisfying an interface at a seam.
- **Leverage** — what callers get from depth.
- **Locality** — what maintainers get from depth: change, bugs, knowledge
  concentrated in one place.

Key principles (see [LANGUAGE.md](LANGUAGE.md) for the full list):

- **Deletion test**: imagine deleting the module. If complexity vanishes, it
  was a pass-through. If complexity reappears across N callers, it was earning
  its keep.
- **The interface is the test surface.**
- **One adapter = hypothetical seam. Two adapters = real seam.**

This skill is _informed_ by the project's domain model. The domain language
gives names to good seams; ADRs record decisions the skill should not
re-litigate.

## Process

### 1. Explore

Read the project's domain glossary and any ADRs in the area you're touching
first.

- Glossary: [CONTEXT.md](../../../CONTEXT.md) (single-context repo).
- Decisions: [docs/adr/](../../../docs/adr/) — read every ADR whose title
  touches the area you're reviewing.
- Subsystem how-to: the relevant `CLAUDE.md` (see the table in the root
  [CLAUDE.md](../../../CLAUDE.md)).

Then use the Agent tool with `subagent_type=explorer` (this project's
read-only Godot subsystem mapper) to walk the codebase. Fall back to
`subagent_type=Explore` for non-domain searches. Don't follow rigid heuristics
— explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small
  modules?
- Where are modules **shallow** — interface nearly as complex as the
  implementation?
- Where have pure functions been extracted just for testability, but the real
  bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their
  current interface?

Apply the **deletion test** to anything you suspect is shallow: would
deleting it concentrate complexity, or just move it? A "yes, concentrates" is
the signal you want.

#### Friction patterns common to this codebase

Godot + server-authoritative multiplayer produces its own characteristic
shallowness. Watch for these:

- **Bag-of-stuff autoloads.** An autoload that started as one concern and grew
  cross-cutting siblings (a `Manager` doing spawning + UI + persistence +
  buff timers). Often a deepening candidate: split the concern that has its
  own lifecycle, fold the rest into a deeper core. See the autoload list in
  the root [CLAUDE.md](../../../CLAUDE.md).
- **Shallow RPC guards repeated everywhere.** Many functions starting with
  `if not multiplayer.is_server(): return` and doing one tiny mutation each.
  Often a sign the *intent* (a verb the player issued) is being smeared
  across N call sites instead of living in one deep module.
- **Component leaks.** A `Component` whose interface forces every caller to
  reach into another component to do its job (e.g. `Combat` callers reading
  `Stats` directly to compute hit chance). The Combat interface is shallow —
  the leverage is missing.
- **".tres" data that's actually behavior.** Resource fields that switch on
  string keys to pick a code path, custom `logic_script` chains, proc handler
  fan-out. If the resource is just a dispatch table for hand-written code,
  the data/code seam is in the wrong place — see
  [scripts/Resources/CLAUDE.md](../../../scripts/Resources/CLAUDE.md) and
  the `ability-mechanics-shape` memory.
- **Bot vs player divergence.** Two parallel code paths for the same verb
  because bots have no client. The deep shape is usually *one* server-side
  module that doesn't care whether the caller is a peer or a bot brain.
  Bot-specific routing belongs at the visualisation seam (autoload broadcast),
  not at the gameplay seam. See [scripts/Bot/CLAUDE.md](../../../scripts/Bot/CLAUDE.md).
- **Save-format vs runtime-format mismatches at every read site.** If every
  call site converts between `player_{username}.json` shape and the runtime
  shape, you have a shallow loader and a wide leak. Deep shape: one loader
  module, runtime values everywhere else.
- **Map / channel confusion at the seam.** Functions that take both a
  `map_id` and a peer-list and have to figure out which channel the recipient
  is on. The shallowness is at the addressing interface.

These are heuristics, not rules. The deletion test is still the arbiter.

### 2. Present candidates as an HTML report

Write a self-contained HTML file to the OS temp directory so nothing lands in
the repo. On this Windows / PowerShell setup, resolve the temp dir from
`$env:TEMP` (e.g. `C:\Users\<user>\AppData\Local\Temp`) and write to
`<tmpdir>\architecture-review-<timestamp>.html` so each run gets a fresh file.
Open it for the user with `Start-Process <path>` (or `start <path>` in the
PowerShell tool) and tell them the absolute path.

On non-Windows machines: `$TMPDIR` → `/tmp` fallback; `open <path>` on macOS,
`xdg-open <path>` on Linux.

The report uses **Tailwind via CDN** for layout and styling, and **Mermaid via
CDN** for diagrams where a graph/flow/sequence reliably communicates the
structure. Mix Mermaid with hand-crafted CSS/SVG visuals — use Mermaid when
relationships are graph-shaped (call graphs, dependencies, sequences), and
hand-built divs/SVG when you want something more editorial (mass diagrams,
cross-sections, collapse animations). Each candidate gets a **before/after
visualisation**. Be visual.

For each candidate, render a card:

- **Files** — which files/modules are involved
- **Problem** — why the current architecture is causing friction
- **Solution** — plain English description of what would change
- **Benefits** — explained in terms of locality and leverage, and how tests
  would improve
- **Before / After diagram** — side-by-side, custom-drawn, illustrating the
  shallowness and the deepening
- **Recommendation strength** — one of `Strong`, `Worth exploring`,
  `Speculative`, rendered as a badge

End the report with a **Top recommendation** section: which candidate you'd
tackle first and why.

**Use [CONTEXT.md](../../../CONTEXT.md) vocabulary for the domain, and
[LANGUAGE.md](LANGUAGE.md) vocabulary for the architecture.** If `CONTEXT.md`
defines "Pet," talk about "the Pet lifecycle module" — not "the
PetManager helper," and not "the pet service." If it defines "Ability," talk
about "the Ability resolution module." Use the canonical terms; avoid the
aliases listed under `_Avoid_:`.

**ADR conflicts**: if a candidate contradicts an existing ADR in
[docs/adr/](../../../docs/adr/), only surface it when the friction is real
enough to warrant revisiting the ADR. Mark it clearly in the card (e.g. a
warning callout: _"contradicts ADR-0001 — but worth reopening because…"_).
Don't list every theoretical refactor an ADR forbids.

See [HTML-REPORT.md](HTML-REPORT.md) for the full HTML scaffold, diagram
patterns, and styling guidance.

Do NOT propose interfaces yet. After the file is written, ask the user:
"Which of these would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, drop into a grilling conversation. Walk the
design tree with them — constraints, dependencies, the shape of the deepened
module, what sits behind the seam, what tests survive.

Side effects happen inline as decisions crystallize:

- **Naming a deepened module after a concept not in
  [CONTEXT.md](../../../CONTEXT.md)?** Add the term using the format in
  [../grill-with-docs/CONTEXT-FORMAT.md](../grill-with-docs/CONTEXT-FORMAT.md)
  — same discipline as the `grill-with-docs` skill. Create the file lazily if
  it doesn't exist (this repo already has one).
- **Sharpening a fuzzy term during the conversation?** Update
  [CONTEXT.md](../../../CONTEXT.md) right there. Don't batch.
- **User rejects the candidate with a load-bearing reason?** Offer an ADR,
  framed as: _"Want me to record this as an ADR so future architecture
  reviews don't re-suggest it?"_ Only offer when the reason would actually
  be needed by a future explorer to avoid re-suggesting the same thing — skip
  ephemeral reasons ("not worth it right now") and self-evident ones. Use the
  format in
  [../grill-with-docs/ADR-FORMAT.md](../grill-with-docs/ADR-FORMAT.md). ADRs
  live in [docs/adr/](../../../docs/adr/) and are sequentially numbered —
  scan for the highest existing number and increment.
- **Want to explore alternative interfaces for the deepened module?** See
  [INTERFACE-DESIGN.md](INTERFACE-DESIGN.md) for the parallel-sub-agent
  "Design It Twice" pattern.

### 4. Server-authority sanity check

Before recommending any deepening that touches gameplay state (health, stats,
inventory, drops, abilities, buffs, progression, equipment, currency, pets),
run it past the project's invariants:

- The server owns the state; clients send intent.
- The three legal RPC shapes (see [scripts/Networking/CLAUDE.md](../../../scripts/Networking/CLAUDE.md)).
- Bots have negative peer IDs and no client; visuals route through autoloads.
- Networked spawns join the `networked_entities` group.
- Persistence has two layers: **character record** (Postgres) and **player
  save** (JSON via `SaveManager`).

A "deepening" that violates server authority is not a deepening — it's a
regression. If a candidate would require client-authoritative state to be
viable, drop it (or surface it as an ADR-worthy decision instead).
