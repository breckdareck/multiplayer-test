Happy to poke holes. Offline mode sounds like a small feature, but in a server-authoritative MMO it's actually one of the hardest things you can attempt — it inverts the rule that governs everything else in this codebase. Before you write a line of code, I'd want you to wrestle with the questions below. I'll group them so you can see where the structural problems are vs. the merely-annoying ones.

## 1. The architectural inversion

The root `CLAUDE.md` is blunt about it:

> The server owns all critical state. Clients send *intent* via RPCs; the server validates it, mutates state, and broadcasts the authoritative result back. Never mutate health, stats, inventory, drops, abilities, or progression on a client and assume it sticks — it will be overwritten.

"Fight enemies, gain XP, pick up items" is *exactly* the list of things that rule forbids the client to do. So the proposal isn't "add an offline mode" — it's "give the client a second, parallel, authoritative implementation of combat, loot, and progression, and then reconcile it with the server's version."

Concretely, things that today only exist server-side that you'd have to re-implement client-side:

- Damage calculation, hit validation, ability cooldowns, buff stacking
- Enemy AI, aggro, pathing
- The loot table roll (`ItemDrop`, rarity, currency)
- XP curves, level-up, stat allocation, level-30 job advancement (`JobAdvancementManager`)
- Quest objective ticks (`QuestManager`)
- Save debouncing (`SaveManager`)

Question: are you prepared to maintain two implementations of combat — one server, one client — and keep them bit-for-bit identical forever? Every ability you add via `add-ability`, every enemy you add via `add-enemy`, every buff via `add-buff` now has to be authored once and verified to behave identically in both authorities. That's the real cost.

## 2. "Loses connection" is several different failure modes

You said "if the player loses their connection." That phrase hides at least four very different events:

1. **Brief network blip** (1–10 s of packet loss) — ENet recovers, no work needed.
2. **Genuine disconnect from the game server** (ENet peer dropped) — `MultiplayerManager` tears down. `networked_entities` get cleared. The map is unloaded on the way out.
3. **Disconnect from the Flask/Postgres backend** — game server still up, but `NetworkManager` HTTP saves are failing. Very different problem.
4. **The player is the host** (this project supports listen-server hosting) — they can't "lose connection to themselves." What does offline mode even mean for them?

Which of these are you trying to handle? They have almost nothing in common. If you mean #2, note that today the disconnect path actively destroys state — you'd have to first stop that teardown from happening, *then* swap authority, which is a much bigger change than "let the loop keep running."

## 3. The reconciliation problem (the actual killer)

Suppose the offline session "works." Player reconnects. Now you have two divergent histories and have to merge them. Walk me through what happens in each of these cases:

- Player A goes offline. Player B (still online) kills the same enemy A was fighting. Whose kill counts? Whose loot? When A reconnects, does the enemy un-die?
- A kills 10 enemies offline. The server, in the meantime, has spawned different enemies in those positions for other players. Does A's "I killed Slime_47" claim get accepted? If yes, what stops a hacked client from claiming 10,000 kills?
- A picks up offline an item that, online, was already taken by B. Who wins?
- A completes a quest objective offline that requires talking to an NPC; meanwhile B has progressed a world quest that despawned that NPC. What happens?
- A gains a level offline and allocates stat points and picks a job advancement at level 30 (`JobAdvancementManager`). The server's `Stats` component has different values. Last-write-wins? Server-wins? Merge?

There is no generic answer. Every system needs an explicit reconciliation policy, and most of them have no good answer for an MMO. The industry-standard reason single-shard MMOs don't have offline mode isn't lack of effort — it's that reconciliation is *unsolvable* without a single source of truth.

## 4. The cheating problem

The server-authoritative rule isn't just for consistency — it's the anti-cheat model. The moment you accept a client's "here's what I did offline, please apply it," you've handed cheaters a tool. Specifically:

