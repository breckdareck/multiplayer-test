# ADR Format

ADRs live in `docs/adr/` and use sequential numbering: `0001-slug.md`,
`0002-slug.md`, etc.

Create `docs/adr/` lazily — only when the first ADR is needed.

## Template

```md
# {Short title of the decision}

{1-3 sentences: what's the context, what did we decide, and why.}
```

That's it. An ADR can be a single paragraph. The value is in recording *that*
a decision was made and *why* — not in filling out sections.

## Optional sections

Only include these when they add genuine value. Most ADRs in this codebase
won't need them.

- **Status** frontmatter (`proposed | accepted | deprecated | superseded by
  ADR-NNNN`) — useful when decisions are revisited.
- **Considered Options** — only when the rejected alternatives are worth
  remembering.
- **Consequences** — only when non-obvious downstream effects need to be
  called out (e.g. "this means existing player saves need a migration").

## Numbering

Scan `docs/adr/` for the highest existing number and increment by one.

## When to offer an ADR

All three must be true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful.
2. **Surprising without context** — a future reader will look at the code and
   wonder *why on earth* it was done this way.
3. **The result of a real trade-off** — there were genuine alternatives and
   you picked one for specific reasons.

If a decision is easy to reverse, skip it — you'll just reverse it. If it's
not surprising, no one will wonder why. If there was no real alternative,
there's nothing to record beyond "we did the obvious thing."

### What qualifies in this codebase

These are the seams where ADRs earn their keep:

- **Server-authority boundary for a new system.** "Trade state is mirrored on
  both peers during a trade, but the server is the tiebreaker." Anything where
  authority is non-trivially split needs writing down.
- **Bot routing strategy.** "Bot melee swings are visualised via a
  `MapManager` autoload broadcast rather than a node-addressed RPC, because
  bots have no client." Future readers will not infer the constraint from the
  code.
- **.tres-vs-code choice for a new content type.** "Quest objectives are
  expressed in code rather than as `.tres` resources because objectives need
  arbitrary predicates and we don't want to ship a mini-DSL in
  `QuestData.gd`."
- **Persistence-layer choice for a new piece of state.** "Friends lists live
  in Postgres rather than the player save because they cross characters
  within an account."
- **A new autoload — or a deliberate refusal to add one.** "We considered a
  `GuildManager` autoload but folded guilds into `PlayerManager` because the
  state is bounded by the party-membership lifecycle."
- **Save-format migrations.** Anything that changes the shape of
  `player_{username}.json` should record what the migration step is and what
  the fallback for old saves is.
- **Deliberate deviations from the documented patterns.** If a feature uses
  `@rpc("any_peer", "call_remote", ...)` instead of the usual `call_local`
  intent shape, write down why.
- **Constraints not visible in the code.** "We won't add WebSocket support
  because the host of choice for the dedicated server only proxies UDP/ENet."

### What does NOT qualify

- Adding a new ability, buff, item, enemy, or map. Those follow the
  `add-*` skills and are not architectural decisions.
- Renaming a variable, splitting a method, or moving a helper.
- Adding a field to an existing component.
- Bug fixes, no matter how clever.
- Choosing a UI control, animation, or sound.
