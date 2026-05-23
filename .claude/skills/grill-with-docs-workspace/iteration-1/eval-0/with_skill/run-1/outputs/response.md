Happy to grill this. Before I poke at member caps or invite flows, I want to nail down the load-bearing piece — because most of the other decisions cascade off it.

**Quick terminology flag before I start:** you said "guild chat channel." In this codebase, **channel** already means a port-switched server instance managed by `ChannelManager` (players hop between channels without a restart). Using "channel" for guild chat will cause real confusion six months from now. I'd call it a **guild chat scope** (or just "guild chat") — a filter inside the existing `ChatManager`, not a new channel. I'll use "guild chat" for the rest of this conversation unless you push back.

Now the real question:

---

**Q1. What is a "shared guild XP pool," exactly?**

This phrase is doing a lot of work in your plan and I can read it three very different ways. Each has different server-authority, persistence, and balance implications, so I want to pin it down before anything else:

- **(a) Guild XP is a separate currency.** Killing a monster gives the player their normal personal XP *and also* contributes some amount to a guild-level XP counter. Guild XP unlocks guild perks / guild level / leaderboard rank, but never flows back to individual characters. Personal progression is untouched.
- **(b) Guild XP is a shared pool that members withdraw from.** Kills go into a pot, members pull XP out to level their characters. This makes the guild a way to share personal progression — and creates a juicy exploit surface (alt-account farming, leecher members).
- **(c) Guild XP is a bonus multiplier.** Being in a guild grants +X% personal XP on kills; "contributing to the pool" is just bookkeeping for the leaderboard. No new currency, no withdrawal mechanic.

**My recommendation: (a).** Reasons:

1. It cleanly preserves the existing personal-XP server-authoritative path. Today, when an enemy dies, the server credits the killer's `Stats` component and broadcasts. We just add one more line on the same server-side death handler that increments `guild.xp` for the killer's guild. No new authority boundary, no new race condition.
2. The guild XP record lives in **Postgres** (account/character layer), not in `SaveManager` JSON — because it's a cross-character, cross-session, server-global record, not per-character state. That matches what the leaderboard wants. (And it means there's a real `add-backend-endpoint` skill for the schema work.)
3. (b) breaks the rule that progression is server-validated *per character* — the server now has to arbitrate withdrawals, prevent double-spends across channels, and the design invites the exact "I made 5 alts to feed my main" exploit MMOs spend years fighting.
4. (c) is the smallest possible feature and might be where you actually want to land, but it doesn't really need a "pool" — it's just a buff. If that's what you mean, the plan shrinks dramatically and we should know now.

Which one did you mean — (a), (b), (c), or a fourth thing I haven't named? And if (a): on a kill, is the guild XP contribution **equal to** the personal XP, a **fraction** of it (e.g. 10%), or a **flat** per-kill value independent of the monster?
