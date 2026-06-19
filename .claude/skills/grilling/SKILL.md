---
name: grilling
description: >-
  Interview the user relentlessly about a plan or design until you reach a shared
  understanding, grilling it against this Godot multiplayer RPG's
  server-authoritative invariants, component model, .tres content layer, RPC
  patterns, and persistence layers. Use whenever the user wants to grill,
  stress-test, pressure-test, pre-mortem, or "poke holes in" a plan, design,
  proposal, or feature idea — especially anything touching networking, server
  authority, components, content (.tres), bots, or persistence. Trigger even if
  the user never says "grill": phrases like "tear this apart", "what's wrong with
  this plan", "before I build X, what am I missing" all qualify. This is the
  reusable interview loop; `grill-me` and `grill-with-docs` wrap it.
---

# Grilling

Interview the user relentlessly about every aspect of this plan until you reach a
shared understanding. Walk down each branch of the design tree, resolving
dependencies between decisions one at a time. For each question you ask, offer
your **recommended answer** so the user reacts to a proposal instead of staring
at a blank page.

Ask one question at a time. Wait for the user's reply before continuing. A
question dump is the opposite of grilling — it lets the user skip the hard ones.

If a question can be answered by exploring the codebase, explore the codebase
instead. Don't make the user recite what's already in the repo.

## This is a server-authoritative Godot RPG — grill against its invariants

Some answers are wrong *by construction* in this codebase. Before and during the
interview, hold the plan against the project's invariants and flag a violation
the moment you see one — directly, with the rule named, the same way you'd flag a
contradiction with the glossary.

Read [INVARIANTS.md](./INVARIANTS.md) for the full set: server authority, the
three legal RPC shapes, bots-have-no-client, components-not-new-scripts,
data-not-code, the `networked_entities` group, autoload reuse, the two
persistence layers, and channels-vs-maps. Read the relevant subsystem `CLAUDE.md`
before grilling its area.

[INVARIANTS.md](./INVARIANTS.md) also opens with **Step 0: is this a
content-creation task in disguise?** — run that check first. If the plan is
mostly a new ability/buff/item/enemy/map/endpoint the repo already has a recipe
for, name the matching `add-*` skill in your opening response, then grill only the
cross-cutting decisions the recipe won't make.
