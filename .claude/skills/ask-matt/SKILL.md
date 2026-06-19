---
name: ask-matt
description: Ask which skill or flow fits your situation. A router over the user-invoked skills in this repo.
disable-model-invocation: true
---

# Ask Matt

You don't remember every skill, so ask.

A **flow** is a path through the skills. Most paths run along one **main flow**, and on-ramps merge onto it. Everything else is standalone.

This repo has **no `/implement` or `/qa` skill** — implementation happens directly in-session, or through a content recipe (the `add-*` skills) with `/tdd` for the test-first loop. The router below reflects the skills that actually exist here.

## The main flow: idea → ship

The route most work travels. You have an idea and want it built.

1. **`/grill-with-docs`** — sharpen the idea by interview. Start here when you **have a codebase** (you do): it's stateful, retaining what it learns in `CONTEXT.md` and ADRs via `/domain-modeling`. (For a plan that doesn't live in this repo, use `/grill-me` — see Standalone.)
2. **Branch — is this really new content?** If the idea is essentially a new ability / buff / item / enemy / map / backend endpoint, the repo has a recipe — run the matching **`add-*`** skill (`add-ability`, `add-buff`, `add-item`, `add-enemy`, `add-map`, `add-backend-endpoint`). `/grilling` will name the right one. Use **`/create-gdd`** when the artifact you want is a design doc, not code.
3. **Branch — can you settle every question in conversation?** If a question needs a runnable answer (state, business logic, a UI you have to see), detour through a prototype, bridged by **`/handoff`** in both directions (see Crossing sessions):
   - **`/handoff`** out, then open a fresh session against that file,
   - **`/prototype`** to answer the question with throwaway code,
   - **`/handoff`** back what you learned, and reference it from the original idea thread.
4. **Branch — is this a multi-session build?**
   - **Yes** → **`/to-prd`** (turn the thread into a PRD) → **`/to-issues`** (split the PRD into independently-grabbable issues). Because the issues are independent, **clear context between each one**: start a fresh session per issue and build it from the PRD + the single issue, test-first with **`/tdd`**.
   - **No** → build it right here, in the same context window — **`/tdd`** for the red-green-refactor loop.

### Context hygiene

Keep the grilling → PRD → issues steps in **one unbroken context window** — don't compact or clear until after `/to-issues` — so the grilling, PRD, and issues all build on the same thinking. Each implementation session then starts fresh, working from the issue.

If a session gets too long before `/to-issues`, don't push on degraded — `/handoff` and continue in a fresh thread.

## On-ramps

A starting situation that generates work, then merges onto the main flow.

- **A hard bug or perf regression** → **`/diagnosing-bugs`**. Builds a tight feedback loop first, then hypothesise/instrument/fix. Hands off architectural findings to `/improve-codebase-architecture`.
- **Bugs and requests piling up** → **`/triage`** (needs `/setup-matt-pocock-skills` first). It moves issues through triage roles and produces agent-ready briefs. Triage is only for issues **you didn't create** — issues that `/to-issues` produced are already agent-ready, so **don't triage them**.

## Codebase health

Not feature work — upkeep.

- **`/improve-codebase-architecture`** — run whenever you have a spare moment to keep the codebase good for agents to operate in. It surfaces deepening opportunities; picking one _generates an idea_ you can take into the main flow at `/grill-with-docs`.

## Crossing sessions

- **`/handoff`** — when a thread is full or you need to branch off (e.g. into a `/prototype` session), this compacts the conversation into a markdown file. You don't continue in place — you **open a new session and reference that file** to carry the context across. It's the bridge between context windows, in either direction.
- **`/compact`** (built-in) — stay in the **same conversation**, letting the earlier turns be summarized. Use it at **intentional breaks between phases**, when you don't mind losing the verbatim history. `/handoff` forks; `/compact` continues.

## Standalone

Off the main flow entirely.

- **`/grill-me`** — the same relentless interview as `/grill-with-docs`, but with **no doc side-effects** (no `CONTEXT.md`, no ADRs). Reach for it to sharpen any plan that doesn't warrant touching the domain model.
- **`/teach`** — learn a concept over multiple sessions, using the current directory as a stateful workspace.
- **`/writing-great-skills`** — reference for writing and editing skills well.

## Engine skills (model-invoked, usually reached *through* the above)

You rarely invoke these by hand — the orchestrators above run them — but they exist:

- **`/grilling`** — the reusable interview loop, grilling against the server-authority invariants.
- **`/domain-modeling`** — maintains `CONTEXT.md` + ADRs.
- **`/codebase-design`** — the deep-module vocabulary (module / interface / depth / seam / adapter).

## Precondition

**`/setup-matt-pocock-skills`** — run before your first `/triage`, `/to-issues`, or `/to-prd` flow to configure the issue tracker, triage labels, and doc layout those skills assume.
