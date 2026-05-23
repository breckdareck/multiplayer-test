# AI Layer

The Claude Code configuration for this repo — the layered context, reusable
workflows, and tooling that make an AI agent effective in this codebase. Adapted
from the patterns in [coleam00/helpline](https://github.com/coleam00/helpline).

## Components

### CLAUDE.md hierarchy

A lean root `CLAUDE.md` (repo-wide truths only) plus one guide per subsystem.
Each subsystem guide loads additively when Claude works in that directory.

| File | Covers |
|---|---|
| `CLAUDE.md` | Server-authoritative model, autoloads, RPC conventions, groups |
| `scripts/Networking/CLAUDE.md` | ENet, RPC patterns, the backend HTTP bridge |
| `scripts/Components/CLAUDE.md` | The character component model |
| `scripts/Bot/CLAUDE.md` | Server-side AI bots |
| `scripts/Resources/CLAUDE.md` | The data resource classes |
| `backend/CLAUDE.md` | The Flask + PostgreSQL backend |

### Skills — `.claude/skills/`

Repeatable workflows. The `add-*` skills are content recipes, path-scoped
(`paths:` frontmatter) so they auto-activate when Claude works in matching
files. `grill-with-docs` is intent-triggered (no path scope) — invoked when
the user wants to pressure-test a plan.

| Skill | Path scope |
|---|---|
| `add-ability` | `resources/Abilities/`, `scripts/Abilities/` |
| `add-buff` | `resources/Buffs/`, `scripts/Buffs/` |
| `add-item` | `resources/Items/`, `scripts/Resources/ItemSystem/` |
| `add-enemy` | `resources/Enemies/`, `scripts/Enemy/`, `scenes/NPC/` |
| `add-map` | `scenes/Levels/`, `scripts/Gameplay/` |
| `add-backend-endpoint` | `backend/` |
| `grill-with-docs` | — (intent-triggered: "grill this plan", "poke holes in X", "what am I missing before I build Y") |

`add-ability` uses progressive disclosure — its `references/ability-fields.md`
holds the full field and formula reference, loaded only when needed.
`grill-with-docs` uses the same pattern: its `CONTEXT-FORMAT.md` and
`ADR-FORMAT.md` siblings only load when the skill is about to write a glossary
entry or an ADR.

### Subagent — `.claude/agents/explorer.md`

A genuinely read-only (`Read`, `Grep`, `Glob` only) subsystem mapper. Dispatch it
to map an unfamiliar area before editing, so the main agent keeps its context
window for the edit itself.

### SessionStart hook — `.claude/hooks/session_start_context.ps1`

Prints a short orientation block at the start of each session: the
server-authoritative invariant, the list of subsystem guides, and which guides
cover any uncommitted changes. Also writes a `.claude/.session-state/<id>.json`
baseline (HEAD SHA at session start) for the Stop hook to diff against. Wired
up in `.claude/settings.json`. PowerShell, so it has no Python/runtime
dependency.

### Stop hook — `.claude/hooks/stop_reflect.ps1`

End-of-turn drift check. Diffs the current tree against the session-start SHA,
maps changed files to their subsystem `CLAUDE.md`, and if a subsystem has code
changes but its guide was never touched this session, blocks the stop with a
structured reason listing the guides that need review. Also nudges a memory
pass for explicit user corrections/confirmations.

Deterministic and free — no LLM call per Stop. Respects `stop_hook_active` so
it nudges at most once per stop-chain; Claude can always finish by updating the
guide or replying with one sentence on why no update is needed.

## Not included, and why

- **LSP config** — Godot ships its own GDScript language server; nothing to add.
- **MCP server / plugin** — helpline's are a Python-AST search server and a
  multi-repo distribution mechanism; neither applies to a single Godot project.
- **`.claudeignore`** — not a supported Claude Code file. Ignore rules live in
  `.gitignore`, which Claude Code already respects.

## Maintaining it

Update these files as conventions change, and give them a full pass every few
months (and after any major model release) — delete guidance newer models no
longer need. The CLAUDE.md hierarchy only helps while it stays accurate.

Note: `.claude/settings.json` is matched by this repo's broad `*.json` rule in
`.gitignore`. Run `git add -f .claude/settings.json` if you want the hook config
committed and shared.
