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
files. `create-gdd` is intent-triggered. The grilling / architecture skills
(ported from [mattpocock/skills](https://github.com/mattpocock/skills)) form a
**composable graph**: three model-invocable **engines** — `grilling`,
`domain-modeling`, `codebase-design` — that auto-trigger on intent, and three
user-invoked **orchestrators** (`disable-model-invocation`) that compose them.

| Skill | Role / trigger |
|---|---|
| `add-ability` | path: `resources/Abilities/`, `scripts/Abilities/` |
| `add-buff` | path: `resources/Buffs/`, `scripts/Buffs/` |
| `add-item` | path: `resources/Items/`, `scripts/Resources/ItemSystem/` |
| `add-enemy` | path: `resources/Enemies/`, `scripts/Enemy/`, `scenes/NPC/` |
| `add-map` | path: `scenes/Levels/`, `scripts/Gameplay/` |
| `add-backend-endpoint` | path: `backend/` |
| `grilling` *(engine)* | model-invoked: the interview loop; grills against `INVARIANTS.md` ("grill this plan", "poke holes in X", "what am I missing") |
| `domain-modeling` *(engine)* | model-invoked: maintains the `CONTEXT.md` glossary and `docs/adr/` ("pin down this term", "record this decision") |
| `codebase-design` *(engine)* | model-invoked: deep-module vocabulary + principles ("design this interface", "where's the seam") |
| `grill-me` *(orchestrator)* | `/grill-me` — grilling, no doc side-effects |
| `grill-with-docs` *(orchestrator)* | `/grill-with-docs` — grilling + domain-modeling |
| `improve-codebase-architecture` *(orchestrator)* | `/improve-codebase-architecture` — explore → HTML report → grilling loop; composes all three engines |
| `create-gdd` | — (intent-triggered: "draft the GDD", "update the design doc", "write the combat chapter") |
| `ask-matt` *(router)* | `/ask-matt` — names the user-invoked skills and the idea→ship flow |
| `tdd` *(engine)* | model-invoked: test-first red-green-refactor against the `test/` harness |
| `diagnosing-bugs` *(engine)* | model-invoked: feedback-loop-first bug/perf diagnosis ("debug this", "it's slow") |
| `prototype` *(orchestrator)* | `/prototype` — throwaway logic TUI or UI variants to answer a design question |
| `handoff` *(orchestrator)* | `/handoff` — compact the thread into a handoff doc for a fresh session |
| `to-prd` *(orchestrator)* | `/to-prd` — synthesize the thread into a PRD on the issue tracker |
| `to-issues` *(orchestrator)* | `/to-issues` — split a plan/PRD into tracer-bullet issues |
| `triage` *(orchestrator)* | `/triage` — move incoming issues/PRs through triage roles |
| `setup-matt-pocock-skills` *(orchestrator)* | `/setup-matt-pocock-skills` — one-time issue-tracker/labels/domain config |
| `teach` *(orchestrator)* | `/teach` — multi-session learning workspace |
| `writing-great-skills` *(orchestrator)* | `/writing-great-skills` — reference + glossary for authoring skills |
| `git-guardrails-claude-code` *(engine)* | model-invoked: install a hook blocking dangerous git commands |
| `setup-pre-commit` *(engine)* | model-invoked: Husky + lint-staged + Prettier (JS/TS subtrees only) |
| `migrate-to-shoehorn` *(engine)* | model-invoked: TS-only test-assertion migration (not the game) |
| `scaffold-exercises` *(engine)* | model-invoked: ai-hero-cli course-authoring layout (not the game) |

The 15 skills below the divider are ported from
[mattpocock/skills](https://github.com/mattpocock/skills) — faithfully, with
light adaptation where this repo's tooling differs (the `test/` harness,
Windows/PowerShell paths, `ask-matt` rewired to this repo's catalog). Four
(`migrate-to-shoehorn`, `scaffold-exercises`, `setup-pre-commit`,
`git-guardrails-claude-code`) target the JS/TS ecosystem and apply only to
tooling subtrees, not the Godot game itself.

`add-ability` uses progressive disclosure — its `references/ability-fields.md`
holds the full field and formula reference, loaded only when needed. The
engine skills do the same: `grilling`'s `INVARIANTS.md` (server-authority rules
+ content-task routing), `domain-modeling`'s `CONTEXT-FORMAT.md` /
`ADR-FORMAT.md` (side-effect write formats), and `codebase-design`'s
`DEEPENING.md` (dependency categories) and `DESIGN-IT-TWICE.md` (parallel
sub-agent interface exploration) load only when the relevant step is reached.
The orchestrators stay tiny and delegate: `improve-codebase-architecture` keeps
only its `HTML-REPORT.md` (report scaffold) and routes vocabulary, glossary, and
grilling through the engines. `create-gdd` does the same: `assets/gdd-template.md` (the 20-section
skeleton), `assets/styles.css` (preview stylesheet), `references/gdd-sections.md`
(per-section guidance), `references/design-principles.md` (core loops, MDA,
Bartle, flow, juice), and `scripts/render_html.py` all load only when the
section the model is filling actually needs them.

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
