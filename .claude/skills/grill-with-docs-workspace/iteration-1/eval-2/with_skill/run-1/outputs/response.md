Before I poke at the edges, I have to flag the load-bearing problem in the middle of the plan, because everything downstream depends on which way you resolve it.

**This plan contradicts the rule that governs everything in this repo.**

From the root `CLAUDE.md`:

> The server owns all critical state. Clients send *intent* via RPCs; the server validates it, mutates state, and broadcasts the authoritative result back. Never mutate health, stats, inventory, drops, abilities, or progression on a client and assume it sticks — it will be overwritten.

Your offline mode is, by definition, "the client keeps mutating health, stats, inventory, drops, and progression with no server to validate it, and we promise to make it stick later." That's not a small bend — it's the inverse of the model. Every component on the player (`Health`, `Stats`, `Combat`, `Ability`, `Buff`, `Equipment`, `Inventory`) currently treats client-side mutation as something the next server tick will overwrite. To make offline play *real*, you'd have to give the client a parallel authoritative mode it can flip into, and then reconcile two divergent state machines on reconnect.

And reconciliation isn't a syncing problem, it's a **trust** problem. The server cannot tell the difference between:

- "I killed 40 slimes in the woods while disconnected"
- "I edited my save file"

The whole reason the server is authoritative is that the client is untrusted. An offline-then-sync flow says "trust the client for a bounded window," which is exactly the door every cheater wants open.

So before I grill the *mechanics* of offline play (save format, conflict resolution, enemy state, bot interaction, party state, quest progress, drops, XP curves), I need to know which of these you actually mean. They sound similar in English and they're radically different builds:

---

**Option A — "Graceful disconnect UX."** When the connection drops, the game freezes combat, shows a "Reconnecting…" overlay, retries the ENet handshake, and on success resumes where the server left off. No offline progression. Nothing the player did during the dropout counts. This is a pure client-side improvement — no server changes, no save-format changes, no trust problem. It's a week of work.

**Option B — "Solo mode."** A separate, single-player game mode where the *client also runs the server* (Godot can host a local ENet server with one peer — `MultiplayerManager` already supports host mode). Progress in Solo mode is saved to a **separate character slot** that can never merge into your online character. This sidesteps the trust problem by refusing to merge. It's real work but it's mostly content/UX — the authority model is unchanged because the local host *is* the server.

**Option C — "Truly offline, then sync."** What you described. Client keeps the world running, simulates enemies, awards XP and drops, then on reconnect we somehow merge it with the server's view of your character. This is the one that violates the model, and the cost is not "implementing offline play" — it's "implementing an anti-cheat system strong enough to trust client-reported progression," plus reconciling every conflicting state (server-side bots, party members, instance enemies, quest objectives, traded items, durability, buff timers…) that kept moving on the server side. For an MMO-shaped game I would push back hard on this one.

My recommendation, given the codebase: **A for the disconnect UX, plus B if you want offline play to feel like a real feature.** C is a category of project, not a feature.

**Which of these did you actually have in mind?** (Or — is there a fourth framing I'm missing? "Offline mode" is the kind of phrase that can mean any of these depending on who said it.)
