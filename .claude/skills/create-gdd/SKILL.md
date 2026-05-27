---
name: create-gdd
description: >-
  Author a detailed, good-looking Game Design Document (GDD) for this Godot
  multiplayer RPG. Reads existing project context (CLAUDE.md, CONTEXT.md,
  docs/adr/, key memory files) so the doc reflects the current direction
  (MapleStory inspiration, weapon-driven identity, server-authoritative
  components, etc.), drafts a 15+ section Markdown GDD using the bundled
  template, and renders a styled HTML preview alongside it. Trigger whenever
  the user wants to write, draft, update, or refresh a GDD, design doc, design
  brief, concept doc, or "one-pager" for the game — including phrases like
  "draft a GDD", "write the design doc", "I need to document the game design",
  "produce a design brief for X", "update the GDD with the new combat
  changes". Also trigger when they ask for sections of a GDD (e.g. "write the
  combat chapter", "draft the progression section") since this skill owns the
  template and the styling.
---

# Create a Game Design Document

Author a **good-looking, detailed Game Design Document** for this Godot 4
multiplayer RPG. The output is two files in `docs/`:

- `docs/GDD.md` — the canonical source, version-controlled alongside the code.
- `docs/GDD.html` — a styled standalone HTML preview, regenerated from the
  Markdown by the bundled render script.