- A modified client can fabricate any offline log it wants: "I killed 10,000 Slimes and picked up 50 rare drops."
- You can't verify by replay without sending down enemy spawn seeds, RNG state, ability tables, loot tables, etc. — at which point you've given the cheater everything they need to forge a *valid-looking* log too.
- Soft mitigations (rate limits, sanity checks on XP/hour, drop-rate caps) work for accidental drift but not against deliberate exploitation.

What's your threat model? If this is a small-friend-group game, "trust the client" might be fine. If it's a public MMO, this single feature undermines the entire authority model.

## 5. The architectural pieces it touches in this repo

Going through the autoload list and groups, here's what would need surgery, not just additions:

- `MultiplayerManager` / `ClientManager` / `ServerManager` — disconnect today clears `networked_entities` and tears down the level. You'd need a new "suspended" state where the network is gone but the level and entities stay alive.
- `PlayerManager` — relies on peer IDs to look up players; offline there is no peer ID 1 to be the server. Who's the authority for the local player? For the enemies still in the scene?
- `MapManager` — handles transitions and spawning; how do offline map transitions work? Are you locked to one map until reconnect?
- Components under `Player/Components/` — `Health`, `Stats`, `Combat`, `Ability`, `Buff`, `Equipment`, `Inventory`. Each currently has implicit server-authority assumptions. They'd all need a "local-authoritative" mode and rules for re-syncing on reconnect.
- Enemies (`Enemies` group, `enemy_spawner.gd` object pool) — today only the server runs AI and the pool. Offline, the client needs to run them. Then on reconnect, the server doesn't know they exist.
- `SaveManager` — today debounces saves to the backend. Offline, you'd need to write to local disk, then upload-and-merge on reconnect. The Flask API has no merge endpoint today.
- `QuestManager`, `JobAdvancementManager`, `TradeManager`, `PartyManager` — every one of these has cross-player implications. Trading and parties obviously can't function offline. Quests with NPC/world dependencies probably can't either.
- `ChatManager` — slash commands and chat go away. Probably fine, but worth being explicit.
- `BotManager` — bots are server-side. Do they keep running offline? If yes, what authority? If no, your offline world is suddenly emptier.

That's at least a dozen subsystems with new states and edge cases — and a permanent ongoing tax on every new feature, because each one has to consider "what does this do offline?"

## 6. Questions I'd want answers to before any code

1. **Is this a single-player-experience game pretending to be multiplayer, or a real multiplayer game?** That determines whether offline progression is *the* design goal or a footgun.
2. **What's your tolerance for losing offline progress?** "Server says no" on reconnect is by far the simplest design, but the user has to accept it.
3. **Scope-cut version: would a graceful 30-second reconnection window — where the game pauses, shows "reconnecting…", and resumes if it gets back in time — solve the actual user problem you're worried about?** That's a week of work. Full offline mode is a year.
4. **Even simpler: do you actually need offline play, or do you need offline-*viewing* (let players see their inventory/character even when the server is gone, but not act)?** Drastically smaller surface.
5. **Where does the host fit?** Players can host their own server in this project. Is "offline" just "auto-host a local server when the remote one drops"? That's a real option, very different from client-side authority, and might be much closer to what you actually want.

## My recommendation before you go deeper

Pick one of these three framings explicitly, because the work and risk differ by ~100x:

- **A. Reconnection grace window** — keep the player's character visible, freeze the world, reconnect in the background. Cheap. Solves "I rebooted my router."
- **B. Local-host fallback** — when the remote server dies, spin up a local listen-server with this player's character only, in a sandboxed "offline shard." No XP/loot syncs back. Honest about being a separate save. Medium cost, intellectually clean, and reuses code paths that already work.
- **C. True offline progression with sync-back** — what you described. Architecturally enormous, opens cheating, requires per-system reconciliation rules. I would not recommend it unless this is the central pillar of the game.

If you tell me which one (or which mix) you actually want, I can start digging into the specific subsystems and write a concrete plan with file-level changes. Right now, "add offline mode" is too underspecified to build, and the most useful thing I can do is stop you from pouring weeks into option C without realizing that's what you signed up for.
