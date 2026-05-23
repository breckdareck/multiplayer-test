Before I poke any holes, I have to surface a structural collision, because the rest of the grilling depends on whether you actually mean what you said.

The rule that governs everything in this repo (root `CLAUDE.md`, and the server-authority section the grill skill is built around) is:

> The server owns all critical state. Clients send *intent* via RPCs; the server validates, mutates, and broadcasts the authoritative result back. Health, stats, inventory, drops, abilities, and progression mutated on a client will be overwritten.

"Fight enemies, gain XP, pick up items" while disconnected is exactly the list of things the invariant says the client *cannot* decide. If a client fights an enemy locally, its HP, the loot table roll, the XP award, and the inventory add are all client-mutated state. When the client reconnects and tries to "sync" them, the server has two options:

1. **Trust the client's report** — which means the server no longer owns those values. Any cheater (or any bug) gets to fabricate XP, items, and gold by going offline, lying about what happened, and reconnecting. The server-authority invariant is gone, not just suspended.
2. **Re-validate the client's report** — but to validate "I killed Goblin #47 and rolled a Rare drop," the server has to know Goblin #47 existed there, with that HP, when the client said it did, and re-run the RNG. That's essentially running a deterministic shadow simulation per disconnected player. That's not "offline mode," that's lockstep replay, which is a much bigger project than I think you're picturing.

There's also a second collision worth naming now, because it shapes everything downstream: enemies in this game are server-spawned and live in the global `Enemies` group, network-spawned through `PlayerManager` / `MapManager` and tracked in `networked_entities`. When the ENet connection drops, those nodes don't keep ticking on the client with real AI — the client has no enemy authority, no spawner, no drop tables running. So "keep fighting enemies" isn't a switch you flip; it requires the client to grow a parallel, local version of the combat/spawn/loot stack that today only exists on the server.

So before I grill the sync protocol, the conflict resolution, the save-format implications, or the bot interaction — I want to pin down what you actually want, because there are at least three very different features hiding inside "offline mode":

- **(A) Single-player mode** — the player intentionally plays a local-authoritative version of the game (the client becomes its own server, like `start_server.bat` in-process). Characters in this mode are flagged offline-only and never sync to the live server character. This is achievable and doesn't break the invariant, because there's no live server to disagree with.
- **(B) Graceful disconnect UX** — when the connection drops, the player keeps moving, animations keep playing, maybe they can open menus and inventory — but combat, XP, and loot are paused/blocked until reconnect. No "sync everything back" because nothing of value happened.
- **(C) True authoritative offline play with sync-on-reconnect** — what you literally described. As argued above, this is incompatible with server-authority unless you replace it with deterministic replay, which is a much larger undertaking and a hard-to-reverse architectural commitment.

**My recommendation: (B), with (A) as a separate, optional feature later.** It preserves the invariant, it's the smallest believable scope, and "offline" becomes a UX problem (reconnect flow, input lock, queued chat) instead of a state-authority problem.

Which of those three are you actually after? If it's something between them, describe the scenario — one concrete player, one concrete disconnect — and we'll walk it.