The skill is **project-aware**: it reads the repo's own context before drafting
so the doc doesn't contradict what's already decided. It is also
**principle-aware**: it leans on the references in `references/` for design
fundamentals (core loops, MDA, Bartle's player types, flow, juice) so sections
are substantive rather than generic.

## When to draft vs. update

| State | What to do |
|---|---|
| `docs/GDD.md` doesn't exist | Draft a new GDD from scratch using the template + project context. |
| `docs/GDD.md` exists, user wants a refresh | Re-read context, diff against the existing GDD, edit in place. Preserve the user's prose; only rewrite stale facts. |
| User asks for one section only | Edit that section in place. Do not rewrite the whole doc. |

Always offer to regenerate `docs/GDD.html` at the end.

## Workflow

### 1. Gather project context (mandatory)

Two tiers — keep them straight.

**Tier 1: source of truth.** Read these in parallel. The GDD must not
contradict them, because they describe what's actually in the repo today:

- `CLAUDE.md` (repo-wide truths: server-authoritative rule, autoloads, RPC
  patterns)
- `CONTEXT.md` (domain glossary — use these terms exactly: **Pet**, **Bot**,
  **Enemy**, **Pet command**, etc. Don't invent synonyms.)
- `docs/adr/*.md` (hard-to-reverse decisions already made)
- `README.md` (whatever the user has already pitched publicly)
- Any existing `docs/GDD.md` (if updating)
- The actual code under `scripts/`, content under `resources/`, scenes under
  `scenes/` — for any concrete claim (a class name, a stat value, a damage
  formula), the file on disk is the truth.

**Tier 2: pointers and history.** These tell you *where to look* and *what
the user was thinking*, but they are **not** authority:

- The memory index at
  `~/.claude/projects/D--Godot-Projects-multiplayer-test/memory/MEMORY.md`
  (especially the **Design Direction** entries: MapleStory direction, weapon
  identity overhaul, art constraint, differentiation direction).

**Verify memory against source before citing it.** Memory entries are
snapshots of what was true when written — the code or direction may have
moved on. When a memory entry materially shapes a section:

1. Open the linked memory file *and* the file/ADR/code it references.
2. If they agree, cite the source (not the memory) in the GDD.
3. If they disagree, the source wins. Flag the discrepancy in your opening
   response so the user knows the memory needs an update.

If the user briefed you on a *new* direction in this conversation that
contradicts both memory and the repo, prefer the conversation, flag both
contradictions, and offer to update the memory after the GDD lands.

### 2. Interview only on gaps

The repo already answers a lot. Don't ask the user to repeat what's in
CLAUDE.md, CONTEXT.md, or memory. Only ask about:

- Sections where the repo is genuinely silent (story beats, target audience
  specifics, monetisation plans, production schedule, accessibility goals).
- Sections where memory has *conflicting* signals (e.g. weapon-driven identity
  vs. the existing 9-class structure — that tension is noted in memory but
  unresolved).
- The **design pillars** if not already stated anywhere. Three to five short
  phrases that the rest of the GDD will be measured against.

Ask one question at a time, recommend an answer, let the user redirect.

### 3. Draft from the template

Copy `assets/gdd-template.md` to `docs/GDD.md`, then fill it in. Section-level
guidance lives in [references/gdd-sections.md](references/gdd-sections.md) —
**read it before writing each section** if you haven't already in this turn.
Principles to cite (so the doc isn't generic) are in
[references/design-principles.md](references/design-principles.md).

Filling rules:

- **Use the project's exact terminology.** "Pet", "Bot", "Enemy" — not
  "companion", "AI player", "NPC". See CONTEXT.md.
- **Be concrete.** Replace `{{placeholders}}` with real values from the repo
  (autoload names, class names, stat names) where they exist. Generic
  marketing-speak ("immersive engaging gameplay") is the failure mode — quote
  specific systems and numbers instead.
- **Show, don't just tell.** Use Mermaid diagrams for the core loop and
  progression curve, tables for stats / classes / enemy tiers, code blocks
  for damage formulas or RPC contracts.
- **Cross-link** to ADRs and existing docs (e.g. the Pet ADR) instead of
  duplicating their content.
- **Flag open questions.** Sections with unresolved tensions get an
  `> ⚠ Open question:` callout, not glossed-over filler.

### 4. Render the HTML preview

Run:

```bash
python "D:\Godot Projects\multiplayer-test\.claude\skills\create-gdd\scripts\render_html.py" docs/GDD.md docs/GDD.html
```

The script produces a self-contained HTML file with the bundled CSS inlined,
auto-generated TOC, Mermaid diagram rendering (via CDN), syntax-highlighted
code, and a dark/light theme toggle. Tell the user the file is ready and
offer to open it.

If Python or the script's deps are missing, fall back to instructing the user
to view the Markdown directly (most editors render it well) — don't block the
draft on rendering.

### 5. Iterate

After the user reads, expect targeted requests: "expand the combat section",
"replace the example weapons with real ones", "add a section on bots". Edit
in place and re-render the HTML. Don't rewrite the whole doc.

## What "good looking and detailed" means here

These are the standards the draft is graded against. Internalise them before
you start writing.

- **Detailed = specific.** Concrete numbers, real class names, actual ability
  IDs from `resources/Abilities/`, real enemy levels from `resources/Enemies/`.
  Vagueness ("various enemies", "many abilities") is the anti-pattern.
- **Detailed ≠ verbose.** Every section earns its space. If a section has
  nothing to say yet, mark it `> ⚠ Open question:` and move on — don't pad.
- **Good-looking = scannable.** Headings, tables, diagrams, callouts. A
  reader skimming the rendered HTML should grasp the game in 60 seconds and
  drill into any section they want.
- **Tone:** confident and concrete, like a real designer wrote it for a real
  team. Not breathless ("revolutionary genre-defining experience") and not
  bureaucratic ("the system shall provide…"). Read it back: does it sound
  like a person who has actually played the game?

## Bundled resources

| File | What it is |
|---|---|
| [assets/gdd-template.md](assets/gdd-template.md) | The 18-section Markdown skeleton to copy into `docs/GDD.md`. |
| [assets/styles.css](assets/styles.css) | The CSS the render script inlines into the HTML preview. |
| [references/gdd-sections.md](references/gdd-sections.md) | Per-section guidance: what each section answers, what *bad* looks like, what *good* looks like. Read sections lazily as you fill them in. |
| [references/design-principles.md](references/design-principles.md) | Core loop, MDA, Bartle, flow, juice, compulsion loops, onboarding pyramid. Cite these by name when relevant. |
| [scripts/render_html.py](scripts/render_html.py) | Markdown → styled HTML. Run after every meaningful edit. |
