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

Repeatable content recipes, path-scoped (`paths:` frontmatter) so they
auto-activate when Claude works in matching files. They also trigger by
description for relevant requests.

| Skill | Path scope |
|---|---|
| `add-ability` | `resources/Abilities/`, `scripts/Abilities/` |
| `add-buff` | `resources/Buffs/`, `scripts/Buffs/` |
| `add-item` | `resources/Items/`, `scripts/Resources/ItemSystem/` |
| `add-enemy` | `resources/Enemies/`, `scripts/Enemy/`, `scenes/NPC/` |
| `add-map` | `scenes/Levels/`, `scripts/Gameplay/` |
| `add-backend-endpoint` | `backend/` |

`add-ability` uses progressive disclosure — its `references/ability-fields.md`
holds the full field and formula reference, loaded only when needed.

### Subagent — `.claude/agents/explorer.md`

A genuinely read-only (`Read`, `Grep`, `Glob` only) subsystem mapper. Dispatch it
to map an unfamiliar area before editing, so the main agent keeps its context
window for the edit itself.

### SessionStart hook — `.claude/hooks/session_start_context.ps1`

Prints a short orientation block at the start of each session: the
server-authoritative invariant, the list of subsystem guides, and which guides
cover any uncommitted changes. Wired up in `.claude/settings.json`. PowerShell,
so it has no Python/runtime dependency.

## Not included, and why

- **Self-improving `Stop` hook** — helpline's `Stop` hook asks a headless model
  to propose `CLAUDE.md` edits after each session. Omitted to keep a single
  source of truth for context; revisit if the guides start drifting.
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
